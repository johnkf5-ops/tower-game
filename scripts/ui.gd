extends CanvasLayer

@onready var money_label: Label = $TopBar/MoneyLabel
@onready var population_label: Label = $TopBar/PopulationLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var satisfaction_label: Label = $TopBar/SatisfactionLabel
@onready var star_label: Label = $TopBar/StarLabel
@onready var floor_button: Button = $BuildPanel/FloorButton
@onready var elevator_button: Button = $BuildPanel/ElevatorButton
@onready var office_button: Button = $BuildPanel/OfficeButton
@onready var apartment_button: Button = $BuildPanel/ApartmentButton
@onready var coworking_button: Button = $BuildPanel/CoworkingButton
@onready var food_court_button: Button = $BuildPanel/FoodCourtButton
@onready var rent_popup: Panel = $RentPopup
@onready var rent_label: Label = $RentPopup/RentLabel

var main: Node2D


func _ready() -> void:
	# Get reference to main after tree is ready
	await get_tree().process_frame
	main = get_parent()
	
	# Connect to signals
	main.money_changed.connect(_on_money_changed)
	main.population_changed.connect(_on_population_changed)
	main.time_changed.connect(_on_time_changed)
	main.build_mode_changed.connect(_on_build_mode_changed)
	main.satisfaction_changed.connect(_on_satisfaction_changed)
	main.star_level_changed.connect(_on_star_level_changed)
	main.rent_collected.connect(_on_rent_collected)

	# Initial update
	_on_money_changed(main.money)
	_on_population_changed(main.population)
	_on_satisfaction_changed(1.0)  # Default to 100%
	_update_star_display()

	# Hide rent popup initially
	rent_popup.visible = false


func _on_money_changed(amount: int) -> void:
	money_label.text = "$" + _format_number(amount)


func _on_population_changed(pop: int) -> void:
	population_label.text = "Pop: " + _format_number(pop)
	_update_star_display()


func _on_time_changed(day: int, hour: float) -> void:
	var hour_int: int = int(hour)
	var minute_int: int = int((hour - hour_int) * 60)
	var am_pm: String = "AM" if hour_int < 12 else "PM"
	var display_hour: int = hour_int % 12
	if display_hour == 0:
		display_hour = 12
	
	time_label.text = "Day %d - %d:%02d %s" % [day, display_hour, minute_int, am_pm]


func _on_satisfaction_changed(satisfaction: float) -> void:
	# Show satisfaction percentage
	var percent = int(satisfaction * 100)
	satisfaction_label.text = "Satisfaction: %d%%" % percent


func _on_star_level_changed(_new_level: int, star_name: String) -> void:
	_update_star_display()
	# Could show a popup/notification here
	print("UI: Star level changed to ", star_name)


func _update_star_display() -> void:
	if main == null:
		return

	var star_level = main.current_star_level
	var star_name = main.STAR_NAMES[star_level - 1]
	var progress = main.get_population_progress()
	var next_threshold = main.get_next_star_threshold()

	# Build star display string
	var star_str = ""
	for i in range(5):
		if i < star_level:
			star_str += "*"
		else:
			star_str += "."

	# Show TOWER if at max level
	if star_level >= 6:
		star_label.text = "TOWER [*****]"
	else:
		var progress_percent = int(progress * 100)
		star_label.text = "[%s] -> %s (%d%%)" % [star_str, _format_number(next_threshold), progress_percent]

	# Update button states based on unlocks
	_update_unlock_states()


func _on_build_mode_changed(mode: int) -> void:
	# Reset all button styles
	floor_button.button_pressed = false
	elevator_button.button_pressed = false
	office_button.button_pressed = false
	apartment_button.button_pressed = false
	coworking_button.button_pressed = false
	food_court_button.button_pressed = false

	# Highlight active mode
	match mode:
		1:  # FLOOR
			floor_button.button_pressed = true
		2:  # ELEVATOR
			elevator_button.button_pressed = true
		3:  # OFFICE
			office_button.button_pressed = true
		4:  # APARTMENT
			apartment_button.button_pressed = true
		5:  # COWORKING
			coworking_button.button_pressed = true
		6:  # FOOD_COURT
			food_court_button.button_pressed = true


func _update_unlock_states() -> void:
	if main == null:
		return

	# All 1-star buildings are available from start
	# Office
	office_button.disabled = false
	office_button.text = "Office ($10k) +6 workers"

	# Apartment
	apartment_button.disabled = false
	apartment_button.text = "Apartment ($15k) +4 residents"

	# Coworking
	coworking_button.disabled = false
	coworking_button.text = "Coworking ($8k) +10 workers"

	# Food Court
	food_court_button.disabled = false
	food_court_button.text = "Food Court ($12k) Lobby/F1"


func _on_rent_collected(total: int, breakdown: Dictionary) -> void:
	# Show rent popup
	var text = "Daily Rent Collected: $%s\n\n" % _format_number(total)
	if breakdown["offices"] > 0:
		text += "Offices: $%s\n" % _format_number(breakdown["offices"])
	if breakdown["apartments"] > 0:
		text += "Apartments: $%s\n" % _format_number(breakdown["apartments"])
	if breakdown["coworking"] > 0:
		text += "Coworking: $%s\n" % _format_number(breakdown["coworking"])
	if breakdown["food_courts"] > 0:
		text += "Food Courts: $%s\n" % _format_number(breakdown["food_courts"])

	rent_label.text = text
	rent_popup.visible = true

	# Hide after 3 seconds
	await get_tree().create_timer(3.0).timeout
	rent_popup.visible = false


func _format_number(num: int) -> String:
	var str_num = str(num)
	var result = ""
	var count = 0

	for i in range(str_num.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_num[i] + result
		count += 1

	return result
