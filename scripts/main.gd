extends Node2D

# Game constants
const TILE_WIDTH: int = 32
const TILE_HEIGHT: int = 32
const FLOOR_HEIGHT: int = 48
const MAX_FLOORS: int = 100
const LOBBY_FLOOR: int = 0

# Game state
var money: int = 100000
var population: int = 0
var current_day: int = 1
var current_hour: float = 6.0  # 6:00 AM start
var game_speed: float = 1.0
var paused: bool = false
var last_rent_hour: int = -1  # Track when we last collected rent

# Economy
const RENT_PER_OFFICE: int = 1000  # Base daily rent per office
const RENT_PER_APARTMENT: int = 800  # Apartments pay slightly less
const RENT_PER_RETAIL: int = 1500  # Retail pays more but needs ground floor
const RENT_COLLECTION_HOUR: int = 9  # Collect rent at 9 AM

# Build mode
enum BuildMode { NONE, FLOOR, ELEVATOR, OFFICE, APARTMENT, RETAIL }
var current_build_mode: BuildMode = BuildMode.NONE

# References
@onready var building: Node2D = $Building
@onready var ui: CanvasLayer = $UI
@onready var camera: Camera2D = $Camera2D

# Signals
signal money_changed(new_amount: int)
signal population_changed(new_amount: int)
signal time_changed(day: int, hour: float)
signal build_mode_changed(mode: BuildMode)
signal satisfaction_changed(satisfaction: float)


func _ready() -> void:
	# Connect UI buttons
	_connect_ui_signals()

	# Connect to building signals
	building.satisfaction_changed.connect(_on_satisfaction_changed)

	# Initialize the lobby floor
	building.add_floor(LOBBY_FLOOR, true)

	print("Tower game initialized")


func _process(delta: float) -> void:
	if not paused:
		_update_game_time(delta)


func _connect_ui_signals() -> void:
	var floor_btn = $UI/BuildPanel/FloorButton
	var elevator_btn = $UI/BuildPanel/ElevatorButton
	var office_btn = $UI/BuildPanel/OfficeButton
	var apartment_btn = $UI/BuildPanel/ApartmentButton
	var retail_btn = $UI/BuildPanel/RetailButton
	var spawn_btn = $UI/BuildPanel/SpawnButton

	floor_btn.pressed.connect(_on_floor_button_pressed)
	elevator_btn.pressed.connect(_on_elevator_button_pressed)
	office_btn.pressed.connect(_on_office_button_pressed)
	apartment_btn.pressed.connect(_on_apartment_button_pressed)
	retail_btn.pressed.connect(_on_retail_button_pressed)
	spawn_btn.pressed.connect(_on_spawn_button_pressed)


func _update_game_time(delta: float) -> void:
	# 1 real second = 1 game minute at normal speed
	current_hour += (delta * game_speed) / 60.0

	if current_hour >= 24.0:
		current_hour -= 24.0
		current_day += 1
		last_rent_hour = -1  # Reset for new day

	# Collect rent at designated hour
	var hour_int = int(current_hour)
	if hour_int >= RENT_COLLECTION_HOUR and last_rent_hour < RENT_COLLECTION_HOUR:
		_collect_rent()
		last_rent_hour = hour_int

	time_changed.emit(current_day, current_hour)


func spend_money(amount: int) -> bool:
	if money >= amount:
		money -= amount
		money_changed.emit(money)
		return true
	return false


func earn_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func change_population(delta: int) -> void:
	population += delta
	population_changed.emit(population)


func set_build_mode(mode: BuildMode) -> void:
	current_build_mode = mode
	build_mode_changed.emit(mode)


func _on_floor_button_pressed() -> void:
	if current_build_mode == BuildMode.FLOOR:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.FLOOR)


func _on_elevator_button_pressed() -> void:
	if current_build_mode == BuildMode.ELEVATOR:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.ELEVATOR)


func _on_office_button_pressed() -> void:
	if current_build_mode == BuildMode.OFFICE:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.OFFICE)


func _on_apartment_button_pressed() -> void:
	if current_build_mode == BuildMode.APARTMENT:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.APARTMENT)


func _on_retail_button_pressed() -> void:
	if current_build_mode == BuildMode.RETAIL:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.RETAIL)


func _on_spawn_button_pressed() -> void:
	building.spawn_person()


func _on_satisfaction_changed(sat: float) -> void:
	satisfaction_changed.emit(sat)


func _collect_rent() -> void:
	var num_offices = building.offices.size()
	var num_apartments = building.apartments.size()
	var num_retail = building.retail.size()

	if num_offices == 0 and num_apartments == 0 and num_retail == 0:
		return

	var satisfaction = building.get_satisfaction()
	# Satisfaction affects rent: 50% at 0 satisfaction, 100% at full satisfaction
	var rent_multiplier = 0.5 + (satisfaction * 0.5)

	var office_rent = int(num_offices * RENT_PER_OFFICE * rent_multiplier)
	var apartment_rent = int(num_apartments * RENT_PER_APARTMENT * rent_multiplier)
	var retail_rent = int(num_retail * RENT_PER_RETAIL * rent_multiplier)
	var total_rent = office_rent + apartment_rent + retail_rent

	earn_money(total_rent)
	print("Collected rent: $", total_rent, " @ ", snapped(satisfaction * 100, 1), "% satisfaction")
