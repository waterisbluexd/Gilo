extends Node3D
class_name NPCMovement

## The NPC unit this controls
var unit: Unit
var spawner: Node3D
var gathering_stand: Node3D

## Navigation
var nav_agent: NavigationAgent3D
var move_speed: float = 10.0  # Default speed (increased from 5.0)
var arrival_distance: float = 0.5

var has_arrived: bool = false

func _ready() -> void:
	unit = get_parent()
	if not unit:
		push_error("NPCMovement must be child of a Unit node")
		return
	
	# Create NavigationAgent3D if it doesn't exist
	nav_agent = get_node_or_null("NavigationAgent3D")
	if not nav_agent:
		nav_agent = NavigationAgent3D.new()
		add_child(nav_agent)
		nav_agent.set_owner(get_tree().edited_scene_root)
	
	# Configure nav agent
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0

func _process(delta: float) -> void:
	if not unit or not unit.target_stand:
		return
	
	if not gathering_stand:
		gathering_stand = unit.target_stand
		spawner = unit.get_parent()
		print("NPCMovement: Set target to %s at %s" % [gathering_stand.name, gathering_stand.global_position])
	
	# Calculate direct direction to target (no navigation mesh needed)
	var target_pos = gathering_stand.global_position
	var distance = unit.global_position.distance_to(target_pos)
	
	# Check if arrived
	if distance <= arrival_distance:
		if not has_arrived:
			on_arrived_at_stand()
		return
	
	# Move toward target
	var direction = (target_pos - unit.global_position).normalized()
	
	if unit.job:
		move_speed = unit.job.movement_speed
	
	unit.global_position += direction * move_speed * delta
	
	# Face direction
	if direction.length() > 0:
		unit.look_at(unit.global_position + direction, Vector3.UP)
	
	# Debug: Show movement
	if randf() < 0.02:  # Print occasionally to avoid spam
		print("NPC %s moving toward %s, distance: %.2f" % [unit.name, gathering_stand.name, distance])

func set_navigation_target(target_pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = target_pos

func on_arrived_at_stand() -> void:
	has_arrived = true
	print("NPC arrived at gathering stand")
	
	if gathering_stand:
		gathering_stand.npc_arrived(unit)
	
	# TODO: Start gathering behavior
