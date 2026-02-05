extends Node

## Singleton instance
static var instance

## Active workplaces and their assignments
var workplaces: Dictionary = {}  # workplace_id -> WorkplaceData
var job_assignments: Dictionary = {}  # unit -> workplace_id
var available_workers: Array[Unit] = []

signal worker_assigned(unit: Unit, workplace: Node3D)
signal worker_unassigned(unit: Unit, workplace: Node3D)

class WorkplaceData:
	var workplace: Node3D
	var job_type: String
	var max_workers: int
	var work_positions: Array[Vector3]
	var assigned_workers: Array[Unit]
	
	func _init(wp: Node3D, jtype: String, max_w: int, positions: Array[Vector3]):
		workplace = wp
		job_type = jtype
		max_workers = max_w
		work_positions = positions
		assigned_workers = []
	
	func has_vacancy() -> bool:
		return assigned_workers.size() < max_workers
	
	func get_next_work_position() -> Vector3:
		if work_positions.is_empty():
			return workplace.global_position
		var index = assigned_workers.size() % work_positions.size()
		return workplace.global_position + work_positions[index]

func _ready():
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	print("JobManager initialized")

## Register a workplace
func register_workplace(workplace: Node3D, job_type: String, max_workers: int, work_positions: Array[Vector3]) -> String:
	var workplace_id = "%s_%d" % [workplace.name, workplace.get_instance_id()]
	
	var data = WorkplaceData.new(workplace, job_type, max_workers, work_positions)
	workplaces[workplace_id] = data
	
	print("Registered workplace: %s (type: %s, max workers: %d)" % [workplace_id, job_type, max_workers])
	return workplace_id

## Unregister a workplace
func unregister_workplace(workplace_id: String):
	if workplaces.has(workplace_id):
		var data = workplaces[workplace_id]
		# Unassign all workers
		for worker in data.assigned_workers.duplicate():
			unassign_worker(worker)
		workplaces.erase(workplace_id)
		print("Unregistered workplace: %s" % workplace_id)

## Register an available worker (peasant)
func register_available_worker(unit: Unit):
	if unit not in available_workers:
		available_workers.append(unit)
		print("Registered available worker: %s" % unit.name)

## Assign a worker to a workplace
func assign_worker_to_workplace(unit: Unit, workplace_id: String) -> bool:
	if not workplaces.has(workplace_id):
		push_error("Workplace not found: %s" % workplace_id)
		return false
	
	var data = workplaces[workplace_id]
	
	# Check if workplace has vacancy
	if not data.has_vacancy():
		print("Workplace %s is full" % workplace_id)
		return false
	
	# Unassign from previous workplace if any
	if job_assignments.has(unit):
		unassign_worker(unit)
	
	# Assign to new workplace
	data.assigned_workers.append(unit)
	job_assignments[unit] = workplace_id
	available_workers.erase(unit)
	
	# Get work position
	var work_position = data.get_next_work_position()
	
	# Tell unit to go to workplace
	if unit.has_method("set_work_destination"):
		unit.set_work_destination(data.workplace, work_position)
	
	# Update the workplace's assigned_workers array (if it has one)
	if data.workplace.has_method("_on_worker_assigned"):
		data.workplace._on_worker_assigned(unit)
	
	emit_signal("worker_assigned", unit, data.workplace)
	print("Assigned %s to %s at position %s" % [unit.name, workplace_id, work_position])
	return true

## Unassign a worker from their workplace
func unassign_worker(unit: Unit):
	if not job_assignments.has(unit):
		return
	
	var workplace_id = job_assignments[unit]
	var data = workplaces[workplace_id]
	
	data.assigned_workers.erase(unit)
	job_assignments.erase(unit)
	
	if unit not in available_workers:
		available_workers.append(unit)
	
	# Notify workplace
	if data.workplace.has_method("_on_worker_unassigned"):
		data.workplace._on_worker_unassigned(unit)
	
	emit_signal("worker_unassigned", unit, data.workplace)
	print("Unassigned %s from %s" % [unit.name, workplace_id])

## Find a workplace with vacancy for a specific job type
func find_workplace_with_vacancy(job_type: String) -> String:
	for workplace_id in workplaces.keys():
		var data = workplaces[workplace_id]
		if data.job_type == job_type and data.has_vacancy():
			return workplace_id
	return ""

## Auto-assign available workers to workplaces
func auto_assign_workers():
	for worker in available_workers.duplicate():
		# Try to find a workplace that needs workers
		for workplace_id in workplaces.keys():
			if assign_worker_to_workplace(worker, workplace_id):
				break

## Get workplace info
func get_workplace_info(workplace_id: String) -> Dictionary:
	if not workplaces.has(workplace_id):
		return {}
	
	var data = workplaces[workplace_id]
	return {
		"job_type": data.job_type,
		"max_workers": data.max_workers,
		"current_workers": data.assigned_workers.size(),
		"has_vacancy": data.has_vacancy()
	}

## Get all workplaces of a specific type
func get_workplaces_by_type(job_type: String) -> Array[String]:
	var result: Array[String] = []
	for workplace_id in workplaces.keys():
		if workplaces[workplace_id].job_type == job_type:
			result.append(workplace_id)
	return result
