class_name TerrainChunk

var chunk_coord: Vector2i
var mesh_instance: MeshInstance3D
var data: Dictionary
var is_dirty: bool = false
var last_access_time: float
var is_visible: bool = true
var distance_to_player: float = 0.0

func _init(coord: Vector2i):
	chunk_coord = coord
	last_access_time = Time.get_ticks_msec() / 1000.0
	data = {}

# Static method to generate chunk data (for threading)
static func generate(data_params: Dictionary) -> Dictionary:
	var chunk_coord = data_params.chunk_coord
	var chunk_size = data_params.chunk_size
	var pixel_size = data_params.pixel_size
	var primary_biome_noise = data_params.primary_biome_noise
	var secondary_biome_noise = data_params.secondary_biome_noise
	var height_noise = data_params.height_noise
	var biome_colors = data_params.biome_colors
	var biome_thresholds = data_params.biome_thresholds
	var enable_height_variation = data_params.enable_height_variation
	var height_influence = data_params.height_influence
	var terrain_height_variation = data_params.terrain_height_variation
	var primary_noise_weight = data_params.primary_noise_weight
	var secondary_noise_weight = data_params.secondary_noise_weight
	var noise_contrast = data_params.noise_contrast
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()
	var total_quads = chunk_size * chunk_size
	vertices.resize(total_quads * 4)
	normals.resize(total_quads * 4)
	uvs.resize(total_quads * 4)
	colors.resize(total_quads * 4)
	indices.resize(total_quads * 6)
	
	var height_grid = _generate_chunk_height_grid_optimized(chunk_coord, chunk_size, pixel_size, height_noise, enable_height_variation, terrain_height_variation, height_influence)
	
	var vertex_idx = 0
	var index_idx = 0
	
	var chunk_world_size = chunk_size * pixel_size
	var chunk_world_pos = Vector2(chunk_coord.x * chunk_world_size, chunk_coord.y * chunk_world_size)
	
	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var world_x = chunk_world_pos.x + (local_x * pixel_size)
			var world_z = chunk_world_pos.y + (local_z * pixel_size)
			var pixel_color = _get_pixel_color_at_world_pos(world_x + pixel_size * 0.5, world_z + pixel_size * 0.5, primary_biome_noise, secondary_biome_noise, primary_noise_weight, secondary_noise_weight, noise_contrast, biome_colors, biome_thresholds)
			
			var height_bl = height_grid[local_z][local_x]
			var height_br = height_grid[local_z][local_x + 1]
			var height_tr = height_grid[local_z + 1][local_x + 1]
			var height_tl = height_grid[local_z + 1][local_x]
			
			var bl_pos = Vector3(local_x * pixel_size, height_bl, local_z * pixel_size)
			var br_pos = Vector3((local_x + 1) * pixel_size, height_br, local_z * pixel_size)
			var tr_pos = Vector3((local_x + 1) * pixel_size, height_tr, (local_z + 1) * pixel_size)
			var tl_pos = Vector3(local_x * pixel_size, height_tl, (local_z + 1) * pixel_size)
			
			var normal = _calculate_quad_normal(bl_pos, br_pos, tr_pos, tl_pos)
			
			vertices[vertex_idx] = bl_pos
			vertices[vertex_idx + 1] = br_pos
			vertices[vertex_idx + 2] = tr_pos
			vertices[vertex_idx + 3] = tl_pos
			normals[vertex_idx] = normal
			normals[vertex_idx + 1] = normal
			normals[vertex_idx + 2] = normal
			normals[vertex_idx + 3] = normal
			colors[vertex_idx] = pixel_color
			colors[vertex_idx + 1] = pixel_color
			colors[vertex_idx + 2] = pixel_color
			colors[vertex_idx + 3] = pixel_color
			uvs[vertex_idx] = Vector2(0, 0)
			uvs[vertex_idx + 1] = Vector2(1, 0)
			uvs[vertex_idx + 2] = Vector2(1, 1)
			uvs[vertex_idx + 3] = Vector2(0, 1)
			
			indices[index_idx] = vertex_idx
			indices[index_idx + 1] = vertex_idx + 1
			indices[index_idx + 2] = vertex_idx + 2
			indices[index_idx + 3] = vertex_idx
			indices[index_idx + 4] = vertex_idx + 2
			indices[index_idx + 5] = vertex_idx + 3
			
			vertex_idx += 4
			index_idx += 6
	
	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"chunk_coord": chunk_coord,
		"generated_time": Time.get_unix_time_from_system()
	}

# Helper methods for generation (now inside TerrainChunk class)
static func _generate_chunk_height_grid_optimized(chunk_coord: Vector2i, chunk_size: int, pixel_size: float, height_noise: FastNoiseLite, enable_height_variation: bool, terrain_height_variation: float, height_influence: float) -> Array:
	var height_grid = []
	height_grid.resize(chunk_size + 1)
	for i in range(chunk_size + 1):
		height_grid[i] = []
		height_grid[i].resize(chunk_size + 1)
	
	if not enable_height_variation or not height_noise:
		var zero_row = []
		zero_row.resize(chunk_size + 1)
		zero_row.fill(0.0)
		for i in range(chunk_size + 1):
			height_grid[i] = zero_row.duplicate()
		return height_grid
	
	var chunk_world_size = chunk_size * pixel_size
	var chunk_world_pos = Vector2(chunk_coord.x * chunk_world_size, chunk_coord.y * chunk_world_size)
	
	for local_z in range(chunk_size + 1):
		for local_x in range(chunk_size + 1):
			var world_x = chunk_world_pos.x + (local_x * pixel_size)
			var world_z = chunk_world_pos.y + (local_z * pixel_size)
			var height = height_noise.get_noise_2d(world_x, world_z) * terrain_height_variation * height_influence
			height_grid[local_z][local_x] = height
	return height_grid

static func _get_pixel_color_at_world_pos(world_x: float, world_z: float, primary_biome_noise: FastNoiseLite, secondary_biome_noise: FastNoiseLite, primary_noise_weight: float, secondary_noise_weight: float, noise_contrast: float, biome_colors: Array[Color], biome_thresholds: Array[float]) -> Color:
	var primary_value = primary_biome_noise.get_noise_2d(world_x, world_z)
	var secondary_value = secondary_biome_noise.get_noise_2d(world_x, world_z)
	var combined_noise = (primary_value * primary_noise_weight + secondary_value * secondary_noise_weight) * noise_contrast
	combined_noise = clamp(combined_noise, -1.0, 1.0)
	for i in biome_thresholds.size():
		if combined_noise < biome_thresholds[i]:
			return biome_colors[i]
	return biome_colors.back()

static func _calculate_quad_normal(bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3) -> Vector3:
	var diagonal1 = tr - bl
	var diagonal2 = tl - br
	var normal = diagonal1.cross(diagonal2).normalized()
	return normal if normal.y >= 0 else -normal

# Method to create the mesh instance from generated data
func create_mesh(chunk_size: int, pixel_size: float, use_geometry_material: bool, custom_material: StandardMaterial3D):
	if not mesh_instance:
		return
		
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_TEX_UV] = data.uvs
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	var material: StandardMaterial3D = null
	if use_geometry_material:
		material = StandardMaterial3D.new()
	if not material and custom_material:
		material = custom_material.duplicate()
	if not material:
		material = StandardMaterial3D.new()
		
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh_instance.material_override = material

# File I/O methods
func save_to_file(path: String):
	var file_path = path + "chunk_%d_%d.dat" % [chunk_coord.x, chunk_coord.y]
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var save_data = {
			"chunk_coord": chunk_coord,
			"vertices": data.vertices,
			"normals": data.normals,
			"uvs": data.uvs,
			"colors": data.colors,
			"indices": data.indices,
			"generated_time": data.get("generated_time", Time.get_unix_time_from_system()),
			"version": 2
		}
		file.store_string(JSON.stringify(save_data))
		file.close()
		is_dirty = false

static func load_from_file(chunk_coord: Vector2i, path: String) -> Dictionary:
	var file_path = path + "chunk_%d_%d.dat" % [chunk_coord.x, chunk_coord.y]
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			var data_from_file = json.data
			return data_from_file
	return {}

# Simple utility methods
func mark_dirty():
	is_dirty = true

func update_access_time():
	last_access_time = Time.get_ticks_msec() / 1000.0

func set_visible(visible: bool):
	if is_visible != visible:
		is_visible = visible
		if mesh_instance:
			mesh_instance.visible = visible
