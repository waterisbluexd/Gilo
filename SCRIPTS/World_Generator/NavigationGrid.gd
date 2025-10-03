@tool
extends Node3D
class_name NavigationGrid

# --- INSPECTOR CONFIGURABLE PARAMETERS ---
@export_group("Grid Settings")
@export var grid_cell_size: float = 1.0
@export var chunk_size: int = 64
@export var active: bool = true

@export_group("Performance")
@export var max_loaded_chunks: int = 100  # Unload chunks when exceeded
@export var auto_unload_distance: float = 200.0  # Unload chunks beyond this distance

@export_group("Debug")
@export var debug_mode: bool = false
@export var show_chunk_info: bool = false

# --- INTERNAL VARIABLES ---
var nav_chunks: Dictionary = {}
var chunk_access_times: Dictionary = {}  # For LRU cache management
var terrain_system: ChunkPixelTerrain

# Cell states
enum CellState { WALKABLE = 0, BLOCKED = 1 }

# --- INITIALIZATION ---
func _ready():
	terrain_system = get_parent() if get_parent() is ChunkPixelTerrain else null
	if debug_mode:
		print("NavigationGrid initialized - Cell size: %s, Chunk size: %s" % [grid_cell_size, chunk_size])

# --- OPTIMIZED CHUNK MANAGEMENT ---
func ensure_chunk_loaded(chunk_coord: Vector2i):
	if not nav_chunks.has(chunk_coord):
		# Check if we need to unload old chunks first
		if nav_chunks.size() >= max_loaded_chunks:
			_unload_oldest_chunk()
		
		var chunk_data = PackedByteArray()
		chunk_data.resize(chunk_size * chunk_size)
		chunk_data.fill(CellState.WALKABLE)
		nav_chunks[chunk_coord] = chunk_data
		
		if show_chunk_info:
			print("Loaded chunk: %s (Total chunks: %s)" % [chunk_coord, nav_chunks.size()])
	
	# Update access time for LRU
	chunk_access_times[chunk_coord] = Time.get_ticks_msec()

func _unload_oldest_chunk():
	if chunk_access_times.is_empty():
		return
	
	var oldest_chunk = null
	var oldest_time = INF
	
	for chunk_coord in chunk_access_times:
		if chunk_access_times[chunk_coord] < oldest_time:
			oldest_time = chunk_access_times[chunk_coord]
			oldest_chunk = chunk_coord
	
	if oldest_chunk:
		unload_chunk(oldest_chunk)

func unload_chunk(chunk_coord: Vector2i):
	nav_chunks.erase(chunk_coord)
	chunk_access_times.erase(chunk_coord)
	if show_chunk_info:
		print("Unloaded chunk: %s" % chunk_coord)

# Auto-unload distant chunks (call this periodically from your main game loop)
func cleanup_distant_chunks(center_world_pos: Vector3):
	var center_chunk = world_to_chunk(center_world_pos)
	var chunks_to_unload = []
	
	for chunk_coord in nav_chunks:
		var chunk_world_pos = Vector3(
			chunk_coord.x * chunk_size * grid_cell_size + (chunk_size * grid_cell_size * 0.5),
			0,
			chunk_coord.y * chunk_size * grid_cell_size + (chunk_size * grid_cell_size * 0.5)
		)
		
		if center_world_pos.distance_to(chunk_world_pos) > auto_unload_distance:
			chunks_to_unload.append(chunk_coord)
	
	for chunk_coord in chunks_to_unload:
		unload_chunk(chunk_coord)

# --- COORDINATE CONVERSION ---
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / grid_cell_size)), 
		int(floor(world_pos.z / grid_cell_size))
	)

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	var chunk_world_size = chunk_size * grid_cell_size
	return Vector2i(
		int(floor(world_pos.x / chunk_world_size)), 
		int(floor(world_pos.z / chunk_world_size))
	)

func grid_to_local(grid_pos: Vector2i) -> Vector2i:
	# Simplified - no need for chunk_coord parameter
	var local_x = ((grid_pos.x % chunk_size) + chunk_size) % chunk_size
	var local_y = ((grid_pos.y % chunk_size) + chunk_size) % chunk_size
	return Vector2i(local_x, local_y)

func get_chunk_coord_from_grid(grid_pos: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(grid_pos.x) / float(chunk_size))),
		int(floor(float(grid_pos.y) / float(chunk_size)))
	)

# --- OPTIMIZED CELL STATE MANAGEMENT ---
func set_cell(grid_pos: Vector2i, state: CellState):
	var chunk_coord = get_chunk_coord_from_grid(grid_pos)
	ensure_chunk_loaded(chunk_coord)
	var local_pos = grid_to_local(grid_pos)
	
	var chunk_data = nav_chunks[chunk_coord]
	chunk_data[local_pos.y * chunk_size + local_pos.x] = state

func get_cell(grid_pos: Vector2i) -> CellState:
	var chunk_coord = get_chunk_coord_from_grid(grid_pos)
	if not nav_chunks.has(chunk_coord):
		return CellState.WALKABLE
	
	var local_pos = grid_to_local(grid_pos)
	var chunk_data = nav_chunks[chunk_coord]
	return chunk_data[local_pos.y * chunk_size + local_pos.x]

func is_walkable(grid_pos: Vector2i) -> bool:
	return get_cell(grid_pos) == CellState.WALKABLE

# --- AREA OPERATIONS ---
func block_area(world_pos: Vector3, size: Vector2):
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	if debug_mode:
		print("Blocking area from grid %s to %s (size: %s)" % [grid_start, grid_end, size])
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			set_cell(Vector2i(x, y), CellState.BLOCKED)

func unblock_area(world_pos: Vector3, size: Vector2):
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	if debug_mode:
		print("Unblocking area from grid %s to %s (size: %s)" % [grid_start, grid_end, size])
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			set_cell(Vector2i(x, y), CellState.WALKABLE)

func is_area_walkable(world_pos: Vector3, size: Vector2) -> bool:
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			if not is_walkable(Vector2i(x, y)):
				return false
	return true

# NEW: Detailed area check with debug info
func check_area_placement(world_pos: Vector3, size: Vector2, building_name: String = "Unknown") -> Dictionary:
	var result = {
		"can_place": true,
		"blocked_cells": [],
		"grid_start": Vector2i.ZERO,
		"grid_end": Vector2i.ZERO,
		"total_cells": 0
	}
	
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	result.grid_start = grid_start
	result.grid_end = grid_end
	result.total_cells = (grid_end.x - grid_start.x) * (grid_end.y - grid_start.y)
	
	if debug_mode:
		print("=== PLACEMENT CHECK ===")
		print("Building: %s" % building_name)
		print("World Position: %s" % world_pos)
		print("Building Size: %s" % size)
		print("Grid Range: %s to %s (%d cells)" % [grid_start, grid_end, result.total_cells])
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			var cell_pos = Vector2i(x, y)
			if not is_walkable(cell_pos):
				result.can_place = false
				result.blocked_cells.append(cell_pos)
				
				if debug_mode:
					print("  ❌ BLOCKED cell at grid %s" % cell_pos)
			elif debug_mode:
				print("  ✅ FREE cell at grid %s" % cell_pos)
	
	if debug_mode:
		var status = "✅ YES" if result.can_place else "❌ NO"
		print("RESULT: Can place '%s'? %s" % [building_name, status])
		if not result.can_place:
			print("Blocked cells: %s" % result.blocked_cells)
		print("======================")
	
	return result

# --- OPTIMIZED PATHFINDING (A*) ---
func find_path(start_world: Vector3, end_world: Vector3, max_iterations: int = 1000) -> Array[Vector3]:
	var start_grid = world_to_grid(start_world)
	var end_grid = world_to_grid(end_world)
	
	if not is_walkable(start_grid) or not is_walkable(end_grid):
		return []
	
	var open_set: Array[Vector2i] = [start_grid]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_grid: 0}
	var f_score: Dictionary = {start_grid: _heuristic(start_grid, end_grid)}
	
	var directions = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var iterations = 0
	
	while open_set.size() > 0 and iterations < max_iterations:
		iterations += 1
		
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
	
	if debug_mode and iterations >= max_iterations:
		print("Pathfinding stopped at max iterations: %s" % max_iterations)
	
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
		var world_pos = Vector3(
			current.x * grid_cell_size + grid_cell_size * 0.5, 
			0, 
			current.y * grid_cell_size + grid_cell_size * 0.5
		)
		path.push_front(world_pos)
		current = came_from[current]
	return path

# --- SIMPLE PUBLIC API ---
func place_building(world_pos: Vector3, building_size: Vector2):
	if debug_mode:
		print("Placing building at: %s, size: %s" % [world_pos, building_size])
	block_area(world_pos, building_size)

func remove_building(world_pos: Vector3, building_size: Vector2):
	if debug_mode:
		print("Removing building at: %s, size: %s" % [world_pos, building_size])
	unblock_area(world_pos, building_size)

func find_navigation_path(start: Vector3, end: Vector3) -> Array[Vector3]:
	return find_path(start, end)

func clear_all():
	nav_chunks.clear()
	chunk_access_times.clear()
	if debug_mode:
		print("Cleared all navigation data")

# --- UTILITY FUNCTIONS ---
func get_chunk_count() -> int:
	return nav_chunks.size()

func get_memory_usage_estimate() -> String:
	var bytes = nav_chunks.size() * chunk_size * chunk_size
	if bytes < 1024:
		return "%d bytes" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
# Add this method to your NavigationGrid class
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	"""Convert grid coordinates to world position (center of cell)"""
	return Vector3(
		grid_pos.x * grid_cell_size + grid_cell_size * 0.5,
		0,
		grid_pos.y * grid_cell_size + grid_cell_size * 0.5
	)
# Add these methods to your existing NavigationGrid.gd

# Enhanced cell types for better pathfinding
enum CellType { 
	WALKABLE = 0, 
	BLOCKED = 1, 
	ROAD = 2,      # Fast travel
	DANGER = 3,    # Avoid unless necessary
	WATER = 4,     # Avoid for most NPCs
	BUILDING = 5   # Blocked but pathfind around
}

# Movement costs for different terrain
var movement_costs = {
	CellType.WALKABLE: 1.0,
	CellType.ROAD: 0.5,      # Roads are faster
	CellType.DANGER: 3.0,    # Avoid dangerous areas
	CellType.WATER: 10.0,    # Very expensive to cross
	CellType.BUILDING: 999.0, # Effectively blocked
	CellType.BLOCKED: 999.0
}

# Enhanced pathfinding with costs and preferences
func find_smart_path(start_world: Vector3, end_world: Vector3, npc_preferences: Dictionary = {}) -> Array[Vector3]:
	var start_grid = world_to_grid(start_world)
	var end_grid = world_to_grid(end_world)
	
	if not is_walkable(start_grid) or not is_walkable(end_grid):
		return []
	
	# A* with terrain costs and NPC preferences
	var open_set: Array[Vector2i] = [start_grid]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_grid: 0.0}
	var f_score: Dictionary = {start_grid: _smart_heuristic(start_grid, end_grid, npc_preferences)}
	
	var directions = [
		Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)  # Diagonal movement
	]
	
	var max_iterations = 2000
	var iterations = 0
	
	while open_set.size() > 0 and iterations < max_iterations:
		iterations += 1
		
		var current = _get_lowest_f_score(open_set, f_score)
		if current == end_grid:
			return _reconstruct_smooth_path(came_from, current)
		
		open_set.erase(current)
		
		for dir in directions:
			var neighbor = current + dir
			var cell_type = get_cell_type(neighbor)
			
			if not _can_traverse(cell_type, npc_preferences):
				continue
			
			var movement_cost = _get_movement_cost(cell_type, npc_preferences)
			var diagonal_cost = 1.414 if abs(dir.x) + abs(dir.y) == 2 else 1.0
			var total_cost = movement_cost * diagonal_cost
			
			var tentative_g = g_score[current] + total_cost
			
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _smart_heuristic(neighbor, end_grid, npc_preferences)
				
				if neighbor not in open_set:
					open_set.append(neighbor)
	
	return []  # No path found

func get_cell_type(grid_pos: Vector2i) -> CellType:
	# Override this to return enhanced cell types
	if not is_walkable(grid_pos):
		return CellType.BLOCKED
	
	# You would set these based on your world data
	# For now, default to walkable
	return CellType.WALKABLE

func _can_traverse(cell_type: CellType, preferences: Dictionary) -> bool:
	match cell_type:
		CellType.BLOCKED, CellType.BUILDING:
			return false
		CellType.WATER:
			return preferences.get("can_swim", false)
		CellType.DANGER:
			return preferences.get("brave", false) or preferences.get("desperate", false)
		_:
			return true

func _get_movement_cost(cell_type: CellType, preferences: Dictionary) -> float:
	var base_cost = movement_costs[cell_type]
	
	# Apply NPC preferences
	if cell_type == CellType.ROAD and preferences.get("prefers_roads", true):
		base_cost *= 0.3  # Even faster on roads for road-preferring NPCs
	elif cell_type == CellType.DANGER and preferences.get("fearless", false):
		base_cost *= 0.5  # Fearless NPCs don't mind danger as much
	
	return base_cost

func _smart_heuristic(a: Vector2i, b: Vector2i, preferences: Dictionary) -> float:
	var distance = sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
	
	# Bias towards roads if NPC prefers them
	if preferences.get("prefers_roads", true):
		# This is simplified - you'd actually check for roads near the path
		distance *= 0.9
	
	return distance

func _reconstruct_smooth_path(came_from: Dictionary, current: Vector2i) -> Array[Vector3]:
	var grid_path: Array[Vector2i] = []
	var temp_current = current
	
	while came_from.has(temp_current):
		grid_path.push_front(temp_current)
		temp_current = came_from[temp_current]
	
	# Convert to world positions and smooth the path
	var world_path: Array[Vector3] = []
	for i in range(grid_path.size()):
		var world_pos = grid_to_world(grid_path[i])
		world_path.append(world_pos)
	
	# Path smoothing - remove unnecessary waypoints
	return _smooth_path(world_path)

func _smooth_path(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() <= 2:
		return path
	
	var smoothed: Array[Vector3] = [path[0]]
	
	for i in range(1, path.size() - 1):
		var prev = path[i - 1]
		var current = path[i]
		var next = path[i + 1]
		
		# Check if we can skip this waypoint
		if not _can_skip_waypoint(prev, current, next):
			smoothed.append(current)
	
	smoothed.append(path[-1])
	return smoothed

func _can_skip_waypoint(prev: Vector3, current: Vector3, next: Vector3) -> bool:
	# Simple line-of-sight check
	var steps = 10
	for i in range(1, steps):
		var t = float(i) / float(steps)
		var test_pos = prev.lerp(next, t)
		var grid_pos = world_to_grid(test_pos)
		
		if not is_walkable(grid_pos):
			return false
	
	return true
