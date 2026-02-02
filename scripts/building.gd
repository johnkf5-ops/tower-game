extends Node2D

const FLOOR_WIDTH: int = 20  # tiles wide
const TILE_WIDTH: int = 32
const FLOOR_HEIGHT: int = 48

# Data structures
var floors: Dictionary = {}  # floor_number -> FloorData
var elevators: Array = []
var elevator_shafts: Dictionary = {}  # x_position -> ElevatorShaft

# Preloads
var floor_scene: PackedScene
var elevator_scene: PackedScene
var person_scene: PackedScene

# References
@onready var floors_node: Node2D = $Floors
@onready var elevators_node: Node2D = $Elevators
@onready var people_node: Node2D = $People
@onready var main: Node2D = get_parent()


class FloorData:
	var floor_number: int
	var is_lobby: bool
	var tiles: Array = []  # What's on each tile
	var tenants: Array = []
	
	func _init(num: int, lobby: bool = false) -> void:
		floor_number = num
		is_lobby = lobby
		tiles.resize(FLOOR_WIDTH)
		for i in range(FLOOR_WIDTH):
			tiles[i] = "empty"


class ElevatorShaft:
	var x_position: int
	var min_floor: int = 0
	var max_floor: int = 0
	var cars: Array = []


func _ready() -> void:
	# Load scenes
	floor_scene = load("res://scenes/floor.tscn") if ResourceLoader.exists("res://scenes/floor.tscn") else null
	elevator_scene = load("res://scenes/elevator.tscn") if ResourceLoader.exists("res://scenes/elevator.tscn") else null
	person_scene = load("res://scenes/person.tscn") if ResourceLoader.exists("res://scenes/person.tscn") else null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(get_global_mouse_position())


func _handle_click(world_pos: Vector2) -> void:
	var build_mode = main.current_build_mode
	
	if build_mode == main.BuildMode.NONE:
		return
	
	# Convert world position to grid position
	var grid_x: int = int(world_pos.x / TILE_WIDTH)
	var floor_num: int = -int(world_pos.y / FLOOR_HEIGHT)  # Negative because Y goes down
	
	match build_mode:
		main.BuildMode.FLOOR:
			_try_build_floor(floor_num)
		main.BuildMode.ELEVATOR:
			_try_build_elevator(grid_x, floor_num)
		main.BuildMode.OFFICE:
			_try_build_office(grid_x, floor_num)


func _try_build_floor(floor_num: int) -> void:
	if floors.has(floor_num):
		print("Floor already exists")
		return
	
	# Must build adjacent to existing floor
	if not floors.has(floor_num - 1) and not floors.has(floor_num + 1):
		if floor_num != 0:  # Exception for lobby
			print("Must build adjacent to existing floor")
			return
	
	if floor_num > 100 or floor_num < -10:
		print("Floor out of range")
		return
	
	if main.spend_money(5000):
		add_floor(floor_num, false)
		print("Built floor ", floor_num)


func _try_build_elevator(grid_x: int, floor_num: int) -> void:
	if not floors.has(floor_num):
		print("Need a floor first")
		return
	
	# Check if shaft exists at this x
	if elevator_shafts.has(grid_x):
		# Extend existing shaft
		var shaft = elevator_shafts[grid_x]
		if floor_num < shaft.min_floor:
			shaft.min_floor = floor_num
		elif floor_num > shaft.max_floor:
			shaft.max_floor = floor_num
		_update_elevator_visual(grid_x)
	else:
		# Create new shaft
		if main.spend_money(20000):
			var shaft = ElevatorShaft.new()
			shaft.x_position = grid_x
			shaft.min_floor = floor_num
			shaft.max_floor = floor_num
			elevator_shafts[grid_x] = shaft
			_create_elevator_car(grid_x, floor_num)
			print("Built elevator at x:", grid_x)


func _try_build_office(grid_x: int, floor_num: int) -> void:
	if not floors.has(floor_num):
		print("Need a floor first")
		return
	
	if floors[floor_num].is_lobby:
		print("Can't build office in lobby")
		return
	
	# Offices take 4 tiles
	if grid_x < 0 or grid_x + 4 > FLOOR_WIDTH:
		print("Out of bounds")
		return
	
	# Check tiles are empty
	var floor_data = floors[floor_num]
	for i in range(4):
		if floor_data.tiles[grid_x + i] != "empty":
			print("Space occupied")
			return
	
	if main.spend_money(10000):
		for i in range(4):
			floor_data.tiles[grid_x + i] = "office"
		_create_office_visual(grid_x, floor_num)
		main.change_population(4)  # Office adds 4 workers
		print("Built office at floor ", floor_num)


func add_floor(floor_num: int, is_lobby: bool) -> void:
	var floor_data = FloorData.new(floor_num, is_lobby)
	floors[floor_num] = floor_data
	_create_floor_visual(floor_num, is_lobby)


func _create_floor_visual(floor_num: int, is_lobby: bool) -> void:
	var floor_node = Node2D.new()
	floor_node.name = "Floor_" + str(floor_num)
	floor_node.position.y = -floor_num * FLOOR_HEIGHT
	
	# Draw floor background
	var rect = ColorRect.new()
	rect.size = Vector2(FLOOR_WIDTH * TILE_WIDTH, FLOOR_HEIGHT)
	rect.position = Vector2(0, 0)
	
	if is_lobby:
		rect.color = Color(0.8, 0.75, 0.6)  # Lobby color
	else:
		rect.color = Color(0.9, 0.9, 0.85)  # Regular floor
	
	floor_node.add_child(rect)
	
	# Add floor number label
	var label = Label.new()
	label.text = str(floor_num) if floor_num != 0 else "L"
	label.position = Vector2(5, 15)
	label.add_theme_color_override("font_color", Color.BLACK)
	floor_node.add_child(label)
	
	floors_node.add_child(floor_node)


func _create_elevator_car(shaft_x: int, floor_num: int) -> void:
	var shaft = elevator_shafts[shaft_x]
	
	var car = Node2D.new()
	car.name = "ElevatorCar_" + str(shaft_x)
	car.set_meta("shaft_x", shaft_x)
	car.set_meta("current_floor", floor_num)
	car.set_meta("target_floor", floor_num)
	car.set_meta("passengers", [])
	car.set_meta("state", "idle")  # idle, moving, boarding
	
	car.position = Vector2(shaft_x * TILE_WIDTH, -floor_num * FLOOR_HEIGHT)
	
	# Visual
	var rect = ColorRect.new()
	rect.size = Vector2(TILE_WIDTH * 2, FLOOR_HEIGHT - 4)
	rect.position = Vector2(0, 2)
	rect.color = Color(0.4, 0.4, 0.5)
	car.add_child(rect)
	
	shaft.cars.append(car)
	elevators_node.add_child(car)


func _update_elevator_visual(shaft_x: int) -> void:
	# Draw shaft background for all floors
	var shaft = elevator_shafts[shaft_x]
	
	# Find or create shaft visual
	var shaft_visual_name = "Shaft_" + str(shaft_x)
	var shaft_visual = elevators_node.get_node_or_null(shaft_visual_name)
	
	if shaft_visual:
		shaft_visual.queue_free()
	
	shaft_visual = Node2D.new()
	shaft_visual.name = shaft_visual_name
	
	for floor_num in range(shaft.min_floor, shaft.max_floor + 1):
		var rect = ColorRect.new()
		rect.size = Vector2(TILE_WIDTH * 2, FLOOR_HEIGHT)
		rect.position = Vector2(shaft_x * TILE_WIDTH, -floor_num * FLOOR_HEIGHT)
		rect.color = Color(0.2, 0.2, 0.25, 0.5)
		shaft_visual.add_child(rect)
	
	elevators_node.add_child(shaft_visual)
	elevators_node.move_child(shaft_visual, 0)  # Behind cars


func _create_office_visual(grid_x: int, floor_num: int) -> void:
	var floor_node = floors_node.get_node("Floor_" + str(floor_num))
	if not floor_node:
		return
	
	var office = ColorRect.new()
	office.size = Vector2(TILE_WIDTH * 4 - 4, FLOOR_HEIGHT - 8)
	office.position = Vector2(grid_x * TILE_WIDTH + 2, 4)
	office.color = Color(0.6, 0.7, 0.8)
	floor_node.add_child(office)


func get_floor_y(floor_num: int) -> float:
	return -floor_num * FLOOR_HEIGHT
