# Camera3D Debugger Tab
extends TabBar

# Toggles (CheckBoxes)
@onready var toggle_visual_debug: CheckBox = $MarginContainer/VBoxContainer/Panel/HBoxContainer/Panel2/MarginContainer/VBoxContainer/toggle_visual_debug
@onready var toggle_cursor_indicator: CheckBox = $MarginContainer/VBoxContainer/Panel/HBoxContainer/Panel2/MarginContainer/VBoxContainer/toggle_cursor_indicator
@onready var toggle_snap: CheckBox = $MarginContainer/VBoxContainer/Panel/HBoxContainer/Panel2/MarginContainer/VBoxContainer/toggle_snap
@onready var toggle_continuous_raycast: CheckBox = $MarginContainer/VBoxContainer/Panel/HBoxContainer/Panel2/MarginContainer/VBoxContainer/toggle_continuous_raycast

# Sliders
@onready var h_slider_set_zoom_level_debug: HSlider = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HSlider_set_zoom_level_debug
@onready var h_slider_set_zoom_speed_debug: HSlider = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HSlider_set_zoom_speed_debug
@onready var h_slider_set_raycast_length_debug: HSlider = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HSlider_set_raycast_length_debug
@onready var h_slider_set_hit_point_size_debug: HSlider = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HSlider_set_hit_point_size_debug
@onready var h_slider_set_cursor_size_debug: HSlider = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HSlider_set_cursor_size_debug

# Value displays (LineEdits - read-only)
@onready var set_zoom_level_debug: LineEdit = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel3/MarginContainer/VBoxContainer/set_zoom_level_debug
@onready var set_zoom_speed_debug: LineEdit = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel3/MarginContainer/VBoxContainer/set_zoom_speed_debug
@onready var set_raycast_length_debug: LineEdit = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel3/MarginContainer/VBoxContainer/set_raycast_length_debug
@onready var set_hit_point_size_debug: LineEdit = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel3/MarginContainer/VBoxContainer/set_hit_point_size_debug
@onready var set_cursor_size_debug: LineEdit = $MarginContainer/VBoxContainer/Panel2/HBoxContainer/Panel3/MarginContainer/VBoxContainer/set_cursor_size_debug

# Teleport inputs
@onready var teleport_to_x: LineEdit = $MarginContainer/VBoxContainer/Panel3/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HBoxContainer/teleport_to_x
@onready var teleport_to_y: LineEdit = $MarginContainer/VBoxContainer/Panel3/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HBoxContainer/teleport_to_y
@onready var teleport_to_z: LineEdit = $MarginContainer/VBoxContainer/Panel3/HBoxContainer/Panel2/MarginContainer/VBoxContainer/HBoxContainer/teleport_to_z

# Reset button
@onready var reset_camera_position: CheckBox = $MarginContainer/VBoxContainer/Panel3/HBoxContainer/Panel2/MarginContainer/VBoxContainer/reset_camera_position

# Swaps
@onready var toggle_functions: Button = $MarginContainer/VBoxContainer/Toggle_Functions
@onready var panel_toggle_functions: Panel = $MarginContainer/VBoxContainer/Panel
@onready var setter_functions: Button = $MarginContainer/VBoxContainer/Setter_Functions
@onready var panel_2_setter_functions: Panel = $MarginContainer/VBoxContainer/Panel2
@onready var camera_manipulation: Button = $"MarginContainer/VBoxContainer/Camera Manipulation"
@onready var panel_3_camera_manipulation: Panel = $MarginContainer/VBoxContainer/Panel3
@onready var console: Button = $MarginContainer/VBoxContainer/Console
@onready var console_panel: Panel = $MarginContainer/VBoxContainer/Console_Panel


# Reference to camera
var camera: Camera3D


func _ready():
	# Wait a frame to ensure DebugManager has registered the camera
	await get_tree().process_frame
	panel_toggle_functions.visible = true
	panel_2_setter_functions.visible = true
	panel_3_camera_manipulation.visible = true
	console_panel.visible = true
	
	# Get camera reference from DebugManager
	camera = DebugManager.camera
	
	if not camera:
		push_error("Camera not found in DebugManager!")
		return
	
	# Load current values from camera
	load_camera_values()
	
	# Connect all signals
	connect_signals()


func load_camera_values():
	"""Load all current values from the camera into the UI"""
	if not camera:
		return
	
	# Set toggle states
	toggle_visual_debug.button_pressed = camera.show_visual_debug
	toggle_cursor_indicator.button_pressed = camera.show_cursor_indicator
	toggle_snap.button_pressed = camera.snap
	toggle_continuous_raycast.button_pressed = camera.continuous_raycast_update
	
	# Setup slider ranges and values
	# Zoom Level
	h_slider_set_zoom_level_debug.min_value = camera.min_size
	h_slider_set_zoom_level_debug.max_value = camera.max_size
	h_slider_set_zoom_level_debug.value = camera.zoom_level
	set_zoom_level_debug.text = str(snappedf(camera.zoom_level, 0.01))
	
	# Zoom Speed
	h_slider_set_zoom_speed_debug.min_value = 1.0
	h_slider_set_zoom_speed_debug.max_value = 50.0
	h_slider_set_zoom_speed_debug.value = camera.zoom_speed
	set_zoom_speed_debug.text = str(snappedf(camera.zoom_speed, 0.01))
	
	# Raycast Length
	h_slider_set_raycast_length_debug.min_value = 100.0
	h_slider_set_raycast_length_debug.max_value = 5000.0
	h_slider_set_raycast_length_debug.value = camera.raycast_length
	set_raycast_length_debug.text = str(snappedf(camera.raycast_length, 0.01))
	
	# Hit Point Size
	h_slider_set_hit_point_size_debug.min_value = 0.1
	h_slider_set_hit_point_size_debug.max_value = 2.0
	h_slider_set_hit_point_size_debug.step = 0.05
	h_slider_set_hit_point_size_debug.value = camera.hit_point_size
	set_hit_point_size_debug.text = str(snappedf(camera.hit_point_size, 0.01))
	
	# Cursor Size
	h_slider_set_cursor_size_debug.min_value = 0.1
	h_slider_set_cursor_size_debug.max_value = 2.0
	h_slider_set_cursor_size_debug.step = 0.05
	h_slider_set_cursor_size_debug.value = camera.cursor_indicator_size
	set_cursor_size_debug.text = str(snappedf(camera.cursor_indicator_size, 0.01))
	
	# Load current camera position into teleport fields
	teleport_to_x.text = str(snappedf(camera.global_position.x, 0.01))
	teleport_to_y.text = str(snappedf(camera.global_position.y, 0.01))
	teleport_to_z.text = str(snappedf(camera.global_position.z, 0.01))


func connect_signals():
	"""Connect all UI elements to their handler functions"""
	# Toggle checkboxes
	toggle_visual_debug.toggled.connect(_on_toggle_visual_debug)
	toggle_cursor_indicator.toggled.connect(_on_toggle_cursor_indicator)
	toggle_snap.toggled.connect(_on_toggle_snap)
	toggle_continuous_raycast.toggled.connect(_on_toggle_continuous_raycast)
	
	# Sliders
	h_slider_set_zoom_level_debug.value_changed.connect(_on_zoom_level_changed)
	h_slider_set_zoom_speed_debug.value_changed.connect(_on_zoom_speed_changed)
	h_slider_set_raycast_length_debug.value_changed.connect(_on_raycast_length_changed)
	h_slider_set_hit_point_size_debug.value_changed.connect(_on_hit_point_size_changed)
	h_slider_set_cursor_size_debug.value_changed.connect(_on_cursor_size_changed)
	
	# Teleport button (when X, Y, Z fields change, update the button)
	teleport_to_x.text_submitted.connect(_on_teleport_submitted)
	teleport_to_y.text_submitted.connect(_on_teleport_submitted)
	teleport_to_z.text_submitted.connect(_on_teleport_submitted)
	
	# Reset camera position
	reset_camera_position.toggled.connect(_on_reset_camera)


# ============================================
# TOGGLE HANDLERS
# ============================================

func _on_toggle_visual_debug(toggled: bool):
	if camera:
		camera.toggle_visual_debug()

func _on_toggle_cursor_indicator(toggled: bool):
	if camera:
		camera.toggle_cursor_indicator()

func _on_toggle_snap(toggled: bool):
	if camera:
		camera.toggle_snap()

func _on_toggle_continuous_raycast(toggled: bool):
	if camera:
		camera.toggle_continuous_raycast()

# ============================================
# SLIDER HANDLERS
# ============================================

func _on_zoom_level_changed(value: float):
	if camera:
		camera.set_zoom_level_debug(value)
		set_zoom_level_debug.text = str(snappedf(value, 0.01))


func _on_zoom_speed_changed(value: float):
	if camera:
		camera.set_zoom_speed_debug(value)
		set_zoom_speed_debug.text = str(snappedf(value, 0.01))


func _on_raycast_length_changed(value: float):
	if camera:
		camera.set_raycast_length_debug(value)
		set_raycast_length_debug.text = str(snappedf(value, 0.01))


func _on_hit_point_size_changed(value: float):
	if camera:
		camera.set_hit_point_size_debug(value)
		set_hit_point_size_debug.text = str(snappedf(value, 0.01))


func _on_cursor_size_changed(value: float):
	if camera:
		camera.set_cursor_size_debug(value)
		set_cursor_size_debug.text = str(snappedf(value, 0.01))


# ============================================
# TELEPORT HANDLERS
# ============================================

func _on_teleport_submitted(_new_text: String = ""):
	if not camera:
		return
	
	var x = float(teleport_to_x.text)
	var y = float(teleport_to_y.text)
	var z = float(teleport_to_z.text)
	
	camera.teleport_to(Vector3(x, y, z))
	print("Camera teleported to: ", Vector3(x, y, z))


func _on_reset_camera(toggled: bool):
	if not camera:
		return
	
	if toggled:
		camera.reset_camera_position()
		# Update teleport fields to show new position
		teleport_to_x.text = "0"
		teleport_to_y.text = "0"
		teleport_to_z.text = "0"
		print("Camera position reset")
		
		# Uncheck the checkbox after reset
		reset_camera_position.button_pressed = false


# ============================================
# UPDATE LOOP (Optional - for live info display)
# ============================================

func _process(_delta):
	# Update position fields to show current camera position in real-time
	if camera:
		# Only update if the field is not focused (so user can type)
		if not teleport_to_x.has_focus():
			teleport_to_x.text = str(snappedf(camera.global_position.x, 0.01))
		if not teleport_to_y.has_focus():
			teleport_to_y.text = str(snappedf(camera.global_position.y, 0.01))
		if not teleport_to_z.has_focus():
			teleport_to_z.text = str(snappedf(camera.global_position.z, 0.01))


func _on_toggle_functions_pressed() -> void:
	if panel_toggle_functions.visible == true:
		panel_toggle_functions.visible = false
	else:
		panel_toggle_functions.visible = true

func _on_setter_functions_pressed() -> void:
	if panel_2_setter_functions.visible == true:
		panel_2_setter_functions.visible = false
	else:
		panel_2_setter_functions.visible = true

func _on_camera_manipulation_pressed() -> void:
	if panel_3_camera_manipulation.visible == true:
		panel_3_camera_manipulation.visible = false
	else:
		panel_3_camera_manipulation.visible = true

func _on_console_pressed() -> void:
	if console_panel.visible == true:
		console_panel.visible = false
	else:
		console_panel.visible = true
