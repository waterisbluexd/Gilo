extends Node3D
class_name Workplace

## Workplace configuration
@export var workplace_name: String = "Workplace"
@export var job_type: String = "worker"  # "woodcutter", "stonecutter", etc.
@export var max_workers: int = 3
@export var work_positions: Array[Vector3] = [
	Vector3(2, 0, 0),
	Vector3(-2, 0, 0),
	Vector3(0, 0, 2)
]

## Internal tracking
var workplace_id: String = ""
var assigned_workers: Array[Unit] = []
var is_registered: bool = false

## Auto-assignment settings
@export var auto_assign_workers: bool = true
@export var auto_assign_delay: float = 0.5  # Delay before auto-assigning

func _ready() -> void:
	# Prevent double registration
	if is_registered:
		return
	
	# Wait for JobManager to be ready
	await get_tree().process_frame
	
	# Register with JobManager
	if JobManager and JobManager.instance:
		workplace_id = JobManager.instance.register_workplace(
			self,
			job_type,
			max_workers,
			work_positions
		)
		is_registered = true
		print("✓ Workplace '%s' registered (ID: %s)" % [workplace_name, workplace_id])
		
		# Auto-assign workers after a short delay (Stronghold style!)
		if auto_assign_workers:
			await get_tree().create_timer(auto_assign_delay).timeout
			_auto_assign_available_workers()
	else:
		push_error("JobManager not found! Make sure it's an AutoLoad singleton named 'JobManager'.")

## Automatically assign available workers to fill this workplace
func _auto_assign_available_workers() -> void:
	if not JobManager or not JobManager.instance:
		return
	
	var workers_needed = max_workers - assigned_workers.size()
	if workers_needed <= 0:
		print("✓ Workplace '%s' is already full" % workplace_name)
		return
	
	print("🏗️ Auto-assigning workers to '%s' (need %d workers)" % [workplace_name, workers_needed])
	
	var assigned_count = 0
	for i in range(workers_needed):
		var available = JobManager.instance.available_workers
		if available.is_empty():
			print("⚠️ No more available workers (assigned %d/%d)" % [assigned_count, workers_needed])
			break
		
		var worker = available[0]
		var success = JobManager.instance.assign_worker_to_workplace(worker, workplace_id)
		
		if success:
			assigned_count += 1
			print("  ✓ Auto-assigned %s to %s (%d/%d)" % [worker.name, workplace_name, assigned_count, max_workers])
		else:
			break
	
	if assigned_count > 0:
		print("✅ Successfully auto-assigned %d workers to '%s'" % [assigned_count, workplace_name])

func _exit_tree() -> void:
	# Unregister when destroyed
	if JobManager.instance and not workplace_id.is_empty():
		JobManager.instance.unregister_workplace(workplace_id)

## Get number of assigned workers
func get_worker_count() -> int:
	return assigned_workers.size()

## Check if workplace has vacancy
func has_vacancy() -> bool:
	return assigned_workers.size() < max_workers

## Get next available work position
func get_next_work_position() -> Vector3:
	if work_positions.is_empty():
		return global_position
	
	var index = assigned_workers.size() % work_positions.size()
	return global_position + work_positions[index]

## Debug: Show work positions in editor
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_work_positions()

func _draw_work_positions() -> void:
	# This would need DebugDraw or similar to visualize
	pass

## Called by JobManager when a worker is assigned
func _on_worker_assigned(worker: Unit) -> void:
	if worker not in assigned_workers:
		assigned_workers.append(worker)
	print("  📋 Workplace '%s' now has %d/%d workers" % [workplace_name, assigned_workers.size(), max_workers])

## Called by JobManager when a worker is unassigned
func _on_worker_unassigned(worker: Unit) -> void:
	assigned_workers.erase(worker)
	print("  📋 Workplace '%s' now has %d/%d workers" % [workplace_name, assigned_workers.size(), max_workers])
