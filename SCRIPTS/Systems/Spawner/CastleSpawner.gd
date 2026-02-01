extends Node3D
class_name CastleSpawner

## How many NPCs can gather at once
@export var max_gatherers: int = 5
## The NPC scene to spawn
@export var npc_scene: PackedScene
## The job to assign spawned NPCs
@export var gatherer_job: PeasantJob

## Child nodes - stores references
var gathering_stands: Array[Node3D] = []
var active_npcs: Array = []

## Spawning
@export var spawn_interval: float = 2.0  # Spawn an NPC every X seconds
var spawn_timer: float = 0.0

func _ready() -> void:
	# Debug: Show what we are and what's around us
	print("CastleSpawner node: %s (type: %s)" % [name, get_class()])
	print("CastleSpawner parent: %s" % [get_parent().name if get_parent() else "NONE"])
	print("CastleSpawner children: %s" % [get_children().map(func(c): return c.name)])
	
	# Find all gathering stands recursively (they're under Gathering_area/gathering_holder)
	_find_gathering_stands(get_parent())
	
	if gathering_stands.is_empty():
		push_error("CastleSpawner: No gathering_stand nodes found in hierarchy!")
	
	print("CastleSpawner ready. Found %d gathering stands. Max gatherers: %d" % [gathering_stands.size(), max_gatherers])
	spawn_timer = spawn_interval  # Spawn first one immediately

## Recursively find all nodes named gathering_stand_*
func _find_gathering_stands(node: Node) -> void:
	for child in node.get_children():
		if child.name.begins_with("gathering_stand"):
			gathering_stands.append(child as Node3D)
		_find_gathering_stands(child)  # Recurse deeper

func _process(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0 and can_spawn():
		spawn_npc()
		spawn_timer = spawn_interval

## Check if we can spawn more NPCs
func can_spawn() -> bool:
	return active_npcs.size() < max_gatherers

## Spawn a new NPC and send it to a gathering stand
func spawn_npc() -> Unit:
	if not can_spawn():
		push_error("Cannot spawn - at max capacity (%d/%d)" % [active_npcs.size(), max_gatherers])
		return null
	
	if not npc_scene:
		push_error("CastleSpawner has no npc_scene assigned!")
		return null
	
	# Find spawnpoint before instantiating NPC
	var spawnpoint = get_node_or_null("unit_spawnpoint")
	var spawn_pos = Vector3.ZERO
	if spawnpoint:
		spawn_pos = spawnpoint.global_position
		print("DEBUG: unit_spawnpoint found at global position: %s" % spawn_pos)
	else:
		spawn_pos = global_position
		print("DEBUG: unit_spawnpoint NOT found, using spawner position: %s" % spawn_pos)
	
	# Instantiate the NPC
	var npc: Unit = npc_scene.instantiate()
	
	# Add to the castle (same parent as Spawner), which is the Type_Castle_1 root
	get_parent().add_child(npc)
	
	# Set position immediately after adding to tree
	npc.global_position = spawn_pos
	print("DEBUG: NPC global_position set to: %s" % npc.global_position)
	
	# Assign the gathering job
	if gatherer_job:
		npc.job = gatherer_job.duplicate()
	
	# Attach movement script
	var movement = NPCMovement.new()
	npc.add_child(movement)
	
	# Track this NPC
	active_npcs.append(npc)
	
	# Send to nearest gathering stand
	var target_stand = get_nearest_stand()
	if target_stand:
		npc.target_stand = target_stand
		print("✓ Spawned NPC #%d at %s, sending to gathering stand %s" % [active_npcs.size(), npc.global_position, target_stand.name])
	
	return npc

## Get the gathering stand with fewest NPCs
func get_nearest_stand() -> Node3D:
	if gathering_stands.is_empty():
		return null
	
	var best_stand = gathering_stands[0]
	var min_npcs = stand_get_npc_count(best_stand)
	
	for stand in gathering_stands:
		var count = stand_get_npc_count(stand)
		if count < min_npcs:
			best_stand = stand
			min_npcs = count
	
	return best_stand

## Count how many NPCs are at this stand
func stand_get_npc_count(stand: Node3D) -> int:
	var count = 0
	for npc in active_npcs:
		if npc.target_stand == stand:
			count += 1
	return count

## Remove NPC from tracking (when it dies, etc)
func remove_npc(npc: Unit) -> void:
	active_npcs.erase(npc)
