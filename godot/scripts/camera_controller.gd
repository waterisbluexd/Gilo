extends Camera3D

@export var move_speed: float = 18.0
@export var zoom_step: float = 1.12
@export var min_zoom: float = 6.0
@export var max_zoom: float = 48.0
@export var fallback_focus_distance: float = 70.0

var _orbit_target: Vector3
var _orbit_distance: float
var _yaw: float
var _pitch: float
var _middle_dragging := false


func _ready() -> void:
	set_process_input(true)

	var forward := -global_basis.z.normalized()
	var target_distance := fallback_focus_distance
	if absf(forward.y) > 0.001:
		var ground_distance := -global_position.y / forward.y
		if ground_distance > 0.0:
			target_distance = ground_distance

	_orbit_target = global_position + forward * target_distance
	_orbit_target.y = 0.0

	var offset := global_position - _orbit_target
	_orbit_distance = maxf(offset.length(), 0.1)
	_yaw = atan2(offset.x, offset.z)
	_pitch = asin(clampf(offset.y / _orbit_distance, -0.95, 0.95))
	_apply_orbit_pose()


func _process(delta: float) -> void:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := global_basis.x
	right.y = 0.0
	right = right.normalized()

	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		movement += forward
	if Input.is_key_pressed(KEY_S):
		movement -= forward
	if Input.is_key_pressed(KEY_D):
		movement += right
	if Input.is_key_pressed(KEY_A):
		movement -= right

	if movement.length_squared() > 0.0:
		movement = movement.normalized()
		_orbit_target += movement * move_speed * (size / 18.0) * delta

	if movement.length_squared() > 0.0:
		_apply_orbit_pose()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_dragging = mouse_button.pressed
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = maxf(min_zoom, size / zoom_step)
			get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = minf(max_zoom, size * zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_E:
				_yaw += PI / 4.0
				_apply_orbit_pose()
				get_viewport().set_input_as_handled()
			elif key_event.keycode == KEY_Q:
				_yaw -= PI / 4.0
				_apply_orbit_pose()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _middle_dragging:
		var mouse_motion := event as InputEventMouseMotion
		_pan_by_pixels(mouse_motion.relative)
		get_viewport().set_input_as_handled()


func _pan_by_pixels(relative: Vector2) -> void:
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var world_units_per_pixel := size / viewport_height

	var right := global_basis.x
	right.y = 0.0
	right = right.normalized()

	var screen_up := global_basis.y
	screen_up.y = 0.0
	screen_up = screen_up.normalized()

	_orbit_target += (-right * relative.x - screen_up * relative.y) * world_units_per_pixel
	_apply_orbit_pose()


func _apply_orbit_pose() -> void:
	var horizontal_distance := cos(_pitch) * _orbit_distance
	var offset := Vector3(
		sin(_yaw) * horizontal_distance,
		sin(_pitch) * _orbit_distance,
		cos(_yaw) * horizontal_distance
	)
	global_position = _orbit_target + offset
	look_at(_orbit_target, Vector3.UP)
