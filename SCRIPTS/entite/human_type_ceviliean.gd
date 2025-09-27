extends Node3D
class_name Peasant

# --- PEASANT STATES ---
enum State {
	SPAWNING,
	MOVING_TO_IDLE,
	IDLE,
	WANDERING,
	MOVING_TO_WORK,
	WORKING
}

# --- SETTINGS ---
@export_group("Movement")
@export var move_speed: float = 3.0
@export var wander_speed: float = 1.5
@export var rotation_speed: float = 5.0

@export_group("Behavior")
@export var idle_time_min: float = 3.0
@export var idle_time_max: float = 8.0
@export var wander_chance: float = 0.3
@export var zone_check_interval: float = 0.5

# --- REFERENCES ---
var target_castle: Castle
var terrain_system: ChunkPixelTerrain
@onready var mesh_instance: MeshInstance3D = $body

# --- INTERNAL STATE ---
var state: State = State.SPAWNING
var target_position: Vector3
var current_zone: IdleZone
var idle_timer: float = 0.0
var zone_check_timer: float = 0.0
var movement_target: Vector3

# --- INITIALIZATION ---
func _ready():
	_setup_peasant_mesh()
	_initialize_state()

func _setup_peasant_mesh():
	# Don't create mesh - assume it's already set up in the scene
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			push_warning("Peasant: No MeshInstance3D found. Please add one to the scene.")

func _initialize_state():
	if target_castle:
		target_position = target_castle.get_idle_position()
		state = State.MOVING_TO_IDLE
	else:
		state = State.IDLE

# --- MAIN UPDATE ---
func _process(delta):
	_update_state(delta)
	_check_zone_membership(delta)
	_snap_to_terrain()

func _update_state(delta):
	match state:
		State.SPAWNING:
			_handle_spawning_state()
		
		State.MOVING_TO_IDLE:
			_handle_moving_to_idle_state(delta)
		
		State.IDLE:
			_handle_idle_state(delta)
		
		State.WANDERING:
			_handle_wandering_state(delta)

# --- STATE HANDLERS ---
func _handle_spawning_state():
	# Just spawned, move to idle zone
	if target_castle:
		target_position = target_castle.get_idle_position()
		state = State.MOVING_TO_IDLE

func _handle_moving_to_idle_state(delta):
	_move_towards_target(delta, move_speed)
	
	# Check if reached idle zone
	if global_position.distance_to(target_position) < 1.0:
		_enter_idle_state()

func _handle_idle_state(delta):
	idle_timer -= delta
	
	# Occasionally wander around
	if idle_timer <= 0 and randf() < wander_chance:
		_start_wandering()
	elif idle_timer <= 0:
		# Reset idle timer
		idle_timer = randf_range(idle_time_min, idle_time_max)

func _handle_wandering_state(delta):
	_move_towards_target(delta, wander_speed)
	
	# Check if reached wander target
	if global_position.distance_to(target_position) < 1.0:
		_enter_idle_state()

# --- MOVEMENT ---
func _move_towards_target(delta: float, speed: float):
	var direction = (target_position - global_position)
	direction.y = 0  # Keep movement on horizontal plane
	
	if direction.length() > 0.1:
		direction = direction.normalized()
		
		# Check for obstacles in the movement path
		var safe_direction = get_safe_movement_direction(direction)
		
		# Move position
		global_position += safe_direction * speed * delta
		
		# Rotate to face movement direction
		if safe_direction.length() > 0.1:
			var target_rotation = atan2(-safe_direction.x, -safe_direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

func get_safe_movement_direction(intended_direction: Vector3) -> Vector3:
	# Check if intended path is clear
	if is_path_clear(intended_direction):
		return intended_direction
	
	# Try alternative directions (simple obstacle avoidance)
	var alternative_directions = [
		intended_direction.rotated(Vector3.UP, PI * 0.25),  # 45° right
		intended_direction.rotated(Vector3.UP, -PI * 0.25), # 45° left
		intended_direction.rotated(Vector3.UP, PI * 0.5),   # 90° right
		intended_direction.rotated(Vector3.UP, -PI * 0.5),  # 90° left
	]
	
	for alt_dir in alternative_directions:
		if is_path_clear(alt_dir):
			return alt_dir
	
	# If all else fails, slow down but keep moving
	return intended_direction * 0.1

func is_path_clear(direction: Vector3) -> bool:
	var check_distance = 2.0  # Look ahead distance
	var future_pos = global_position + direction * check_distance
	
	# Check against building obstacles
	var building_obstacles = get_tree().get_nodes_in_group("Avoid_Building")
	
	for obstacle in building_obstacles:
		if obstacle is CollisionShape3D:
			var collision_shape = obstacle as CollisionShape3D
			var shape_pos = collision_shape.global_position
			var distance = future_pos.distance_to(shape_pos)
			
			var min_distance = get_collision_shape_radius(collision_shape) + 1.0
			
			if distance < min_distance:
				return false  # Path blocked
	
	return true  # Path clear

func get_collision_shape_radius(collision_shape: CollisionShape3D) -> float:
	var shape = collision_shape.shape
	
	if shape is BoxShape3D:
		var box = shape as BoxShape3D
		return max(box.size.x, max(box.size.y, box.size.z)) * 0.5
	
	elif shape is CylinderShape3D:
		var cylinder = shape as CylinderShape3D
		return max(cylinder.top_radius, cylinder.bottom_radius)
	
	elif shape is SphereShape3D:
		var sphere = shape as SphereShape3D
		return sphere.radius
	
	else:
		return 2.0  # Default radius

func _snap_to_terrain():
	# Snap peasant to terrain height
	if terrain_system:
		var terrain_height = terrain_system.get_height_at_position(global_position)
		global_position.y = terrain_height

# --- STATE TRANSITIONS ---
func _enter_idle_state():
	state = State.IDLE
	idle_timer = randf_range(idle_time_min, idle_time_max)

func _start_wandering():
	if target_castle and target_castle.idle_zone:
		# Get new wander position within idle zone
		target_position = target_castle.idle_zone.find_nearest_free_position(global_position)
		state = State.WANDERING

# --- ZONE MANAGEMENT ---
func _check_zone_membership(delta):
	zone_check_timer -= delta
	if zone_check_timer > 0:
		return
	
	zone_check_timer = zone_check_interval
	
	# Check if we're in an idle zone
	var in_zone = _find_current_zone()
	
	if in_zone != current_zone:
		# Zone changed
		if current_zone:
			current_zone.remove_peasant_from_zone(self)
		
		current_zone = in_zone
		
		if current_zone:
			current_zone.add_peasant_to_zone(self)

func _find_current_zone() -> IdleZone:
	# Check if we're in the castle's idle zone
	if target_castle and target_castle.idle_zone:
		if target_castle.idle_zone.is_position_inside(global_position):
			return target_castle.idle_zone
	
	return null

# --- PUBLIC API ---
func get_state_name() -> String:
	match state:
		State.SPAWNING: return "Spawning"
		State.MOVING_TO_IDLE: return "Moving to Idle"
		State.IDLE: return "Idle"
		State.WANDERING: return "Wandering"
		State.MOVING_TO_WORK: return "Moving to Work"
		State.WORKING: return "Working"
		_: return "Unknown"

func is_idle() -> bool:
	return state == State.IDLE

func assign_work(work_position: Vector3):
	# Future: Assign peasant to work at a specific location
	target_position = work_position
	state = State.MOVING_TO_WORK

# --- CLEANUP ---
func _exit_tree():
	# Remove from zone when peasant is deleted
	if current_zone:
		current_zone.remove_peasant_from_zone(self)
	
	# Remove from castle's peasant list
	if target_castle:
		target_castle.remove_peasant(self)
