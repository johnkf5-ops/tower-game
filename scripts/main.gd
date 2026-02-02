extends Node2D

# Game constants
const TILE_WIDTH: int = 32
const TILE_HEIGHT: int = 32
const FLOOR_HEIGHT: int = 48
const MAX_FLOORS: int = 100
const LOBBY_FLOOR: int = 0

# Star rating thresholds (population required)
const STAR_THRESHOLDS: Array = [0, 1000, 5000, 25000, 50000, 100000]
const STAR_NAMES: Array = ["1 Star", "2 Stars", "3 Stars", "4 Stars", "5 Stars", "TOWER"]

# Unlock requirements (star level required for each feature)
const UNLOCKS: Dictionary = {
	"floor": 1,        # Available from start
	"elevator": 1,     # Available from start
	"office": 1,       # Available from start
	"apartment": 1,    # Available from start
	"coworking": 1,    # Available from start
	"food_court": 1,   # Available from start
	"restaurant": 2,   # Unlocks at 2 stars (1000 pop)
	"hotel": 3,        # Unlocks at 3 stars (5000 pop)
	"cinema": 4,       # Unlocks at 4 stars (25000 pop)
	"parking": 4,      # Unlocks at 4 stars (25000 pop)
	"cathedral": 5,    # Unlocks at 5 stars (50000 pop)
}

# Game state
var money: int = 100000
var population: int = 0
var current_day: int = 1
var current_hour: float = 6.0  # 6:00 AM start
var game_speed: float = 1.0
var paused: bool = false
var last_rent_hour: int = -1  # Track when we last collected rent

# Star rating state
var current_star_level: int = 1  # 1-6 (6 = TOWER)
var vip_visit_pending: bool = false
var vip_visits_completed: int = 0

# Economy - rent collected at midnight
const RENT_PER_OFFICE: int = 1000
const RENT_PER_APARTMENT: int = 500
const RENT_PER_COWORKING: int = 600
const RENT_PER_FOOD_COURT: int = 1500
const RENT_COLLECTION_HOUR: int = 0  # Collect rent at midnight

# Build mode
enum BuildMode { NONE, FLOOR, ELEVATOR, OFFICE, APARTMENT, COWORKING, FOOD_COURT }
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
signal star_level_changed(new_level: int, star_name: String)
signal unlock_available(feature_name: String)
signal rent_collected(total: int, breakdown: Dictionary)


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
	var coworking_btn = $UI/BuildPanel/CoworkingButton
	var food_court_btn = $UI/BuildPanel/FoodCourtButton
	var spawn_btn = $UI/BuildPanel/SpawnButton
	var vip_btn = $UI/BuildPanel/VIPButton

	floor_btn.pressed.connect(_on_floor_button_pressed)
	elevator_btn.pressed.connect(_on_elevator_button_pressed)
	office_btn.pressed.connect(_on_office_button_pressed)
	apartment_btn.pressed.connect(_on_apartment_button_pressed)
	coworking_btn.pressed.connect(_on_coworking_button_pressed)
	food_court_btn.pressed.connect(_on_food_court_button_pressed)
	spawn_btn.pressed.connect(_on_spawn_button_pressed)
	vip_btn.pressed.connect(_on_vip_button_pressed)


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
	_check_star_upgrade()


func _check_star_upgrade() -> void:
	# Check if we've reached the threshold for the next star level
	if current_star_level >= STAR_THRESHOLDS.size():
		return  # Already at max (TOWER)

	var next_threshold = STAR_THRESHOLDS[current_star_level]
	if population >= next_threshold:
		# Ready for upgrade - in original SimTower, VIP visit triggers it
		if not vip_visit_pending:
			vip_visit_pending = true
			print("VIP visit pending! Population threshold reached for ", STAR_NAMES[current_star_level])


func trigger_vip_visit() -> void:
	# Called when VIP arrives and approves the tower
	if vip_visit_pending:
		vip_visit_pending = false
		current_star_level += 1
		vip_visits_completed += 1

		var star_name = STAR_NAMES[current_star_level - 1]
		star_level_changed.emit(current_star_level, star_name)
		print("Congratulations! Tower upgraded to ", star_name)

		# Check for new unlocks
		for feature in UNLOCKS:
			if UNLOCKS[feature] == current_star_level:
				unlock_available.emit(feature)
				print("New feature unlocked: ", feature)


func is_feature_unlocked(feature_name: String) -> bool:
	if not UNLOCKS.has(feature_name):
		return true  # Unknown features are allowed
	return current_star_level >= UNLOCKS[feature_name]


func get_unlock_star_level(feature_name: String) -> int:
	if UNLOCKS.has(feature_name):
		return UNLOCKS[feature_name]
	return 1


func get_population_progress() -> float:
	# Returns 0.0 to 1.0 progress toward next star level
	if current_star_level >= STAR_THRESHOLDS.size():
		return 1.0  # Max level

	var current_threshold = STAR_THRESHOLDS[current_star_level - 1]
	var next_threshold = STAR_THRESHOLDS[current_star_level]
	var range_size = next_threshold - current_threshold

	if range_size <= 0:
		return 1.0

	var progress = float(population - current_threshold) / float(range_size)
	return clamp(progress, 0.0, 1.0)


func get_next_star_threshold() -> int:
	if current_star_level >= STAR_THRESHOLDS.size():
		return population  # Already at max
	return STAR_THRESHOLDS[current_star_level]


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


func _on_coworking_button_pressed() -> void:
	if current_build_mode == BuildMode.COWORKING:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.COWORKING)


func _on_food_court_button_pressed() -> void:
	if current_build_mode == BuildMode.FOOD_COURT:
		set_build_mode(BuildMode.NONE)
	else:
		set_build_mode(BuildMode.FOOD_COURT)


func _on_spawn_button_pressed() -> void:
	building.spawn_person()


func _on_vip_button_pressed() -> void:
	if vip_visit_pending:
		trigger_vip_visit()
	else:
		print("No VIP visit pending - need to reach population threshold first")


func _on_satisfaction_changed(sat: float) -> void:
	satisfaction_changed.emit(sat)


func _collect_rent() -> void:
	var num_offices = building.offices.size()
	var num_apartments = building.apartments.size()
	var num_coworking = building.coworking.size()
	var num_food_courts = building.food_courts.size()

	if num_offices == 0 and num_apartments == 0 and num_coworking == 0 and num_food_courts == 0:
		return

	var satisfaction = building.get_satisfaction()
	# Satisfaction affects rent: 50% at 0 satisfaction, 100% at full satisfaction
	var rent_multiplier = 0.5 + (satisfaction * 0.5)

	var office_rent = int(num_offices * RENT_PER_OFFICE * rent_multiplier)
	var apartment_rent = int(num_apartments * RENT_PER_APARTMENT * rent_multiplier)
	var coworking_rent = int(num_coworking * RENT_PER_COWORKING * rent_multiplier)
	var food_court_rent = int(num_food_courts * RENT_PER_FOOD_COURT * rent_multiplier)
	var total_rent = office_rent + apartment_rent + coworking_rent + food_court_rent

	earn_money(total_rent)

	# Show rent summary popup
	rent_collected.emit(total_rent, {
		"offices": office_rent,
		"apartments": apartment_rent,
		"coworking": coworking_rent,
		"food_courts": food_court_rent
	})
	print("Daily rent collected: $", total_rent)
