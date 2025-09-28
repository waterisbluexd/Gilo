extends Node3D
class_name RTSGridNPC

# --- GRID MOVEMENT ---
var navigation_grid: NavigationGrid
var current_grid_position: Vector2i
var target_grid_position: Vector2i
var current_path: Array[Vector2i] = []
var path_index: int = 0
var is_moving: bool = false

# --- MOVEMENT TIMING ---
var movement_speed: float = 2.0
var move_timer: float = 0.0
var move_interval: float = 0.5  # Time between grid steps
var grid_cell_size: float = 1.0

# --- AI STATE ---
enum AIState { IDLE, MOVING_TO_IDLE, WORKING, WANDERING, MOVING_TO_WORK }
var current_state: AIState = AIState.IDLE
var idle_timer: float = 0.0
var wander_cooldown: float = 8.0

# --- VISUAL COMPONENTS ---
@onready var mesh_container: Node3D = $MeshContainer if has_node("MeshContainer") else null

# --- SETTINGS ---
@export_group("Movement")
@export var enable_wandering: bool = true
@export var wander_radius: int = 3
@export var smooth_rotation: bool = true

@export_group("Debug")
@export var debug_movement: bool = false
@export var debug_ai: bool = false

# --- SIGNALS ---
signal reached_destination()
signal state_changed(new_state: AIState)

func _ready():
	# Will be set by castle spawner or externally
	if not navigation_grid:
		navigation_grid = _find_navigation_grid()
	
	if navigation_grid:
		grid_cell_size = navigation_grid.grid_cell_size
		move_interval = grid_cell_size / movement_speed
		
		# Set initial grid position
		current_grid_position = navigation_grid.world_to_grid(global_position)
		_snap_to_grid_position(current_grid_position)
		target_grid_position = current_grid_position
		
		if debug_ai:
			print("RTS NPC %s ready at grid %s" % [name, current_grid_position])

func _find_navigation_grid() -> NavigationGrid:
	"""Find NavigationGrid in scene"""
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
	"""Handle grid-based movement without physics"""
	if not is_moving or current_path.is_empty():
		return
	
	move_timer += delta
	
	if move_timer >= move_interval:
		move_timer = 0.0
		_step_to_next_grid_cell()

func _step_to_next_grid_cell():
	"""Move to next cell in path"""
	if path_index >= current_path.size():
		_finish_movement()
		return
	
	var next_grid = current_path[path_index]
	
	# Verify cell is still walkable
	if not navigation_grid.is_walkable(next_grid):
		if debug_movement:
			print("%s: Path blocked, recalculating" % name)
		_recalculate_path()
		return
	
	# Move to next cell
	current_grid_position = next_grid
	_snap_to_grid_position(current_grid_position)
	
	# Face movement direction
	if smooth_rotation and path_index > 0:
		var direction = current_grid_position - current_path[path_index - 1]
		_face_grid_direction(direction)
	
	path_index += 1
	
	if debug_movement:
		print("%s moved to grid %s" % [name, current_grid_position])

func _snap_to_grid_position(grid_pos: Vector2i):
	"""Snap world position to grid cell center"""
	global_position = Vector3(
		grid_pos.x * grid_cell_size + grid_cell_size * 0.5,
		global_position.y,
		grid_pos.y * grid_cell_size + grid_cell_size * 0.5
	)

func _face_grid_direction(direction: Vector2i):
	"""Rotate to face movement direction"""
	if direction == Vector2i.ZERO:
		return
	
	var angle = atan2(direction.x, direction.y)
	if smooth_rotation:
		var tween = create_tween()
		tween.tween_property(self, "rotation:y", angle, 0.2)
	else:
		rotation.y = angle

func _update_ai_behavior(delta):
	"""Simple AI state machine"""
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
	"""Try to find a wander target"""
	var wander_target = _find_wander_position()
	if wander_target != Vector2i(-999, -999):  # Valid position
		move_to_grid_position(wander_target)
		_change_state(AIState.WANDERING)
	else:
		idle_timer = 0.0  # Reset idle timer

func _find_wander_position() -> Vector2i:
	"""Find random walkable position nearby"""
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
	
	return Vector2i(-999, -999)  # Invalid

func _change_state(new_state: AIState):
	"""Change AI state"""
	var old_state = current_state
	current_state = new_state
	idle_timer = 0.0
	
	if debug_ai:
		print("%s: %s -> %s" % [name, AIState.keys()[old_state], AIState.keys()[new_state]])
	
	state_changed.emit(new_state)

func _finish_movement():
	"""Complete movement"""
	is_moving = false
	current_path.clear()
	path_index = 0
	target_grid_position = current_grid_position
	
	if debug_movement:
		print("%s reached destination at %s" % [name, current_grid_position])
	
	reached_destination.emit()

func _recalculate_path():
	"""Recalculate path when blocked"""
	if target_grid_position == current_grid_position:
		_finish_movement()
		return
	
	# Convert to world coordinates for pathfinding
	var start_world = Vector3(current_grid_position.x, 0, current_grid_position.y)
	var end_world = Vector3(target_grid_position.x, 0, target_grid_position.y)
	
	var world_path = navigation_grid.find_path(start_world, end_world)
	if world_path.is_empty():
		if debug_movement:
			print("%s: No alternate path found" % name)
		_finish_movement()
		return
	
	# Convert back to grid path
	current_path.clear()
	for world_pos in world_path:
		current_path.append(navigation_grid.world_to_grid(world_pos))
	
	# Remove current position from path
	if current_path.size() > 0 and current_path[0] == current_grid_position:
		current_path.remove_at(0)
	
	path_index = 0

# --- PUBLIC API ---
func set_navigation_grid(grid: NavigationGrid):
	"""Set navigation grid reference"""
	navigation_grid = grid
	if navigation_grid:
		grid_cell_size = navigation_grid.grid_cell_size
		move_interval = grid_cell_size / movement_speed
		current_grid_position = navigation_grid.world_to_grid(global_position)
		_snap_to_grid_position(current_grid_position)
		target_grid_position = current_grid_position

func move_to_grid_position(target: Vector2i):
	"""Move to specific grid position"""
	if not navigation_grid or target == current_grid_position:
		return
	
	if not navigation_grid.is_walkable(target):
		if debug_movement:
			print("%s: Target %s not walkable" % [name, target])
		return
	
	target_grid_position = target
	
	# Get path from navigation grid
	var start_world = Vector3(current_grid_position.x, 0, current_grid_position.y)
	var end_world = Vector3(target.x, 0, target.y)
	
	var world_path = navigation_grid.find_path(start_world, end_world)
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
		return
	
	path_index = 0
	is_moving = true
	move_timer = 0.0
	
	if debug_movement:
		print("%s moving to %s (path: %d steps)" % [name, target, current_path.size()])

func move_to_world_position(world_pos: Vector3):
	"""Move to world position (converted to grid)"""
	if not navigation_grid:
		return
	var grid_pos = navigation_grid.world_to_grid(world_pos)
	move_to_grid_position(grid_pos)

func move_to_idle_zone(idle_pos: Vector3):
	"""Move to idle zone (called by castle spawner)"""
	move_to_world_position(idle_pos)
	_change_state(AIState.MOVING_TO_IDLE)

func set_work_position(work_pos: Vector3):
	"""Assign work location"""
	move_to_world_position(work_pos)
	_change_state(AIState.MOVING_TO_WORK)

func stop_movement():
	"""Stop current movement"""
	is_moving = false
	current_path.clear()
	path_index = 0
	target_grid_position = current_grid_position

func set_movement_speed(speed: float):
	"""Change movement speed"""
	movement_speed = speed
	if navigation_grid:
		move_interval = grid_cell_size / movement_speed

# --- UTILITY FUNCTIONS ---
func is_at_grid_position(grid_pos: Vector2i) -> bool:
	"""Check if at specific grid position"""
	return current_grid_position == grid_pos

func get_current_grid_position() -> Vector2i:
	"""Get current grid position"""
	return current_grid_position

func can_reach_position(target: Vector2i) -> bool:
	"""Check if position is reachable"""
	if not navigation_grid:
		return false
	
	var start_world = Vector3(current_grid_position.x, 0, current_grid_position.y)
	var end_world = Vector3(target.x, 0, target.y)
	
	var path = navigation_grid.find_path(start_world, end_world)
	return not path.is_empty()

func get_grid_distance_to(target: Vector2i) -> int:
	"""Get Manhattan distance to target"""
	return abs(current_grid_position.x - target.x) + abs(current_grid_position.y - target.y)

func is_idle() -> bool:
	"""Check if NPC is currently idle"""
	return current_state == AIState.IDLE

func is_working() -> bool:
	"""Check if NPC is working"""
	return current_state == AIState.WORKING

# --- SAVE/LOAD ---
func get_save_data() -> Dictionary:
	return {
		"grid_pos": [current_grid_position.x, current_grid_position.y],
		"state": current_state,
		"speed": movement_speed
	}

func load_save_data(data: Dictionary):
	if "grid_pos" in data:
		var pos = data.grid_pos
		current_grid_position = Vector2i(pos[0], pos[1])
		target_grid_position = current_grid_position
		_snap_to_grid_position(current_grid_position)
	
	if "state" in data:
		current_state = data.state
	
	if "speed" in data:
		set_movement_speed(data.speed)
