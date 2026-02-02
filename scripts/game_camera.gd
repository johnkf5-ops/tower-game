extends Camera2D

const PAN_SPEED: float = 500.0
const ZOOM_SPEED: float = 0.1
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 2.0

var dragging: bool = false
var drag_start: Vector2


func _ready() -> void:
	# Center on lobby area
	position = Vector2(320, 200)
	zoom = Vector2(1.0, 1.0)

	# Disable camera limits to allow free scrolling (use max int values)
	limit_top = -10000000
	limit_bottom = 10000000
	limit_left = -10000000
	limit_right = 10000000
	limit_smoothed = false


func _input(event: InputEvent) -> void:
	# Middle mouse or right mouse to drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			drag_start = event.position
		
		# Scroll to zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(ZOOM_SPEED)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(-ZOOM_SPEED)
	
	# Drag to pan
	if event is InputEventMouseMotion and dragging:
		var delta = event.position - drag_start
		position -= delta / zoom
		drag_start = event.position


func _process(delta: float) -> void:
	# Arrow keys to pan
	var pan_input = Vector2.ZERO
	
	if Input.is_action_pressed("ui_left"):
		pan_input.x -= 1
	if Input.is_action_pressed("ui_right"):
		pan_input.x += 1
	if Input.is_action_pressed("ui_up"):
		pan_input.y -= 1
	if Input.is_action_pressed("ui_down"):
		pan_input.y += 1
	
	if pan_input != Vector2.ZERO:
		position += pan_input.normalized() * PAN_SPEED * delta / zoom.x


func _zoom_camera(amount: float) -> void:
	var new_zoom = clamp(zoom.x + amount, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
