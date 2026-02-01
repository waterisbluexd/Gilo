extends Node3D
class_name BuildingPlacer

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

@export_group("Preview Settings")
@export var preview_height: float = 0.0
@export var preview_transparency: float = 0.6
@export var show_invalid_overlay: bool = true
@export var invalid_modulate: Color = Color(1.0, 0.4, 0.4, 0.7)

@export_group("Destroy Settings")
@export var destroy_indicator_color: Color = Color(1.0, 0.0, 0.0, 0.5)

var navigation_grid: NavigationGrid
var is_placing_mode: bool = false
var is_destroy_mode: bool = false
var preview_node: Node3D
var preview_materials: Array[Material] = []
var last_click_time: float = 0.0
var is_placement_valid: bool = true
var invalid_indicator: MeshInstance3D
var destroy_indicator: MeshInstance3D

var is_building_wall: bool = false
var wall_start_point: Vector3 = Vector3.ZERO
var is_mouse_held: bool = false
var last_hovered_snapped_pos: Vector3 = Vector3.ZERO
var grid_cell_size: float = 1.0
@onready var wall_preview_container: Node3D = Node3D.new()

var is_shift_held: bool = false
var wall_type_1_index: int = -1
var wall_type_2_index: int = -1

var current_rotation: int = 0
var max_rotations: int = 4

var category_indices: Array[int] = []
var is_category_mode: bool = false

var placed_buildings: Dictionary = {}
var hovered_building: Node3D = null
var is_destroy_mouse_held: bool = false
var destroyed_building_keys: Array[String] = []

signal placement_mode_changed(is_active: bool)
signal destroy_mode_changed(is_active: bool)
signal building_destroyed(building_name: String, position: Vector3)


func get_current_building() -> BuildingData:
	if building_data.is_empty() or current_building_index >= building_data.size():
		return null
	return building_data[current_building_index]


func get_building_by_index(index: int) -> BuildingData:
	if building_data.is_empty() or index < 0 or index >= building_data.size():
		return null
	return building_data[index]


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
	_create_invalid_indicator()
	_create_destroy_indicator()
	
	wall_preview_container.name = "WallPreviewContainer"
	add_child(wall_preview_container)


func _input(event):
	if event is InputEventKey:
		if event.keycode == KEY_SHIFT or event.physical_keycode == KEY_SHIFT:
			is_shift_held = event.pressed
			
			if is_shift_held and is_building_wall and is_mouse_held and wall_type_2_index == -1:
				var available_wall_indices: Array[int] = []
				
				if is_category_mode:
					for idx in category_indices:
						var building = get_building_by_index(idx)
						if building and building.is_wall():
							available_wall_indices.append(idx)
				else:
					available_wall_indices = _get_all_wall_building_indices()
				
				if available_wall_indices.size() > 1:
					var current_pos = available_wall_indices.find(wall_type_1_index)
					if current_pos != -1:
						wall_type_2_index = available_wall_indices[(current_pos + 1) % available_wall_indices.size()]
					else:
						wall_type_2_index = available_wall_indices[0]
			
			if is_building_wall and is_mouse_held:
				_draw_wall_preview(wall_start_point, last_hovered_snapped_pos)
			return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_destroy_mode:
				if event.pressed:
					is_destroy_mouse_held = true
					destroyed_building_keys.clear()
				else:
					is_destroy_mouse_held = false
					destroyed_building_keys.clear()
				get_viewport().set_input_as_handled()
				return
			
			if is_building_wall and is_mouse_held and not event.pressed:
				_finish_wall_placement()
				is_mouse_held = false
				get_viewport().set_input_as_handled()
				return
	
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_placing_mode or is_building_wall or is_destroy_mode:
				_cancel_all_modes()
				get_viewport().set_input_as_handled()
			return
		
		elif is_building_wall:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_cycle_wall_type_up()
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_cycle_wall_type_down()
				get_viewport().set_input_as_handled()
				return
		
		elif is_placing_mode and is_category_mode:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_cycle_building_previous()
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_cycle_building_next()
				get_viewport().set_input_as_handled()
				return

	elif event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select_building(event.keycode - KEY_1)
		elif event.keycode == KEY_Q and is_placing_mode and not is_building_wall:
			rotate_building_left()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and is_placing_mode and not is_building_wall:
			rotate_building_right()
			get_viewport().set_input_as_handled()


func _cycle_wall_type_up():
	var all_wall_indices = _get_all_wall_building_indices()
	if all_wall_indices.is_empty():
		return
	
	if is_shift_held:
		if wall_type_2_index == -1:
			var type1_pos = all_wall_indices.find(wall_type_1_index)
			if type1_pos != -1:
				wall_type_2_index = all_wall_indices[(type1_pos + 1) % all_wall_indices.size()]
			else:
				wall_type_2_index = all_wall_indices[0]
		else:
			var current_pos = all_wall_indices.find(wall_type_2_index)
			wall_type_2_index = all_wall_indices[(current_pos + 1) % all_wall_indices.size()]
	else:
		var current_pos = all_wall_indices.find(wall_type_1_index)
		wall_type_1_index = all_wall_indices[(current_pos + 1) % all_wall_indices.size()]
		current_building_index = wall_type_1_index
	
	if is_mouse_held:
		_draw_wall_preview(wall_start_point, last_hovered_snapped_pos)


func _cycle_wall_type_down():
	var all_wall_indices = _get_all_wall_building_indices()
	if all_wall_indices.is_empty():
		return
	
	if is_shift_held:
		if wall_type_2_index == -1:
			var type1_pos = all_wall_indices.find(wall_type_1_index)
			if type1_pos != -1:
				wall_type_2_index = all_wall_indices[(type1_pos - 1 + all_wall_indices.size()) % all_wall_indices.size()]
			else:
				wall_type_2_index = all_wall_indices[all_wall_indices.size() - 1]
		else:
			var current_pos = all_wall_indices.find(wall_type_2_index)
			wall_type_2_index = all_wall_indices[(current_pos - 1 + all_wall_indices.size()) % all_wall_indices.size()]
	else:
		var current_pos = all_wall_indices.find(wall_type_1_index)
		wall_type_1_index = all_wall_indices[(current_pos - 1 + all_wall_indices.size()) % all_wall_indices.size()]
		current_building_index = wall_type_1_index
	
	if is_mouse_held:
		_draw_wall_preview(wall_start_point, last_hovered_snapped_pos)


func _get_all_wall_building_indices() -> Array[int]:
	var wall_indices: Array[int] = []
	for i in range(building_data.size()):
		if building_data[i].is_wall():
			wall_indices.append(i)
	return wall_indices


func _on_world_position_hovered(world_pos: Vector3, _hit_normal: Vector3, hit_object: Node3D):
	if is_destroy_mode:
		_update_destroy_hover(world_pos, hit_object)
		return
	
	if not is_placing_mode and not is_building_wall:
		return

	var snapped_pos = snap_to_grid_position(world_pos)
	last_hovered_snapped_pos = snapped_pos
	
	if is_building_wall:
		if is_mouse_held:
			_draw_wall_preview(wall_start_point, snapped_pos)
	else:
		_update_preview(snapped_pos)


func _on_world_position_clicked(world_pos: Vector3, hit_object: Node3D):
	if is_destroy_mode:
		_handle_destroy_click(world_pos, hit_object)
		return
	
	if not is_placing_mode:
		return
	
	var building = get_current_building()
	if not building:
		return
	
	var snapped_pos = snap_to_grid_position(world_pos)
	
	if building.is_wall():
		is_building_wall = true
		is_mouse_held = true
		wall_start_point = snapped_pos
		
		wall_type_1_index = current_building_index
		wall_type_2_index = -1
		
		if preview_node:
			preview_node.visible = false
		
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_click_time < click_cooldown:
		return

	last_click_time = current_time
	
	var rotated_size = get_rotated_building_size()
	var corner_pos = snapped_pos - Vector3(rotated_size.x * 0.5, 0, rotated_size.y * 0.5)
	_try_place_building(corner_pos)


func snap_to_grid_position(world_pos: Vector3) -> Vector3:
	if not navigation_grid:
		return world_pos

	var cell_size = navigation_grid.grid_cell_size if navigation_grid else 1.0
	var snapped_x = floor(world_pos.x / cell_size) * cell_size
	var snapped_z = floor(world_pos.z / cell_size) * cell_size
	return Vector3(snapped_x, 0, snapped_z)


func _try_place_building(world_pos: Vector3, override_building_index: int = -1):
	var building: BuildingData
	if override_building_index >= 0:
		building = get_building_by_index(override_building_index)
	else:
		building = get_current_building()
	
	if not building:
		return

	if _can_place_at(world_pos, building):
		_place_building_at(world_pos, building)


func _can_place_at(world_pos: Vector3, building: BuildingData = null) -> bool:
	if not navigation_grid:
		return true

	if not building:
		building = get_current_building()
	
	if not building:
		return false
		
	var building_size = building.size if building.is_wall() else get_rotated_building_size()

	var check_result
	if building.is_wall():
		if navigation_grid.has_method("check_area_placement_with_props"):
			check_result = navigation_grid.check_area_placement_with_props(world_pos, building_size, building.name)
		else:
			check_result = navigation_grid.check_area_placement(world_pos, building_size, building.name)
	else:
		if navigation_grid.has_method("check_area_placement_with_rotation"):
			check_result = navigation_grid.check_area_placement_with_rotation(world_pos, building_size, current_rotation, building.name)
		elif navigation_grid.has_method("check_area_placement_with_props"):
			check_result = navigation_grid.check_area_placement_with_props(world_pos, building_size, building.name)
		else:
			check_result = navigation_grid.check_area_placement(world_pos, building_size, building.name)
	
	if check_result.can_place:
		return true
	
	if not "ignore_collision_with_names" in building or building.ignore_collision_with_names.is_empty():
		return false
	
	if check_result.has("blocking_buildings") and check_result.blocking_buildings.size() > 0:
		for building_name_blocking in check_result.blocking_buildings:
			if not building.ignore_collision_with_names.has(building_name_blocking):
				return false
	
	if check_result.has("blocking_props") and check_result.blocking_props.size() > 0:
		return false
	
	if check_result.has("is_area_blocked") and check_result.is_area_blocked:
		return false

	return true


func _place_building_at(world_pos: Vector3, building: BuildingData = null):
	if not building:
		building = get_current_building()
	
	if not building:
		return

	if not _can_place_at(world_pos, building):
		return

	# Remove preview node before creating the actual building to avoid duplicate _Ready() calls
	if preview_node:
		preview_node.queue_free()
		preview_node = null

	var rotated_size = get_rotated_building_size()
	
	if building.is_wall():
		navigation_grid.place_building_with_name(world_pos, building.size, building.name)
	else:
		if navigation_grid.has_method("place_building_with_rotation_and_name"):
			navigation_grid.place_building_with_rotation_and_name(world_pos, rotated_size, current_rotation, building.name)
		else:
			navigation_grid.place_building_with_name(world_pos, rotated_size, building.name)
	
	var building_node = _create_building_visual(world_pos, building)
	if building_node:
		var grid_key = _get_grid_key(world_pos)
		placed_buildings[grid_key] = {
			"node": building_node,
			"position": world_pos,
			"size": rotated_size if not building.is_wall() else building.size,
			"building_data": building,
			"rotation": current_rotation if not building.is_wall() else 0
		}


func _create_preview_node():
	if preview_node:
		preview_node.queue_free()
	
	var building = get_current_building()
	if not building:
		return
	
	if building.prefab:
		preview_node = building.prefab.instantiate()
		# Mark as preview so Castle script doesn't initialize
		if preview_node.has_method("SetAsPreview"):
			preview_node.call("SetAsPreview", true)
	else:
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(building.size.x, 2.0, building.size.y)
		mesh_instance.mesh = box_mesh
		preview_node = mesh_instance
	
	preview_node.name = "BuildingPreview"
	add_child(preview_node)
	
	_apply_stronghold_preview_materials(preview_node)
	_update_preview_rotation()
	
	preview_node.visible = is_placing_mode


func _create_invalid_indicator():
	if invalid_indicator:
		invalid_indicator.queue_free()
	
	invalid_indicator = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(2.0, 2.0)
	invalid_indicator.mesh = plane_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	invalid_indicator.material_override = material
	invalid_indicator.rotation_degrees.x = -90
	invalid_indicator.visible = false
	add_child(invalid_indicator)


func _create_destroy_indicator():
	destroy_indicator = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(2.0, 2.0)
	destroy_indicator.mesh = plane_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = destroy_indicator_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	destroy_indicator.material_override = material
	destroy_indicator.rotation_degrees.x = -90
	destroy_indicator.visible = false
	add_child(destroy_indicator)


func _apply_stronghold_preview_materials(node: Node):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var original_material = mesh_instance.get_active_material(0)
		var preview_material = StandardMaterial3D.new()
		
		if original_material and original_material is StandardMaterial3D:
			var orig = original_material as StandardMaterial3D
			preview_material.albedo_texture = orig.albedo_texture
			preview_material.albedo_color = orig.albedo_color
		else:
			preview_material.albedo_color = Color.WHITE
		
		preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview_material.albedo_color.a = preview_transparency
		preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		
		mesh_instance.material_override = preview_material
		preview_materials.append(preview_material)
	
	for child in node.get_children():
		_apply_stronghold_preview_materials(child)


func _update_preview_tint(node: Node, tint: Color):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var material = mesh_instance.material_override
		if material and material is StandardMaterial3D:
			var mat = material as StandardMaterial3D
			if not mat.has_meta("original_color"):
				mat.set_meta("original_color", mat.albedo_color)
			
			var original = mat.get_meta("original_color") as Color
			mat.albedo_color = Color(
				original.r * tint.r,
				original.g * tint.g,
				original.b * tint.b,
				preview_transparency
			)
	
	for child in node.get_children():
		_update_preview_tint(child, tint)


func _update_preview(world_pos: Vector3):
	if not preview_node or not is_placing_mode:
		return

	var building = get_current_building()
	if not building:
		return

	var rotated_size = get_rotated_building_size()
	var corner_pos = world_pos - Vector3(rotated_size.x * 0.5, 0, rotated_size.y * 0.5)
	
	preview_node.position = corner_pos + Vector3(rotated_size.x * 0.5, preview_height, rotated_size.y * 0.5)

	var can_place = _can_place_at(corner_pos)
	is_placement_valid = can_place
	
	if show_invalid_overlay and invalid_indicator:
		invalid_indicator.visible = not can_place
		if not can_place:
			invalid_indicator.global_position = corner_pos + Vector3(rotated_size.x * 0.5, 0.1, rotated_size.y * 0.5)
			invalid_indicator.scale = Vector3(rotated_size.x, 1, rotated_size.y)
	
	_update_preview_tint(preview_node, invalid_modulate if not can_place else Color.WHITE)


func _cancel_all_modes():
	_cancel_placement_mode()
	_cancel_destroy_mode()


func _cancel_placement_mode():
	is_placing_mode = false
	is_building_wall = false
	is_mouse_held = false
	is_category_mode = false
	is_shift_held = false
	category_indices.clear()
	wall_type_1_index = -1
	wall_type_2_index = -1
	
	if preview_node:
		preview_node.visible = false
	
	if invalid_indicator:
		invalid_indicator.visible = false
	
	_clear_wall_preview()
	
	emit_signal("placement_mode_changed", false)


func _create_building_visual(world_pos: Vector3, building: BuildingData) -> Node3D:
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
	
	if not building.is_wall():
		building_node.rotation_degrees.y = current_rotation * rotation_snap_angle
	
	building_node.name = "Building_" + building.name + "_" + str(Time.get_ticks_msec())
	get_parent().add_child(building_node)

	var spawner = building_node.get_node("BuildingSpawner") if building_node.has_node("BuildingSpawner") else null
	if spawner:
		spawner.configure_building(building)
		spawner.start_spawning()
	
	return building_node


func select_building(index: int):
	if index >= 0 and index < building_data.size():
		current_building_index = index
		is_category_mode = false
		category_indices.clear()
		
		_create_preview_node()
		
		if not is_placing_mode:
			is_placing_mode = true
			if preview_node:
				preview_node.visible = true
			emit_signal("placement_mode_changed", true)


func select_building_category(indices: Array[int]):
	if indices.is_empty():
		return
	
	for idx in indices:
		if idx < 0 or idx >= building_data.size():
			return
	
	is_category_mode = true
	category_indices = indices.duplicate()
	current_building_index = category_indices[0]
	
	_create_preview_node()
	
	if not is_placing_mode:
		is_placing_mode = true
		if preview_node:
			preview_node.visible = true
		emit_signal("placement_mode_changed", true)


func _cycle_building_next():
	if is_category_mode:
		var current_pos = category_indices.find(current_building_index)
		if current_pos == -1:
			current_building_index = category_indices[0]
		else:
			current_building_index = category_indices[(current_pos + 1) % category_indices.size()]
	else:
		current_building_index = (current_building_index + 1) % building_data.size()
	
	_create_preview_node()


func _cycle_building_previous():
	if is_category_mode:
		var current_pos = category_indices.find(current_building_index)
		if current_pos == -1:
			current_building_index = category_indices[category_indices.size() - 1]
		else:
			current_building_index = category_indices[(current_pos - 1 + category_indices.size()) % category_indices.size()]
	else:
		current_building_index = (current_building_index - 1 + building_data.size()) % building_data.size()
	
	_create_preview_node()


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
	
	var building_type_1 = get_building_by_index(wall_type_1_index)
	var building_type_2 = get_building_by_index(wall_type_2_index) if is_shift_held and wall_type_2_index >= 0 else null
	
	if not building_type_1:
		return

	for i in range(wall_points.size()):
		var grid_pos = wall_points[i]
		var center_pos = navigation_grid.grid_to_world(grid_pos)
		var placement_pos = center_pos - Vector3(grid_cell_size * 0.5, 0, grid_cell_size * 0.5)
		
		var current_building: BuildingData
		if is_shift_held and building_type_2:
			current_building = building_type_1 if i % 2 == 0 else building_type_2
		else:
			current_building = building_type_1
		
		if not current_building or not current_building.prefab:
			continue
		
		var preview_instance = current_building.prefab.instantiate()
		# Mark as preview so Castle script doesn't initialize
		if preview_instance.has_method("SetAsPreview"):
			preview_instance.call("SetAsPreview", true)
		wall_preview_container.add_child(preview_instance)
		preview_instance.global_position = placement_pos + Vector3(grid_cell_size * 0.5, 0, grid_cell_size * 0.5)
		
		_apply_stronghold_preview_materials(preview_instance)
		
		var can_place_wall_segment = _can_place_at(placement_pos, current_building)
		_update_preview_tint(preview_instance, invalid_modulate if not can_place_wall_segment else Color.WHITE)


func _finish_wall_placement():
	if not is_building_wall:
		return
	
	_build_wall_line(wall_start_point, last_hovered_snapped_pos)
	_clear_wall_preview()
	
	is_building_wall = false
	is_mouse_held = false
	
	if preview_node:
		preview_node.visible = true


func _build_wall_line(from_world: Vector3, to_world: Vector3):
	if not navigation_grid:
		return
	
	var start_grid = navigation_grid.world_to_grid(from_world)
	var end_grid = navigation_grid.world_to_grid(to_world)
	var points = _get_grid_line(start_grid, end_grid)
	
	var type_1 = get_building_by_index(wall_type_1_index)
	var type_2 = get_building_by_index(wall_type_2_index) if is_shift_held and wall_type_2_index >= 0 else null

	for i in range(points.size()):
		var grid_pos = points[i]
		var center_pos = navigation_grid.grid_to_world(grid_pos)
		var placement_pos = center_pos - Vector3(grid_cell_size * 0.5, 0, grid_cell_size * 0.5)
		
		var current_building: BuildingData
		if is_shift_held and type_2:
			current_building = type_1 if i % 2 == 0 else type_2
		else:
			current_building = type_1
		
		if not current_building:
			continue
		
		_try_place_building(placement_pos, current_building_index if current_building == type_1 else wall_type_2_index)


func enable_destroy_mode():
	_cancel_placement_mode()
	is_destroy_mode = true
	emit_signal("destroy_mode_changed", true)


func _cancel_destroy_mode():
	is_destroy_mode = false
	is_destroy_mouse_held = false
	destroyed_building_keys.clear()
	hovered_building = null
	if destroy_indicator:
		destroy_indicator.visible = false
	emit_signal("destroy_mode_changed", false)


func _update_destroy_hover(world_pos: Vector3, hit_object: Node3D):
	var snapped_pos = snap_to_grid_position(world_pos)
	var building_info = _find_building_at_position(snapped_pos)
	
	if building_info:
		hovered_building = building_info.node
		if destroy_indicator:
			var size = building_info.size
			destroy_indicator.visible = true
			destroy_indicator.global_position = building_info.position + Vector3(size.x * 0.5, 0.1, size.y * 0.5)
			destroy_indicator.scale = Vector3(size.x, 1, size.y)
		
		if is_destroy_mouse_held:
			var grid_key = _get_grid_key(building_info.position)
			if not destroyed_building_keys.has(grid_key):
				_destroy_building(building_info)
				destroyed_building_keys.append(grid_key)
	else:
		hovered_building = null
		if destroy_indicator:
			destroy_indicator.visible = false


func _handle_destroy_click(world_pos: Vector3, hit_object: Node3D):
	if not is_destroy_mouse_held:
		return
	
	var snapped_pos = snap_to_grid_position(world_pos)
	var building_info = _find_building_at_position(snapped_pos)
	
	if building_info:
		var grid_key = _get_grid_key(building_info.position)
		if not destroyed_building_keys.has(grid_key):
			_destroy_building(building_info)
			destroyed_building_keys.append(grid_key)


func _find_building_at_position(world_pos: Vector3) -> Dictionary:
	for grid_key in placed_buildings.keys():
		var building_info = placed_buildings[grid_key]
		var pos = building_info.position
		var size = building_info.size
		
		if world_pos.x >= pos.x and world_pos.x < pos.x + size.x and world_pos.z >= pos.z and world_pos.z < pos.z + size.y:
			return building_info
	
	return {}


func _destroy_building(building_info: Dictionary):
	if not building_info or not building_info.has("node"):
		return
	
	var building_node = building_info.node
	var building_pos = building_info.position
	var building_size = building_info.size
	var building_data_res = building_info.building_data
	
	if navigation_grid:
		if navigation_grid.has_method("remove_building_with_name"):
			navigation_grid.remove_building_with_name(building_pos, building_size, building_data_res.name)
		elif navigation_grid.has_method("remove_building"):
			navigation_grid.remove_building(building_pos, building_size)
	
	if building_node and is_instance_valid(building_node):
		building_node.queue_free()
	
	var grid_key = _get_grid_key(building_pos)
	placed_buildings.erase(grid_key)
	
	emit_signal("building_destroyed", building_data_res.name, building_pos)
	
	if hovered_building == building_node:
		hovered_building = null
		if destroy_indicator:
			destroy_indicator.visible = false


func _get_grid_key(world_pos: Vector3) -> String:
	return str(int(world_pos.x)) + "_" + str(int(world_pos.z))
