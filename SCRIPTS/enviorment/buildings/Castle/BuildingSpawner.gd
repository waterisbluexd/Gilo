extends Node3D
class_name BuildingSpawner

@export_group("Spawning")
@export var auto_spawn: bool = true
@export var spawn_interval: float = 8.0
@export var fade_duration: float = 1.5

@export_group("Markers")
@export var spawn_marker: Node3D
@export var idle_marker: Node3D

@export_group("Debug")
@export var debug_mode: bool = false

# Internal
var navigation_grid: NavigationGrid
var building_data: BuildingData
var spawned_npcs: Array[RTSGridNPC] = []
var spawn_timer: Timer
var npc_counter: int = 0

signal npc_spawned(npc: RTSGridNPC)
signal spawn_failed(reason: String)

func _ready():
	_setup_systems()
	_setup_markers()
	_setup_timer()

func _setup_systems():
	navigation_grid = _find_in_scene("NavigationGrid") as NavigationGrid
	if not navigation_grid and debug_mode:
		print("Warning: No NavigationGrid found")

func _setup_markers():
	if not spawn_marker:
		spawn_marker = Node3D.new()
		spawn_marker.name = "SpawnMarker"
		spawn_marker.position = Vector3(0, 0, -1)
		add_child(spawn_marker)
	
	if not idle_marker:
		idle_marker = Node3D.new()
		idle_marker.name = "IdleMarker" 
		idle_marker.position = Vector3(2, 0, 2)
		add_child(idle_marker)

func _setup_timer():
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_try_spawn)
	add_child(spawn_timer)

func _find_in_scene(node_name: String) -> Node:
	var current = get_parent()
	while current:
		var found = current.find_child(node_name, true, false)
		if found:
			return found
		current = current.get_parent()
	return null

func configure_building(data: BuildingData):
	building_data = data
	if debug_mode:
		print("Configured spawner for: %s" % data.name)

func start_spawning():
	if not building_data or not auto_spawn:
		return
	
	spawn_timer.start()
	if debug_mode:
		print("Started spawning for: %s" % building_data.name)

func stop_spawning():
	spawn_timer.stop()

func _try_spawn():
	if not _can_spawn():
		return
	
	var spawn_pos = _get_spawn_position()
	if spawn_pos == Vector3.INF:
		spawn_failed.emit("No valid spawn position")
		return
	
	_spawn_npc_at(spawn_pos)

func _can_spawn() -> bool:
	if not building_data:
		return false
	
	var current_count = _get_living_npc_count()
	var max_pop = _get_max_population()
	
	if current_count >= max_pop:
		if debug_mode:
			print("Population limit reached: %d/%d" % [current_count, max_pop])
		return false
	
	var spawn_types = _get_spawnable_types()
	return not spawn_types.is_empty()

func _get_spawn_position() -> Vector3:
	if not navigation_grid:
		return spawn_marker.global_position
	
	var base_pos = spawn_marker.global_position
	var base_grid = navigation_grid.world_to_grid(base_pos)
	
	if navigation_grid.is_walkable(base_grid):
		return navigation_grid.grid_to_world(base_grid)
	
	for i in range(8):
		var offset = Vector2i(randi_range(-2, 2), randi_range(-2, 2))
		var test_grid = base_grid + offset
		if navigation_grid.is_walkable(test_grid):
			return navigation_grid.grid_to_world(test_grid)
	
	return Vector3.INF

func _spawn_npc_at(pos: Vector3):
	var npc_types = _get_spawnable_types()
	if npc_types.is_empty():
		return
	
	var npc_type = npc_types[0]
	if not npc_type.visual_scene:
		spawn_failed.emit("No visual scene for: " + npc_type.npc_name)
		return
	
	var npc_node = npc_type.visual_scene.instantiate() as RTSGridNPC
	if not npc_node:
		spawn_failed.emit("Failed to instantiate NPC")
		return
	
	npc_node.name = "%s_%d" % [npc_type.npc_name, npc_counter]
	npc_counter += 1
	
	_get_scene_root().add_child(npc_node)
	npc_node.global_position = pos
	
	if npc_node.has_method("set_navigation_grid"):
		npc_node.set_navigation_grid(navigation_grid)
	
	spawned_npcs.append(npc_node)
	
	_fade_in_npc(npc_node)
	
	npc_spawned.emit(npc_node)
	
	if debug_mode:
		print("Spawned: %s at %s" % [npc_node.name, pos])

func _fade_in_npc(npc: RTSGridNPC):
	_set_npc_opacity(npc, 0.0)
	
	var tween = create_tween()
	tween.tween_method(func(opacity): _set_npc_opacity(npc, opacity), 0.0, 1.0, fade_duration)
	tween.tween_callback(_send_to_idle.bind(npc))

func _set_npc_opacity(npc: RTSGridNPC, opacity: float):
	if not is_instance_valid(npc):
		return
	
	_apply_opacity_to_node(npc, opacity, true)

func _apply_opacity_to_node(node: Node, opacity: float, create_unique: bool):
	if node is MeshInstance3D:
		var mesh = node as MeshInstance3D
		var material = mesh.get_active_material(0)
		
		if material is StandardMaterial3D:
			var std_mat = material as StandardMaterial3D
			
			if create_unique and not mesh.material_override:
				std_mat = std_mat.duplicate()
				mesh.material_override = std_mat
			elif mesh.material_override:
				std_mat = mesh.material_override as StandardMaterial3D
			
			if std_mat:
				std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var color = std_mat.albedo_color
				color.a = opacity
				std_mat.albedo_color = color
	
	for child in node.get_children():
		_apply_opacity_to_node(child, opacity, create_unique)

func _send_to_idle(npc: RTSGridNPC):
	if not is_instance_valid(npc):
		return
	
	if npc.has_method("move_to_world_position"):
		var idle_pos = idle_marker.global_position
		idle_pos += Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		npc.move_to_world_position(idle_pos)

func _get_living_npc_count() -> int:
	spawned_npcs = spawned_npcs.filter(func(npc): return is_instance_valid(npc))
	return spawned_npcs.size()

func _get_max_population() -> int:
	if building_data.building_type == BuildingData.BuildingType.CASTLE:
		return building_data.max_peasants
	else:
		return 10

func _get_spawnable_types() -> Array[NPCType]:
	if building_data.building_type == BuildingData.BuildingType.CASTLE:
		return building_data.peasant_types
	else:
		return []

func _get_scene_root() -> Node:
	var current = self
	while current.get_parent():
		var parent = current.get_parent()
		if not parent.get_parent() or parent.name == "Main":
			return parent
		current = parent
	return get_tree().current_scene

func get_spawned_count() -> int:
	return _get_living_npc_count()

func can_spawn_more() -> bool:
	return _can_spawn()
