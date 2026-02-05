extends Resource
class_name WoodcutterJob

@export var job_id: String = "woodcutter"
@export var job_name: String = "Woodcutter"
@export var job_description: String = "Cuts wood at the woodcutter's hut."

@export var movement_speed: float = 5.0

@export var can_work: bool = true
@export var can_fight: bool = false
@export var can_be_assigned: bool = true

@export var idle_animation: String = "chop_wood"

@export var model_scene: PackedScene

@export var chop_rate: float = 1.0  
@export var work_range: float = 2.0  
