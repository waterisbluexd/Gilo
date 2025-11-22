extends MeshInstance3D

@export var appear_hour: float = 18.0
@export var disappear_hour: float = 6.0

func _ready() -> void:
	TimeManager.time_changed.connect(_on_time_changed)
	_update_visibility()

func _on_time_changed(current_hour: float) -> void:
	_update_visibility()

func _update_visibility() -> void:
	visible = TimeManager.is_between_hours(appear_hour, disappear_hour)
