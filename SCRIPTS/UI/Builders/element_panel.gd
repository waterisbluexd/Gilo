extends Panel

@onready var tent_button: Button = $House_Select/MarginContainer/GridContainer/Tent_Panel/Tent_Button
@onready var hovels_button: Button = $House_Select/MarginContainer/GridContainer/Hovels_Panel/Hovels_Button
@onready var type_wall_1_button: Button = $Castle_Select/MarginContainer/GridContainer/Panel/Type_Wall_1_button
@onready var type_wall_2_button: Button = $Castle_Select/MarginContainer/GridContainer/Panel2/Type_Wall_2_button
@onready var type_tower_1_button: Button = $Castle_Select/MarginContainer/GridContainer/Panel3/Type_Tower_1_button

var building_placer: BuildingPlacer

func _ready():
	building_placer = get_tree().get_first_node_in_group("building_placer")
	
	if not building_placer:
		return
	
	# Connect buttons
	tent_button.pressed.connect(_on_tent_pressed)
	hovels_button.pressed.connect(_on_hovels_pressed)
	type_wall_1_button.pressed.connect(_on_type_wall_1_pressed)
	type_wall_2_button.pressed.connect(_on_type_wall_2_button_pressed)
	type_tower_1_button.pressed.connect(_on_type_tower_1_pressed)


func _on_tent_pressed():
	if building_placer:
		building_placer.select_building_category(8, 10)


func _on_hovels_pressed():
	if building_placer:
		building_placer.select_building_category(13, 19)

func _on_type_wall_1_pressed():
	if building_placer:
		building_placer.select_building(11)

func _on_type_wall_2_button_pressed():
	if building_placer:
		building_placer.select_building(12)

func _on_type_tower_1_pressed():
	if building_placer:
		building_placer.select_building(20)
