extends TabBar

# Debug toggles
@onready var enable_debug_checkbox: CheckBox = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer/Control2/VBoxContainer/Enable_Debug_checkbox
@onready var show_debug_print_checkbox: CheckBox = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer/Control2/VBoxContainer/Show_Debug_Print_checkbox

# Rotation settings
@onready var target_angle: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/target_angle
@onready var current_angle: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/current_angle
@onready var mouse_sensitivity: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/mouse_sensitivity
@onready var rotation_speed: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/rotation_speed
@onready var mouse_movement: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/mouse_movement

# Movement settings
@onready var movement_speed: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/movement_speed
@onready var sprint_multiplier: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/sprint_multiplier
@onready var smooth_movement: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/smooth_movement
@onready var movement_smoothness: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/movement_smoothness
@onready var chunk_update_distance: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer2/Control2/VBoxContainer/chunk_update_distance

# Panning settings with sliders
@onready var pan_sensitivity_h_slider: HSlider = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/HBoxContainer/HSlider
@onready var pan_sensitivity: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/HBoxContainer/pan_sensitivity
@onready var pan_speed_multiplier_h_slider: HSlider = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/HBoxContainer2/HSlider
@onready var pan_speed_multiplier: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/HBoxContainer2/pan_speed_multiplier
@onready var pan_acceleration_h_slider: HSlider = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/HBoxContainer3/HSlider
@onready var pan_acceleration: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/HBoxContainer3/pan_acceleration
@onready var fast_pan_threshold_value: LineEdit = $ScrollContainer/MarginContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer3/Control2/VBoxContainer/fast_pan_threshold_value

# Reference to camera pivot
var camera_pivot: Node3D

# Update timer
var update_timer: Timer

func _ready():
	# Wait for scene tree to be ready
	await get_tree().process_frame
	
	# Get camera pivot reference from DebugManager
	camera_pivot = DebugManager.camera_pivot
	
	if not camera_pivot:
		ConsoleCapture.console_log("WARNING: Camera Pivot not found yet, waiting...")
		# Set up a timer to retry finding the camera pivot
		var retry_timer = Timer.new()
		add_child(retry_timer)
		retry_timer.wait_time = 0.5
		retry_timer.timeout.connect(_try_find_camera_pivot)
		retry_timer.start()
		return
	
	_initialize_ui()

func _try_find_camera_pivot():
	camera_pivot = DebugManager.camera_pivot
	if camera_pivot:
		ConsoleCapture.console_log("Camera Pivot found!")
		_initialize_ui()

func _initialize_ui():
	if not camera_pivot:
		return
	
	# Setup update timer for real-time value display
	update_timer = Timer.new()
	add_child(update_timer)
	update_timer.wait_time = 0.1  # Update 10 times per second
	update_timer.timeout.connect(_update_display_values)
	update_timer.start()
	
	# Connect checkbox signals
	enable_debug_checkbox.toggled.connect(_on_enable_debug_toggled)
	show_debug_print_checkbox.toggled.connect(_on_show_debug_print_toggled)
	
	# Connect slider signals
	pan_sensitivity_h_slider.value_changed.connect(_on_pan_sensitivity_slider_changed)
	pan_speed_multiplier_h_slider.value_changed.connect(_on_pan_speed_multiplier_slider_changed)
	pan_acceleration_h_slider.value_changed.connect(_on_pan_acceleration_slider_changed)
	
	# Connect LineEdit signals for direct input
	target_angle.text_submitted.connect(_on_target_angle_submitted)
	mouse_sensitivity.text_submitted.connect(_on_mouse_sensitivity_submitted)
	rotation_speed.text_submitted.connect(_on_rotation_speed_submitted)
	movement_speed.text_submitted.connect(_on_movement_speed_submitted)
	sprint_multiplier.text_submitted.connect(_on_sprint_multiplier_submitted)
	movement_smoothness.text_submitted.connect(_on_movement_smoothness_submitted)
	chunk_update_distance.text_submitted.connect(_on_chunk_update_distance_submitted)
	pan_sensitivity.text_submitted.connect(_on_pan_sensitivity_submitted)
	pan_speed_multiplier.text_submitted.connect(_on_pan_speed_multiplier_submitted)
	pan_acceleration.text_submitted.connect(_on_pan_acceleration_submitted)
	fast_pan_threshold_value.text_submitted.connect(_on_fast_pan_threshold_submitted)
	
	# Setup slider ranges
	setup_slider_ranges()
	
	# Initialize display with current values
	_update_display_values()
	
	ConsoleCapture.console_log("Camera Pivot Debug UI initialized")

func setup_slider_ranges():
	# Set ranges FIRST
	pan_sensitivity_h_slider.min_value = 0.05
	pan_sensitivity_h_slider.max_value = 5.0
	pan_sensitivity_h_slider.step = 0.02
	
	pan_speed_multiplier_h_slider.min_value = 40.0
	pan_speed_multiplier_h_slider.max_value = 100.0
	pan_speed_multiplier_h_slider.step = 10.0
	
	pan_acceleration_h_slider.min_value = 5.0
	pan_acceleration_h_slider.max_value = 10.0
	pan_acceleration_h_slider.step = 0.5
	
	# THEN set values from camera_pivot (after ranges are set)
	if camera_pivot:
		pan_sensitivity_h_slider.value = camera_pivot.pan_sensitivity
		pan_speed_multiplier_h_slider.value = camera_pivot.pan_speed_multiplier
		pan_acceleration_h_slider.value = camera_pivot.pan_acceleration
func _update_display_values():
	if not camera_pivot or not is_instance_valid(camera_pivot):
		return
	
	# Update checkboxes
	enable_debug_checkbox.button_pressed = camera_pivot.enable_debug
	show_debug_print_checkbox.button_pressed = camera_pivot.show_debug_print
	
	# Update rotation values (read-only display)
	target_angle.text = "%.1f" % camera_pivot.target_angle
	current_angle.text = "%.1f" % camera_pivot.current_angle
	mouse_sensitivity.text = "%.2f" % camera_pivot.mouse_sensitivity
	rotation_speed.text = "%.1f" % camera_pivot.rotation_speed
	mouse_movement.text = "%.1f" % camera_pivot.mouse_movement
	
	# Update movement values
	movement_speed.text = "%.1f" % camera_pivot.movement_speed
	sprint_multiplier.text = "%.1f" % camera_pivot.sprint_multiplier
	smooth_movement.text = str(camera_pivot.smooth_movement)
	movement_smoothness.text = "%.1f" % camera_pivot.movement_smoothness
	chunk_update_distance.text = "%.1f" % camera_pivot.chunk_update_distance
	
	# Update panning values and sync sliders
	pan_sensitivity.text = "%.4f" % camera_pivot.pan_sensitivity
	pan_sensitivity_h_slider.value = camera_pivot.pan_sensitivity
	
	pan_speed_multiplier.text = "%.1f" % camera_pivot.pan_speed_multiplier
	pan_speed_multiplier_h_slider.value = camera_pivot.pan_speed_multiplier
	
	pan_acceleration.text = "%.2f" % camera_pivot.pan_acceleration
	pan_acceleration_h_slider.value = camera_pivot.pan_acceleration
	
	fast_pan_threshold_value.text = "%.1f" % camera_pivot.fast_pan_threshold

# ========================================
# CHECKBOX HANDLERS
# ========================================

func _on_enable_debug_toggled(pressed: bool):
	if camera_pivot and is_instance_valid(camera_pivot):
		camera_pivot.enable_debug = pressed
		ConsoleCapture.console_log("Debug %s" % ("ENABLED" if pressed else "DISABLED"))

func _on_show_debug_print_toggled(pressed: bool):
	if camera_pivot and is_instance_valid(camera_pivot):
		camera_pivot.show_debug_print = pressed
		ConsoleCapture.console_log("Debug printing %s" % ("ENABLED" if pressed else "DISABLED"))

# ========================================
# SLIDER HANDLERS
# ========================================

func _on_pan_sensitivity_slider_changed(value: float):
	if camera_pivot and is_instance_valid(camera_pivot):
		camera_pivot.pan_sensitivity = value
		pan_sensitivity.text = "%.4f" % value

func _on_pan_speed_multiplier_slider_changed(value: float):
	if camera_pivot and is_instance_valid(camera_pivot):
		camera_pivot.pan_speed_multiplier = value
		pan_speed_multiplier.text = "%.1f" % value

func _on_pan_acceleration_slider_changed(value: float):
	if camera_pivot and is_instance_valid(camera_pivot):
		camera_pivot.pan_acceleration = value
		pan_acceleration.text = "%.2f" % value

# ========================================
# LINE EDIT HANDLERS (for manual input)
# ========================================

func _on_target_angle_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.target_angle = value
		ConsoleCapture.console_log("Target angle set to: %.1f°" % value)

func _on_mouse_sensitivity_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.mouse_sensitivity = value
		ConsoleCapture.console_log("Mouse sensitivity set to: %.2f" % value)

func _on_rotation_speed_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.rotation_speed = value
		ConsoleCapture.console_log("Rotation speed set to: %.1f" % value)

func _on_movement_speed_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.movement_speed = value
		ConsoleCapture.console_log("Movement speed set to: %.1f" % value)

func _on_sprint_multiplier_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.sprint_multiplier = value
		ConsoleCapture.console_log("Sprint multiplier set to: %.1f" % value)

func _on_movement_smoothness_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.movement_smoothness = value
		ConsoleCapture.console_log("Movement smoothness set to: %.1f" % value)

func _on_chunk_update_distance_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.chunk_update_distance = value
		ConsoleCapture.console_log("Chunk update distance set to: %.1f" % value)

func _on_pan_sensitivity_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = clamp(float(new_text), 0.001, 0.05)
		camera_pivot.pan_sensitivity = value
		pan_sensitivity_h_slider.value = value
		ConsoleCapture.console_log("Pan sensitivity set to: %.4f" % value)

func _on_pan_speed_multiplier_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = clamp(float(new_text), 0.1, 40.0)
		camera_pivot.pan_speed_multiplier = value
		pan_speed_multiplier_h_slider.value = value
		ConsoleCapture.console_log("Pan speed multiplier set to: %.1f" % value)

func _on_pan_acceleration_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = clamp(float(new_text), 1.0, 5.0)
		camera_pivot.pan_acceleration = value
		pan_acceleration_h_slider.value = value
		ConsoleCapture.console_log("Pan acceleration set to: %.2f" % value)

func _on_fast_pan_threshold_submitted(new_text: String):
	if camera_pivot and is_instance_valid(camera_pivot):
		var value = float(new_text)
		camera_pivot.fast_pan_threshold = value
		ConsoleCapture.console_log("Fast pan threshold set to: %.1f" % value)

# ========================================
# UTILITY FUNCTIONS
# ========================================

func refresh_values():
	"""Force refresh all displayed values"""
	_update_display_values()

func reset_to_defaults():
	"""Reset all camera pivot settings to default values"""
	if not camera_pivot or not is_instance_valid(camera_pivot):
		return
	
	camera_pivot.target_angle = 45.0
	camera_pivot.mouse_sensitivity = -0.5
	camera_pivot.rotation_speed = 5.0
	camera_pivot.movement_speed = 10.0
	camera_pivot.sprint_multiplier = 2.0
	camera_pivot.smooth_movement = true
	camera_pivot.movement_smoothness = 8.0
	camera_pivot.pan_sensitivity = 0.005
	camera_pivot.pan_speed_multiplier = 1.0
	camera_pivot.pan_acceleration = 1.5
	camera_pivot.fast_pan_threshold = 50.0
	camera_pivot.chunk_update_distance = 2.0
	
	_update_display_values()
	ConsoleCapture.console_log("Camera Pivot settings reset to defaults")

func get_all_values() -> Dictionary:
	"""Get all current values as a dictionary"""
	if not camera_pivot or not is_instance_valid(camera_pivot):
		return {}
	
	return camera_pivot.get_debug_info()

func print_all_values():
	"""Print all current values to console"""
	if not camera_pivot or not is_instance_valid(camera_pivot):
		return
	
	camera_pivot.print_detailed_status()
