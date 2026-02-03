extends Node3D
class_name CastleSpawner

## Maximum NPCs that can gather simultaneously
@export var max_gatherers: int = 50

## The NPC scene to spawn
@export var npc_scene: PackedScene

## The job to assign to spawned NPCs
@export var gatherer_job: PeasantJob

## Spawning settings
@export var spawn_interval: float = 0.5
@export var auto_spawn: bool = true

## Performance settings
@export var enable_npc_pooling: bool = true
@export var pool_size: int = 10
@export var path_update_interval: float = 3.0

## Internal references
var gathering_stands: Array[Node3D] = []
var active_npcs: Array[Unit] = []
var inactive_pool: Array[Unit] = []
var spawn_timer: float = 0.0
var spawnpoint: Node3D

## Track assignments
var stand_assignments: Dictionary = {}

## Statistics
var total_spawned: int = 0
var from_pool: int = 0

func _ready() -> void:
	print("=== CastleSpawner Initializing ===")
	
	# Find spawn point
	spawnpoint = get_node_or_null("unit_spawnpoint")
	if not spawnpoint:
		push_warning("No unit_spawnpoint found - will spawn at spawner position")
	else:
		print("✓ Spawnpoint found at: %s" % spawnpoint.global_position)
	
	# Find gathering stands
	var castle_root = get_parent()
	print("Searching for gathering stands in: %s" % castle_root.name)
	_find_gathering_stands(castle_root)
	
	if gathering_stands.is_empty():
		push_error("CastleSpawner: No gathering stands found!")
		return
	
	# Initialize stand tracking
	for stand in gathering_stands:
		stand_assignments[stand] = []
	
	print("✓ Found %d gathering stands" % gathering_stands.size())
	print("✓ Max gatherers: %d" % max_gatherers)
	
	# Pre-populate pool
	if enable_npc_pooling:
		call_deferred("_populate_pool")
	
	if auto_spawn:
		spawn_timer = spawn_interval

func _populate_pool() -> void:
	if not npc_scene:
		return
	
	print("Pre-populating NPC pool with %d units..." % pool_size)
	for i in range(pool_size):
		var npc = await _create_npc_instance()
		if npc:
			npc.visible = false
			npc.process_mode = Node.PROCESS_MODE_DISABLED
			inactive_pool.append(npc)
	print("✓ Pool ready with %d NPCs" % inactive_pool.size())

func _process(delta: float) -> void:
	if not auto_spawn:
		return
	
	spawn_timer -= delta
	if spawn_timer <= 0 and can_spawn():
		spawn_npc_deferred()
		spawn_timer = spawn_interval

func spawn_npc_deferred() -> void:
	var npc = await spawn_npc()

func _find_gathering_stands(node: Node) -> void:
	if node == null:
		return
	
	for child in node.get_children():
		if child.name.begins_with("gathering_stand") or child.name.begins_with("GatheringStand"):
			if child is Node3D:
				gathering_stands.append(child as Node3D)
				print("  → Found stand: %s at %s" % [child.name, child.global_position])
		_find_gathering_stands(child)

func can_spawn() -> bool:
	active_npcs = active_npcs.filter(func(npc): return is_instance_valid(npc))
	return active_npcs.size() < max_gatherers

func spawn_npc() -> Unit:
	if not can_spawn():
		return null
	
	var npc: Unit = null
	
	# Try to get from pool first
	if enable_npc_pooling and not inactive_pool.is_empty():
		npc = inactive_pool.pop_back()
		npc.visible = true
		npc.process_mode = Node.PROCESS_MODE_INHERIT
		from_pool += 1
		print("→ Using NPC from pool: %s" % npc.name)
	else:
		# Create new instance
		npc = await _create_npc_instance()
		if not npc:
			return null
		print("→ Created new NPC: %s" % npc.name)
	
	# Position the NPC
	var spawn_pos = spawnpoint.global_position if spawnpoint else global_position
	npc.global_position = spawn_pos
	npc.spawner = self
	
	print("  NPC positioned at: %s" % npc.global_position)
	
	# Assign job
	if gatherer_job:
		if not npc.job:
			npc.job = gatherer_job.duplicate()
		npc.apply_job(npc.job)
		print("  Job assigned: %s (can_work: %s, can_fight: %s)" % [npc.job.job_name, npc.job.can_work, npc.job.can_fight])
	
	# Reset movement component
	var movement = npc.get_node_or_null("NPCMovement")
	if movement:
		print("  Movement component found")
		
		if movement.has_method("stop"):
			movement.stop()
		if movement.has_method("set_path_update_interval"):
			movement.set_path_update_interval(path_update_interval)
		
		# Reset movement state directly
		movement.has_arrived = false
		movement.is_moving = false
		movement.waiting_for_path = false
		movement.active = true
	else:
		print("  ✗ NO MOVEMENT COMPONENT!")
	
	# Check if unit should gather
	var should_gather = false
	if npc.has_method("should_gather"):
		should_gather = npc.should_gather()
		print("  should_gather() returned: %s" % should_gather)
	else:
		print("  ✗ NPC has no should_gather() method!")
	
	# Only assign gathering stand if unit should gather (peasants)
	if should_gather:
		var target_stand = get_best_stand()
		if target_stand:
			npc.target_stand = target_stand
			assign_npc_to_stand(npc, target_stand)
			
			print("  ✓ Assigned to gathering stand: %s at %s" % [target_stand.name, target_stand.global_position])
			
			# Trigger path request
			if movement and movement.has_method("request_path_to_target"):
				print("  ✓ Requesting path...")
				movement.request_path_to_target()
			else:
				print("  ✗ Can't request path - movement is null or missing method")
		else:
			print("  ✗ No available gathering stand!")
	else:
		# Non-peasant unit - disable movement
		print("  → Non-peasant unit - staying at spawn")
		if movement:
			movement.active = false
	
	active_npcs.append(npc)
	total_spawned += 1
	
	print("✓ Spawned NPC #%d (total: %d)\n" % [active_npcs.size(), total_spawned])
	
	return npc

func _create_npc_instance() -> Unit:
	if not npc_scene:
		push_error("No npc_scene assigned!")
		return null
	
	var npc: Unit = npc_scene.instantiate()
	if not npc:
		return null
	
	get_parent().call_deferred("add_child", npc)
	await npc.ready
	
	return npc

func get_best_stand() -> Node3D:
	if gathering_stands.is_empty():
		return null
	
	var best_stand: Node3D = null
	var min_count: int = 999999
	
	for stand in gathering_stands:
		var count = get_stand_npc_count(stand)
		if count < min_count:
			best_stand = stand
			min_count = count
	
	return best_stand

func get_stand_npc_count(stand: Node3D) -> int:
	if not stand_assignments.has(stand):
		return 0
	
	stand_assignments[stand] = stand_assignments[stand].filter(
		func(npc): return is_instance_valid(npc)
	)
	
	return stand_assignments[stand].size()

func assign_npc_to_stand(npc: Unit, stand: Node3D) -> void:
	if not stand_assignments.has(stand):
		stand_assignments[stand] = []
	stand_assignments[stand].append(npc)

func remove_npc(npc: Unit) -> void:
	active_npcs.erase(npc)
	
	# Remove from stand assignments
	for stand in stand_assignments.keys():
		stand_assignments[stand].erase(npc)
	
	# Return to pool if enabled
	if enable_npc_pooling and inactive_pool.size() < pool_size:
		npc.visible = false
		npc.process_mode = Node.PROCESS_MODE_DISABLED
		
		var spawn_pos = spawnpoint.global_position if spawnpoint else global_position
		npc.global_position = spawn_pos
		
		inactive_pool.append(npc)
	else:
		npc.queue_free()

func force_spawn() -> void:
	var old_auto = auto_spawn
	auto_spawn = false
	await spawn_npc()
	auto_spawn = old_auto

func despawn_all() -> void:
	for npc in active_npcs.duplicate():
		remove_npc(npc)
