extends Node3D
class_name UnitVisuals

var _current_model: Node3D

func set_model(model_scene: PackedScene) -> void:
	if _current_model != null:
		_current_model.queue_free()
		_current_model = null
	
	if model_scene == null:
		push_error("UnitVisuals.set_model() called with null scene!")
		return
	
	_current_model = model_scene.instantiate()
	add_child(_current_model)
	print("UnitVisuals: Loaded model scene: %s" % model_scene.resource_path)
