# === ENHANCED BUT COMPATIBLE RTSGridNPC ===
# Replace your existing RTSGridNPC.gd with this version
# This maintains compatibility with your spawner while adding enhancements

extends Node3D
class_name RTSGridNPC

# --- GRID MOVEMENT (Enhanced) ---
var navigation_grid: NavigationGrid
var current_grid_position: Vector2i
var target_grid_position: Vector2i
var current_path: Array[Vector2i] = []
var path_index: int = 0
var is_moving: bool = false

# --- SMOOTH MOVEMENT (NEW) ---
var smooth_movement: bool = true
var movement_speed: float = 2.0
var move_timer: float = 0.0
var move_interval: float = 0.5
var grid_cell_size: float = 1.0
var arrival_threshold: float = 0.1

# --- AI STATE ---
enum AIState { IDLE, MOVING_TO_IDLE, WORKING, WANDERING, MOVING_TO_WORK }
var current_state: AIState = AIState.IDLE
var idle_timer: float = 0.0
var wander_cooldown: float = 8.0

# --- NPC PERSONALITY (NEW) ---
var prefers_roads: bool = true
var avoid_danger: bool = true
var movement_preferences: Dictionary = {}

# --- JOB SYSTEM ---
var assigned_workplace: Node3D
var assigned_home: Node3D
var current_job_type: String = ""

# --- VISUAL COMPONENTS ---
@onready var mesh_container: Node3D = $MeshContainer if has_node("MeshContainer") else null

# --- SETTINGS ---
@export_group("Movement")
@export var enable_wandering: bool = true
@export var wander_radius: int = 3
@export var smooth_rotation: bool = true
@export var use_smooth_movement: bool = true

@export_group("Debug")
@export var debug_movement: bool = false
@export var debug_ai: bool = false

# --- SIGNALS ---
signal reached_destination()
signal state_changed(new_state: AIState)

func _ready():
	if not navigation_grid:
		navigation_grid = _find_navigation_grid()
	
	if navigation_grid:
		grid_cell_size = navigation_grid.grid_cell_size
		move_interval = grid_cell_size / movement_speed
		
		# Set initial grid position
		current_grid_position = navigation_grid.world_to_grid(global_position)
		_snap_to_grid_position(current_grid_position)
		target_grid_position = current_grid_position
		
		# Setup movement preferences for smart pathfinding
		movement_preferences = {
			"prefers_roads": prefers_roads,
			"avoid_danger": avoid_danger,
			"can_swim": false,
			"brave": false
		}
		
		if debug_ai:
			print("Enhanced NPC %s ready at grid %s" % [name, current_grid_position])

func _find_navigation_grid() -> NavigationGrid:
	var current = get_parent()
	while current:
		for child in current.get_children():
			if child is NavigationGrid:
				return child as NavigationGrid
		current = current.get_parent()
	return null

func _process(delta):
	if not navigation_grid:
		return
	
	_update_movement(delta)
	_update_ai_behavior(delta)

func _update_movement(delta):
	if not is_moving or current_path.is_empty():
		return
	
	if use_smooth_movement:
		_smooth_movement_update(delta)
	else:
		_grid_movement_update(delta)

func _smooth_movement_update(delta):
	"""Enhanced smooth movement between grid cells"""
	if path_index >= current_path.size():
		_finish_movement()
		return
	
	var target_grid = current_path[path_index]
	var target_world = _grid_to_world_center(target_grid)
	var distance = global_position.distance_to(target_world)
	
	if distance > arrival_threshold:
		# Move smoothly toward target
		var direction = (target_world - global_position).normalized()
		global_position += direction * movement_speed * delta
		
		# Smooth rotation
		if smooth_rotation and direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, 5.0 * delta)
	else:
		# Arrived at waypoint
		current_grid_position = target_grid
		path_index += 1
		
		if debug_movement:
			print("%s reached waypoint %d/%d at grid %s" % [name, path_index, current_path.size(), target_grid])

func _grid_movement_update(delta):
	"""Original grid-based movement"""
	move_timer += delta
	
	if move_timer >= move_interval:
		move_timer = 0.0
		_step_to_next_grid_cell()

func _step_to_next_grid_cell():
	if path_index >= current_path.size():
		_finish_movement()
		return
	
	var next_grid = current_path[path_index]
	
	if not navigation_grid.is_walkable(next_grid):
		if debug_movement:
			print("%s: Path blocked, recalculating" % name)
		_recalculate_path()
		return
	
	current_grid_position = next_grid
	_snap_to_grid_position(current_grid_position)
	
	if smooth_rotation and path_index > 0:
		var direction = current_grid_position - current_path[path_index - 1]
		_face_grid_direction(direction)
	
	path_index += 1
	
	if debug_movement:
		print("%s moved to grid %s" % [name, current_grid_position])

func _grid_to_world_center(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		grid_pos.x * grid_cell_size + grid_cell_size * 0.5,
		global_position.y,  # Keep current Y position
		grid_pos.y * grid_cell_size + grid_cell_size * 0.5
	)

func _snap_to_grid_position(grid_pos: Vector2i):
	global_position = _grid_to_world_center(grid_pos)

func _face_grid_direction(direction: Vector2i):
	if direction == Vector2i.ZERO:
		return
	
	var angle = atan2(direction.x, direction.y)
	if smooth_rotation:
		var tween = create_tween()
		tween.tween_property(self, "rotation:y", angle, 0.2)
	else:
		rotation.y = angle

func _update_ai_behavior(delta):
	match current_state:
		AIState.IDLE:
			idle_timer += delta
			if enable_wandering and idle_timer >= wander_cooldown:
				_try_start_wandering()
		
		AIState.MOVING_TO_IDLE:
			if not is_moving:
				_change_state(AIState.IDLE)
		
		AIState.WANDERING:
			if not is_moving:
				_change_state(AIState.IDLE)
		
		AIState.MOVING_TO_WORK:
			if not is_moving:
				_change_state(AIState.WORKING)

func _try_start_wandering():
	var wander_target = _find_wander_position()
	if wander_target != Vector2i(-999, -999):
		move_to_grid_position(wander_target)
		_change_state(AIState.WANDERING)
	else:
		idle_timer = 0.0

func _find_wander_position() -> Vector2i:
	var attempts = 8
	while attempts > 0:
		var offset = Vector2i(
			randi_range(-wander_radius, wander_radius),
			randi_range(-wander_radius, wander_radius)
		)
		var target = current_grid_position + offset
		
		if navigation_grid.is_walkable(target):
			return target
		
		attempts -= 1
	
	return Vector2i(-999, -999)

func _change_state(new_state: AIState):
	var old_state = current_state
	current_state = new_state
	idle_timer = 0.0
	
	if debug_ai:
		print("%s: %s -> %s" % [name, AIState.keys()[old_state], AIState.keys()[new_state]])
	
	state_changed.emit(new_state)

func _finish_movement():
	is_moving = false
	current_path.clear()
	path_index = 0
	target_grid_position = current_grid_position
	
	if debug_movement:
		print("%s reached final destination at %s" % [name, current_grid_position])
	
	reached_destination.emit()

func _recalculate_path():
	if target_grid_position == current_grid_position:
		_finish_movement()
		return
	
	var start_world = _grid_to_world_center(current_grid_position)
	var end_world = _grid_to_world_center(target_grid_position)
	
	var world_path: Array[Vector3]
	
	# Use enhanced pathfinding if available
	if navigation_grid.has_method("find_smart_path"):
		world_path = navigation_grid.find_smart_path(start_world, end_world, movement_preferences)
	else:
		world_path = navigation_grid.find_path(start_world, end_world)
	
	if world_path.is_empty():
		if debug_movement:
			print("%s: No alternate path found" % name)
		_finish_movement()
		return
	
	current_path.clear()
	for world_pos in world_path:
		current_path.append(navigation_grid.world_to_grid(world_pos))
	
	if current_path.size() > 0 and current_path[0] == current_grid_position:
		current_path.remove_at(0)
	
	path_index = 0

# === COMPATIBLE PUBLIC API (Your spawner uses these) ===
func set_navigation_grid(grid: NavigationGrid):
	navigation_grid = grid
	if navigation_grid:
		grid_cell_size = navigation_grid.grid_cell_size
		move_interval = grid_cell_size / movement_speed
		current_grid_position = navigation_grid.world_to_grid(global_position)
		_snap_to_grid_position(current_grid_position)
		target_grid_position = current_grid_position

func move_to_world_position(world_pos: Vector3):
	"""This method is called by your BuildingSpawner"""
	if not navigation_grid:
		if debug_movement:
			print("%s: No navigation grid for move_to_world_position" % name)
		return
	
	var grid_pos = navigation_grid.world_to_grid(world_pos)
	move_to_grid_position(grid_pos)
	
	if debug_movement:
		print("%s: Moving to world position %s (grid %s)" % [name, world_pos, grid_pos])

func move_to_grid_position(target: Vector2i):
	if not navigation_grid or target == current_grid_position:
		return
	
	if not navigation_grid.is_walkable(target):
		if debug_movement:
			print("%s: Target %s not walkable" % [name, target])
		return
	
	target_grid_position = target
	
	# Get path using enhanced pathfinding
	var start_world = _grid_to_world_center(current_grid_position)
	var end_world = _grid_to_world_center(target)
	
	var world_path: Array[Vector3]
	
	# Use enhanced pathfinding if available
	if navigation_grid.has_method("find_smart_path"):
		world_path = navigation_grid.find_smart_path(start_world, end_world, movement_preferences)
	else:
		world_path = navigation_grid.find_path(start_world, end_world)
	
	if world_path.is_empty():
		if debug_movement:
			print("%s: No path to %s" % [name, target])
		return
	
	# Convert to grid path
	current_path.clear()
	for world_pos in world_path:
		current_path.append(navigation_grid.world_to_grid(world_pos))
	
	# Remove current position
	if current_path.size() > 0 and current_path[0] == current_grid_position:
		current_path.remove_at(0)
	
	if current_path.is_empty():
		if debug_movement:
			print("%s: Path is empty after processing" % name)
		return
	
	path_index = 0
	is_moving = true
	move_timer = 0.0
	
	if debug_movement:
		print("%s: Starting movement to %s via %d waypoints" % [name, target, current_path.size()])

# === COMPATIBILITY METHODS ===
func move_to_idle_zone(idle_pos: Vector3):
	move_to_world_position(idle_pos)
	_change_state(AIState.MOVING_TO_IDLE)

func set_work_position(work_pos: Vector3):
	move_to_world_position(work_pos)
	_change_state(AIState.MOVING_TO_WORK)

func stop_movement():
	is_moving = false
	current_path.clear()
	path_index = 0
	target_grid_position = current_grid_position

func set_movement_speed(speed: float):
	movement_speed = speed
	if navigation_grid:
		move_interval = grid_cell_size / movement_speed

# === JOB SYSTEM ===
func assign_job(workplace: Node3D, job_type: String):
	assigned_workplace = workplace
	current_job_type = job_type
	if debug_ai:
		print("%s assigned job: %s" % [name, job_type])

func remove_job():
	assigned_workplace = null
	current_job_type = ""
	if debug_ai:
		print("%s lost job" % name)

func assign_home(home: Node3D):
	assigned_home = home
	if debug_ai:
		print("%s assigned home" % name)

func remove_home():
	assigned_home = null
	if debug_ai:
		print("%s lost home" % name)

func has_job() -> bool:
	return assigned_workplace != null

func has_home() -> bool:
	return assigned_home != null

func get_job_type() -> String:
	return current_job_type

# === UTILITY FUNCTIONS ===
func is_at_grid_position(grid_pos: Vector2i) -> bool:
	return current_grid_position == grid_pos

func get_current_grid_position() -> Vector2i:
	return current_grid_position

func can_reach_position(target: Vector2i) -> bool:
	if not navigation_grid:
		return false
	
	var start_world = _grid_to_world_center(current_grid_position)
	var end_world = _grid_to_world_center(target)
	
	var path: Array[Vector3]
	if navigation_grid.has_method("find_smart_path"):
		path = navigation_grid.find_smart_path(start_world, end_world, movement_preferences)
	else:
		path = navigation_grid.find_path(start_world, end_world)
	
	return not path.is_empty()

func get_grid_distance_to(target: Vector2i) -> int:
	return abs(current_grid_position.x - target.x) + abs(current_grid_position.y - target.y)

func is_idle() -> bool:
	return current_state == AIState.IDLE

func is_working() -> bool:
	return current_state == AIState.WORKING

# === DEBUG/TEST METHOD ===
func force_move_test():
	"""Call this to test if NPC can move"""
	if debug_movement:
		print("=== TESTING NPC MOVEMENT ===")
		print("Position: %s" % global_position)
		print("Grid position: %s" % current_grid_position)
		print("Navigation grid: %s" % (navigation_grid != null))
		print("Can move: %s" % (navigation_grid != null and navigation_grid.is_walkable(current_grid_position)))
	
	# Try to move to a nearby position
	var test_target = current_grid_position + Vector2i(2, 2)
	if navigation_grid and navigation_grid.is_walkable(test_target):
		move_to_grid_position(test_target)
		print("Test movement started to: %s" % test_target)
	else:
		print("Cannot move to test target: %s" % test_target)
