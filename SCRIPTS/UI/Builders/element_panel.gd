extends HBoxContainer

# Castle buttons
@onready var wall_1_button: Button = $LeftPage/MarginContainer/Castle_Item_Selector/GridContainer/Wall_1/Button
@onready var wall_2_button: Button = $LeftPage/MarginContainer/Castle_Item_Selector/GridContainer/Wall_2/Button
@onready var tower_1_button: Button = $LeftPage/MarginContainer/Castle_Item_Selector/GridContainer/Tower_1/Button
@onready var tower_2_button: Button = $LeftPage/MarginContainer/Castle_Item_Selector/GridContainer/Tower_2/Button
@onready var tower_3_button: Button = $LeftPage/MarginContainer/Castle_Item_Selector/GridContainer/Tower_3/Button

# Crafts buttons
@onready var stock_pile_button: Button = $LeftPage/MarginContainer/Crafts_Item_Selector/GridContainer/StockPile/Button
@onready var wood_cutter_button: Button = $LeftPage/MarginContainer/Crafts_Item_Selector/GridContainer/WoodCutter/Button
@onready var stone_cutter_button: Button = $LeftPage/MarginContainer/Crafts_Item_Selector/GridContainer/StoneCutter/Button
@onready var bulk_button: Button = $LeftPage/MarginContainer/Crafts_Item_Selector/GridContainer/Bulk/Button
@onready var iron_mine_button: Button = $LeftPage/MarginContainer/Crafts_Item_Selector/GridContainer/IronMine/Button

# Houses buttons
@onready var tent_button: Button = $LeftPage/MarginContainer/Houses_Item_Selector/GridContainer/Tent/Button
@onready var houses_button: Button = $LeftPage/MarginContainer/Houses_Item_Selector/GridContainer/Houses/Button
@onready var well_button: Button = $LeftPage/MarginContainer/Houses_Item_Selector/GridContainer/well/Button

var building_placer: BuildingPlacer

func _ready():
	building_placer = get_tree().get_first_node_in_group("building_placer")
	
	if not building_placer:
		return
	
	# Connect Castle buttons
	if wall_1_button:
		wall_1_button.pressed.connect(_on_wall_1_pressed)
	else:
		print("wall_1_button value not set")
	
	if wall_2_button:
		wall_2_button.pressed.connect(_on_wall_2_pressed)
	else:
		print("wall_2_button value not set")
	
	if tower_1_button:
		tower_1_button.pressed.connect(_on_tower_1_pressed)
	else:
		print("tower_1_button value not set")
	
	if tower_2_button:
		tower_2_button.pressed.connect(_on_tower_2_pressed)
	else:
		print("tower_2_button value not set")
	
	if tower_3_button:
		tower_3_button.pressed.connect(_on_tower_3_pressed)
	else:
		print("tower_3_button value not set")
	
	# Connect Crafts buttons
	if stock_pile_button:
		stock_pile_button.pressed.connect(_on_stock_pile_pressed)
	else:
		print("stock_pile_button value not set")
	
	if wood_cutter_button:
		wood_cutter_button.pressed.connect(_on_wood_cutter_pressed)
	else:
		print("wood_cutter_button value not set")
	
	if stone_cutter_button:
		stone_cutter_button.pressed.connect(_on_stone_cutter_pressed)
	else:
		print("stone_cutter_button value not set")
	
	if bulk_button:
		bulk_button.pressed.connect(_on_bulk_pressed)
	else:
		print("bulk_button value not set")
	
	if iron_mine_button:
		iron_mine_button.pressed.connect(_on_iron_mine_pressed)
	else:
		print("iron_mine_button value not set")
	
	# Connect Houses buttons
	if tent_button:
		tent_button.pressed.connect(_on_tent_pressed)
	else:
		print("tent_button value not set")
	
	if houses_button:
		houses_button.pressed.connect(_on_houses_pressed)
	else:
		print("houses_button value not set")
	
	if well_button:
		well_button.pressed.connect(_on_well_pressed)
	else:
		print("well_button value not set")

# Castle callbacks
func _on_wall_1_pressed():
	if building_placer:
		# NEW: Use array syntax [10, 11] instead of (10, 11)
		building_placer.select_building_category([10, 11])

func _on_wall_2_pressed():
	if building_placer:
		building_placer.select_building_category([23, 24])

func _on_tower_1_pressed():
	if building_placer:
		building_placer.select_building(22)

func _on_tower_2_pressed():
	if building_placer:
		building_placer.select_building(19)

func _on_tower_3_pressed():
	if building_placer:
		building_placer.select_building(20)

# Crafts callbacks
func _on_stock_pile_pressed():
	print("stock_pile value not set")

func _on_wood_cutter_pressed():
	print("wood_cutter value not set")

func _on_stone_cutter_pressed():
	print("stone_cutter value not set")

func _on_bulk_pressed():
	print("bulk value not set")

func _on_iron_mine_pressed():
	print("iron_mine value not set")

# Houses callbacks
func _on_tent_pressed():
	if building_placer:
		# NEW: Use array syntax [7, 8, 9] instead of (7, 9)
		building_placer.select_building_category([7, 8, 9])

func _on_houses_pressed():
	if building_placer:
		# NEW: Use array syntax [12, 13, 14, 15, 16, 17] instead of (12, 17)
		building_placer.select_building_category([12, 13, 14, 15, 16, 17])

func _on_well_pressed():
	print("well value not set")
