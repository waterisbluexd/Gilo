extends Node3D
class_name BuildingPlacer

# --- REFERENCES ---
@export var camera: Camera3D  # Drag and drop your isometric camera here
@export var building_data: Array[BuildingData] = []
@export var current_building_index: int = 0
@export var snap_to_grid: bool = true

# --- INTERNAL ---
var navigation_grid: NavigationGrid
var is_placing_mode: bool = false
var preview_mesh: MeshInstance3D

# --- Grid visualization ---
var grid_lines: Node3D
@export var show_grid: bool = true
@export var grid_size: float = 1.0
@export var grid_extent: int = 50  # How far the grid extends from center
@export var grid_color: Color = Color(0.5, 0.5, 0.5, 0.3)
# --- NEW: Variables to smartly update the grid ---
# How far the camera must move before the grid redraws
@export var grid_update_threshold: float = 5.0 
var last_grid_update_camera_pos: Vector3 = Vector3.INF


func get_current_building() -> BuildingData:
	if building_data.is_empty() or current_building_index >= building_data.size():
		return null
	return building_data[current_building_index]

func get_current_building_size() -> Vector2:
	var building = get_current_building()
	return building.size if building else Vector2(4, 4)

func _ready():
	# Try to find navigation grid in parent
	var parent = get_parent()
	if parent.has_method("get_node"): # Check if parent is a valid Node
		navigation_grid = parent.get_node("NavigationGrid") as NavigationGrid

	if not camera:
		camera = get_viewport().get_camera_3d()

	if not camera:
		push_error("BuildingPlacer: No camera assigned! Please assign the camera in the inspector.")
		return

	if not navigation_grid:
		push_warning("BuildingPlacer: No NavigationGrid found. Some features may not work properly.")

	print("BuildingPlacer ready.")
	
	if camera:
		if camera.has_signal("mouse_world_position_changed"):
			camera.mouse_world_position_changed.connect(_on_world_position_hovered)
			print("Successfully connected to camera 'mouse_world_position_changed' signal.")
		else:
			push_warning("Camera script is missing the 'mouse_world_position_changed' signal!")
			
		if camera.has_signal("mouse_world_position_clicked"):
			camera.mouse_world_position_clicked.connect(_on_world_position_clicked)
			print("Successfully connected to camera 'mouse_world_position_clicked' signal.")
		else:
			push_warning("Camera script is missing the 'mouse_world_position_clicked' signal! (This is for placing buildings).")
	
	_create_preview_mesh()
	_create_grid_visualization()

# --- NEW: _process function to handle grid updates ---
func _process(_delta):
	# Only check for grid updates if we are in placement mode and the grid is visible
	if is_placing_mode and show_grid and camera:
		# Project current camera position to the ground plane for a stable comparison
		var current_cam_pos_flat = camera.global_position
		current_cam_pos_flat.y = 0
		
		# Check if the camera has moved past our threshold distance
		if current_cam_pos_flat.distance_to(last_grid_update_camera_pos) > grid_update_threshold:
			_update_grid_visualization()


func _create_grid_visualization():
	if not grid_lines:
		grid_lines = Node3D.new()
		grid_lines.name = "GridLines"
		add_child(grid_lines)
	
	grid_lines.visible = show_grid
	if show_grid:
		_update_grid_visualization()

func _update_grid_visualization():
	if not grid_lines or not show_grid or not camera:
		return
	
	for child in grid_lines.get_children():
		child.queue_free()
	
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = grid_color
	line_material.flags_unshaded = true
	line_material.flags_transparent = true
	
	var camera_pos = camera.global_position
	camera_pos.y = 0
	
	# --- NEW: Store the position where we last updated the grid ---
	last_grid_update_camera_pos = camera_pos
	
	var visible_radius = (camera.size if camera else 50.0) + 20.0
	
	var min_x = floor((camera_pos.x - visible_radius) / grid_size) * grid_size
	var max_x = ceil((camera_pos.x + visible_radius) / grid_size) * grid_size
	var min_z = floor((camera_pos.z - visible_radius) / grid_size) * grid_size
	var max_z = ceil((camera_pos.z + visible_radius) / grid_size) * grid_size
	
	var x = min_x
	while x <= max_x:
		var line = _create_line_mesh(Vector3(x, 0.01, min_z), Vector3(x, 0.01, max_z))
		line.material_override = line_material
		grid_lines.add_child(line)
		x += grid_size
	
	var z = min_z
	while z <= max_z:
		var line = _create_line_mesh(Vector3(min_x, 0.01, z), Vector3(max_x, 0.01, z))
		line.material_override = line_material
		grid_lines.add_child(line)
		z += grid_size

func _create_line_mesh(start: Vector3, end: Vector3) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var imm_mesh = ImmediateMesh.new()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	imm_mesh.surface_add_vertex(start)
	imm_mesh.surface_add_vertex(end)
	imm_mesh.surface_end()
	mesh_instance.mesh = imm_mesh
	return mesh_instance

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_toggle_placement_mode()
	
	elif event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select_building(event.keycode - KEY_1)
		elif event.keycode == KEY_G:
			toggle_grid_visibility()

func _on_world_position_hovered(world_pos: Vector3, _hit_normal: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return
		
	var snapped_pos = snap_to_grid_position(world_pos)
	_update_preview(snapped_pos)

func _on_world_position_clicked(world_pos: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return
		
	var snapped_pos = snap_to_grid_position(world_pos)
	_try_place_building(snapped_pos)

func snap_to_grid_position(world_pos: Vector3) -> Vector3:
	if not navigation_grid:
		return world_pos
	var cell_size = 1.0 # Fallback
	if "grid_cell_size" in navigation_grid:
		cell_size = navigation_grid.grid_cell_size
	var snapped_x = floor(world_pos.x / cell_size) * cell_size
	var snapped_z = floor(world_pos.z / cell_size) * cell_size
	return Vector3(snapped_x, 0, snapped_z)

func _try_place_building(world_pos: Vector3):
	if _can_place_at(world_pos):
		_place_building_at(world_pos)

func _can_place_at(world_pos: Vector3) -> bool:
	if not navigation_grid:
		return true 
	var building_size = get_current_building_size()
	var grid_start = navigation_grid.world_to_grid(world_pos)
	
	for x in range(grid_start.x, grid_start.x + int(building_size.x)):
		for y in range(grid_start.y, grid_start.y + int(building_size.y)):
			if not navigation_grid.is_walkable(Vector2i(x, y)):
				return false
	return true

func _place_building_at(world_pos: Vector3):
	var building = get_current_building()
	if not building: return
	
	navigation_grid.place_building(world_pos, building.size)
	_create_building_visual(world_pos, building)
	print("Building placed: ", building.name, " at: ", world_pos)

func _create_preview_mesh():
	preview_mesh = MeshInstance3D.new()
	preview_mesh.name = "BuildingPreview"
	add_child(preview_mesh)
	_update_preview_mesh()
	preview_mesh.visible = false

func _update_preview_mesh():
	if not preview_mesh: return
	var building_size = get_current_building_size()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(building_size.x, 1.0, building_size.y)
	preview_mesh.mesh = box_mesh
	
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview_mesh.material_override = material

func _update_preview(world_pos: Vector3):
	if not preview_mesh or not is_placing_mode: return
		
	var building_size = get_current_building_size()
	preview_mesh.position = world_pos + Vector3(building_size.x * 0.5, 0.5, building_size.y * 0.5)
	
	var can_place = _can_place_at(world_pos)
	var material = preview_mesh.material_override as StandardMaterial3D
	if material:
		material.albedo_color = Color(0, 1, 0, 0.5) if can_place else Color(1, 0, 0, 0.5)

func _toggle_placement_mode():
	is_placing_mode = not is_placing_mode
	preview_mesh.visible = is_placing_mode
	
	if is_placing_mode:
		# Force an immediate grid update when entering placement mode
		last_grid_update_camera_pos = Vector3.INF # Invalidate last pos
		_process(0) # Call process once to draw the grid
	
	if grid_lines:
		grid_lines.visible = is_placing_mode and show_grid
		
	print("Placement mode: ", "ON" if is_placing_mode else "OFF")

func toggle_grid_visibility():
	show_grid = not show_grid
	if grid_lines:
		grid_lines.visible = show_grid and is_placing_mode
		if show_grid and is_placing_mode:
			_update_grid_visualization()
	print("Grid visibility: ", "ON" if show_grid else "OFF")

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
	building_node.name = "Building_" + building.name
	get_parent().add_child(building_node)

func select_building(index: int):
	if index >= 0 and index < building_data.size():
		current_building_index = index
		_update_preview_mesh()
		print("Selected: ", building_data[index].name)
