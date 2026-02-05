extends Node3D
class_name NPCMovementOptimized

## Reference to the unit this controls
var unit: Unit

## Movement properties - get from job, these are just defaults if no job
@export var default_move_speed: float = 5.0
@export var rotation_speed: float = 10.0

## Arrival distances - tune these for your needs
@export var arrival_distance: float = 1.5  # How close to final destination to stop
@export var waypoint_reached_distance: float = 2.0  # How close to waypoint before moving to next

## Pathfinding
var current_path: Array[Vector3] = []
var current_waypoint_index: int = 0
var path_update_timer: float = 0.0
var path_update_interval: float = 3.0

## State tracking
var has_arrived: bool = false
var is_moving: bool = false
var waiting_for_path: bool = false

## Current destination
var current_destination: Node3D

## Smoothing
var velocity: Vector3 = Vector3.ZERO
var acceleration: float = 3.0

## Performance optimization
var update_offset: float = 0.0
var active: bool = true

func _ready() -> void:
	unit = get_parent() as Unit
	if not unit:
		push_error("NPCMovement must be child of a Unit node")
		return
	
	# Stagger updates
	update_offset = randf() * path_update_interval
	
	call_deferred("_setup_navigation")

func _setup_navigation() -> void:
	await get_tree().process_frame
	
	# Check for workplace assignment first
	if unit.is_assigned_to_work and unit.assigned_workplace:
		print("NPC %s setup - assigned to workplace at: %s" % [unit.name, unit.work_position])
		var work_marker = Node3D.new()
		work_marker.global_position = unit.work_position
		get_parent().get_parent().add_child(work_marker)
		current_destination = work_marker
		request_path_to_target()
	elif unit.target_stand:
		print("NPC %s setup - target: %s" % [unit.name, unit.target_stand.name])
		current_destination = unit.target_stand
		request_path_to_target()

func set_path_update_interval(interval: float) -> void:
	path_update_interval = interval

func _physics_process(delta: float) -> void:
	if not active or not unit or has_arrived:
		return
	
	# Determine current target
	var target = current_destination
	if not target:
		if unit.is_assigned_to_work:
			# Create temp marker for work position
			return
		elif unit.target_stand:
			target = unit.target_stand
			current_destination = target
	
	if not target:
		return
	
	# Update path periodically
	path_update_timer += delta
	if path_update_timer >= (path_update_interval + update_offset):
		path_update_timer = 0.0
		update_offset = 0.0
		if not waiting_for_path:
			request_path_to_target()
	
	# Move along path
	if current_path.size() > 0:
		_follow_path(delta)
	elif not waiting_for_path:
		# No path and not waiting - try direct movement
		_move_direct(delta)

func request_path_to_target() -> void:
	var target_pos: Vector3
	
	if unit.is_assigned_to_work:
		target_pos = unit.work_position
	elif current_destination:
		target_pos = current_destination.global_position
	else:
		return
	
	# Check if PathfindingManager exists
	if PathfindingManager.instance:
		waiting_for_path = true
		PathfindingManager.instance.request_path(
			unit.global_position,
			target_pos,
			_on_path_received
		)
	else:
		# Fallback to direct grid pathfinding
		_request_path_direct(target_pos)

func _request_path_direct(target_pos: Vector3) -> void:
	var nav_grid = _find_navigation_grid()
	if nav_grid:
		current_path = nav_grid.find_path(
			unit.global_position,
			target_pos
		)
		current_waypoint_index = 0
		waiting_for_path = false
		
		if current_path.size() > 0:
			print("NPC %s: Path found with %d waypoints" % [unit.name, current_path.size()])
		else:
			print("NPC %s: No path found, using direct movement" % unit.name)

func _on_path_received(path: Array[Vector3]) -> void:
	current_path = path
	current_waypoint_index = 0
	waiting_for_path = false
	
	if path.size() > 0:
		print("NPC %s: Path received with %d waypoints" % [unit.name, path.size()])

func _follow_path(delta: float) -> void:
	if current_waypoint_index >= current_path.size():
		# Reached end of path, check if at destination
		_check_arrival()
		return
	
	var target_waypoint = current_path[current_waypoint_index]
	var current_pos = unit.global_position
	
	# Flatten Y for 2D movement
	current_pos.y = 0
	target_waypoint.y = 0
	
	var distance_to_waypoint = current_pos.distance_to(target_waypoint)
	
	# Check if this is the last waypoint (actual destination)
	var is_last_waypoint = (current_waypoint_index == current_path.size() - 1)
	var distance_threshold = arrival_distance if is_last_waypoint else waypoint_reached_distance
	
	# Check if reached current waypoint
	if distance_to_waypoint <= distance_threshold:
		if is_last_waypoint:
			# Reached final destination
			_check_arrival()
			return
		else:
			# Move to next waypoint
			current_waypoint_index += 1
			if current_waypoint_index >= current_path.size():
				_check_arrival()
				return
	
	# Get speed from job or use default
	var move_speed = default_move_speed
	if unit.job:
		move_speed = unit.job.movement_speed
	
	# Move toward waypoint
	var direction = (target_waypoint - current_pos).normalized()
	
	# Smooth acceleration
	var target_velocity = direction * move_speed
	velocity = velocity.lerp(target_velocity, acceleration * delta)
	
	# Apply movement
	var new_pos = unit.global_position + velocity * delta
	new_pos.y = unit.global_position.y  # Maintain Y position
	unit.global_position = new_pos
	
	# Smooth rotation
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		unit.rotation.y = lerp_angle(unit.rotation.y, target_rotation, rotation_speed * delta)
	
	is_moving = true

func _move_direct(delta: float) -> void:
	var target_pos: Vector3
	
	if unit.is_assigned_to_work:
		target_pos = unit.work_position
	elif current_destination:
		target_pos = current_destination.global_position
	else:
		return
	
	var current_pos = unit.global_position
	
	# Flatten Y
	target_pos.y = 0
	current_pos.y = 0
	
	var distance = current_pos.distance_to(target_pos)
	
	# Check arrival
	if distance <= arrival_distance:
		_check_arrival()
		return
	
	# Get speed from job or use default
	var move_speed = default_move_speed
	if unit.job:
		move_speed = unit.job.movement_speed
	
	# Calculate direction
	var direction = (target_pos - current_pos).normalized()
	
	# Smooth movement
	var target_velocity = direction * move_speed
	velocity = velocity.lerp(target_velocity, acceleration * delta)
	
	# Move
	var new_pos = unit.global_position + velocity * delta
	new_pos.y = unit.global_position.y
	unit.global_position = new_pos
	
	# Rotate
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		unit.rotation.y = lerp_angle(unit.rotation.y, target_rotation, rotation_speed * delta)
	
	is_moving = true

func _check_arrival() -> void:
	if has_arrived:
		return
	
	var target_pos: Vector3
	if unit.is_assigned_to_work:
		target_pos = unit.work_position
	elif current_destination:
		target_pos = current_destination.global_position
	else:
		return
	
	var current_pos = unit.global_position
	target_pos.y = 0
	current_pos.y = 0
	
	var distance = current_pos.distance_to(target_pos)
	
	# Use a slightly larger distance for arrival check to avoid jittering
	if distance <= arrival_distance * 1.2:
		has_arrived = true
		is_moving = false
		velocity = Vector3.ZERO
		current_path.clear()
		
		if unit.is_assigned_to_work:
			print("✓ NPC %s arrived at workplace (distance: %.2f)" % [unit.name, distance])
		else:
			print("✓ NPC %s arrived at %s (distance: %.2f)" % [unit.name, current_destination.name if current_destination else "target", distance])
		
		# Notify unit
		unit.on_reached_stand()

func set_active(enabled: bool) -> void:
	active = enabled
	if not active:
		velocity = Vector3.ZERO

func stop() -> void:
	has_arrived = true
	is_moving = false
	velocity = Vector3.ZERO
	current_path.clear()
	waiting_for_path = false

func set_destination(target: Node3D) -> void:
	print("🎯 [%s] SET_DESTINATION called:" % (unit.name if unit else "Unknown"))
	print("  Target: %s" % (target.name if target else "null"))
	print("  Target position: %s" % (target.global_position if target else "N/A"))
	print("  Current position: %s" % (unit.global_position if unit else "N/A"))
	
	current_destination = target
	has_arrived = false
	current_path.clear()
	
	print("  ✓ Destination set, calling request_path_to_target...")
	request_path_to_target()

static var _cached_grid: NavigationGrid = null
func _find_navigation_grid() -> NavigationGrid:
	if _cached_grid:
		return _cached_grid
	
	var root = get_tree().root
	for child in root.get_children():
		var grid = _search_for_grid(child)
		if grid:
			_cached_grid = grid
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
