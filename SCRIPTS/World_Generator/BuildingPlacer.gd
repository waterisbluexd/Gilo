extends Node3D
class_name BuildingPlacer

# --- INSPECTOR CONFIGURABLE PARAMETERS ---
@export_group("References")
@export var camera: Camera3D # Drag and drop your isometric camera here
@export var building_data: Array[BuildingData] = []

@export_group("Building Settings")
@export var current_building_index: int = 0
@export var snap_to_grid: bool = true
@export var click_cooldown: float = 0.2 # Delay between building placements (seconds)

@export_group("Rotation Settings")
@export var enable_rotation: bool = true
@export var use_8_directions: bool = false  # Enable 8-directional (45° increments)
@export var rotation_snap_angle: float = 90.0  # Degrees per rotation step

@export_group("Preview Settings - RTS Style")
@export var preview_height: float = 0.0 # Preview at ground level
@export var preview_transparency: float = 0.6 # How transparent the preview is (0-1)
@export var valid_color_tint: Color = Color(0.5, 1.0, 0.5, 1.0) # Green tint
@export var invalid_color_tint: Color = Color(1.0, 0.3, 0.3, 1.0) # Red tint
@export var prop_blocked_color_tint: Color = Color(1.0, 0.7, 0.3, 1.0) # Orange tint
@export var use_emission: bool = true
@export var emission_strength: float = 0.3

@export_group("Debug")
@export var debug_placement: bool = false
@export var show_grid_coordinates: bool = false
@export var always_show_placement_attempts: bool = true

# --- INTERNAL ---
var navigation_grid: NavigationGrid
var is_placing_mode: bool = false
var preview_node: Node3D
var preview_materials: Array[Material] = []
var last_click_time: float = 0.0

# Rotation variables
var current_rotation: int = 0
var max_rotations: int = 4

# Building category cycling (for variations)
var category_start_index: int = -1
var category_end_index: int = -1
var is_category_mode: bool = false

# Signal for camera communication
signal placement_mode_changed(is_active: bool)


func get_current_building() -> BuildingData:
	if building_data.is_empty() or current_building_index >= building_data.size():
		return null
	return building_data[current_building_index]


func get_current_building_size() -> Vector2:
	var building = get_current_building()
	return building.size if building else Vector2(4, 4)


# Get rotated building size for collision checking
func get_rotated_building_size() -> Vector2:
	var building_size = get_current_building_size()
	
	# For 4-directional: swap at 90° and 270°
	if not use_8_directions:
		if current_rotation == 1 or current_rotation == 3:
			return Vector2(building_size.y, building_size.x)
		return building_size
	
	# For 8-directional: swap at 90°, 270° (rotations 2 and 6)
	if current_rotation == 2 or current_rotation == 6:
		return Vector2(building_size.y, building_size.x)
	elif current_rotation == 1 or current_rotation == 3 or current_rotation == 5 or current_rotation == 7:
		# Diagonal rotations need expanded collision box
		var diagonal_size = max(building_size.x, building_size.y) * 1.2
		return Vector2(diagonal_size, diagonal_size)
	
	return building_size


func _ready():
	# Set rotation parameters based on directional mode
	if use_8_directions:
		max_rotations = 8
		rotation_snap_angle = 45.0
	else:
		max_rotations = 4
		rotation_snap_angle = 90.0
	
	# Try to find navigation grid in parent
	var parent = get_parent()
	if parent.has_method("get_node"):
		navigation_grid = parent.get_node("NavigationGrid") as NavigationGrid

	if not camera:
		camera = get_viewport().get_camera_3d()

	if not camera:
		push_error("BuildingPlacer: No camera assigned! Please assign the camera in the inspector.")
		return

	if not navigation_grid:
		push_warning("BuildingPlacer: No NavigationGrid found. Some features may not work properly.")
	elif debug_placement:
		ConsoleCapture.console_log("NavigationGrid found: %s chunks loaded" % navigation_grid.get_chunk_count())

	if debug_placement:
		ConsoleCapture.console_log("BuildingPlacer ready - %d buildings available" % building_data.size())
		ConsoleCapture.console_log("Rotation mode: %s directions (%d° increments)" % [max_rotations, rotation_snap_angle])

	if camera:
		if camera.has_signal("mouse_world_position_changed"):
			camera.mouse_world_position_changed.connect(_on_world_position_hovered)
			ConsoleCapture.console_log("Successfully connected to camera 'mouse_world_position_changed' signal.")
		else:
			push_warning("Camera script is missing the 'mouse_world_position_changed' signal!")

		if camera.has_signal("mouse_world_position_clicked"):
			camera.mouse_world_position_clicked.connect(_on_world_position_clicked)
			print("Successfully connected to camera 'mouse_world_position_clicked' signal.")
		else:
			push_warning("Camera script is missing the 'mouse_world_position_clicked' signal!")

	_create_preview_node()


func _input(event):
	# RIGHT CLICK - Cancel placement mode (RTS style)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_placing_mode:
				_cancel_placement_mode()
				get_viewport().set_input_as_handled()
			return
		
		# MOUSE SCROLL - Cycle through buildings when in placement mode
		elif is_placing_mode and is_category_mode:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_cycle_building_previous()
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_cycle_building_next()
				get_viewport().set_input_as_handled()
				return

	# KEY INPUTS
	elif event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select_building(event.keycode - KEY_1)
		# Q and E for rotation ONLY in placement mode
		elif event.keycode == KEY_Q and is_placing_mode:
			rotate_building_left()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and is_placing_mode:
			rotate_building_right()
			get_viewport().set_input_as_handled()


func _on_world_position_hovered(world_pos: Vector3, _hit_normal: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return

	var snapped_pos = snap_to_grid_position(world_pos)
	_update_preview(snapped_pos)


func _on_world_position_clicked(world_pos: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return

	# Check cooldown to prevent multiple rapid placements
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_click_time < click_cooldown:
		if debug_placement:
			ConsoleCapture.console_log("Click ignored due to cooldown (%.2fs remaining)" % (click_cooldown - (current_time - last_click_time)))
		return

	last_click_time = current_time
	var snapped_pos = snap_to_grid_position(world_pos)
	_try_place_building(snapped_pos)


func snap_to_grid_position(world_pos: Vector3) -> Vector3:
	if not navigation_grid:
		return world_pos

	var cell_size = navigation_grid.grid_cell_size if navigation_grid else 1.0
	var snapped_x = floor(world_pos.x / cell_size) * cell_size
	var snapped_z = floor(world_pos.z / cell_size) * cell_size
	return Vector3(snapped_x, 0, snapped_z)


func _try_place_building(world_pos: Vector3):
	var building = get_current_building()
	if not building:
		if debug_placement or always_show_placement_attempts:
			ConsoleCapture.console_log("❌ No building selected!")
		return

	if debug_placement:
		ConsoleCapture.console_log("Attempting to place building at: %s" % world_pos)

	if show_grid_coordinates:
		var grid_pos = navigation_grid.world_to_grid(world_pos) if navigation_grid else Vector2i.ZERO
		ConsoleCapture.console_log("Grid coordinates: %s" % grid_pos)

	if _can_place_at(world_pos):
		_place_building_at(world_pos)


func _can_place_at(world_pos: Vector3) -> bool:
	if not navigation_grid:
		return true

	var building = get_current_building()
	var building_name = building.name if building else "Unknown"
	var building_size = get_rotated_building_size()

	# Use the enhanced placement check with prop detection and rotation
	var check_result
	if navigation_grid.has_method("check_area_placement_with_rotation"):
		check_result = navigation_grid.check_area_placement_with_rotation(world_pos, building_size, current_rotation, building_name)
	elif navigation_grid.has_method("check_area_placement_with_props"):
		check_result = navigation_grid.check_area_placement_with_props(world_pos, building_size, building_name)
	else:
		check_result = navigation_grid.check_area_placement(world_pos, building_size, building_name)
	return check_result.can_place


func _place_building_at(world_pos: Vector3):
	var building = get_current_building()
	if not building:
		return

	# Double-check before placing
	if not _can_place_at(world_pos):
		if debug_placement:
			ConsoleCapture.console_log("Cannot place building - area became blocked!")
		return

	var rotated_size = get_rotated_building_size()
	
	# Place in navigation grid with rotation info
	if navigation_grid.has_method("place_building_with_rotation"):
		navigation_grid.place_building_with_rotation(world_pos, rotated_size, current_rotation)
	else:
		navigation_grid.place_building(world_pos, rotated_size)
	
	_create_building_visual(world_pos, building)

	if debug_placement:
		ConsoleCapture.console_log("Building placed: %s at: %s (rotation: %d°)" % [building.name, world_pos, current_rotation * rotation_snap_angle])
		if navigation_grid.has_method("get_memory_usage_estimate"):
			ConsoleCapture.console_log("Navigation grid memory: %s" % navigation_grid.get_memory_usage_estimate())
	
	# RTS Style: Keep placement mode active after placing


func _create_preview_node():
	if preview_node:
		preview_node.queue_free()
	
	var building = get_current_building()
	if not building:
		return
	
	# Clone the actual building prefab or create default visual
	if building.prefab:
		preview_node = building.prefab.instantiate()
	else:
		# Create default cube preview
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(building.size.x, 2.0, building.size.y)
		mesh_instance.mesh = box_mesh
		preview_node = mesh_instance
	
	preview_node.name = "BuildingPreview_RTS"
	add_child(preview_node)
	
	# Make all materials transparent and store originals
	_apply_preview_materials(preview_node, valid_color_tint)
	
	# Apply current rotation to new preview
	_update_preview_rotation()
	
	preview_node.visible = is_placing_mode


func _apply_preview_materials(node: Node, color_tint: Color):
	"""Apply transparent material to all mesh instances in the preview"""
	preview_materials.clear()
	
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		
		# Get current material or create new one
		var original_material = mesh_instance.get_active_material(0)
		var preview_material = StandardMaterial3D.new()
		
		# Copy properties from original if it exists
		if original_material and original_material is StandardMaterial3D:
			var orig = original_material as StandardMaterial3D
			preview_material.albedo_texture = orig.albedo_texture
			preview_material.albedo_color = orig.albedo_color * color_tint
		else:
			preview_material.albedo_color = color_tint
		
		# Make it transparent
		preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview_material.albedo_color.a = preview_transparency
		preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		# Add emission glow
		if use_emission:
			preview_material.emission_enabled = true
			preview_material.emission = Color(color_tint.r, color_tint.g, color_tint.b) * emission_strength
		
		mesh_instance.material_override = preview_material
		preview_materials.append(preview_material)
	
	# Recursively apply to children
	for child in node.get_children():
		_apply_preview_materials(child, color_tint)


func _update_preview_color(color_tint: Color):
	"""Update the color tint of all preview materials"""
	for material in preview_materials:
		if material is StandardMaterial3D:
			var mat = material as StandardMaterial3D
			mat.albedo_color = Color(color_tint.r, color_tint.g, color_tint.b, preview_transparency)
			
			if use_emission:
				mat.emission = Color(color_tint.r, color_tint.g, color_tint.b) * emission_strength


func _update_preview(world_pos: Vector3):
	if not preview_node or not is_placing_mode:
		return

	var building_size = get_current_building_size()
	preview_node.position = world_pos + Vector3(building_size.x * 0.5, preview_height, building_size.y * 0.5)

	# Check if placement is valid and update color accordingly
	var can_place = _can_place_at(world_pos)
	var color_tint = valid_color_tint
	
	if not can_place:
		var rotated_size = get_rotated_building_size()
		
		# Check if blocked by props specifically
		if navigation_grid:
			var check_result
			if navigation_grid.has_method("check_area_placement_with_rotation"):
				check_result = navigation_grid.check_area_placement_with_rotation(world_pos, rotated_size, current_rotation)
			elif navigation_grid.has_method("check_area_placement_with_props"):
				check_result = navigation_grid.check_area_placement_with_props(world_pos, rotated_size)
			else:
				check_result = {"blocking_props": []}
			
			if check_result.blocking_props.size() > 0:
				color_tint = prop_blocked_color_tint  # Orange for prop blocking
			else:
				color_tint = invalid_color_tint  # Red for other blocking
		else:
			color_tint = invalid_color_tint
	
	_update_preview_color(color_tint)


func _cancel_placement_mode():
	"""Cancel placement mode (RTS style - right click)"""
	is_placing_mode = false
	is_category_mode = false
	category_start_index = -1
	category_end_index = -1
	
	if preview_node:
		preview_node.visible = false
	
	# Notify camera that placement mode ended
	emit_signal("placement_mode_changed", false)

	if debug_placement:
		ConsoleCapture.console_log("Placement mode CANCELLED")


func _create_building_visual(world_pos: Vector3, building: BuildingData):
	var building_node: Node3D
	if building.prefab:
		building_node = building.prefab.instantiate()
	else:
		# Create default visual
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(building.size.x, 2.0, building.size.y)
		mesh_instance.mesh = box_mesh

		var material = StandardMaterial3D.new()
		material.albedo_color = building.color if "color" in building else Color.BLUE
		mesh_instance.material_override = material

		building_node = mesh_instance

	building_node.position = world_pos + Vector3(building.size.x * 0.5, 0, building.size.y * 0.5)
	
	# Apply rotation when placing
	building_node.rotation_degrees.y = current_rotation * rotation_snap_angle
	
	building_node.name = "Building_" + building.name + "_" + str(Time.get_ticks_msec())
	get_parent().add_child(building_node)

	# Configure spawner for buildings that can spawn NPCs
	var spawner = building_node.get_node("BuildingSpawner") if building_node.has_node("BuildingSpawner") else null
	if spawner:
		spawner.configure_building(building)
		spawner.start_spawning()
		if debug_placement:
			ConsoleCapture.console_log("Configured spawner for: %s" % building.name)
	elif building.building_type == BuildingData.BuildingType.CASTLE:
		if debug_placement:
			ConsoleCapture.console_log("Warning: Castle building has no BuildingSpawner component: %s" % building.name)


# ============ PUBLIC API FOR UI BUTTONS ============

func select_building(index: int):
	"""Select a single building by index (from number keys)"""
	if index >= 0 and index < building_data.size():
		current_building_index = index
		is_category_mode = false  # Single building selection, no category cycling
		category_start_index = -1
		category_end_index = -1
		
		_create_preview_node()
		
		# Auto-enable placement mode when selecting
		if not is_placing_mode:
			is_placing_mode = true
			if preview_node:
				preview_node.visible = true
			# Notify camera that placement mode started
			emit_signal("placement_mode_changed", true)
		
		if debug_placement:
			ConsoleCapture.console_log("Selected: %s (Index: %d)" % [building_data[index].name, index])


func select_building_category(start_index: int, end_index: int):
	"""Select a category of buildings (e.g., tent variations 8-10)
	User can then scroll through this range with mouse wheel
	Called by UI buttons like Tent_Button, Hovels_Button, etc."""
	if start_index < 0 or end_index >= building_data.size() or start_index > end_index:
		push_error("Invalid building category range: %d to %d (total buildings: %d)" % [start_index, end_index, building_data.size()])
		return
	
	is_category_mode = true
	category_start_index = start_index
	category_end_index = end_index
	current_building_index = start_index  # Start with first in category
	
	_create_preview_node()
	
	# Auto-enable placement mode
	if not is_placing_mode:
		is_placing_mode = true
		if preview_node:
			preview_node.visible = true
		# Notify camera that placement mode started
		emit_signal("placement_mode_changed", true)
	
	if debug_placement:
		ConsoleCapture.console_log("Selected building category: indices %d to %d (%d variations)" % [start_index, end_index, end_index - start_index + 1])
		var building = get_current_building()
		ConsoleCapture.console_log("Starting with: %s (Index: %d)" % [building.name if building else "None", current_building_index])


# ============ MOUSE SCROLL CYCLING ============

func _cycle_building_next():
	"""Cycle to next building using mouse scroll (within category if active)"""
	if is_category_mode:
		# Cycle within category range
		current_building_index += 1
		if current_building_index > category_end_index:
			current_building_index = category_start_index  # Wrap to start
	else:
		# Cycle through all buildings
		current_building_index = (current_building_index + 1) % building_data.size()
	
	_create_preview_node()
	
	if debug_placement:
		var building = get_current_building()
		var range_text = " (category %d-%d)" % [category_start_index, category_end_index] if is_category_mode else ""
		ConsoleCapture.console_log("Scrolled to NEXT: %s (Index: %d)%s" % [building.name if building else "None", current_building_index, range_text])


func _cycle_building_previous():
	"""Cycle to previous building using mouse scroll (within category if active)"""
	if is_category_mode:
		# Cycle within category range
		current_building_index -= 1
		if current_building_index < category_start_index:
			current_building_index = category_end_index  # Wrap to end
	else:
		# Cycle through all buildings
		current_building_index = (current_building_index - 1 + building_data.size()) % building_data.size()
	
	_create_preview_node()
	
	if debug_placement:
		var building = get_current_building()
		var range_text = " (category %d-%d)" % [category_start_index, category_end_index] if is_category_mode else ""
		ConsoleCapture.console_log("Scrolled to PREVIOUS: %s (Index: %d)%s" % [building.name if building else "None", current_building_index, range_text])


# ============ ROTATION FUNCTIONS ============

func rotate_building_left():
	"""Rotate building counterclockwise (Q key)"""
	if not enable_rotation:
		return
	
	current_rotation = (current_rotation - 1 + max_rotations) % max_rotations
	_update_preview_rotation()
	
	# Recheck placement validity with new rotation
	if preview_node and is_placing_mode:
		var world_pos = preview_node.position - Vector3(get_current_building_size().x * 0.5, 0, get_current_building_size().y * 0.5)
		_update_preview(world_pos)
	
	if debug_placement:
		ConsoleCapture.console_log("Rotated left: %d degrees" % (current_rotation * rotation_snap_angle))


func rotate_building_right():
	"""Rotate building clockwise (E key)"""
	if not enable_rotation:
		return
	
	current_rotation = (current_rotation + 1) % max_rotations
	_update_preview_rotation()
	
	# Recheck placement validity with new rotation
	if preview_node and is_placing_mode:
		var world_pos = preview_node.position - Vector3(get_current_building_size().x * 0.5, 0, get_current_building_size().y * 0.5)
		_update_preview(world_pos)
	
	if debug_placement:
		ConsoleCapture.console_log("Rotated right: %d degrees" % (current_rotation * rotation_snap_angle))


func _update_preview_rotation():
	"""Update preview node rotation"""
	if not preview_node:
		return
	
	var rotation_degrees = current_rotation * rotation_snap_angle
	preview_node.rotation_degrees.y = rotation_degrees
