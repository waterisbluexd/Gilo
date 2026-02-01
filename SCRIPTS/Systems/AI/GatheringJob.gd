extends Resource
class_name GatheringJob

@export var job_id: String = "gatherer"
@export var job_name: String = "Gatherer"
@export var job_description: String = "Gathers resources from gathering stands."

@export var movement_speed: float = 5.0

@export var can_work: bool = true
@export var can_fight: bool = false
@export var can_be_assigned: bool = true

@export var idle_animation: String = "gather"

@export var model_scene: PackedScene

# Gathering specific
@export var gather_rate: float = 1.0  ## Resources per second
@export var gather_range: float = 2.0  ## How close to stand
