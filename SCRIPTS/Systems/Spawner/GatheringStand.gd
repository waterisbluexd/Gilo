extends Node3D
class_name GatheringStand

## NPCs currently gathering here
var gathering_npcs: Array = []

func _ready() -> void:
	print("GatheringStand '%s' initialized" % name)

## NPC arrives to gather
func npc_arrived(npc: Unit) -> void:
	if npc not in gathering_npcs:
		gathering_npcs.append(npc)
		print("NPC arrived at %s (total: %d)" % [name, gathering_npcs.size()])

## NPC leaves this stand
func npc_left(npc: Unit) -> void:
	gathering_npcs.erase(npc)
	print("NPC left %s (total: %d)" % [name, gathering_npcs.size()])

## Get count of NPCs here
func get_npc_count() -> int:
	return gathering_npcs.size()
