@tool
extends Node3D
class_name ChunkPixelTerrain

# --- CHUNK SYSTEM PARAMETERS ---
@export_group("Chunk Settings")
@export var chunk_size: int = 32
@export var render_distance: int = 3
@export var unload_distance: int = 5
@export var save_path: String = "res://SHADER/resources/cache/"

# --- TERRAIN PARAMETERS ---	
@export_group("Pixel Terrain Settings")
@export var pixel_size: float = 4.0
@export var terrain_height_variation: float = 0.5

# Generation control with toggle
@export_group("Generation Control")
@export var world_active: bool = false : set = set_world_active
@export var auto_generate_on_ready: bool = false

# Noise Resources
@export_group("Noise Settings")
@export var primary_biome_noise: FastNoiseLite
@export var secondary_biome_noise: FastNoiseLite
@export var height_noise: FastNoiseLite
@export var auto_create_default_noise: bool = true

# Noise combination settings
@export_subgroup("Noise Mixing")
@export_range(0.0, 1.0) var primary_noise_weight: float = 0.85
@export_range(0.0, 1.0) var secondary_noise_weight: float = 0.15
@export_range(0.0, 2.0) var noise_contrast: float = 0.8

# Height settings
@export_group("Height Settings")
@export var enable_height_variation: bool = false
@export_range(0.0, 1.0) var height_influence: float = 1.0

# Biome Colors & Thresholds
@export_group("Biome Colors & Thresholds")
@export var color_1: Color = Color(0.169, 0.239, 0.075, 1.0)
@export_range(-1.0, 1.0) var threshold_1: float = -0.6
@export var color_2: Color = Color(0.196, 0.341, 0.133, 1.0)
@export_range(-1.0, 1.0) var threshold_2: float = -0.3
@export var color_3: Color = Color(0.38, 0.408, 0.133, 1.0)
@export_range(-1.0, 1.0) var threshold_3: float = -0.1
@export var color_4: Color = Color(0.447, 0.569, 0.267, 1.0)
@export_range(-1.0, 1.0) var threshold_4: float = 0.1
@export var color_5: Color = Color(0.78, 0.69, 0.282, 1.0)
@export_range(-1.0, 1.0) var threshold_5: float = 0.3
@export var color_6: Color = Color(0.482, 0.624, 0.2, 1.0)
@export_range(-1.0, 1.0) var threshold_6: float = 0.5
@export var color_7: Color = Color(0.545, 0.702, 0.22, 1.0)
@export_range(-1.0, 1.0) var threshold_7: float = 0.7
@export var color_8: Color = Color(0.647, 0.753, 0.208, 1.0)

# Material settings
@export_group("Material Settings")
@export var use_geometry_material: bool = true
@export var custom_material: StandardMaterial3D

# Performance settings
@export_group("Performance")
@export var use_multithreading: bool = true
@export_range(1, 16) var thread_count: int = 4
@export var enable_frustum_culling: bool = true
@export var max_chunks_per_frame: int = 2
@export var cache_enabled: bool = true

# --- INTERNAL VARIABLES ---
@export var player: Node3D
@export var camera3D: Camera3D
@onready var navigation_grid: NavigationGrid = $NavigationGrid
@onready var building_placer: BuildingPlacer = $BuildingPlacer
@onready var sub_viewport: SubViewport = $".."

var loaded_chunks: Dictionary = {}
var loading_chunks: Dictionary = {}
var chunk_save_queue: Array[Vector2i] = []
var generation_queue: Array[Vector2i] = []

# Thread management
var thread_pool: Array[Thread] = []
var generation_mutex: Mutex = Mutex.new()
var generation_semaphore: Semaphore = Semaphore.new()

# Biome data
var _biome_colors: Array[Color]
var _biome_thresholds: Array[float]

# Performance caches
var _noise_cache: Dictionary = {}

# Optimization variables
var last_player_chunk: Vector2i = Vector2i(999999, 999999)
var chunks_generated_this_frame: int = 0
var camera: Camera3D

# Frustum culling
var frustum_planes: Array[Plane] = []

# --- INITIALIZATION ---
func _ready():
	_setup_biomes()
	_setup_noise()
	_create_save_directory()
	_initialize_thread_pool()
	_find_camera()
	_find_player()
	
	if auto_generate_on_ready:
		world_active = true

func _exit_tree():
	_cleanup_threads()
	_save_all_dirty_chunks()

# --- TOGGLE FUNCTIONALITY ---
func set_world_active(value: bool):
	if world_active == value:
		return
	
	world_active = value
	
	if world_active:
		_generate_world()
	else:
		_clear_world()
	
	if Engine.is_editor_hint():
		notify_property_list_changed()

func _generate_world():
	_setup_biomes()
	_setup_noise()
	
	if player:
		var player_chunk = world_to_chunk(player.global_position)
		_update_chunks_around_player(player_chunk)
	elif Engine.is_editor_hint():
		var origin_chunk = Vector2i(0, 0)
		_load_chunk_async(origin_chunk)
		for x in range(-1, 2):
			for z in range(-1, 2):
				var chunk_coord = Vector2i(x, z)
				if chunk_coord != origin_chunk:
					_load_chunk_async(chunk_coord)

func _clear_world():
	_cleanup_threads()
	_clear_all_chunks()
	_clear_caches()

# --- SETUP FUNCTIONS ---
func _setup_biomes():
	_biome_colors = [color_1, color_2, color_3, color_4, color_5, color_6, color_7, color_8]
	_biome_thresholds = [threshold_1, threshold_2, threshold_3, threshold_4, threshold_5, threshold_6, threshold_7]

func _setup_noise():
	if auto_create_default_noise:
		if not primary_biome_noise:
			primary_biome_noise = _create_default_biome_noise()
		if not secondary_biome_noise:
			secondary_biome_noise = _create_default_secondary_noise()
		if not height_noise and enable_height_variation:
			height_noise = _create_default_height_noise()

func _create_save_directory():
	var dir = DirAccess.open("res://")
	if not dir:
		return
	if not dir.dir_exists(save_path):
		dir.make_dir_recursive(save_path)

func _initialize_thread_pool():
	if not use_multithreading:
		return
	thread_pool.resize(thread_count)
	for i in range(thread_count):
		thread_pool[i] = Thread.new()

func _find_camera():
	if Engine.is_editor_hint():
		return
	var viewport = get_viewport()
	if viewport:
		camera = viewport.get_camera_3d()

func _find_player():
	if player:
		return
	var scene_root = get_tree().current_scene if get_tree().current_scene else self
	var potential_players = scene_root.find_children("Player*", "Node3D")
	if potential_players.size() > 0:
		player = potential_players[0]
	else:
		potential_players = scene_root.find_children("*Camera*", "Node3D")
		if potential_players.size() > 0:
			player = potential_players[0]

func _cleanup_threads():
	for thread in thread_pool:
		if thread.is_started():
			generation_semaphore.post()
			thread.wait_to_finish()

# --- MAIN UPDATE LOOP ---
func _process(_delta):
	if not world_active or not player:
		return
	
	var player_chunk = world_to_chunk(player.global_position)
	if player_chunk != last_player_chunk:
		last_player_chunk = player_chunk
		_update_chunks_around_player(player_chunk)
	
	if enable_frustum_culling and camera:
		_update_chunk_visibility()
	
	_process_generation_queue()
	_process_chunk_save_queue()
	
	chunks_generated_this_frame = 0

func _update_chunks_around_player(player_chunk: Vector2i):
	var chunks_to_load: Array[Vector2i] = []
	var chunks_to_unload: Array[Vector2i] = []
	
	for x in range(player_chunk.x - render_distance, player_chunk.x + render_distance + 1):
		for z in range(player_chunk.y - render_distance, player_chunk.y + render_distance + 1):
			var chunk_coord = Vector2i(x, z)
			if not loaded_chunks.has(chunk_coord) and not loading_chunks.has(chunk_coord):
				chunks_to_load.append(chunk_coord)
	
	chunks_to_load.sort_custom(func(a, b): return _get_chunk_distance_to_player(a, player_chunk) < _get_chunk_distance_to_player(b, player_chunk))
	
	for chunk_coord in loaded_chunks.keys():
		var distance = max(abs(chunk_coord.x - player_chunk.x), abs(chunk_coord.y - player_chunk.y))
		if distance > unload_distance:
			chunks_to_unload.append(chunk_coord)
	
	for chunk_coord in chunks_to_load:
		if generation_queue.size() < max_chunks_per_frame * 3:
			generation_queue.append(chunk_coord)
	
	for chunk_coord in chunks_to_unload:
		_unload_chunk(chunk_coord)

func _get_chunk_distance_to_player(chunk_coord: Vector2i, player_chunk: Vector2i) -> float:
	var dx = chunk_coord.x - player_chunk.x
	var dz = chunk_coord.y - player_chunk.y
	return sqrt(dx * dx + dz * dz)

func _process_generation_queue():
	var chunks_to_process = min(max_chunks_per_frame, generation_queue.size())
	for i in range(chunks_to_process):
		var chunk_coord = generation_queue.pop_front()
		if not loaded_chunks.has(chunk_coord) and not loading_chunks.has(chunk_coord):
			_load_chunk_async(chunk_coord)
			chunks_generated_this_frame += 1

func _update_chunk_visibility():
	if not camera:
		return
	
	_calculate_frustum_planes()
	
	for chunk in loaded_chunks.values():
		var chunk_world_pos = chunk_to_world(chunk.chunk_coord)
		var chunk_center = Vector3(
			chunk_world_pos.x + (chunk_size * pixel_size * 0.5),
			0,
			chunk_world_pos.y + (chunk_size * pixel_size * 0.5)
		)
		var chunk_radius = chunk_size * pixel_size * 0.7071
		var is_visible = _is_sphere_in_frustum(chunk_center, chunk_radius)
		chunk.set_visible(is_visible)

func _calculate_frustum_planes():
	if not camera:
		return
	
	var transform = camera.get_camera_transform()
	frustum_planes.clear()
	var forward = -transform.basis.z
	var right = transform.basis.x
	var up = transform.basis.y
	
	frustum_planes.append(Plane(forward, transform.origin + forward * camera.near))
	frustum_planes.append(Plane(-forward, transform.origin + forward * camera.far))

func _is_sphere_in_frustum(center: Vector3, radius: float) -> bool:
	if frustum_planes.is_empty():
		return true
	for plane in frustum_planes:
		if plane.distance_to(center) < -radius:
			return false
	return true

# --- CHUNK LOADING/UNLOADING ---
func _load_chunk_async(chunk_coord: Vector2i):
	if loading_chunks.has(chunk_coord) or loaded_chunks.has(chunk_coord):
		return
	loading_chunks[chunk_coord] = true
	var available_thread = null
	if use_multithreading:
		for thread in thread_pool:
			if not thread.is_started():
				available_thread = thread
				break
	
	var thread_data = {
		"chunk_coord": chunk_coord,
		"chunk_size": chunk_size,
		"pixel_size": pixel_size,
		"primary_biome_noise": primary_biome_noise,
		"secondary_biome_noise": secondary_biome_noise,
		"height_noise": height_noise,
		"biome_colors": _biome_colors,
		"biome_thresholds": _biome_thresholds,
		"save_path": save_path,
		"enable_height_variation": enable_height_variation,
		"height_influence": height_influence,
		"terrain_height_variation": terrain_height_variation,
		"primary_noise_weight": primary_noise_weight,
		"secondary_noise_weight": secondary_noise_weight,
		"noise_contrast": noise_contrast,
		"cache_enabled": cache_enabled
	}
	
	if available_thread:
		available_thread.start(_generate_chunk_thread.bind(thread_data))
	else:
		_on_chunk_generated(chunk_coord, TerrainChunk.generate(thread_data))

func _generate_chunk_thread(data: Dictionary):
	var chunk_data = TerrainChunk.generate(data)
	call_deferred("_on_chunk_generated", data.chunk_coord, chunk_data)

func _on_chunk_generated(chunk_coord: Vector2i, chunk_data: Dictionary):
	if not world_active:
		return
	generation_mutex.lock()
	if chunk_coord in loading_chunks:
		loading_chunks.erase(chunk_coord)
		var chunk = TerrainChunk.new(chunk_coord)
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.set_name("chunk_%s" % chunk_coord)
		chunk.data = chunk_data
		chunk.create_mesh(chunk_size, pixel_size, use_geometry_material, custom_material)
		var world_pos = chunk_to_world(chunk_coord)
		chunk.mesh_instance.position = Vector3(world_pos.x, 0, world_pos.y)
		
		# IMPORTANT: Configure shadows after mesh creation
		_configure_chunk_shadows(chunk)
		
		add_child(chunk.mesh_instance)
		loaded_chunks[chunk_coord] = chunk
	generation_mutex.unlock()
func _unload_chunk(chunk_coord: Vector2i):
	if chunk_coord in loaded_chunks:
		var chunk = loaded_chunks[chunk_coord]
		if chunk.is_dirty:
			chunk.save_to_file(save_path)
		if chunk.mesh_instance.get_parent():
			chunk.mesh_instance.get_parent().remove_child(chunk.mesh_instance)
		chunk.mesh_instance.queue_free()
		loaded_chunks.erase(chunk_coord)

func _process_chunk_save_queue():
	var saves_per_frame = 2
	for i in range(min(saves_per_frame, chunk_save_queue.size())):
		var chunk_coord = chunk_save_queue.pop_front()
		if chunk_coord in loaded_chunks:
			loaded_chunks[chunk_coord].save_to_file(save_path)

func _save_all_dirty_chunks():
	for chunk in loaded_chunks.values():
		if chunk.is_dirty:
			chunk.save_to_file(save_path)

# --- UTILITY FUNCTIONS ---
func world_to_chunk(world_pos: Vector3) -> Vector2i:
	var chunk_world_size = chunk_size * pixel_size
	return Vector2i(
		int(floor(world_pos.x / chunk_world_size)),
		int(floor(world_pos.z / chunk_world_size))
	)

func chunk_to_world(chunk_coord: Vector2i) -> Vector2:
	var chunk_world_size = chunk_size * pixel_size
	return Vector2(
		chunk_coord.x * chunk_world_size,
		chunk_coord.y * chunk_world_size
	)

# --- CACHE MANAGEMENT ---
func _clear_caches():
	_noise_cache.clear()

func _clear_all_chunks():
	for chunk_coord in loaded_chunks.keys():
		_unload_chunk(chunk_coord)
	loaded_chunks.clear()
	loading_chunks.clear()
	generation_queue.clear()

# --- DEFAULT NOISE CREATION ---
func _create_default_biome_noise() -> FastNoiseLite:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.02
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.3
	noise.fractal_lacunarity = 1.8
	noise.seed = randi()
	return noise

func _create_default_secondary_noise() -> FastNoiseLite:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.05
	noise.fractal_octaves = 1
	noise.seed = randi()
	return noise

func _create_default_height_noise() -> FastNoiseLite:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.08
	noise.fractal_octaves = 2
	noise.seed = randi()
	return noise

# --- PUBLIC API ---
func get_chunk_at_position(world_pos: Vector3) -> TerrainChunk:
	var chunk_coord = world_to_chunk(world_pos)
	return loaded_chunks.get(chunk_coord, null)

func force_save_all_chunks():
	for chunk in loaded_chunks.values():
		if chunk.is_dirty:
			chunk_save_queue.append(chunk.chunk_coord)

func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()

func get_loading_chunk_count() -> int:
	return loading_chunks.size()

func get_biome_at_position(world_pos: Vector3) -> int:
	if not primary_biome_noise:
		return -1
	var combined_noise = (primary_biome_noise.get_noise_2d(world_pos.x, world_pos.z) * primary_noise_weight + secondary_biome_noise.get_noise_2d(world_pos.x, world_pos.z) * secondary_noise_weight) * noise_contrast
	combined_noise = clamp(combined_noise, -1.0, 1.0)
	for i in _biome_thresholds.size():
		if combined_noise < _biome_thresholds[i]:
			return i
	return _biome_colors.size() - 1

func get_height_at_position(world_pos: Vector3) -> float:
	if not enable_height_variation or not height_noise:
		return 0.0
	return height_noise.get_noise_2d(world_pos.x, world_pos.z) * terrain_height_variation * height_influence

func _configure_chunk_shadows(chunk: TerrainChunk):
	"""Ensure chunk is properly configured for shadows"""
	if not chunk.mesh_instance:
		return	
	
	# Force shadow casting on
	chunk.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Set proper layer for lighting
	chunk.mesh_instance.layers = 1
	
	# Ensure material allows lighting
	var material = chunk.mesh_instance.material_override
	if material and material is StandardMaterial3D:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
