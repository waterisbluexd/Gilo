extends Node3D
class_name BuildingPlacer

# --- INSPECTOR CONFIGURABLE PARAMETERS ---
@export_group("References")
@export var camera: Camera3D
@export var building_data: Array[BuildingData] = []

@export_group("Building Settings")
@export var current_building_index: int = 0
@export var snap_to_grid: bool = true
@export var click_cooldown: float = 0.2

@export_group("Rotation Settings")
@export var enable_rotation: bool = true
@export var use_8_directions: bool = false
@export var rotation_snap_angle: float = 90.0

@export_group("Preview Settings - RTS Style")
@export var preview_height: float = 0.0
@export var preview_transparency: float = 0.6
@export var valid_color_tint: Color = Color(0.5, 1.0, 0.5, 1.0)
@export var invalid_color_tint: Color = Color(1.0, 0.3, 0.3, 1.0)
@export var prop_blocked_color_tint: Color = Color(1.0, 0.7, 0.3, 1.0)
@export var use_emission: bool = true
@export var emission_strength: float = 0.3

# --- INTERNAL ---
var navigation_grid: NavigationGrid
var is_placing_mode: bool = false
var preview_node: Node3D
var preview_materials: Array[Material] = []
var last_click_time: float = 0.0

# --- WALL BUILDING STATE ---
var is_building_wall: bool = false
var wall_start_point: Vector3 = Vector3.ZERO
var is_mouse_held: bool = false
var last_hovered_snapped_pos: Vector3 = Vector3.ZERO
var grid_cell_size: float = 1.0
@onready var wall_preview_container: Node3D = Node3D.new()

# Rotation variables
var current_rotation: int = 0
var max_rotations: int = 4

# Building category cycling
var category_start_index: int = -1
var category_end_index: int = -1
var is_category_mode: bool = false

signal placement_mode_changed(is_active: bool)


func get_current_building() -> BuildingData:
	if building_data.is_empty() or current_building_index >= building_data.size():
		return null
	return building_data[current_building_index]


func get_current_building_size() -> Vector2:
	var building = get_current_building()
	return building.size if building else Vector2(4, 4)


func get_rotated_building_size() -> Vector2:
	var building_size = get_current_building_size()
	
	if not use_8_directions:
		if current_rotation == 1 or current_rotation == 3:
			return Vector2(building_size.y, building_size.x)
		return building_size
	
	if current_rotation == 2 or current_rotation == 6:
		return Vector2(building_size.y, building_size.x)
	elif current_rotation == 1 or current_rotation == 3 or current_rotation == 5 or current_rotation == 7:
		var diagonal_size = max(building_size.x, building_size.y) * 1.2
		return Vector2(diagonal_size, diagonal_size)
	
	return building_size


func _ready():
	if use_8_directions:
		max_rotations = 8
		rotation_snap_angle = 45.0
	else:
		max_rotations = 4
		rotation_snap_angle = 90.0
	
	var parent = get_parent()
	if parent.has_method("get_node"):
		navigation_grid = parent.get_node("NavigationGrid") as NavigationGrid

	if not camera:
		camera = get_viewport().get_camera_3d()

	if not camera:
		push_error("BuildingPlacer: No camera assigned!")
		return

	if not navigation_grid:
		push_warning("BuildingPlacer: No NavigationGrid found.")
	else:
		grid_cell_size = navigation_grid.grid_cell_size

	if camera:
		if camera.has_signal("mouse_world_position_changed"):
			camera.mouse_world_position_changed.connect(_on_world_position_hovered)
		
		if camera.has_signal("mouse_world_position_clicked"):
			camera.mouse_world_position_clicked.connect(_on_world_position_clicked)

	_create_preview_node()
	
	wall_preview_container.name = "WallPreviewContainer"
	add_child(wall_preview_container)


func _input(event):
	# Handle wall building mouse release
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_building_wall and is_mouse_held and not event.pressed:
				# Finish wall placement on mouse release
				_finish_wall_placement()
				is_mouse_held = false
				get_viewport().set_input_as_handled()
				return
	
		# RIGHT CLICK - Cancel placement mode
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_placing_mode or is_building_wall:
				_cancel_placement_mode()
				get_viewport().set_input_as_handled()
			return
		
		# MOUSE SCROLL - Cycle through buildings
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
		elif event.keycode == KEY_Q and is_placing_mode and not is_building_wall:
			rotate_building_left()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and is_placing_mode and not is_building_wall:
			rotate_building_right()
			get_viewport().set_input_as_handled()


func _on_world_position_hovered(world_pos: Vector3, _hit_normal: Vector3, _hit_object: Node3D):
	if not is_placing_mode and not is_building_wall:
		return

	var snapped_pos = snap_to_grid_position(world_pos)
	last_hovered_snapped_pos = snapped_pos
	
	if is_building_wall:
		if is_mouse_held:
			# Update wall preview while dragging
			_draw_wall_preview(wall_start_point, snapped_pos)
	else:
		# Regular building preview
		_update_preview(snapped_pos)


func _on_world_position_clicked(world_pos: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return
	
	var building = get_current_building()
	if not building:
		return
	
	var snapped_pos = snap_to_grid_position(world_pos)
	
	# --- WALL BUILDING START ---
	if building.is_wall():
		is_building_wall = true
		is_mouse_held = true
		wall_start_point = snapped_pos
		
		# Hide single building preview, show wall preview
		if preview_node:
			preview_node.visible = false
		
		return
	
	# --- REGULAR BUILDING PLACEMENT ---
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_click_time < click_cooldown:
		return

	last_click_time = current_time
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
		return

	if _can_place_at(world_pos):
		_place_building_at(world_pos)


func _can_place_at(world_pos: Vector3) -> bool:
	if not navigation_grid:
		return true

	var building = get_current_building()
	var building_name = building.name if building else "Unknown"
	
	# Walls always use their base size (no rotation)
	var building_size = building.size if building.is_wall() else get_rotated_building_size()

	var check_result
	if building.is_wall():
		# Walls don't use rotation checks
		if navigation_grid.has_method("check_area_placement_with_props"):
			check_result = navigation_grid.check_area_placement_with_props(world_pos, building_size, building_name)
		else:
			check_result = navigation_grid.check_area_placement(world_pos, building_size, building_name)
	else:
		# Regular buildings use rotation
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

	if not _can_place_at(world_pos):
		return

	var rotated_size = get_rotated_building_size()
	
	# Walls don't use rotation
	if building.is_wall():
		navigation_grid.place_building(world_pos, building.size)
	else:
		# Regular buildings use rotation
		if navigation_grid.has_method("place_building_with_rotation"):
			navigation_grid.place_building_with_rotation(world_pos, rotated_size, current_rotation)
		else:
			navigation_grid.place_building(world_pos, rotated_size)
	
	_create_building_visual(world_pos, building)


func _create_preview_node():
	if preview_node:
		preview_node.queue_free()
	
	var building = get_current_building()
	if not building:
		return
	
	if building.prefab:
		preview_node = building.prefab.instantiate()
	else:
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(building.size.x, 2.0, building.size.y)
		mesh_instance.mesh = box_mesh
		preview_node = mesh_instance
	
	preview_node.name = "BuildingPreview_RTS"
	add_child(preview_node)
	
	_apply_preview_materials(preview_node, valid_color_tint)
	_update_preview_rotation()
	
	preview_node.visible = is_placing_mode


func _apply_preview_materials(node: Node, color_tint: Color):
	preview_materials.clear()
	
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var original_material = mesh_instance.get_active_material(0)
		var preview_material = StandardMaterial3D.new()
		
		if original_material and original_material is StandardMaterial3D:
			var orig = original_material as StandardMaterial3D
			preview_material.albedo_texture = orig.albedo_texture
			preview_material.albedo_color = orig.albedo_color * color_tint
		else:
			preview_material.albedo_color = color_tint
		
		preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview_material.albedo_color.a = preview_transparency
		preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		if use_emission:
			preview_material.emission_enabled = true
			preview_material.emission = Color(color_tint.r, color_tint.g, color_tint.b) * emission_strength
		
		mesh_instance.material_override = preview_material
		preview_materials.append(preview_material)
	
	for child in node.get_children():
		_apply_preview_materials(child, color_tint)


func _update_preview_color(color_tint: Color):
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

	var can_place = _can_place_at(world_pos)
	var color_tint = valid_color_tint
	
	if not can_place:
		var rotated_size = get_rotated_building_size()
		
		if navigation_grid:
			var check_result
			if navigation_grid.has_method("check_area_placement_with_rotation"):
				check_result = navigation_grid.check_area_placement_with_rotation(world_pos, rotated_size, current_rotation)
			elif navigation_grid.has_method("check_area_placement_with_props"):
				check_result = navigation_grid.check_area_placement_with_props(world_pos, rotated_size)
			else:
				check_result = {"blocking_props": []}
			
			if check_result.blocking_props.size() > 0:
				color_tint = prop_blocked_color_tint
			else:
				color_tint = invalid_color_tint
		else:
			color_tint = invalid_color_tint
	
	_update_preview_color(color_tint)


func _cancel_placement_mode():
	is_placing_mode = false
	is_building_wall = false
	is_mouse_held = false
	is_category_mode = false
	category_start_index = -1
	category_end_index = -1
	
	if preview_node:
		preview_node.visible = false
	
	_clear_wall_preview()
	
	emit_signal("placement_mode_changed", false)


func _create_building_visual(world_pos: Vector3, building: BuildingData):
	var building_node: Node3D
	if building.prefab:
		building_node = building.prefab.instantiate()
	else:
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(building.size.x, 2.0, building.size.y)
		mesh_instance.mesh = box_mesh

		var material = StandardMaterial3D.new()
		material.albedo_color = building.color if "color" in building else Color.BLUE
		mesh_instance.material_override = material

		building_node = mesh_instance

	building_node.position = world_pos + Vector3(building.size.x * 0.5, 0, building.size.y * 0.5)
	
	# Walls never rotate, regular buildings use current_rotation
	if not building.is_wall():
		building_node.rotation_degrees.y = current_rotation * rotation_snap_angle
	
	building_node.name = "Building_" + building.name + "_" + str(Time.get_ticks_msec())
	get_parent().add_child(building_node)

	# Configure spawner if present
	var spawner = building_node.get_node("BuildingSpawner") if building_node.has_node("BuildingSpawner") else null
	if spawner:
		spawner.configure_building(building)
		spawner.start_spawning()


# ============ PUBLIC API FOR UI BUTTONS ============

func select_building(index: int):
	if index >= 0 and index < building_data.size():
		current_building_index = index
		is_category_mode = false
		category_start_index = -1
		category_end_index = -1
		
		_create_preview_node()
		
		if not is_placing_mode:
			is_placing_mode = true
			if preview_node:
				preview_node.visible = true
			emit_signal("placement_mode_changed", true)


func select_building_category(start_index: int, end_index: int):
	if start_index < 0 or end_index >= building_data.size() or start_index > end_index:
		push_error("Invalid building category range: %d to %d" % [start_index, end_index])
		return
	
	is_category_mode = true
	category_start_index = start_index
	category_end_index = end_index
	current_building_index = start_index
	
	_create_preview_node()
	
	if not is_placing_mode:
		is_placing_mode = true
		if preview_node:
			preview_node.visible = true
		emit_signal("placement_mode_changed", true)


# ============ MOUSE SCROLL CYCLING ============

func _cycle_building_next():
	if is_category_mode:
		current_building_index += 1
		if current_building_index > category_end_index:
			current_building_index = category_start_index
	else:
		current_building_index = (current_building_index + 1) % building_data.size()
	
	_create_preview_node()


func _cycle_building_previous():
	if is_category_mode:
		current_building_index -= 1
		if current_building_index < category_start_index:
			current_building_index = category_end_index
	else:
		current_building_index = (current_building_index - 1 + building_data.size()) % building_data.size()
	
	_create_preview_node()


# ============ ROTATION FUNCTIONS ============

func rotate_building_left():
	if not enable_rotation:
		return
	
	current_rotation = (current_rotation - 1 + max_rotations) % max_rotations
	_update_preview_rotation()
	
	if preview_node and is_placing_mode:
		var world_pos = preview_node.position - Vector3(get_current_building_size().x * 0.5, 0, get_current_building_size().y * 0.5)
		_update_preview(world_pos)


func rotate_building_right():
	if not enable_rotation:
		return
	
	current_rotation = (current_rotation + 1) % max_rotations
	_update_preview_rotation()
	
	if preview_node and is_placing_mode:
		var world_pos = preview_node.position - Vector3(get_current_building_size().x * 0.5, 0, get_current_building_size().y * 0.5)
		_update_preview(world_pos)


func _update_preview_rotation():
	if not preview_node:
		return
	
	var rotation_degrees = current_rotation * rotation_snap_angle
	preview_node.rotation_degrees.y = rotation_degrees


# ============ WALL BUILDING FUNCTIONS ============

func _get_grid_line(start_grid_pos: Vector2i, end_grid_pos: Vector2i) -> Array[Vector2i]:
	var line_points: Array[Vector2i] = []
	var x0 = start_grid_pos.x
	var y0 = start_grid_pos.y
	var x1 = end_grid_pos.x
	var y1 = end_grid_pos.y

	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	while true:
		line_points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	
	return line_points


func _clear_wall_preview():
	for child in wall_preview_container.get_children():
		child.queue_free()


func _draw_wall_preview(from_world: Vector3, to_world: Vector3):
	_clear_wall_preview()
	
	if not navigation_grid:
		return
	
	var start_grid = navigation_grid.world_to_grid(from_world)
	var end_grid = navigation_grid.world_to_grid(to_world)
	var wall_points = _get_grid_line(start_grid, end_grid)
	
	var building = get_current_building()
	if not building or not building.prefab:
		return

	for grid_pos in wall_points:
		var center_pos = navigation_grid.grid_to_world(grid_pos)
		var placement_pos = center_pos - Vector3(grid_cell_size * 0.5, 0, grid_cell_size * 0.5)
		
		var preview_instance = building.prefab.instantiate()
		
		# Add to scene FIRST before setting global_position
		wall_preview_container.add_child(preview_instance)
		
		# Now set position (node is in tree)
		preview_instance.global_position = placement_pos + Vector3(grid_cell_size * 0.5, 0, grid_cell_size * 0.5)
		
		# Apply materials and colors
		_apply_preview_materials(preview_instance, valid_color_tint)
		
		if _can_place_at(placement_pos):
			_update_preview_color_for_node(preview_instance, valid_color_tint)
		else:
			_update_preview_color_for_node(preview_instance, invalid_color_tint)


func _update_preview_color_for_node(node: Node, color_tint: Color):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var material = mesh_instance.material_override
		if material and material is StandardMaterial3D:
			var mat = material as StandardMaterial3D
			mat.albedo_color = Color(color_tint.r, color_tint.g, color_tint.b, preview_transparency)
			if use_emission:
				mat.emission = Color(color_tint.r, color_tint.g, color_tint.b) * emission_strength
	
	for child in node.get_children():
		_update_preview_color_for_node(child, color_tint)


func _finish_wall_placement():
	if not is_building_wall:
		return
	
	_build_wall_line(wall_start_point, last_hovered_snapped_pos)
	_clear_wall_preview()
	
	# Reset wall state but keep placement mode active
	is_building_wall = false
	is_mouse_held = false
	
	# Show single building preview again
	if preview_node:
		preview_node.visible = true


func _build_wall_line(from_world: Vector3, to_world: Vector3):
	if not navigation_grid:
		return
	
	var start_grid = navigation_grid.world_to_grid(from_world)
	var end_grid = navigation_grid.world_to_grid(to_world)
	var wall_points = _get_grid_line(start_grid, end_grid)

	for grid_pos in wall_points:
		var center_pos = navigation_grid.grid_to_world(grid_pos)
		var placement_pos = center_pos - Vector3(grid_cell_size * 0.5, 0, grid_cell_size * 0.5)
		_try_place_building(placement_pos)
