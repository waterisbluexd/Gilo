extends Node
class_name PathfindingManager

## Singleton reference
static var instance: PathfindingManager

## Navigation grid reference
var navigation_grid: NavigationGrid

## Pathfinding queue
var pathfinding_queue: Array[Dictionary] = []
var paths_cache: Dictionary = {}  # Cache paths temporarily

## Performance settings
@export var max_paths_per_frame: int = 5
@export var cache_duration: float = 1.0  # How long to cache paths
@export var batch_process_enabled: bool = true

## Statistics
var total_requests: int = 0
var cached_hits: int = 0
var paths_calculated: int = 0

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	# Find navigation grid
	navigation_grid = _find_navigation_grid()
	if not navigation_grid:
		push_error("PathfindingManager: No NavigationGrid found!")

func _find_navigation_grid() -> NavigationGrid:
	var root = get_tree().root
	for child in root.get_children():
		var grid = _search_for_grid(child)
		if grid:
			return grid
	return null

func _search_for_grid(node: Node) -> NavigationGrid:
	if node is NavigationGrid:
		return node
	for child in node.get_children():
		var result = _search_for_grid(child)
		if result:
			return result
	return null

func _process(_delta: float) -> void:
	if not batch_process_enabled or pathfinding_queue.is_empty():
		return
	
	# Process multiple requests per frame
	var processed = 0
	while processed < max_paths_per_frame and not pathfinding_queue.is_empty():
		var request = pathfinding_queue.pop_front()
		_process_pathfinding_request(request)
		processed += 1

## Request a path (async)
func request_path(from: Vector3, to: Vector3, callback: Callable) -> void:
	total_requests += 1
	
	# Check cache first
	var cache_key = _get_cache_key(from, to)
	if paths_cache.has(cache_key):
		var cached_data = paths_cache[cache_key]
		if Time.get_ticks_msec() - cached_data.timestamp < cache_duration * 1000:
			cached_hits += 1
			callback.call(cached_data.path)
			return
	
	# Add to queue
	pathfinding_queue.append({
		"from": from,
		"to": to,
		"callback": callback,
		"timestamp": Time.get_ticks_msec()
	})

## Process a single pathfinding request
func _process_pathfinding_request(request: Dictionary) -> void:
	if not navigation_grid:
		request.callback.call([])
		return
	
	var path = navigation_grid.find_path(request.from, request.to)
	paths_calculated += 1
	
	# Cache the result
	var cache_key = _get_cache_key(request.from, request.to)
	paths_cache[cache_key] = {
		"path": path,
		"timestamp": Time.get_ticks_msec()
	}
	
	# Call callback
	request.callback.call(path)

## Generate cache key from positions
func _get_cache_key(from: Vector3, to: Vector3) -> String:
	var from_grid = navigation_grid.world_to_grid(from)
	var to_grid = navigation_grid.world_to_grid(to)
	return "%d_%d_%d_%d" % [from_grid.x, from_grid.y, to_grid.x, to_grid.y]

## Clear old cache entries
func cleanup_cache() -> void:
	var current_time = Time.get_ticks_msec()
	var keys_to_remove = []
	
	for key in paths_cache.keys():
		var data = paths_cache[key]
		if current_time - data.timestamp > cache_duration * 1000:
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		paths_cache.erase(key)
