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

# --- CLICK PREVENTION ---
var last_click_time: float = 0.0
var click_cooldown: float = 0.2  # 200ms cooldown between clicks

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
	if parent.has_method("get_node"):
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
			push_warning("Camera script is missing the 'mouse_world_position_clicked' signal!")
	
	_create_preview_mesh()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_toggle_placement_mode()
	
	elif event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select_building(event.keycode - KEY_1)

func _on_world_position_hovered(world_pos: Vector3, _hit_normal: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return
		
	var snapped_pos = snap_to_grid_position(world_pos)
	_update_preview(snapped_pos)

func _on_world_position_clicked(world_pos: Vector3, _hit_object: Node3D):
	if not is_placing_mode:
		return
	
	# Check cooldown to prevent multiple rapid placements
	var current_time = Time.get_time_dict_from_system()
	var time_float = current_time.hour * 3600.0 + current_time.minute * 60.0 + current_time.second + current_time.get("millisecond", 0) / 1000.0
	
	if time_float - last_click_time < click_cooldown:
		print("Click ignored due to cooldown")
		return
	
	last_click_time = time_float
		
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
	print("Attempting to place building at: %s" % world_pos)
	
	var building = get_current_building()
	if not building:
		print("No building selected!")
		return
	
	if _can_place_at(world_pos):
		_place_building_at(world_pos)
	else:
		print("Cannot place building at %s - area is blocked" % world_pos)

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
	if not building: 
		return
	
	# Double-check before placing
	if not _can_place_at(world_pos):
		print("Cannot place building - area became blocked!")
		return
	
	navigation_grid.place_building(world_pos, building.size)
	_create_building_visual(world_pos, building)
	print("Building placed: %s at: %s" % [building.name, world_pos])

func _create_preview_mesh():
	preview_mesh = MeshInstance3D.new()
	preview_mesh.name = "BuildingPreview"
	add_child(preview_mesh)
	_update_preview_mesh()
	preview_mesh.visible = false

func _update_preview_mesh():
	if not preview_mesh: 
		return
		
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
	if not preview_mesh or not is_placing_mode: 
		return
		
	var building_size = get_current_building_size()
	preview_mesh.position = world_pos + Vector3(building_size.x * 0.5, 0.5, building_size.y * 0.5)
	
	var can_place = _can_place_at(world_pos)
	var material = preview_mesh.material_override as StandardMaterial3D
	if material:
		material.albedo_color = Color(0, 1, 0, 0.5) if can_place else Color(1, 0, 0, 0.5)

func _toggle_placement_mode():
	is_placing_mode = not is_placing_mode
	preview_mesh.visible = is_placing_mode
	print("Placement mode: %s" % ("ON" if is_placing_mode else "OFF"))

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
	building_node.name = "Building_" + building.name + "_" + str(Time.get_ticks_msec())
	get_parent().add_child(building_node)

func select_building(index: int):
	if index >= 0 and index < building_data.size():
		current_building_index = index
		_update_preview_mesh()
		print("Selected: %s" % building_data[index].name)
