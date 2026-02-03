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
	return job.can_work and not job.can_fight

## Called when unit reaches the gathering stand
func on_reached_stand() -> void:
	pass  # Empty for now - add behavior later if needed
