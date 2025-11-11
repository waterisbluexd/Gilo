extends Panel

@onready var tent_button: Button = $House_Select/MarginContainer/GridContainer/Tent_Panel/Tent_Button
@onready var hovels_button: Button = $House_Select/MarginContainer/GridContainer/Hovels_Panel/Hovels_Button

var building_placer: BuildingPlacer


func _ready():
	building_placer = get_tree().get_first_node_in_group("building_placer")
	
	if not building_placer:
		push_error("BuildingPlacer not found! Make sure it's in a group called 'building_placer'")
		return
	
	# Connect buttons
	tent_button.pressed.connect(_on_tent_pressed)
	hovels_button.pressed.connect(_on_hovels_pressed)
	
	print("BuildingUI ready - connected to BuildingPlacer")


func _on_tent_pressed():
	"""Select tent variations (indices 8-10)
	User can now scroll with mouse wheel to cycle through tent types"""
	if building_placer:
		building_placer.select_building_category(8, 10)
		print("✅ Tent category selected (indices 8-10)")
		print("   🖱️ Use MOUSE SCROLL to cycle through tent variations")
		print("   🖱️ LEFT CLICK to place, RIGHT CLICK to cancel")


func _on_hovels_pressed():
	"""Select hovel variations (indices 0-7)
	User can now scroll with mouse wheel to cycle through hovel types"""
	if building_placer:
		building_placer.select_building_category(0, 7)
		print("✅ Hovels category selected (indices 0-7)")
		print("   🖱️ Use MOUSE SCROLL to cycle through hovel variations")
		print("   🖱️ LEFT CLICK to place, RIGHT CLICK to cancel")
