extends Node2D

const FLOOR_WIDTH: int = 20  # tiles wide
const TILE_WIDTH: int = 32
const FLOOR_HEIGHT: int = 48
const ELEVATOR_SPEED: float = 200.0  # pixels per second
const PERSON_SPEED: float = 60.0  # pixels per second
const PERSON_SIZE: float = 8.0  # dot radius
const ELEVATOR_CAPACITY: int = 6
const QUEUE_SPACING: float = 10.0  # horizontal spacing between waiting people

# Data structures
var floors: Dictionary = {}  # floor_number -> FloorData
var elevators: Array = []
var elevator_shafts: Dictionary = {}  # x_position -> ElevatorShaft
var offices: Array = []  # Array of {floor: int, x: int} for quick lookup
var people: Array = []  # Active person nodes
var waiting_queues: Dictionary = {}  # shaft_x -> {floor_num -> [person, ...]}

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


enum PersonState { WALKING_TO_ELEVATOR, WAITING, RIDING, WALKING_TO_OFFICE, AT_OFFICE }


func _ready() -> void:
	# Load scenes
	floor_scene = load("res://scenes/floor.tscn") if ResourceLoader.exists("res://scenes/floor.tscn") else null
	elevator_scene = load("res://scenes/elevator.tscn") if ResourceLoader.exists("res://scenes/elevator.tscn") else null
	person_scene = load("res://scenes/person.tscn") if ResourceLoader.exists("res://scenes/person.tscn") else null


func _process(delta: float) -> void:
	_update_elevators(delta)
	_update_people(delta)


func _update_elevators(delta: float) -> void:
	for shaft_x in elevator_shafts:
		var shaft = elevator_shafts[shaft_x]
		for car in shaft.cars:
			_update_elevator_car(car, delta)


func _update_elevator_car(car: Node2D, delta: float) -> void:
	var state = car.get_meta("state")

	if state == "idle":
		# Check if we should pick up waiting people or go somewhere
		_elevator_check_for_work(car)
		return

	if state != "moving":
		return

	var target_floor: int = car.get_meta("target_floor")
	var target_y: float = -target_floor * FLOOR_HEIGHT
	var current_y: float = car.position.y

	var distance: float = target_y - current_y
	var move_amount: float = ELEVATOR_SPEED * delta

	if abs(distance) <= move_amount:
		# Arrived at target floor
		car.position.y = target_y
		car.set_meta("current_floor", target_floor)

		# Remove this floor from stops
		var floor_stops: Array = car.get_meta("floor_stops")
		floor_stops.erase(target_floor)

		# Handle arrivals - let people off, board waiting people
		_elevator_handle_arrival(car, target_floor)
	else:
		# Move toward target
		car.position.y += sign(distance) * move_amount


func _elevator_handle_arrival(car: Node2D, floor_num: int) -> void:
	var shaft_x: int = car.get_meta("shaft_x")
	var passengers: Array = car.get_meta("passengers")
	var floor_stops: Array = car.get_meta("floor_stops")

	# Let passengers off who want this floor
	var exiting = []
	for p in passengers:
		if p.get_meta("dest_floor") == floor_num:
			exiting.append(p)

	for p in exiting:
		passengers.erase(p)
		p.set_meta("state", PersonState.WALKING_TO_OFFICE)
		p.set_meta("current_floor", floor_num)
		p.set_meta("elevator_car", null)
		p.position.y = -floor_num * FLOOR_HEIGHT + FLOOR_HEIGHT - PERSON_SIZE
		print("Person exited at floor ", floor_num)

	# Board waiting people (up to capacity)
	_elevator_board_waiting(car, shaft_x, floor_num)

	# Pick next destination
	_elevator_pick_next_stop(car)


func _elevator_board_waiting(car: Node2D, shaft_x: int, floor_num: int) -> void:
	var passengers: Array = car.get_meta("passengers")
	var floor_stops: Array = car.get_meta("floor_stops")

	# Get waiting queue for this shaft/floor
	if not waiting_queues.has(shaft_x):
		return
	if not waiting_queues[shaft_x].has(floor_num):
		return

	var queue: Array = waiting_queues[shaft_x][floor_num]

	# Board people from front of queue until full
	while queue.size() > 0 and passengers.size() < ELEVATOR_CAPACITY:
		var person = queue.pop_front()
		passengers.append(person)
		person.set_meta("state", PersonState.RIDING)
		person.set_meta("elevator_car", car)

		# Add their destination to floor stops
		var dest = person.get_meta("dest_floor")
		if dest not in floor_stops:
			floor_stops.append(dest)

		print("Person boarded (", passengers.size(), "/", ELEVATOR_CAPACITY, "), going to floor ", dest)

	# Update positions of remaining waiters
	_update_queue_positions(shaft_x, floor_num)


func _elevator_pick_next_stop(car: Node2D) -> void:
	var floor_stops: Array = car.get_meta("floor_stops")
	var current_floor: int = car.get_meta("current_floor")

	if floor_stops.is_empty():
		car.set_meta("state", "idle")
		return

	# Pick closest floor
	var closest = floor_stops[0]
	var closest_dist = abs(closest - current_floor)
	for f in floor_stops:
		var dist = abs(f - current_floor)
		if dist < closest_dist:
			closest = f
			closest_dist = dist

	car.set_meta("target_floor", closest)
	car.set_meta("state", "moving")


func _elevator_check_for_work(car: Node2D) -> void:
	var shaft_x: int = car.get_meta("shaft_x")
	var current_floor: int = car.get_meta("current_floor")
	var passengers: Array = car.get_meta("passengers")
	var floor_stops: Array = car.get_meta("floor_stops")

	# First, board anyone waiting at current floor
	if passengers.size() < ELEVATOR_CAPACITY:
		_elevator_board_waiting(car, shaft_x, current_floor)

	# If we have stops, go to them
	if not floor_stops.is_empty():
		_elevator_pick_next_stop(car)
		return

	# Check if anyone is waiting at other floors
	if not waiting_queues.has(shaft_x):
		return

	var shaft = elevator_shafts[shaft_x]
	for floor_num in waiting_queues[shaft_x]:
		var queue: Array = waiting_queues[shaft_x][floor_num]
		if queue.size() > 0 and floor_num >= shaft.min_floor and floor_num <= shaft.max_floor:
			floor_stops.append(floor_num)
			_elevator_pick_next_stop(car)
			return


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(get_global_mouse_position())


func _handle_click(world_pos: Vector2) -> void:
	var build_mode = main.current_build_mode

	# Convert world position to grid position
	var grid_x: int = int(world_pos.x / TILE_WIDTH)
	var floor_num: int = -floori(world_pos.y / FLOOR_HEIGHT)  # floori for correct rounding with negative Y

	if build_mode == main.BuildMode.NONE:
		# Try to call an elevator
		_try_call_elevator(grid_x, floor_num)
		return

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
		offices.append({"floor": floor_num, "x": grid_x})
		_create_office_visual(grid_x, floor_num)
		main.change_population(4)  # Office adds 4 workers
		print("Built office at floor ", floor_num)


func _try_call_elevator(grid_x: int, floor_num: int) -> void:
	# Check if clicking within an elevator shaft (2 tiles wide)
	for shaft_x in elevator_shafts:
		var shaft = elevator_shafts[shaft_x]
		if grid_x >= shaft_x and grid_x < shaft_x + 2:
			if floor_num >= shaft.min_floor and floor_num <= shaft.max_floor:
				# Call the elevator to this floor
				if shaft.cars.size() > 0:
					var car = shaft.cars[0]  # Use first car for now
					var current = car.get_meta("current_floor")
					if current == floor_num:
						print("Elevator already at floor ", floor_num)
						return
					car.set_meta("target_floor", floor_num)
					car.set_meta("state", "moving")
					print("Elevator at floor ", current, " called to floor ", floor_num)
				return
			else:
				print("Click at floor ", floor_num, " outside shaft range [", shaft.min_floor, ", ", shaft.max_floor, "]")


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
	car.set_meta("floor_stops", [])  # floors to visit (passenger destinations + calls)
	car.set_meta("state", "idle")  # idle, moving
	
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


# ============ PERSON SYSTEM ============

func spawn_person() -> void:
	if offices.is_empty():
		print("No offices to go to")
		return
	if elevator_shafts.is_empty():
		print("No elevators")
		return

	# Pick random office as destination
	var office = offices[randi() % offices.size()]
	var dest_floor = office["floor"]
	var dest_x = office["x"]

	# Find an elevator shaft that can reach both lobby and destination
	var shaft_x = _find_usable_shaft(0, dest_floor)
	if shaft_x == -1:
		print("No elevator reaches floor ", dest_floor)
		return

	# Create person node
	var person = Node2D.new()
	person.name = "Person_" + str(randi())

	# Spawn at left side of lobby
	var spawn_x = 20.0
	person.position = Vector2(spawn_x, -0 * FLOOR_HEIGHT + FLOOR_HEIGHT - PERSON_SIZE)

	# Store state as metadata
	person.set_meta("state", PersonState.WALKING_TO_ELEVATOR)
	person.set_meta("current_floor", 0)
	person.set_meta("dest_floor", dest_floor)
	person.set_meta("dest_x", dest_x)
	person.set_meta("shaft_x", shaft_x)
	person.set_meta("elevator_car", null)

	# Visual - colored dot
	var dot = ColorRect.new()
	dot.size = Vector2(PERSON_SIZE, PERSON_SIZE)
	dot.position = Vector2(-PERSON_SIZE / 2, -PERSON_SIZE)
	dot.color = Color(randf_range(0.2, 0.8), randf_range(0.2, 0.8), randf_range(0.2, 0.8))
	person.add_child(dot)

	people.append(person)
	people_node.add_child(person)
	print("Person spawned, going to floor ", dest_floor)


func _find_usable_shaft(from_floor: int, to_floor: int) -> int:
	for shaft_x in elevator_shafts:
		var shaft = elevator_shafts[shaft_x]
		if shaft.min_floor <= from_floor and shaft.max_floor >= from_floor:
			if shaft.min_floor <= to_floor and shaft.max_floor >= to_floor:
				return shaft_x
	return -1


func _update_people(delta: float) -> void:
	for person in people:
		_update_person(person, delta)


func _update_person(person: Node2D, delta: float) -> void:
	var state = person.get_meta("state")

	match state:
		PersonState.WALKING_TO_ELEVATOR:
			_person_walk_to_elevator(person, delta)
		PersonState.WAITING:
			_person_wait_for_elevator(person, delta)
		PersonState.RIDING:
			_person_ride_elevator(person, delta)
		PersonState.WALKING_TO_OFFICE:
			_person_walk_to_office(person, delta)
		PersonState.AT_OFFICE:
			pass  # Done


func _person_walk_to_elevator(person: Node2D, delta: float) -> void:
	var shaft_x: int = person.get_meta("shaft_x")
	var current_floor: int = person.get_meta("current_floor")

	# Walk toward queue position
	var queue_index = _get_queue_index(person, shaft_x, current_floor)
	var target_x: float = shaft_x * TILE_WIDTH + TILE_WIDTH - (queue_index * QUEUE_SPACING)
	var current_x: float = person.position.x

	var distance = target_x - current_x
	var move_amount = PERSON_SPEED * delta

	if abs(distance) <= move_amount:
		person.position.x = target_x
		person.set_meta("state", PersonState.WAITING)
		# Add to waiting queue
		_add_to_waiting_queue(person, shaft_x, current_floor)
	else:
		person.position.x += sign(distance) * move_amount


func _get_queue_index(person: Node2D, shaft_x: int, floor_num: int) -> int:
	if not waiting_queues.has(shaft_x):
		return 0
	if not waiting_queues[shaft_x].has(floor_num):
		return 0
	return waiting_queues[shaft_x][floor_num].size()


func _add_to_waiting_queue(person: Node2D, shaft_x: int, floor_num: int) -> void:
	# Initialize queue structure if needed
	if not waiting_queues.has(shaft_x):
		waiting_queues[shaft_x] = {}
	if not waiting_queues[shaft_x].has(floor_num):
		waiting_queues[shaft_x][floor_num] = []

	var queue: Array = waiting_queues[shaft_x][floor_num]
	if person not in queue:
		queue.append(person)

	# Add this floor as a stop request
	if elevator_shafts.has(shaft_x):
		var shaft = elevator_shafts[shaft_x]
		if shaft.cars.size() > 0:
			var car = shaft.cars[0]
			var floor_stops: Array = car.get_meta("floor_stops")
			if floor_num not in floor_stops:
				floor_stops.append(floor_num)


func _update_queue_positions(shaft_x: int, floor_num: int) -> void:
	if not waiting_queues.has(shaft_x):
		return
	if not waiting_queues[shaft_x].has(floor_num):
		return

	var queue: Array = waiting_queues[shaft_x][floor_num]
	for i in range(queue.size()):
		var person = queue[i]
		var target_x = shaft_x * TILE_WIDTH + TILE_WIDTH - (i * QUEUE_SPACING)
		person.position.x = target_x


func _person_wait_for_elevator(person: Node2D, _delta: float) -> void:
	# Boarding is handled by _elevator_board_waiting when elevator arrives
	# Just keep queue position updated
	var shaft_x: int = person.get_meta("shaft_x")
	var current_floor: int = person.get_meta("current_floor")
	_update_queue_positions(shaft_x, current_floor)


func _person_ride_elevator(person: Node2D, _delta: float) -> void:
	var car = person.get_meta("elevator_car")
	if car == null:
		return

	# Move with elevator - exiting is handled by _elevator_handle_arrival
	var passengers: Array = car.get_meta("passengers")
	var idx = passengers.find(person)
	# Offset passengers so they don't stack
	var offset_x = (idx % 3) * PERSON_SIZE
	var offset_y = (idx / 3) * PERSON_SIZE

	person.position.x = car.position.x + TILE_WIDTH / 2 + offset_x
	person.position.y = car.position.y + FLOOR_HEIGHT - PERSON_SIZE - offset_y


func _person_walk_to_office(person: Node2D, delta: float) -> void:
	var dest_x: int = person.get_meta("dest_x")
	var target_x: float = dest_x * TILE_WIDTH + TILE_WIDTH * 2  # Center of 4-tile office
	var current_x: float = person.position.x

	var distance = target_x - current_x
	var move_amount = PERSON_SPEED * delta

	if abs(distance) <= move_amount:
		person.position.x = target_x
		person.set_meta("state", PersonState.AT_OFFICE)
		print("Person arrived at office")
	else:
		person.position.x += sign(distance) * move_amount
