extends CanvasLayer

@onready var money_label: Label = $TopBar/MoneyLabel
@onready var population_label: Label = $TopBar/PopulationLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var satisfaction_label: Label = $TopBar/SatisfactionLabel
@onready var floor_button: Button = $BuildPanel/FloorButton
@onready var elevator_button: Button = $BuildPanel/ElevatorButton
@onready var office_button: Button = $BuildPanel/OfficeButton
@onready var apartment_button: Button = $BuildPanel/ApartmentButton
@onready var retail_button: Button = $BuildPanel/RetailButton

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

	# Initial update
	_on_money_changed(main.money)
	_on_population_changed(main.population)
	_on_satisfaction_changed(1.0)  # Default to 100%


func _on_money_changed(amount: int) -> void:
	money_label.text = "$" + _format_number(amount)


func _on_population_changed(pop: int) -> void:
	population_label.text = "Population: " + str(pop)


func _on_time_changed(day: int, hour: float) -> void:
	var hour_int: int = int(hour)
	var minute_int: int = int((hour - hour_int) * 60)
	var am_pm: String = "AM" if hour_int < 12 else "PM"
	var display_hour: int = hour_int % 12
	if display_hour == 0:
		display_hour = 12
	
	time_label.text = "Day %d - %d:%02d %s" % [day, display_hour, minute_int, am_pm]


func _on_satisfaction_changed(satisfaction: float) -> void:
	# Convert to 5-star rating
	var stars = int(satisfaction * 5)
	var star_str = ""
	for i in range(5):
		if i < stars:
			star_str += "*"
		else:
			star_str += "."
	var percent = int(satisfaction * 100)
	satisfaction_label.text = "Rating: [%s] %d%%" % [star_str, percent]


func _on_build_mode_changed(mode: int) -> void:
	# Reset all button styles
	floor_button.button_pressed = false
	elevator_button.button_pressed = false
	office_button.button_pressed = false
	apartment_button.button_pressed = false
	retail_button.button_pressed = false

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
		5:  # RETAIL
			retail_button.button_pressed = true


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
