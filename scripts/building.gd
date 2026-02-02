extends Node2D

const FLOOR_WIDTH: int = 20  # tiles wide
const TILE_WIDTH: int = 32
const FLOOR_HEIGHT: int = 48
const ELEVATOR_SPEED: float = 200.0  # pixels per second
const PERSON_SPEED: float = 60.0  # pixels per second
const PERSON_SIZE: float = 8.0  # dot radius
const ELEVATOR_CAPACITY: int = 6
const QUEUE_SPACING: float = 10.0  # horizontal spacing between waiting people
const PATIENCE_MAX: float = 100.0
const PATIENCE_DECAY_RATE: float = 5.0  # per second while waiting

# Tenant type colors
const COLOR_OFFICE = Color(0.3, 0.5, 0.8)  # Blue
const COLOR_APARTMENT = Color(0.3, 0.7, 0.4)  # Green
const COLOR_RETAIL = Color(0.9, 0.6, 0.2)  # Orange

# Tenant types
enum TenantType { OFFICE, APARTMENT, RETAIL }

# Data structures
var floors: Dictionary = {}  # floor_number -> FloorData
var elevators: Array = []
var elevator_shafts: Dictionary = {}  # x_position -> ElevatorShaft
var offices: Array = []  # Array of {floor: int, x: int, type: TenantType}
var apartments: Array = []
var retail: Array = []
var people: Array = []  # Active person nodes
var waiting_queues: Dictionary = {}  # shaft_x -> {floor_num -> [person, ...]}

# Schedule tracking
var last_spawn_minute: int = -1

# Satisfaction tracking
var total_satisfaction: float = 0.0  # Sum of all completed trip satisfaction scores
var completed_trips: int = 0  # Number of completed trips
var angry_departures: int = 0  # People who left angry

signal satisfaction_changed(satisfaction: float)

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


enum PersonState {
	WALKING_TO_ELEVATOR,  # Walking toward elevator
	WAITING,              # Waiting for elevator
	RIDING,               # In elevator
	WALKING_TO_DEST,      # Walking to office/apartment/retail
	AT_DEST,              # At destination (working/home)
	WALKING_TO_EXIT,      # Walking to lobby exit
	LEAVING               # Angry, leaving building
}


func _ready() -> void:
	# Load scenes
	floor_scene = load("res://scenes/floor.tscn") if ResourceLoader.exists("res://scenes/floor.tscn") else null
	elevator_scene = load("res://scenes/elevator.tscn") if ResourceLoader.exists("res://scenes/elevator.tscn") else null
	person_scene = load("res://scenes/person.tscn") if ResourceLoader.exists("res://scenes/person.tscn") else null


func _process(delta: float) -> void:
	_update_elevators(delta)
	_update_people(delta)
	_update_schedules()


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
		p.set_meta("current_floor", floor_num)
		p.set_meta("elevator_car", null)
		p.position.y = -floor_num * FLOOR_HEIGHT + FLOOR_HEIGHT - PERSON_SIZE
		# Check if going to destination or exiting (lobby = exit)
		if floor_num == 0:
			p.set_meta("state", PersonState.WALKING_TO_EXIT)
		else:
			p.set_meta("state", PersonState.WALKING_TO_DEST)
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

	# Check if anyone is waiting at other floors - but only respond if we're the nearest idle car
	if not waiting_queues.has(shaft_x):
		return

	var shaft = elevator_shafts[shaft_x]
	for floor_num in waiting_queues[shaft_x]:
		var queue: Array = waiting_queues[shaft_x][floor_num]
		if queue.size() > 0 and floor_num >= shaft.min_floor and floor_num <= shaft.max_floor:
			# Check if we're the best car to respond
			if _is_best_car_for_floor(car, shaft, floor_num):
				floor_stops.append(floor_num)
				_elevator_pick_next_stop(car)
				return


func _is_best_car_for_floor(car: Node2D, shaft: ElevatorShaft, target_floor: int) -> bool:
	var my_floor: int = car.get_meta("current_floor")
	var my_distance = abs(my_floor - target_floor)

	for other_car in shaft.cars:
		if other_car == car:
			continue

		var other_state = other_car.get_meta("state")
		var other_floor: int = other_car.get_meta("current_floor")
		var other_stops: Array = other_car.get_meta("floor_stops")

		# If another car is already going to this floor, don't duplicate
		if target_floor in other_stops:
			return false

		# If another idle car is closer, let it handle this
		if other_state == "idle":
			var other_distance = abs(other_floor - target_floor)
			if other_distance < my_distance:
				return false
			# Tie-breaker: lower car index wins
			if other_distance == my_distance:
				if other_car.get_meta("car_index") < car.get_meta("car_index"):
					return false

	return true


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
		main.BuildMode.APARTMENT:
			_try_build_apartment(grid_x, floor_num)
		main.BuildMode.RETAIL:
			_try_build_retail(grid_x, floor_num)


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

	# Elevators are 2 tiles wide, must fit within floor bounds
	if grid_x < 0 or grid_x + 2 > FLOOR_WIDTH:
		print("Elevator out of bounds")
		return

	# Check if shaft exists at this x
	if elevator_shafts.has(grid_x):
		var shaft = elevator_shafts[grid_x]
		# If clicking within shaft range, add another car
		if floor_num >= shaft.min_floor and floor_num <= shaft.max_floor:
			if main.spend_money(10000):
				_create_elevator_car(grid_x, floor_num)
				_update_elevator_visual(grid_x)
				print("Added car to shaft (", shaft.cars.size(), " cars)")
		else:
			# Extend shaft range
			if floor_num < shaft.min_floor:
				shaft.min_floor = floor_num
			elif floor_num > shaft.max_floor:
				shaft.max_floor = floor_num
			_update_elevator_visual(grid_x)
			print("Extended shaft to floor ", floor_num)
	else:
		# Create new shaft
		if main.spend_money(20000):
			var shaft = ElevatorShaft.new()
			shaft.x_position = grid_x
			shaft.min_floor = floor_num
			shaft.max_floor = floor_num
			elevator_shafts[grid_x] = shaft
			_create_elevator_car(grid_x, floor_num)
			_update_elevator_visual(grid_x)
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
		_create_tenant_visual(grid_x, floor_num, COLOR_OFFICE)
		main.change_population(4)
		print("Built office at floor ", floor_num)


func _try_build_apartment(grid_x: int, floor_num: int) -> void:
	if not floors.has(floor_num):
		print("Need a floor first")
		return

	if floors[floor_num].is_lobby:
		print("Can't build apartment in lobby")
		return

	if grid_x < 0 or grid_x + 4 > FLOOR_WIDTH:
		print("Out of bounds")
		return

	var floor_data = floors[floor_num]
	for i in range(4):
		if floor_data.tiles[grid_x + i] != "empty":
			print("Space occupied")
			return

	if main.spend_money(15000):
		for i in range(4):
			floor_data.tiles[grid_x + i] = "apartment"
		apartments.append({"floor": floor_num, "x": grid_x})
		_create_tenant_visual(grid_x, floor_num, COLOR_APARTMENT)
		main.change_population(2)  # Apartment has 2 residents
		print("Built apartment at floor ", floor_num)


func _try_build_retail(grid_x: int, floor_num: int) -> void:
	if not floors.has(floor_num):
		print("Need a floor first")
		return

	# Retail must be on lobby or floor 1
	if floor_num > 1:
		print("Retail must be on lobby or floor 1")
		return

	if grid_x < 0 or grid_x + 4 > FLOOR_WIDTH:
		print("Out of bounds")
		return

	var floor_data = floors[floor_num]
	for i in range(4):
		if floor_data.tiles[grid_x + i] != "empty":
			print("Space occupied")
			return

	if main.spend_money(25000):
		for i in range(4):
			floor_data.tiles[grid_x + i] = "retail"
		retail.append({"floor": floor_num, "x": grid_x})
		_create_tenant_visual(grid_x, floor_num, COLOR_RETAIL)
		print("Built retail at floor ", floor_num)


func _try_call_elevator(grid_x: int, floor_num: int) -> void:
	# Check if clicking within an elevator shaft (2 tiles wide)
	for shaft_x in elevator_shafts:
		var shaft = elevator_shafts[shaft_x]
		if grid_x >= shaft_x and grid_x < shaft_x + 2:
			if floor_num >= shaft.min_floor and floor_num <= shaft.max_floor:
				# Check if any car is already at this floor
				for car in shaft.cars:
					if car.get_meta("current_floor") == floor_num:
						print("Elevator already at floor ", floor_num)
						return

				# Find best car to respond
				var best_car = _find_best_car_for_floor(shaft, floor_num)
				if best_car:
					var floor_stops: Array = best_car.get_meta("floor_stops")
					if floor_num not in floor_stops:
						floor_stops.append(floor_num)
					var current = best_car.get_meta("current_floor")
					print("Car ", best_car.get_meta("car_index") + 1, " called to floor ", floor_num)
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
	var car_index = shaft.cars.size()

	var car = Node2D.new()
	car.name = "ElevatorCar_" + str(shaft_x) + "_" + str(car_index)
	car.set_meta("shaft_x", shaft_x)
	car.set_meta("car_index", car_index)
	car.set_meta("current_floor", floor_num)
	car.set_meta("target_floor", floor_num)
	car.set_meta("passengers", [])
	car.set_meta("floor_stops", [])
	car.set_meta("state", "idle")

	car.position = Vector2(shaft_x * TILE_WIDTH, -floor_num * FLOOR_HEIGHT)

	# Visual - car body
	var rect = ColorRect.new()
	rect.size = Vector2(TILE_WIDTH * 2, FLOOR_HEIGHT - 4)
	rect.position = Vector2(0, 2)
	# Different color tint per car
	var hue = fmod(car_index * 0.15, 1.0)
	rect.color = Color.from_hsv(hue, 0.3, 0.5)
	car.add_child(rect)

	# Car number label
	var label = Label.new()
	label.text = str(car_index + 1)
	label.position = Vector2(TILE_WIDTH - 8, 15)
	label.add_theme_color_override("font_color", Color.WHITE)
	car.add_child(label)

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

	# Car count indicator at top of shaft
	var count_label = Label.new()
	count_label.text = str(shaft.cars.size()) + " cars"
	count_label.position = Vector2(shaft_x * TILE_WIDTH, -shaft.max_floor * FLOOR_HEIGHT - 20)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_font_size_override("font_size", 12)
	shaft_visual.add_child(count_label)

	elevators_node.add_child(shaft_visual)
	elevators_node.move_child(shaft_visual, 0)  # Behind cars


func _create_tenant_visual(grid_x: int, floor_num: int, color: Color) -> void:
	var floor_node = floors_node.get_node("Floor_" + str(floor_num))
	if not floor_node:
		return

	var tenant = ColorRect.new()
	tenant.size = Vector2(TILE_WIDTH * 4 - 4, FLOOR_HEIGHT - 8)
	tenant.position = Vector2(grid_x * TILE_WIDTH + 2, 4)
	tenant.color = color
	floor_node.add_child(tenant)


func get_floor_y(floor_num: int) -> float:
	return -floor_num * FLOOR_HEIGHT


# ============ PERSON SYSTEM ============

func _update_schedules() -> void:
	var hour = main.current_hour
	var minute = int((hour - int(hour)) * 60)
	var current_minute = int(hour) * 60 + minute

	# Only spawn once per game minute
	if current_minute == last_spawn_minute:
		return
	last_spawn_minute = current_minute

	var hour_int = int(hour)

	# Office workers ARRIVE 8-9am
	if hour_int >= 8 and hour_int < 9:
		for office in offices:
			if randf() < 0.1:  # 10% chance per minute per office
				_spawn_office_worker(office, true)  # arriving

	# Office workers LEAVE 5-6pm
	if hour_int >= 17 and hour_int < 18:
		_trigger_office_departure()

	# Apartment residents LEAVE 7-9am
	if hour_int >= 7 and hour_int < 9:
		_trigger_apartment_departure()

	# Apartment residents RETURN 6-9pm
	if hour_int >= 18 and hour_int < 21:
		for apt in apartments:
			if randf() < 0.08:  # 8% chance per minute
				_spawn_apartment_resident(apt, true)  # returning home

	# Retail customers throughout day, peak at lunch
	if hour_int >= 10 and hour_int < 20:
		var retail_chance = 0.05
		if hour_int >= 11 and hour_int < 14:  # Lunch peak
			retail_chance = 0.15
		for shop in retail:
			if randf() < retail_chance:
				_spawn_retail_customer(shop)


func _spawn_office_worker(office: Dictionary, arriving: bool) -> void:
	if elevator_shafts.is_empty():
		return

	var dest_floor = office["floor"]
	var dest_x = office["x"]

	var shaft_x = _find_usable_shaft(0, dest_floor)
	if shaft_x == -1:
		return

	var person = _create_person(COLOR_OFFICE, TenantType.OFFICE)
	person.set_meta("home_floor", 0)  # Workers come from outside
	person.set_meta("work_floor", dest_floor)
	person.set_meta("dest_floor", dest_floor)
	person.set_meta("dest_x", dest_x)
	person.set_meta("shaft_x", shaft_x)

	# Spawn at lobby entrance
	person.position = Vector2(20.0, FLOOR_HEIGHT - PERSON_SIZE)
	person.set_meta("current_floor", 0)
	person.set_meta("state", PersonState.WALKING_TO_ELEVATOR)


func _spawn_apartment_resident(apt: Dictionary, returning: bool) -> void:
	if elevator_shafts.is_empty():
		return

	var apt_floor = apt["floor"]
	var apt_x = apt["x"]

	var shaft_x = _find_usable_shaft(0, apt_floor)
	if shaft_x == -1:
		return

	var person = _create_person(COLOR_APARTMENT, TenantType.APARTMENT)
	person.set_meta("home_floor", apt_floor)
	person.set_meta("home_x", apt_x)
	person.set_meta("dest_floor", apt_floor)
	person.set_meta("dest_x", apt_x)
	person.set_meta("shaft_x", shaft_x)

	# Spawn at lobby entrance (returning home)
	person.position = Vector2(20.0, FLOOR_HEIGHT - PERSON_SIZE)
	person.set_meta("current_floor", 0)
	person.set_meta("state", PersonState.WALKING_TO_ELEVATOR)


func _spawn_retail_customer(shop: Dictionary) -> void:
	if elevator_shafts.is_empty():
		return

	var shop_floor = shop["floor"]
	var shop_x = shop["x"]

	# Retail on lobby doesn't need elevator
	if shop_floor == 0:
		var person = _create_person(COLOR_RETAIL, TenantType.RETAIL)
		person.set_meta("dest_floor", 0)
		person.set_meta("dest_x", shop_x)
		person.set_meta("shaft_x", -1)
		person.position = Vector2(20.0, FLOOR_HEIGHT - PERSON_SIZE)
		person.set_meta("current_floor", 0)
		person.set_meta("state", PersonState.WALKING_TO_DEST)
		return

	var shaft_x = _find_usable_shaft(0, shop_floor)
	if shaft_x == -1:
		return

	var person = _create_person(COLOR_RETAIL, TenantType.RETAIL)
	person.set_meta("dest_floor", shop_floor)
	person.set_meta("dest_x", shop_x)
	person.set_meta("shaft_x", shaft_x)
	person.position = Vector2(20.0, FLOOR_HEIGHT - PERSON_SIZE)
	person.set_meta("current_floor", 0)
	person.set_meta("state", PersonState.WALKING_TO_ELEVATOR)


func _trigger_office_departure() -> void:
	# Find workers at their desks and send them home
	for person in people:
		if person.get_meta("state") == PersonState.AT_DEST:
			if person.get_meta("tenant_type") == TenantType.OFFICE:
				if randf() < 0.1:  # 10% chance per minute
					_send_person_to_lobby(person)


func _trigger_apartment_departure() -> void:
	# Find residents at home and send them out
	for person in people:
		if person.get_meta("state") == PersonState.AT_DEST:
			if person.get_meta("tenant_type") == TenantType.APARTMENT:
				if randf() < 0.08:
					_send_person_to_lobby(person)


func _send_person_to_lobby(person: Node2D) -> void:
	var current_floor = person.get_meta("current_floor")
	if current_floor == 0:
		person.set_meta("state", PersonState.WALKING_TO_EXIT)
		return

	var shaft_x = _find_usable_shaft(current_floor, 0)
	if shaft_x == -1:
		return

	person.set_meta("dest_floor", 0)
	person.set_meta("shaft_x", shaft_x)
	person.set_meta("patience", PATIENCE_MAX)  # Reset patience
	person.set_meta("state", PersonState.WALKING_TO_ELEVATOR)


func _create_person(color: Color, tenant_type: TenantType) -> Node2D:
	var person = Node2D.new()
	person.name = "Person_" + str(randi())

	person.set_meta("tenant_type", tenant_type)
	person.set_meta("elevator_car", null)
	person.set_meta("patience", PATIENCE_MAX)

	var dot = ColorRect.new()
	dot.name = "Dot"
	dot.size = Vector2(PERSON_SIZE, PERSON_SIZE)
	dot.position = Vector2(-PERSON_SIZE / 2, -PERSON_SIZE)
	dot.color = color
	person.set_meta("original_color", color)
	person.add_child(dot)

	people.append(person)
	people_node.add_child(person)
	return person


# Legacy spawn for testing
func spawn_person() -> void:
	if offices.size() > 0:
		_spawn_office_worker(offices[randi() % offices.size()], true)
	elif apartments.size() > 0:
		_spawn_apartment_resident(apartments[randi() % apartments.size()], true)
	elif retail.size() > 0:
		_spawn_retail_customer(retail[randi() % retail.size()])
	else:
		print("No tenants to spawn")


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
		PersonState.WALKING_TO_DEST:
			_person_walk_to_dest(person, delta)
		PersonState.AT_DEST:
			pass  # At destination, waiting for schedule
		PersonState.WALKING_TO_EXIT:
			_person_walk_to_exit(person, delta)
		PersonState.LEAVING:
			_person_leave_building(person, delta)


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

	# Smart dispatch: find the best car to respond
	if elevator_shafts.has(shaft_x):
		var shaft = elevator_shafts[shaft_x]
		var best_car = _find_best_car_for_floor(shaft, floor_num)
		if best_car:
			var floor_stops: Array = best_car.get_meta("floor_stops")
			if floor_num not in floor_stops:
				floor_stops.append(floor_num)


func _find_best_car_for_floor(shaft: ElevatorShaft, target_floor: int) -> Node2D:
	var best_car: Node2D = null
	var best_distance: int = 9999

	for car in shaft.cars:
		var car_floor: int = car.get_meta("current_floor")
		var car_state = car.get_meta("state")
		var floor_stops: Array = car.get_meta("floor_stops")

		# Skip if already assigned to this floor
		if target_floor in floor_stops:
			return null  # Someone's already handling it

		var distance = abs(car_floor - target_floor)

		# Prefer idle cars
		if car_state == "idle":
			if distance < best_distance:
				best_distance = distance
				best_car = car
		# Or cars already moving toward this floor
		elif car_state == "moving":
			var target = car.get_meta("target_floor")
			# If car is passing by this floor on its way
			if (car_floor < target_floor and target_floor < target) or \
			   (car_floor > target_floor and target_floor > target):
				if distance < best_distance:
					best_distance = distance
					best_car = car

	return best_car


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


func _person_wait_for_elevator(person: Node2D, delta: float) -> void:
	var shaft_x: int = person.get_meta("shaft_x")
	var current_floor: int = person.get_meta("current_floor")

	# Decay patience while waiting
	var patience: float = person.get_meta("patience")
	patience -= PATIENCE_DECAY_RATE * delta
	person.set_meta("patience", patience)

	# Update color based on patience (fade to red as patience decreases)
	var dot = person.get_node("Dot")
	var original_color: Color = person.get_meta("original_color")
	var anger_ratio = 1.0 - (patience / PATIENCE_MAX)
	dot.color = original_color.lerp(Color.RED, anger_ratio)

	# Check if patience ran out
	if patience <= 0:
		_person_become_angry(person, shaft_x, current_floor)
		return

	# Keep queue position updated
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


func _person_walk_to_dest(person: Node2D, delta: float) -> void:
	var dest_x: int = person.get_meta("dest_x")
	var target_x: float = dest_x * TILE_WIDTH + TILE_WIDTH * 2  # Center of 4-tile unit
	var current_x: float = person.position.x

	var distance = target_x - current_x
	var move_amount = PERSON_SPEED * delta

	if abs(distance) <= move_amount:
		person.position.x = target_x
		person.set_meta("state", PersonState.AT_DEST)
		# Record satisfaction based on remaining patience
		var patience: float = person.get_meta("patience")
		var trip_satisfaction = patience / PATIENCE_MAX  # 0.0 to 1.0
		_record_satisfaction(trip_satisfaction)
		var tenant_type = person.get_meta("tenant_type")
		print("Person arrived at destination (satisfaction: ", snapped(trip_satisfaction * 100, 1), "%)")
	else:
		person.position.x += sign(distance) * move_amount


func _person_walk_to_exit(person: Node2D, delta: float) -> void:
	# Walk to left side of lobby then remove
	var target_x: float = -50.0
	var current_x: float = person.position.x

	var distance = target_x - current_x
	var move_amount = PERSON_SPEED * delta

	if abs(distance) <= move_amount:
		# Record satisfaction for completed trip
		var patience: float = person.get_meta("patience")
		var trip_satisfaction = patience / PATIENCE_MAX
		_record_satisfaction(trip_satisfaction)
		_remove_person(person)
	else:
		person.position.x += sign(distance) * move_amount


func _person_become_angry(person: Node2D, shaft_x: int, floor_num: int) -> void:
	# Remove from waiting queue
	if waiting_queues.has(shaft_x) and waiting_queues[shaft_x].has(floor_num):
		var queue: Array = waiting_queues[shaft_x][floor_num]
		queue.erase(person)
		_update_queue_positions(shaft_x, floor_num)

	# Turn bright red and start leaving
	var dot = person.get_node("Dot")
	dot.color = Color(1.0, 0.0, 0.0)  # Bright red
	person.set_meta("state", PersonState.LEAVING)

	# Record as angry departure (0% satisfaction)
	angry_departures += 1
	_record_satisfaction(0.0)
	print("Person got angry and is leaving!")


func _person_leave_building(person: Node2D, delta: float) -> void:
	# Walk back to the left edge of the building and disappear
	var target_x: float = -50.0  # Off screen to the left
	var current_x: float = person.position.x

	var distance = target_x - current_x
	var move_amount = PERSON_SPEED * delta

	if abs(distance) <= move_amount:
		# Remove person from the game
		_remove_person(person)
	else:
		person.position.x += sign(distance) * move_amount


func _remove_person(person: Node2D) -> void:
	people.erase(person)
	person.queue_free()


func _record_satisfaction(trip_satisfaction: float) -> void:
	total_satisfaction += trip_satisfaction
	completed_trips += 1
	satisfaction_changed.emit(get_satisfaction())


func get_satisfaction() -> float:
	if completed_trips == 0:
		return 1.0  # Default to 100% if no trips yet
	return total_satisfaction / completed_trips
