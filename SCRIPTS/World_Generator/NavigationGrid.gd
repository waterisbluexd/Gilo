@tool
extends Node3D
class_name NavigationGrid

# --- INSPECTOR CONFIGURABLE PARAMETERS ---
@export_group("Grid Settings")
@export var grid_cell_size: float = 1.0
@export var chunk_size: int = 64
@export var active: bool = true

@export_group("Performance")
@export var max_loaded_chunks: int = 100
@export var auto_unload_distance: float = 200.0

@export_group("Debug")
@export var debug_mode: bool = false
@export var show_chunk_info: bool = false

# --- INTERNAL VARIABLES ---
var nav_chunks: Dictionary = {}
var chunk_access_times: Dictionary = {}
var chunk_terrain

# Store prop blocking data with precise tracking
var prop_blocked_cells: Dictionary = {}  # grid_pos -> prop_name
var prop_registrations: Dictionary = {}  # world_pos_key -> {grid_cells: Array, size: Vector2}

# Cell states
enum CellState { WALKABLE = 0, BLOCKED = 1 }

func _ready():
	var parent = get_parent()
	
	if parent and parent.has_method("world_to_chunk") and parent.has_method("chunk_to_world"):
		chunk_terrain = parent
	else:
		for sibling in parent.get_children():
			if sibling.has_method("world_to_chunk") and sibling.has_method("chunk_to_world"):
				chunk_terrain = sibling
				break
	
	if debug_mode:
		if chunk_terrain:
			print("NavigationGrid initialized - Connected to terrain system")
		else:
			print("NavigationGrid initialized - No terrain system found")
		print("Cell size: %s, Chunk size: %s" % [grid_cell_size, chunk_size])

# --- OPTIMIZED CHUNK MANAGEMENT ---
func ensure_chunk_loaded(chunk_coord: Vector2i):
	if not nav_chunks.has(chunk_coord):
		if nav_chunks.size() >= max_loaded_chunks:
			_unload_oldest_chunk()
		
		var chunk_data = PackedByteArray()
		chunk_data.resize(chunk_size * chunk_size)
		chunk_data.fill(CellState.WALKABLE)
		nav_chunks[chunk_coord] = chunk_data
		
		if show_chunk_info:
			print("Loaded chunk: %s (Total chunks: %s)" % [chunk_coord, nav_chunks.size()])
	
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
	var local_x = ((grid_pos.x % chunk_size) + chunk_size) % chunk_size
	var local_y = ((grid_pos.y % chunk_size) + chunk_size) % chunk_size
	return Vector2i(local_x, local_y)

func get_chunk_coord_from_grid(grid_pos: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(grid_pos.x) / float(chunk_size))),
		int(floor(float(grid_pos.y) / float(chunk_size)))
	)

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		grid_pos.x * grid_cell_size + grid_cell_size * 0.5,
		0,
		grid_pos.y * grid_cell_size + grid_cell_size * 0.5
	)

# NEW: Generate unique key for world position (with rounding)
func _world_pos_to_key(world_pos: Vector3) -> String:
	var rounded_x = snapped(world_pos.x, 0.01)
	var rounded_z = snapped(world_pos.z, 0.01)
	return "%.2f_%.2f" % [rounded_x, rounded_z]

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

func check_area_placement_with_props(world_pos: Vector3, size: Vector2, building_name: String = "Unknown") -> Dictionary:
	var result = {
		"can_place": true,
		"blocked_cells": [],
		"blocking_props": [],
		"grid_start": Vector2i.ZERO,
		"grid_end": Vector2i.ZERO,
		"total_cells": 0
	}
	
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(size.x, 0, size.y))
	
	result.grid_start = grid_start
	result.grid_end = grid_end
	result.total_cells = (grid_end.x - grid_start.x) * (grid_end.y - grid_start.y)
	
	var blocking_props_set = {}
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			var cell_pos = Vector2i(x, y)
			if not is_walkable(cell_pos):
				result.can_place = false
				result.blocked_cells.append(cell_pos)
				
				if prop_blocked_cells.has(cell_pos):
					var prop_name = prop_blocked_cells[cell_pos]
					blocking_props_set[prop_name] = true
	
	for prop_name in blocking_props_set:
		result.blocking_props.append(prop_name)
	
	if debug_mode:
		print("=== PLACEMENT CHECK (WITH PROPS) ===")
		print("Building: %s" % building_name)
		print("World Position: %s" % world_pos)
		print("Grid Range: %s to %s (%d cells)" % [grid_start, grid_end, result.total_cells])
		print("Can place: %s" % ("YES" if result.can_place else "NO"))
		if not result.can_place and result.blocking_props.size() > 0:
			print("Blocked by props: %s" % ", ".join(result.blocking_props))
		print("====================================")
	
	return result

# IMPROVED: Register environment prop with tracking
func register_prop_obstacle(world_pos: Vector3, prop_size: Vector2, prop_name: String):
	var pos_key = _world_pos_to_key(world_pos)
	
	# Check if already registered
	if prop_registrations.has(pos_key):
		if debug_mode:
			print("⚠️ Prop already registered at %s" % world_pos)
		return
	
	var grid_start = world_to_grid(world_pos)
	var grid_end = world_to_grid(world_pos + Vector3(prop_size.x, 0, prop_size.y))
	
	var affected_cells = []
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			var grid_pos = Vector2i(x, y)
			set_cell(grid_pos, CellState.BLOCKED)
			prop_blocked_cells[grid_pos] = prop_name
			affected_cells.append(grid_pos)
	
	# Store registration info for precise unregistration
	prop_registrations[pos_key] = {
		"grid_cells": affected_cells,
		"size": prop_size,
		"name": prop_name
	}
	
	if debug_mode:
		print("🌲 Registered prop: %s at %s (%d cells)" % [prop_name, world_pos, affected_cells.size()])

# IMPROVED: Unregister prop with verification
func unregister_prop_obstacle(world_pos: Vector3, prop_size: Vector2):
	var pos_key = _world_pos_to_key(world_pos)
	
	if not prop_registrations.has(pos_key):
		if debug_mode:
			print("⚠️ No prop registration found at %s (key: %s)" % [world_pos, pos_key])
			print("   Available keys: %s" % prop_registrations.keys())
		return
	
	var reg_data = prop_registrations[pos_key]
	var affected_cells = reg_data.grid_cells
	
	# Clear the exact cells that were blocked
	for grid_pos in affected_cells:
		prop_blocked_cells.erase(grid_pos)
		set_cell(grid_pos, CellState.WALKABLE)
	
	prop_registrations.erase(pos_key)
	
	if debug_mode:
		print("🪓 Unregistered prop at %s (%d cells freed)" % [world_pos, affected_cells.size()])

# NEW: Clear all prop obstacles (useful for chunk unloading)
func clear_prop_obstacles_in_area(world_start: Vector3, world_end: Vector3):
	var grid_start = world_to_grid(world_start)
	var grid_end = world_to_grid(world_end)
	
	var cleared_count = 0
	
	for x in range(grid_start.x, grid_end.x):
		for y in range(grid_start.y, grid_end.y):
			var grid_pos = Vector2i(x, y)
			if prop_blocked_cells.has(grid_pos):
				prop_blocked_cells.erase(grid_pos)
				set_cell(grid_pos, CellState.WALKABLE)
				cleared_count += 1
	
	if debug_mode and cleared_count > 0:
		print("🧹 Cleared %d prop obstacles in area" % cleared_count)

# --- PATHFINDING (A*) ---
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

# --- PUBLIC API ---
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
	prop_blocked_cells.clear()
	prop_registrations.clear()
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

func get_prop_blocked_count() -> int:
	return prop_blocked_cells.size()

func get_prop_registration_count() -> int:
	return prop_registrations.size()
