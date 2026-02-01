extends Node3D
class_name Unit

@export var job: PeasantJob

var _visuals: Node3D

func _ready() -> void:
	_visuals = get_node_or_null("unitVisual")
	if _visuals == null:
		push_error("%s missing unitVisual child node!" % name)
	
	if job == null:
		push_error("%s spawned with NO job assigned!" % name)
		return
	apply_job(job)

func assign_job(new_job: PeasantJob) -> void:
	if new_job == null:
		push_error("Attempted to assign null job")
		return
	if job == new_job:
		return
	job = new_job
	apply_job(job)

func apply_job(new_job: PeasantJob) -> void:
	if _visuals != null and _visuals.has_method("set_model"):
		_visuals.set_model(new_job.model_scene)
