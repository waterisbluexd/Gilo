extends Node3D
class_name Unit

## The job this unit is assigned to
@export var job: PeasantJob

## Visual representation of the unit
var _visuals: Node3D

## Current target location (GatheringStand node)
var target_stand: Node3D

## Reference to parent spawner
var spawner: Node3D

## Workplace assignment
var assigned_workplace: Node3D
var work_position: Vector3
var is_at_workplace: bool = false
var is_assigned_to_work: bool = false

func _ready() -> void:
	_visuals = get_node_or_null("unitVisual")
	if _visuals == null:
		push_warning("%s missing unitVisual child node" % name)
	
	if job == null:
		push_error("%s spawned with NO job assigned!" % name)
		return
	
	apply_job(job)

## Assign a new job to this unit
func assign_job(new_job: PeasantJob) -> void:
	if new_job == null:
		return
	
	job = new_job
	apply_job(job)

## Apply job properties to the unit
func apply_job(new_job: PeasantJob) -> void:
	if _visuals != null and _visuals.has_method("set_model"):
		_visuals.set_model(new_job.model_scene)

## Check if this unit should go to gathering stands
func should_gather() -> bool:
	if not job:
		return false
	
	# Only peasants with can_work = true should gather
	return job.can_work and not job.can_fight and not is_assigned_to_work

## Set workplace destination
func set_work_destination(workplace: Node3D, position: Vector3) -> void:
	assigned_workplace = workplace
	work_position = position
	is_assigned_to_work = true
	is_at_workplace = false
	
	print("🏗️ [%s] SET WORK DESTINATION:" % name)
	print("  Workplace: %s" % workplace.name)
	print("  Position: %s" % position)
	print("  Current position: %s" % global_position)
	
	# Clear gathering stand if previously assigned
	target_stand = null
	
	# Get movement component and set new destination
	var movement = get_node_or_null("NPCMovement")
	if not movement:
		push_error("[%s] NO MOVEMENT COMPONENT FOUND!" % name)
		return
	
	print("  ✓ Movement component found")
	
	# Stop any current movement
	if movement.has_method("stop"):
		movement.stop()
	
	# Create a temporary marker at work position
	var work_marker = Node3D.new()
	work_marker.name = "WorkMarker_%s" % name
	work_marker.global_position = position
	
	# Add to scene
	if get_parent():
		get_parent().add_child(work_marker)
		print("  ✓ Work marker created at: %s" % work_marker.global_position)
	else:
		push_error("[%s] No parent to add work marker!" % name)
		return
	
	# Enable movement
	movement.active = true
	
	# Set as new target using the movement's set_destination method
	if movement.has_method("set_destination"):
		movement.set_destination(work_marker)
		print("  ✓ Destination set, requesting path...")
	else:
		push_error("[%s] Movement has no set_destination method!" % name)

## Called when unit reaches the gathering stand
func on_reached_stand() -> void:
	if is_assigned_to_work:
		is_at_workplace = true
		print("✓ %s arrived at workplace" % name)
	else:
		pass  # Empty for now - add behavior later if needed

## Clear workplace assignment
func clear_work_assignment() -> void:
	assigned_workplace = null
	work_position = Vector3.ZERO
	is_assigned_to_work = false
	is_at_workplace = false
	print("✓ %s cleared from workplace" % name)
