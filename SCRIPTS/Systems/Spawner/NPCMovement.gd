extends Node3D
class_name NPCMovementOptimized

## Reference to the unit this controls
var unit: Unit

## Movement properties
@export var default_move_speed: float = 5.0
@export var rotation_speed: float = 10.0

## Arrival distances
@export var arrival_distance: float = 1.0
@export var waypoint_reached_distance: float = 0.5

## Godot's built-in Navigation
var navigation_agent: NavigationAgent3D

## State tracking
var has_arrived: bool = false
var active: bool = true

## Current destination
var current_destination: Vector3

## Smoothing
var velocity: Vector3 = Vector3.ZERO
var acceleration: float = 10.0

func _ready() -> void:
	unit = get_parent() as Unit
	if not unit:
		push_error("NPCMovement must be child of a Unit node")
		return
	
	# Create NavigationAgent3D node - Godot's built-in navigation
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "NavigationAgent3D"
	add_child(navigation_agent)
	
	# Configure for RTS-style movement
	navigation_agent.agent_height = 2.0
	navigation_agent.agent_max_speed = default_move_speed
	navigation_agent.radius = 0.5
	navigation_agent.avoidance_enabled = true  # Enable obstacle avoidance
	
	# Connect navigation events
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	navigation_agent.navigation_finished.connect(_on_navigation_finished)
	
	# Small delay to let scene setup complete
	call_deferred("_setup_initial_destination")

func _setup_initial_destination() -> void:
	await get_tree().process_frame
	
	# Check for workplace assignment first
	if unit.is_assigned_to_work and unit.work_position != Vector3.ZERO:
		set_destination(unit.work_position)
	elif unit.target_stand:
		set_destination(unit.target_stand.global_position)

func set_destination(pos: Vector3) -> void:
	if not navigation_agent:
		return
	
	current_destination = pos
	has_arrived = false
	
	# Set target - Godot's navigation system handles the rest
	navigation_agent.target_position = pos
	
	# Force path calculation
	var next_pos = navigation_agent.get_next_path_position()
	if next_pos == Vector3.ZERO:
		# Try again
		navigation_agent.target_position = pos
	
	print("[%s] Setting destination to: %s" % [unit.name if unit else "NPC", pos])

func _physics_process(delta: float) -> void:
	if not active or not navigation_agent or has_arrived:
		return
	
	# Get the next position along the path
	var next_path_pos = navigation_agent.get_next_path_position()
	
	if next_path_pos == Vector3.ZERO:
		# No valid path
		return
	
	# Calculate direction to next waypoint
	var direction = (next_path_pos - global_position).normalized()
	
	# Check if close enough to waypoint
	var distance_to_target = global_position.distance_to(current_destination)
	if distance_to_target <= arrival_distance:
		has_arrived = true
		_on_navigation_finished()
		return
	
	# Move towards target using avoidance
	var target_velocity = direction * default_move_speed
	navigation_agent.set_velocity(target_velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	# Apply the computed safe velocity with smoothing
	velocity = velocity.lerp(safe_velocity, acceleration * get_physics_process_delta_time())
	global_position += velocity * get_physics_process_delta_time()
	
	# Rotate to face movement direction
	if velocity.length() > 0.1:
		var target_rotation = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * get_physics_process_delta_time())

func _on_navigation_finished() -> void:
	has_arrived = true
	velocity = Vector3.ZERO
	
	if unit:
		print("[%s] Arrived at destination!" % unit.name)
		unit.on_reached_stand()

func stop() -> void:
	active = false
	has_arrived = true
	if navigation_agent:
		navigation_agent.target_position = global_position  # Stop movement

func is_navigation_valid() -> bool:
	return navigation_agent != null and navigation_agent.is_navigation_finished() == false
