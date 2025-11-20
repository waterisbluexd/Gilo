extends Button

var building_placer: BuildingPlacer

func _ready():
	pressed.connect(_on_pressed)
	call_deferred("_find_building_placer")

func _find_building_placer():
	var placers = get_tree().get_nodes_in_group("building_placer")
	if placers.size() > 0:
		building_placer = placers[0]

func _on_pressed():
	if building_placer:
		building_placer.enable_destroy_mode()
