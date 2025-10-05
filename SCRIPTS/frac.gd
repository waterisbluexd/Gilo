extends Node3D

@onready var window: Window = get_window()
@onready var base_size: Vector2i = window.content_scale_size

func ready() -> void: 
	window.size_changed.connect(window_size_changed) 

func window_size_changed(): 
	var scale: Vector2i = window.size/base_size
	window.content_scale_size = window.size / (scale.y if scale.y <= scale.x else scale.x)
