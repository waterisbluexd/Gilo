#CameraPivot Script with Chunk System Integration and RTS-style Panning
extends Node3D

# Rotation settings
var target_angle := 45.0
var current_angle := 0.0
var mouse_sensitivity := -0.5
var rotation_speed := 5.0
var dragging := false
var mouse_movement := 1

# Panning settings - RTS style
var panning := false  # Only active when middle mouse is held
# MODIFIED: Exposed panning speed controls to the Godot Inspector with sliders.
@export_range(0.001, 0.05, 0.001) var pan_sensitivity := 0.005  # Base sensitivity for mouse panning
@export_range(0.1, 40.0, 0.1) var pan_speed_multiplier := 1.0  # Overall speed multiplier for panning
@export_range(1.0, 5.0, 0.1) var pan_acceleration := 1.5      # Speed boost for fast mouse movements
var last_mouse_position := Vector2.ZERO
var middle_mouse_pressed := false
@export var fast_pan_threshold := 50.0  # Pixel movement threshold to trigger fast panning

# Movement settings
@export var movement_speed := 10.0  # Units per second
@export var sprint_multiplier := 2.0  # Speed multiplier when sprinting
@export var smooth_movement := true  # Enable smooth movement
@export var movement_smoothness := 8.0  # How smooth the movement is
@onready var camera_3d: Camera3D = $Camera3D

# Snap and grid settings
var texel_error: Vector2
var snap_space: Transform3D
var player = null
var grid_size := 1.0  # Define the size of your grid cell

# Movement variables
var movement_input := Vector3.ZERO
var target_position := Vector3.ZERO
var is_sprinting := false

# Chunk system integration
var chunk_terrain: ChunkPixelTerrain
var last_chunk_position: Vector2i
var chunk_update_distance := 2.0  # Minimum distance to move before updating chunks

func _ready():
	player = get_node("..")
	target_position = global_position
	_setup_chunk_integration()

func _setup_chunk_integration():
	# Find the chunk terrain system
	chunk_terrain = get_node_or_null("../ChunkPixelTerrain")
	if not chunk_terrain:
		# Try to find it in the parent or scene tree
		var parent = get_parent()
		for child in parent.get_children():
			if child is ChunkPixelTerrain or child.get_script() and child.get_script().get_global_name() == "ChunkPixelTerrain":
				chunk_terrain = child
				break
		
		# If still not found, try searching the entire scene tree
		if not chunk_terrain:
			var scene_root = get_tree().current_scene
			chunk_terrain = _find_chunk_terrain_recursive(scene_root)
	
	if chunk_terrain:
		print("CameraPivot connected to chunk terrain system")
		last_chunk_position = chunk_terrain.world_to_chunk(global_position)
	else:
		print("Warning: ChunkPixelTerrain not found in scene!")

func _find_chunk_terrain_recursive(node: Node) -> ChunkPixelTerrain:
	if node is ChunkPixelTerrain or (node.get_script() and node.get_script().get_global_name() == "ChunkPixelTerrain"):
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

func handle_movement_input():
	# Get input for movement - using the WORKING method from your CharacterBody3D
	movement_input = Vector3.ZERO
	
	# Use the same logic as your working example
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		movement_input += -transform.basis.z  # Forward (note the negative!)
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		movement_input -= -transform.basis.z  # Backward (becomes positive)
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		movement_input -= transform.basis.x   # Left
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		movement_input += transform.basis.x   # Right
	
	# Arrow keys as alternative
	if Input.is_key_pressed(KEY_UP):
		movement_input += -transform.basis.z
	if Input.is_key_pressed(KEY_DOWN):
		movement_input -= -transform.basis.z
	if Input.is_key_pressed(KEY_LEFT):
		movement_input -= transform.basis.x
	if Input.is_key_pressed(KEY_RIGHT):
		movement_input += transform.basis.x
	
	# Sprint detection
	is_sprinting = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SHIFT)
	
	# Normalize diagonal movement
	if movement_input.length() > 0:
		movement_input = movement_input.normalized()

func update_position(delta):
	# Calculate the current speed
	var current_speed = movement_speed
	if is_sprinting:
		current_speed *= sprint_multiplier
	
	# Use the movement_input directly (it's already in world space)
	if movement_input.length() > 0:
		# Calculate the change in position
		var movement_delta = movement_input * current_speed * delta
		
		if smooth_movement:
			# Smooth movement
			target_position += movement_delta
			global_position = global_position.lerp(target_position, movement_smoothness * delta)
		else:
			# Direct movement
			global_position += movement_delta
			target_position = global_position
	elif smooth_movement:
		# Smooth stop
		global_position = global_position.lerp(target_position, movement_smoothness * delta)

func update_chunk_system():
	if not chunk_terrain:
		return
	
	var current_chunk = chunk_terrain.world_to_chunk(global_position)
	
	# Check if we've moved far enough or to a different chunk
	if current_chunk != last_chunk_position:
		last_chunk_position = current_chunk
		# The chunk system will automatically handle loading/unloading

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
				target_angle -= 45.0  # Rotate anticlockwise
			KEY_Q:
				target_angle += 45.0  # Rotate clockwise
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				# Reset position and rotation
				reset_camera()
			KEY_T:
				# Toggle smooth movement
				smooth_movement = not smooth_movement
				print("Smooth movement: ", smooth_movement)
			KEY_P:
				# Print panning status
				print("=== Panning Status ===")
				print("Panning active: ", panning)
				print("Middle mouse pressed: ", middle_mouse_pressed)
				print("Pan sensitivity: ", pan_sensitivity)
				print("Pan speed multiplier: ", pan_speed_multiplier)
				print("Pan acceleration: ", pan_acceleration)
			KEY_BRACKETLEFT:  # [ key
				# Decrease pan sensitivity
				pan_sensitivity = max(0.001, pan_sensitivity - 0.001)
				print("Pan sensitivity: ", pan_sensitivity)
			KEY_BRACKETRIGHT:  # ] key
				# Increase pan sensitivity
				pan_sensitivity = min(0.02, pan_sensitivity + 0.001)
				print("Pan sensitivity: ", pan_sensitivity)
			KEY_MINUS:  # - key
				# Decrease pan speed multiplier
				pan_speed_multiplier = max(0.1, pan_speed_multiplier - 0.1)
				print("Pan speed multiplier: ", pan_speed_multiplier)
			KEY_EQUAL:  # + key (= key without shift)
				# Increase pan speed multiplier
				pan_speed_multiplier = min(5.0, pan_speed_multiplier + 0.1)
				print("Pan speed multiplier: ", pan_speed_multiplier)
			KEY_COMMA:  # , key
				# Decrease pan acceleration
				pan_acceleration = max(0.5, pan_acceleration - 0.1)
				print("Pan acceleration: ", pan_acceleration)
			KEY_PERIOD:  # . key
				# Increase pan acceleration
				pan_acceleration = min(3.0, pan_acceleration + 0.1)
				print("Pan acceleration: ", pan_acceleration)
			KEY_SLASH:  # / key
				# Reset all panning values to defaults
				pan_sensitivity = 0.005
				pan_speed_multiplier = 1.0
				pan_acceleration = 1.0
				print("Pan settings reset to defaults")
			KEY_F5:
				# Force save all chunks
				if chunk_terrain:
					chunk_terrain.force_save_all_chunks()
					print("Forced save of all chunks")
			KEY_F6:
				# Clear all chunks (for testing)
				if chunk_terrain:
					chunk_terrain.clear_all_chunks()
					print("Cleared all chunks")
			KEY_F9:  # ADD THIS
				# Test coordinate system
				if chunk_terrain:
					chunk_terrain.debug_test_coordinates()
					chunk_terrain.debug_print_chunk_loading(global_position)
			KEY_F12:
				# Print detailed status
				print_detailed_status()

func handle_mouse_input(event):
	if event is InputEventMouseButton:
		# Handle middle mouse button for panning (like RTS games)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				middle_mouse_pressed = true
				panning = true
				last_mouse_position = event.position
				# Change cursor to indicate panning mode
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
			else:
				middle_mouse_pressed = false
				panning = false
				# Reset cursor
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		
		# Handle right mouse button for rotation
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				dragging = true
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
			else:
				dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	elif event is InputEventMouseMotion:
		if panning and middle_mouse_pressed:
			# RTS-style panning: drag to move camera
			var mouse_delta = event.position - last_mouse_position
			last_mouse_position = event.position
			
			# Calculate movement distance for acceleration
			var movement_magnitude = mouse_delta.length()
			
			# Apply acceleration for fast movements
			var acceleration_factor = 1.0
			if movement_magnitude > fast_pan_threshold:
				acceleration_factor = pan_acceleration
			
			# Get the camera's right and forward vectors
			var camera_right = transform.basis.x
			var camera_forward = -transform.basis.z
			
			# Calculate pan movement with all multipliers
			var final_sensitivity = pan_sensitivity * pan_speed_multiplier * acceleration_factor
			var pan_movement = Vector3.ZERO
			pan_movement += camera_right * -mouse_delta.x * final_sensitivity
			pan_movement += camera_forward * mouse_delta.y * final_sensitivity
			
			# Keep movement on the horizontal plane
			pan_movement.y = 0
			
			# Apply movement
			if smooth_movement:
				target_position += pan_movement
			else:
				global_position += pan_movement
				target_position = global_position
		
		elif dragging:
			# Handle rotation
			mouse_movement += event.relative.x

func reset_camera():
	"""Reset camera to origin with 45 degree angle"""
	target_position = Vector3.ZERO
	global_position = Vector3.ZERO
	target_angle = 45.0
	current_angle = 45.0
	print("Camera reset to origin")

# Utility functions
func get_movement_direction() -> Vector3:
	"""Get the current movement direction in world space"""
	if movement_input.length() > 0:
		return movement_input.rotated(Vector3.UP, rotation.y)
	return Vector3.ZERO

func get_forward_direction() -> Vector3:
	"""Get the camera's forward direction"""
	return -transform.basis.z

func get_right_direction() -> Vector3:
	"""Get the camera's right direction"""
	return transform.basis.x

func is_moving() -> bool:
	"""Check if the camera/player is currently moving"""
	return movement_input.length() > 0 or panning

func get_current_speed() -> float:
	"""Get the current movement speed"""
	var speed = movement_speed
	if is_sprinting:
		speed *= sprint_multiplier
	return speed

func get_chunk_position() -> Vector2i:
	"""Get the current chunk coordinates"""
	if chunk_terrain:
		return chunk_terrain.world_to_chunk(global_position)
	return Vector2i.ZERO

func teleport_to_chunk(chunk_coord: Vector2i):
	"""Teleport to the center of a specific chunk"""
	if chunk_terrain:
		var world_pos = chunk_terrain.chunk_to_world(chunk_coord)
		var chunk_center = Vector3(
			world_pos.x + (chunk_terrain.chunk_size * chunk_terrain.pixel_size * 0.5),
			global_position.y,  # Maintain current height
			world_pos.y + (chunk_terrain.chunk_size * chunk_terrain.pixel_size * 0.5)
		)
		global_position = chunk_center
		target_position = chunk_center
		print("Teleported to chunk ", chunk_coord)

func set_pan_sensitivity(sensitivity: float):
	"""Set the panning sensitivity"""
	pan_sensitivity = clamp(sensitivity, 0.001, 0.02)
	print("Pan sensitivity set to: ", pan_sensitivity)

func set_pan_speed_multiplier(multiplier: float):
	"""Set the panning speed multiplier"""
	pan_speed_multiplier = clamp(multiplier, 0.1, 5.0)
	print("Pan speed multiplier set to: ", pan_speed_multiplier)

func set_pan_acceleration(acceleration: float):
	"""Set the panning acceleration factor"""
	pan_acceleration = clamp(acceleration, 0.5, 3.0)
	print("Pan acceleration set to: ", pan_acceleration)

func get_effective_pan_speed() -> float:
	"""Get the current effective pan speed (for UI display)"""
	return pan_sensitivity * pan_speed_multiplier

# Debug functions
func print_status():
	print("Position: ", global_position)
	print("Rotation: ", rad_to_deg(rotation.y))
	print("Moving: ", is_moving())
	print("Sprinting: ", is_sprinting)
	print("Panning: ", panning)

func print_detailed_status():
	print("=== Camera Status ===")
	print("Position: ", global_position)
	print("Target Position: ", target_position)
	print("Rotation: ", rad_to_deg(rotation.y), "°")
	print("Moving: ", is_moving())
	print("Sprinting: ", is_sprinting)
	print("=== Panning Settings ===")
	print("Panning active: ", panning)
	print("Middle mouse pressed: ", middle_mouse_pressed)
	print("Pan sensitivity: ", pan_sensitivity)
	print("Pan speed multiplier: ", pan_speed_multiplier)
	print("Pan acceleration: ", pan_acceleration)
	print("Effective pan speed: ", get_effective_pan_speed())
	if chunk_terrain:
		print("=== Chunk System ===")
		print("Current Chunk: ", get_chunk_position())
		print("Loaded Chunks: ", chunk_terrain.get_loaded_chunk_count())
		print("Loading Chunks: ", chunk_terrain.get_loading_chunk_count())
	else:
		print("No chunk terrain system found")
