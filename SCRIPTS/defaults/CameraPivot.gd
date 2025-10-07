#CameraPivot Script with Chunk System Integration and Debug System
extends Node3D

# Rotation settings
@export var target_angle := 45.0
@export var current_angle := 0.0
@export var mouse_sensitivity := -0.5
@export var rotation_speed := 5.0
var dragging := false
@export var mouse_movement := 1

# Panning settings - RTS style
var panning := false
@export_range(0.001, 0.05, 0.001) var pan_sensitivity := 0.05
@export_range(0.1, 40.0, 0.1) var pan_speed_multiplier := 40.0
@export_range(1.0, 5.0, 0.1) var pan_acceleration := 5.0
var last_mouse_position := Vector2.ZERO
var middle_mouse_pressed := false
@export var fast_pan_threshold := 50.0

# Movement settings
@export var movement_speed := 10.0
@export var sprint_multiplier := 2.0
@export var smooth_movement := true
@export var movement_smoothness := 8.0
@onready var camera_3d: Camera3D = $Camera3D

# Snap and grid settings
var texel_error: Vector2
var snap_space: Transform3D
var player = null
@export var grid_size := 1.0

# Movement variables
var movement_input := Vector3.ZERO
var target_position := Vector3.ZERO
var is_sprinting := false

# Chunk system integration
var chunk_terrain 
var last_chunk_position: Vector2i
@export var chunk_update_distance := 2.0

# Debug settings
@export var enable_debug: bool = false
@export var show_debug_print: bool = true
@export var debug_log_interval: int = 120

func _ready():
	player = get_node("..")
	target_position = global_position
	_setup_chunk_integration()
	
	DebugManager.register_camera_pivot(self)
	
	if enable_debug:
		ConsoleCapture.console_log("CameraPivot initialized and registered")
		
		if show_debug_print:
			await get_tree().process_frame
			#print_initialization_debug()

#func print_initialization_debug():
	#if not enable_debug:
		#return
	#ConsoleCapture.console_log("=== CAMERA PIVOT INITIALIZATION ===")
	#ConsoleCapture.console_log("Position: " + str(global_position))
	#ConsoleCapture.console_log("Rotation: " + str(rad_to_deg(rotation.y)) + "°")
	#ConsoleCapture.console_log("Movement Speed: " + str(movement_speed))
	#ConsoleCapture.console_log("Sprint Multiplier: " + str(sprint_multiplier))
	#ConsoleCapture.console_log("Smooth Movement: " + str(smooth_movement))
	#ConsoleCapture.console_log("Pan Sensitivity: " + str(pan_sensitivity))
	#ConsoleCapture.console_log("Grid Size: " + str(grid_size))
	#ConsoleCapture.console_log("===================================")

func _setup_chunk_integration():
	chunk_terrain = get_node_or_null("../ChunkPixelTerrain")
	
	if not chunk_terrain:
		var parent = get_parent()
		for child in parent.get_children():
			if child.has_method("WorldToChunk") and child.has_method("ChunkToWorld"):
				chunk_terrain = child
				break
	
	if not chunk_terrain:
		var scene_root = get_tree().current_scene
		chunk_terrain = _find_chunk_terrain_recursive(scene_root)
	
	if chunk_terrain:
		ConsoleCapture.console_log("CameraPivot connected to chunk terrain system")
		last_chunk_position = chunk_terrain.WorldToChunk(global_position)
	#else:
		#if enable_debug:
			#ConsoleCapture.console_log("Warning: ChunkPixelTerrain not found in scene!")

func _find_chunk_terrain_recursive(node: Node):
	if node.has_method("WorldToChunk") and node.has_method("ChunkToWorld"):
		return node
	
	for child in node.get_children():
		var result = _find_chunk_terrain_recursive(child)
		if result:
			return result
	
	return null

func _process(delta):
	handle_movement_input()
	update_position(delta)
	handle_rotation(delta)
	apply_snap_effects()
	update_chunk_system()
	
	if enable_debug and show_debug_print:
		var frame = Engine.get_frames_drawn()
		if frame % debug_log_interval == 0:
			log_periodic_status()

func log_periodic_status():
	if not enable_debug or not is_moving() and not panning:
		return
	#
	#ConsoleCapture.console_log("🎮 CAMERA STATUS:")
	#ConsoleCapture.console_log("  Position: %s" % global_position)
	#ConsoleCapture.console_log("  Moving: %s | Panning: %s | Sprinting: %s" % [is_moving(), panning, is_sprinting])
	#if chunk_terrain:
		#ConsoleCapture.console_log("  Chunk: %s" % get_chunk_position())

func handle_movement_input():
	movement_input = Vector3.ZERO
	
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		movement_input += -transform.basis.z
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		movement_input -= -transform.basis.z
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		movement_input -= transform.basis.x
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		movement_input += transform.basis.x
	
	if Input.is_key_pressed(KEY_UP):
		movement_input += -transform.basis.z
	if Input.is_key_pressed(KEY_DOWN):
		movement_input -= -transform.basis.z
	if Input.is_key_pressed(KEY_LEFT):
		movement_input -= transform.basis.x
	if Input.is_key_pressed(KEY_RIGHT):
		movement_input += transform.basis.x
	
	is_sprinting = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SHIFT)
	
	if movement_input.length() > 0:
		movement_input = movement_input.normalized()

func update_position(delta):
	var current_speed = movement_speed
	if is_sprinting:
		current_speed *= sprint_multiplier
	
	if movement_input.length() > 0:
		var movement_delta = movement_input * current_speed * delta
		
		if smooth_movement:
			target_position += movement_delta
			global_position = global_position.lerp(target_position, movement_smoothness * delta)
		else:
			global_position += movement_delta
			target_position = global_position
	elif smooth_movement:
		global_position = global_position.lerp(target_position, movement_smoothness * delta)

func update_chunk_system():
	if not chunk_terrain:
		return
	
	var current_chunk = chunk_terrain.WorldToChunk(global_position)
	
	if current_chunk != last_chunk_position:
		if enable_debug and show_debug_print:
			ConsoleCapture.console_log("Chunk changed: %s -> %s" % [last_chunk_position, current_chunk])
		last_chunk_position = current_chunk

func handle_rotation(delta):
	if dragging:
		target_angle += mouse_movement * mouse_sensitivity
		mouse_movement = 0.0
	else:
		target_angle = round(target_angle / 45.0) * 45.0
	
	current_angle = lerp(current_angle, target_angle, rotation_speed * delta)

func apply_snap_effects():
	var viewport_size: Vector2 = get_viewport().size
	var texel_snap: float = float(viewport_size.y) / grid_size
	var snap_space_pos := global_position * snap_space
	var snapped_snap_space_pos: Vector3 = floor(snap_space_pos * texel_snap) / texel_snap
	var snap_error := snapped_snap_space_pos - snap_space_pos
	
	rotation.y = deg_to_rad(current_angle + snap_error.y)
	texel_error = Vector2(snap_error.x, -snap_error.y) * texel_snap

func _input(event):
	handle_keyboard_input(event)
	handle_mouse_input(event)

func handle_keyboard_input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				target_angle -= 45.0
				#ConsoleCapture.console_log("Rotated CCW to %s°" % target_angle)
			KEY_Q:
				target_angle += 45.0
				#ConsoleCapture.console_log("Rotated CW to %s°" % target_angle)
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				reset_camera()
			KEY_T:
				smooth_movement = not smooth_movement
				#ConsoleCapture.console_log("Smooth movement: " + str(smooth_movement))
			#KEY_P:
				#print_panning_status()
			KEY_BRACKETLEFT:
				pan_sensitivity = max(0.001, pan_sensitivity - 0.001)
				#ConsoleCapture.console_log("Pan sensitivity: %.3f" % pan_sensitivity)
			KEY_BRACKETRIGHT:
				pan_sensitivity = min(0.02, pan_sensitivity + 0.001)
				#ConsoleCapture.console_log("Pan sensitivity: %.3f" % pan_sensitivity)
			KEY_MINUS:
				pan_speed_multiplier = max(0.1, pan_speed_multiplier - 0.1)
				#ConsoleCapture.console_log("Pan speed multiplier: %.1f" % pan_speed_multiplier)
			KEY_EQUAL:
				pan_speed_multiplier = min(5.0, pan_speed_multiplier + 0.1)
				#ConsoleCapture.console_log("Pan speed multiplier: %.1f" % pan_speed_multiplier)
			KEY_COMMA:
				pan_acceleration = max(0.5, pan_acceleration - 0.1)
				#ConsoleCapture.console_log("Pan acceleration: %.1f" % pan_acceleration)
			KEY_PERIOD:
				pan_acceleration = min(3.0, pan_acceleration + 0.1)
				#ConsoleCapture.console_log("Pan acceleration: %.1f" % pan_acceleration)
			KEY_SLASH:
				reset_pan_settings()
			KEY_F12:
				print_detailed_status()
			KEY_F7:
				if chunk_terrain and chunk_terrain.has_method("ClearChunkCache"):
					chunk_terrain.ClearChunkCache()
					ConsoleCapture.console_log("Cleared chunk cache - restart to regenerate")

#func print_panning_status():
	#ConsoleCapture.console_log("=== PANNING STATUS ===")
	#ConsoleCapture.console_log("Panning active: " + str(panning))
	#ConsoleCapture.console_log("Middle mouse pressed: " + str(middle_mouse_pressed))
	#ConsoleCapture.console_log("Pan sensitivity: %.3f" % pan_sensitivity)
	#ConsoleCapture.console_log("Pan speed multiplier: %.1f" % pan_speed_multiplier)
	#ConsoleCapture.console_log("Pan acceleration: %.1f" % pan_acceleration)
	#ConsoleCapture.console_log("Effective speed: %.4f" % get_effective_pan_speed())
	#ConsoleCapture.console_log("=====================")

func reset_pan_settings():
	pan_sensitivity = 0.005
	pan_speed_multiplier = 1.0
	pan_acceleration = 1.0
	ConsoleCapture.console_log("Pan settings reset to defaults")

func handle_mouse_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				middle_mouse_pressed = true
				panning = true
				last_mouse_position = event.position
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
				if enable_debug and show_debug_print:
					ConsoleCapture.console_log("Panning started")
			else:
				middle_mouse_pressed = false
				panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				if enable_debug and show_debug_print:
					ConsoleCapture.console_log("Panning stopped")
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				dragging = true
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
			else:
				dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	elif event is InputEventMouseMotion:
		if panning and middle_mouse_pressed:
			var mouse_delta = event.position - last_mouse_position
			last_mouse_position = event.position
			
			var movement_magnitude = mouse_delta.length()
			var acceleration_factor = 1.0
			if movement_magnitude > fast_pan_threshold:
				acceleration_factor = pan_acceleration
			
			var camera_right = transform.basis.x
			var camera_forward = -transform.basis.z
			
			var final_sensitivity = pan_sensitivity * pan_speed_multiplier * acceleration_factor
			var pan_movement = Vector3.ZERO
			pan_movement += camera_right * -mouse_delta.x * final_sensitivity
			pan_movement += camera_forward * mouse_delta.y * final_sensitivity
			pan_movement.y = 0
			
			if smooth_movement:
				target_position += pan_movement
			else:
				global_position += pan_movement
				target_position = global_position
		
		elif dragging:
			mouse_movement += event.relative.x

func reset_camera():
	target_position = Vector3.ZERO
	global_position = Vector3.ZERO
	target_angle = 45.0
	current_angle = 45.0
	if enable_debug:
		ConsoleCapture.console_log("Camera reset to origin")

# PUBLIC UTILITY FUNCTIONS

func get_movement_direction() -> Vector3:
	if movement_input.length() > 0:
		return movement_input.rotated(Vector3.UP, rotation.y)
	return Vector3.ZERO

func get_forward_direction() -> Vector3:
	return -transform.basis.z

func get_right_direction() -> Vector3:
	return transform.basis.x

func is_moving() -> bool:
	return movement_input.length() > 0 or panning

func get_current_speed() -> float:
	var speed = movement_speed
	if is_sprinting:
		speed *= sprint_multiplier
	return speed

func get_chunk_position() -> Vector2i:
	if chunk_terrain:
		return chunk_terrain.WorldToChunk(global_position)
	return Vector2i.ZERO

func teleport_to_chunk(chunk_coord: Vector2i):
	if chunk_terrain:
		var world_pos = chunk_terrain.ChunkToWorld(chunk_coord)
		var chunk_center = Vector3(
			world_pos.x + (chunk_terrain.ChunkSize * chunk_terrain.PixelSize * 0.5),
			global_position.y,
			world_pos.y + (chunk_terrain.ChunkSize * chunk_terrain.PixelSize * 0.5)
		)
		global_position = chunk_center
		target_position = chunk_center
		if enable_debug:
			ConsoleCapture.console_log("Teleported to chunk " + str(chunk_coord))

func set_pan_sensitivity(sensitivity: float):
	pan_sensitivity = clamp(sensitivity, 0.001, 0.02)
	if enable_debug:
		ConsoleCapture.console_log("Pan sensitivity set to: %.3f" % pan_sensitivity)

func set_pan_speed_multiplier(multiplier: float):
	pan_speed_multiplier = clamp(multiplier, 0.1, 5.0)
	if enable_debug:
		ConsoleCapture.console_log("Pan speed multiplier set to: %.1f" % pan_speed_multiplier)

func set_pan_acceleration(acceleration: float):
	pan_acceleration = clamp(acceleration, 0.5, 3.0)
	if enable_debug:
		ConsoleCapture.console_log("Pan acceleration set to: %.1f" % pan_acceleration)

func get_effective_pan_speed() -> float:
	return pan_sensitivity * pan_speed_multiplier

# DEBUG INTERFACE

func toggle_debug():
	enable_debug = !enable_debug
	if enable_debug:
		ConsoleCapture.console_log("Debug system ENABLED")
	else:
		ConsoleCapture.console_log("Debug system DISABLED")

func toggle_debug_logging():
	if not enable_debug:
		return
	show_debug_print = !show_debug_print
	ConsoleCapture.console_log("Debug logging: " + str(show_debug_print))

func toggle_smooth_movement():
	smooth_movement = !smooth_movement
	if enable_debug:
		ConsoleCapture.console_log("Smooth movement: " + str(smooth_movement))

func set_movement_speed_debug(value: float):
	movement_speed = value
	if enable_debug:
		ConsoleCapture.console_log("Movement speed set to: %.1f" % movement_speed)

func set_sprint_multiplier_debug(value: float):
	sprint_multiplier = value
	if enable_debug:
		ConsoleCapture.console_log("Sprint multiplier set to: %.1f" % sprint_multiplier)

func set_rotation_speed_debug(value: float):
	rotation_speed = value
	if enable_debug:
		ConsoleCapture.console_log("Rotation speed set to: %.1f" % rotation_speed)

func teleport_to(pos: Vector3):
	global_position = pos
	target_position = pos
	if enable_debug:
		ConsoleCapture.console_log("Teleported to: " + str(pos))

func get_debug_info() -> Dictionary:
	var loaded_chunks = 0
	if chunk_terrain and chunk_terrain.has_method("GetLoadedChunkCount"):
		loaded_chunks = chunk_terrain.GetLoadedChunkCount()
	
	return {
		"position": global_position,
		"target_position": target_position,
		"rotation": rad_to_deg(rotation.y),
		"target_angle": target_angle,
		"current_angle": current_angle,
		"is_moving": is_moving(),
		"is_sprinting": is_sprinting,
		"is_panning": panning,
		"movement_speed": movement_speed,
		"current_speed": get_current_speed(),
		"smooth_movement": smooth_movement,
		"pan_sensitivity": pan_sensitivity,
		"pan_speed_multiplier": pan_speed_multiplier,
		"pan_acceleration": pan_acceleration,
		"effective_pan_speed": get_effective_pan_speed(),
		"chunk_position": get_chunk_position() if chunk_terrain else "N/A",
		"loaded_chunks": loaded_chunks,
		"debug_logging": show_debug_print
	}

func print_status():
	ConsoleCapture.console_log("Position: " + str(global_position))
	ConsoleCapture.console_log("Rotation: %.1f°" % rad_to_deg(rotation.y))
	ConsoleCapture.console_log("Moving: " + str(is_moving()))
	ConsoleCapture.console_log("Sprinting: " + str(is_sprinting))
	ConsoleCapture.console_log("Panning: " + str(panning))

func print_detailed_status():
	ConsoleCapture.console_log("=== CAMERA PIVOT STATUS ===")
	ConsoleCapture.console_log("Position: " + str(global_position))
	ConsoleCapture.console_log("Target Position: " + str(target_position))
	ConsoleCapture.console_log("Rotation: %.1f°" % rad_to_deg(rotation.y))
	ConsoleCapture.console_log("Target Angle: %.1f°" % target_angle)
	ConsoleCapture.console_log("Moving: " + str(is_moving()))
	ConsoleCapture.console_log("Sprinting: " + str(is_sprinting))
	ConsoleCapture.console_log("Current Speed: %.1f" % get_current_speed())
	ConsoleCapture.console_log("")
	ConsoleCapture.console_log("=== PANNING SETTINGS ===")
	ConsoleCapture.console_log("Panning active: " + str(panning))
	ConsoleCapture.console_log("Pan sensitivity: %.3f" % pan_sensitivity)
	ConsoleCapture.console_log("Pan speed multiplier: %.1f" % pan_speed_multiplier)
	ConsoleCapture.console_log("Pan acceleration: %.1f" % pan_acceleration)
	ConsoleCapture.console_log("Effective pan speed: %.4f" % get_effective_pan_speed())
	
	if chunk_terrain:
		ConsoleCapture.console_log("")
		ConsoleCapture.console_log("=== CHUNK SYSTEM ===")
		ConsoleCapture.console_log("Current Chunk: " + str(get_chunk_position()))
		if chunk_terrain.has_method("GetLoadedChunkCount"):
			ConsoleCapture.console_log("Loaded Chunks: " + str(chunk_terrain.GetLoadedChunkCount()))
		if chunk_terrain.has_method("GetLoadingChunkCount"):
			ConsoleCapture.console_log("Loading Chunks: " + str(chunk_terrain.GetLoadingChunkCount()))
	
	ConsoleCapture.console_log("=========================")
