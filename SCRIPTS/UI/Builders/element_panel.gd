extends Panel

@onready var tent_button: Button = $House_Select/MarginContainer/GridContainer/Tent_Panel/Tent_Button
@onready var hovels_button: Button = $House_Select/MarginContainer/GridContainer/Hovels_Panel/Hovels_Button

var building_placer: BuildingPlacer


func _ready():
	building_placer = get_tree().get_first_node_in_group("building_placer")
	
	if not building_placer:
		return
	
	# Connect buttons
	tent_button.pressed.connect(_on_tent_pressed)
	hovels_button.pressed.connect(_on_hovels_pressed)


func _on_tent_pressed():
	if building_placer:
		building_placer.select_building_category(8, 10)


func _on_hovels_pressed():
	if building_placer:
		building_placer.select_building_category(0, 7)
