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

# Build mode
enum BuildMode { NONE, FLOOR, ELEVATOR, OFFICE }
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


func _ready() -> void:
	# Connect UI buttons
	_connect_ui_signals()
	
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
	
	floor_btn.pressed.connect(_on_floor_button_pressed)
	elevator_btn.pressed.connect(_on_elevator_button_pressed)
	office_btn.pressed.connect(_on_office_button_pressed)


func _update_game_time(delta: float) -> void:
	# 1 real second = 1 game minute at normal speed
	current_hour += (delta * game_speed) / 60.0
	
	if current_hour >= 24.0:
		current_hour -= 24.0
		current_day += 1
	
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
