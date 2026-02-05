extends Node
class_name WorkerAssigner

## Call this to assign the first available worker to a workplace
static func assign_next_worker_to_workplace(workplace: Workplace) -> bool:
	if not JobManager or not JobManager.instance:
		push_error("JobManager not found!")
		return false
	
	if not workplace or workplace.workplace_id.is_empty():
		push_error("Invalid workplace!")
		return false
	
	# Get available workers
	var available = JobManager.instance.available_workers
	if available.is_empty():
		print("⚠ No available workers to assign")
		return false
	
	# Assign first available worker
	var worker = available[0]
	var success = JobManager.instance.assign_worker_to_workplace(worker, workplace.workplace_id)
	
	if success:
		print("✅ Assigned %s to %s" % [worker.name, workplace.workplace_name])
	else:
		print("❌ Failed to assign worker to %s" % workplace.workplace_name)
	
	return success

## Assign multiple workers to a workplace
static func assign_workers_to_workplace(workplace: Workplace, count: int) -> int:
	var assigned_count = 0
	
	for i in range(count):
		if assign_next_worker_to_workplace(workplace):
			assigned_count += 1
		else:
			break
	
	return assigned_count

## Auto-fill all workplaces with available workers
static func auto_fill_all_workplaces() -> void:
	if not JobManager or not JobManager.instance:
		return
	
	JobManager.instance.auto_assign_workers()
	print("✅ Auto-assigned workers to all workplaces")

## Debug: Print workplace status
static func print_workplace_status(workplace: Workplace) -> void:
	if not JobManager or not JobManager.instance:
		return
	
	var info = JobManager.instance.get_workplace_info(workplace.workplace_id)
	if info.is_empty():
		print("❌ Workplace not found in JobManager")
		return
	
	print("=== %s ===" % workplace.workplace_name)
	print("Job Type: %s" % info.job_type)
	print("Workers: %d / %d" % [info.current_workers, info.max_workers])
	print("Has Vacancy: %s" % info.has_vacancy)
	print("Workplace ID: %s" % workplace.workplace_id)

## Debug: Print all available workers
static func print_available_workers() -> void:
	if not JobManager or not JobManager.instance:
		return
	
	var workers = JobManager.instance.available_workers
	print("=== Available Workers ===")
	print("Count: %d" % workers.size())
	for worker in workers:
		print("  - %s" % worker.name)
