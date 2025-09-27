#CameraPivot Script with Chunk System Integration and Panning
extends Node3D

# Rotation settings
var target_angle := 45.0
var current_angle := 0.0
var mouse_sensitivity := -0.5
var rotation_speed := 5.0
var dragging := false
var mouse_movement := 0.0

# Panning settings
var panning := true
var pan_sensitivity := 0.03
var pan_input := Vector2.ZERO

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
	handle_panning_input(delta)
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

func handle_panning_input(delta):
	# Apply panning movement if panning is active
	if panning and pan_input.length() > 0:
		# Get the camera's right and forward vectors (relative to camera orientation)
		var camera_right = transform.basis.x    # Camera's right direction
		var camera_forward = -transform.basis.z # Camera's forward direction (negative Z)
		
		# Calculate pan movement relative to camera orientation
		# Invert the input to make it feel like "grabbing and dragging" the world
		var pan_movement = Vector3.ZERO
		pan_movement += camera_right * -pan_input.x     # Drag left = move camera right (world moves left)
		pan_movement += camera_forward * pan_input.y    # Drag down = move camera forward (world moves back)
		
		# Keep movement on the horizontal plane (no Y movement)
		pan_movement.y = 0
		
		# Apply pan movement
		if smooth_movement:
			target_position += pan_movement
		else:
			global_position += pan_movement
			target_position = global_position
		
		# Reset pan input for next frame
		pan_input = Vector2.ZERO

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
				print("Panning: ", panning)
				print("Pan sensitivity: ", pan_sensitivity)
			KEY_BRACKETLEFT:  # [ key
				# Decrease pan sensitivity
				pan_sensitivity = max(0.001, pan_sensitivity - 0.005)
				print("Pan sensitivity: ", pan_sensitivity)
			KEY_BRACKETRIGHT:  # ] key
				# Increase pan sensitivity
				pan_sensitivity = min(0.1, pan_sensitivity + 0.005)
				print("Pan sensitivity: ", pan_sensitivity)
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
	if event is InputEventMouseMotion:
		if dragging:
			# Handle rotation
			mouse_movement += event.relative.x
		elif panning:
			# Handle panning
			pan_input += event.relative * pan_sensitivity

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
	pan_sensitivity = clamp(sensitivity, 0.001, 0.1)
	#print("Pan sensitivity set to: ", pan_sensitivity)

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
	print("Panning: ", panning)
	print("Pan Sensitivity: ", pan_sensitivity)
	if chunk_terrain:
		print("Current Chunk: ", get_chunk_position())
		print("Loaded Chunks: ", chunk_terrain.get_loaded_chunk_count())
		print("Loading Chunks: ", chunk_terrain.get_loading_chunk_count())
	else:
		print("No chunk terrain system found")
