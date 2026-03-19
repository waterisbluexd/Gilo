extends Node3D
class_name Workplace

## Workplace configuration
@export var workplace_name: String = "Workplace"
@export var job_type: String = "worker"  # "woodcutter", "stonecutter", etc.
@export var max_workers: int = 3

## Work positions - USER CAN DRAG Marker3D NODES HERE IN INSPECTOR!
## Drag and drop Marker3D nodes from the Scene tree into this array
@export var work_position_markers: Array[Marker3D] = []

## Or use array of Vector3 positions (manual entry)
@export var work_positions: Array[Vector3] = []

## Auto-populate from markers on _ready (keeps inspector in sync)
@export var auto_detect_markers: bool = true
@export var marker_name_prefixes: Array[String] = ["WorkPos", "WorkPosition", "Work"]

## Internal tracking
var workplace_id: String = ""
var assigned_workers: Array[Unit] = []
var is_registered: bool = false

## Auto-assignment settings
@export var auto_assign_workers: bool = true
@export var auto_assign_delay: float = 0.5  # Delay before auto-assignment

func _ready() -> void:
	# Prevent double registration
	if is_registered:
		return
	
	# Use work_positions if manually set via inspector
	if work_positions.is_empty() and not work_position_markers.is_empty():
		# Convert Marker3D references to Vector3 positions
		for marker in work_position_markers:
			if is_instance_valid(marker):
				work_positions.append(marker.position)
				print("  → Using inspector marker: %s at %s" % [marker.name, marker.position])
	elif auto_detect_markers:
		# Auto-detect from scene
		_detect_work_positions_from_markers()
	
	# If still empty, use defaults
	if work_positions.is_empty():
		work_positions = [
			Vector3(2.5, 0, 0),
			Vector3(-2.5, 0, 0),
			Vector3(0, 0, 2.5),
			Vector3(0, 0, -2.5)
		]
		print("⚠ Workplace '%s': Using default work positions" % workplace_name)
	else:
		print("✓ Workplace '%s': Using %d work positions" % [workplace_name, work_positions.size()])
	
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

## Detect work positions from Marker3D nodes in this building's scene
func _detect_work_positions_from_markers() -> void:
	var detected_positions: Array[Vector3] = []
	
	# Look for Marker3D children with names starting with any of the prefixes
	for child in get_children():
		if child is Marker3D:
			var marker_name = child.name
			# Check if marker name starts with any of the prefixes
			for prefix in marker_name_prefixes:
				if marker_name.begins_with(prefix):
					# Store the local position offset (relative to building)
					detected_positions.append(child.position)
					print("  → Found work marker: %s at local position %s" % [marker_name, child.position])
					break  # Only match one prefix
			
			# Also check for markers in subfolders/groups
			_for_find_markers(child, detected_positions)
	
	if not detected_positions.is_empty():
		work_positions = detected_positions

func _for_find_markers(node: Node, positions: Array[Vector3]) -> void:
	for child in node.get_children():
		if child is Marker3D:
			var marker_name = child.name
			for prefix in marker_name_prefixes:
				if marker_name.begins_with(prefix):
					# Get global position and convert to local
					var local_pos = to_local(child.global_position)
					positions.append(local_pos)
					print("  → Found nested work marker: %s at local position %s" % [marker_name, local_pos])
					break
			
			# Recurse
			_for_find_markers(child, positions)

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
