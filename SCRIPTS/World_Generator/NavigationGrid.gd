@tool
extends Node3D
class_name NavigationGrid

# --- GRID PARAMETERS ---
@export var grid_cell_size: float = 1.0
@export var chunk_size: int = 64
@export var active: bool = false

# --- INTERNAL VARIABLES ---
var nav_chunks: Dictionary = {}
var terrain_system: ChunkPixelTerrain

# Cell states
enum CellState { WALKABLE = 0, BLOCKED = 1 }

# --- INITIALIZATION ---
func _ready():
	terrain_system = get_parent() if get_parent() is ChunkPixelTerrain else null

# --- CHUNK MANAGEMENT ---
func ensure_chunk_loaded(chunk_coord: Vector2i):
	if not nav_chunks.has(chunk_coord):
		var chunk_data = PackedByteArray()
		chunk_data.resize(chunk_size * chunk_size)
		chunk_data.fill(CellState.WALKABLE)
		nav_chunks[chunk_coord] = chunk_data

func unload_chunk(chunk_coord: Vector2i):
	nav_chunks.erase(chunk_coord)

# --- COORDINATE CONVERSION ---
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / grid_cell_size)), int(floor(world_pos.z / grid_cell_size)))

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	var chunk_world_size = chunk_size * grid_cell_size
	return Vector2i(int(floor(world_pos.x / chunk_world_size)), int(floor(world_pos.z / chunk_world_size)))

# FIXED: Proper local coordinate calculation
func grid_to_local(grid_pos: Vector2i, chunk_coord: Vector2i) -> Vector2i:
	# Use modulo for proper local coordinates, handling negative numbers correctly
	var local_x = ((grid_pos.x % chunk_size) + chunk_size) % chunk_size
	var local_y = ((grid_pos.y % chunk_size) + chunk_size) % chunk_size
	return Vector2i(local_x, local_y)

# FIXED: More robust chunk coordinate calculation
func get_chunk_coord_from_grid(grid_pos: Vector2i) -> Vector2i:
	# Handle negative coordinates properly
	var chunk_x = int(floor(float(grid_pos.x) / float(chunk_size)))
	var chunk_y = int(floor(float(grid_pos.y) / float(chunk_size)))
	return Vector2i(chunk_x, chunk_y)

# --- CELL STATE MANAGEMENT ---
func set_cell(grid_pos: Vector2i, state: CellState):
	var chunk_coord = get_chunk_coord_from_grid(grid_pos)
	ensure_chunk_loaded(chunk_coord)
	var local_pos = grid_to_local(grid_pos, chunk_coord)
	
	# Bounds check (should always pass with proper modulo, but safety first)
	if local_pos.x >= 0 and local_pos.x < chunk_size and local_pos.y >= 0 and local_pos.y < chunk_size:
		var chunk_data = nav_chunks[chunk_coord]
		chunk_data[local_pos.y * chunk_size + local_pos.x] = state
	else:
		push_error("Invalid local coordinates: %s in chunk %s" % [local_pos, chunk_coord])

func get_cell(grid_pos: Vector2i) -> CellState:
	var chunk_coord = get_chunk_coord_from_grid(grid_pos)
	if not nav_chunks.has(chunk_coord):
		return CellState.WALKABLE
	
	var local_pos = grid_to_local(grid_pos, chunk_coord)
	if local_pos.x >= 0 and local_pos.x < chunk_size and local_pos.y >= 0 and local_pos.y < chunk_size:
		var chunk_data = nav_chunks[chunk_coord]
		return chunk_data[local_pos.y * chunk_size + local_pos.x]
	
	push_error("Invalid local coordinates: %s in chunk %s" % [local_pos, chunk_coord])
	return CellState.WALKABLE

func is_walkable(grid_pos: Vector2i) -> bool:
	return get_cell(grid_pos) == CellState.WALKABLE

# --- AREA BLOCKING ---
func block_area(world_pos: Vector3, size: Vector2):
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	print("Blocking area from grid %s to %s (size: %s)" % [grid_start, grid_end, size])
	
	for x in range(grid_start.x, grid_end.x + 1):
		for y in range(grid_start.y, grid_end.y + 1):
			set_cell(Vector2i(x, y), CellState.BLOCKED)

func unblock_area(world_pos: Vector3, size: Vector2):
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	print("Unblocking area from grid %s to %s (size: %s)" % [grid_start, grid_end, size])
	
	for x in range(grid_start.x, grid_end.x + 1):
		for y in range(grid_start.y, grid_end.y + 1):
			set_cell(Vector2i(x, y), CellState.WALKABLE)

# NEW: Debug function to check area state
func is_area_walkable(world_pos: Vector3, size: Vector2) -> bool:
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	for x in range(grid_start.x, grid_end.x + 1):
		for y in range(grid_start.y, grid_end.y + 1):
			if not is_walkable(Vector2i(x, y)):
				return false
	return true

# --- PATHFINDING (A*) ---
func find_path(start_world: Vector3, end_world: Vector3) -> Array[Vector3]:
	var start_grid = world_to_grid(start_world)
	var end_grid = world_to_grid(end_world)
	
	if not is_walkable(start_grid) or not is_walkable(end_grid):
		return []
	
	var open_set: Array[Vector2i] = [start_grid]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_grid: 0}
	var f_score: Dictionary = {start_grid: _heuristic(start_grid, end_grid)}
	
	var directions = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	
	while open_set.size() > 0:
		var current = _get_lowest_f_score(open_set, f_score)
		if current == end_grid:
			return _reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		for dir in directions:
			var neighbor = current + dir
			if not is_walkable(neighbor):
				continue
			
			var tentative_g = g_score[current] + 1
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end_grid)
				if neighbor not in open_set:
					open_set.append(neighbor)
	
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _get_lowest_f_score(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var lowest = open_set[0]
	var lowest_score = f_score.get(lowest, INF)
	for node in open_set:
		var score = f_score.get(node, INF)
		if score < lowest_score:
			lowest = node
			lowest_score = score
	return lowest

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector3]:
	var path: Array[Vector3] = []
	while came_from.has(current):
		var world_pos = Vector3(current.x * grid_cell_size + grid_cell_size * 0.5, 0, current.y * grid_cell_size + grid_cell_size * 0.5)
		path.push_front(world_pos)
		current = came_from[current]
	return path

# --- PUBLIC API ---
func place_building(world_pos: Vector3, building_size: Vector2):
	print("Placing building at world pos: %s, size: %s" % [world_pos, building_size])
	block_area(world_pos, building_size)

func remove_building(world_pos: Vector3, building_size: Vector2):
	print("Removing building at world pos: %s, size: %s" % [world_pos, building_size])
	unblock_area(world_pos, building_size)

func find_navigation_path(start: Vector3, end: Vector3) -> Array[Vector3]:
	return find_path(start, end)

func clear_all():
	nav_chunks.clear()

# NEW: Debug function to print chunk state
func debug_print_chunk_state(world_pos: Vector3):
	var grid_pos = world_to_grid(world_pos)
	var chunk_coord = get_chunk_coord_from_grid(grid_pos)
	var local_pos = grid_to_local(grid_pos, chunk_coord)
	
	print("World: %s -> Grid: %s -> Chunk: %s -> Local: %s -> Walkable: %s" % [
		world_pos, grid_pos, chunk_coord, local_pos, is_walkable(grid_pos)
	])
