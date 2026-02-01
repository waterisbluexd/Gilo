extends Resource
class_name PeasantJob

@export var job_id: String = "peasant"
@export var job_name: String = "Peasant"
@export var job_description: String = "A humble peasant who waits near the castle and can be assigned to work or training."

@export var movement_speed: float = 5.0

@export var can_work: bool = false
@export var can_fight: bool = false
@export var can_be_assigned: bool = true

@export var idle_animation: String = "idle"

@export var model_scene: PackedScene
