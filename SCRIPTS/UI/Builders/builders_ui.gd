extends Control
#######################
# Openers
@onready var castle_clip_button: Button = $Control/Clips/Castle/Castle_Clip_button
@onready var crafts_clip_button: Button = $Control/Clips/Crafts/Crafts_Clip_Button
@onready var armors_clip_button: Button = $Control/Clips/Armors/Armors_Clip_Button
@onready var houses_clip_button: Button = $Control/Clips/Houses/Houses_Clip_Button
@onready var farm_clip_button: Button = $Control/Clips/Farm/Farm_Clip_Button
@onready var bakery_clip_button: Button = $Control/Clips/Bakery/Bakery_Clip_Button
# Selectors
@onready var castle_item_selector: Control = $Control/Book/LeftPage/MarginContainer/Castle_Item_Selector
@onready var crafts_item_selector: Control = $Control/Book/LeftPage/MarginContainer/Crafts_Item_Selector
@onready var armors_item_selector: Control = $Control/Book/LeftPage/MarginContainer/Armors_Item_Selector
@onready var houses_item_selector: Control = $Control/Book/LeftPage/MarginContainer/Houses_Item_Selector
@onready var farm_item_selector: Control = $Control/Book/LeftPage/MarginContainer/Farm_Item_Selector
@onready var bakery_item_selector: Control = $Control/Book/LeftPage/MarginContainer/Bakery_Item_Selector
########################
var selectors: Array[Control] = []

func _ready() -> void:
	selectors = [castle_item_selector, crafts_item_selector, armors_item_selector, houses_item_selector, farm_item_selector, bakery_item_selector]
	
	# Connect button signals
	castle_clip_button.pressed.connect(_on_castle_button_pressed)
	crafts_clip_button.pressed.connect(_on_crafts_button_pressed)
	armors_clip_button.pressed.connect(_on_armors_button_pressed)
	houses_clip_button.pressed.connect(_on_houses_button_pressed)
	farm_clip_button.pressed.connect(_on_farm_button_pressed)
	bakery_clip_button.pressed.connect(_on_bakery_button_pressed)
	
	# Show only castle selector on start
	show_selector(castle_item_selector)

func show_selector(selector_to_show: Control) -> void:
	for selector in selectors:
		selector.visible = (selector == selector_to_show)

func _on_castle_button_pressed() -> void:
	show_selector(castle_item_selector)

func _on_crafts_button_pressed() -> void:
	show_selector(crafts_item_selector)

func _on_armors_button_pressed() -> void:
	show_selector(armors_item_selector)

func _on_houses_button_pressed() -> void:
	show_selector(houses_item_selector)

func _on_farm_button_pressed() -> void:
	show_selector(farm_item_selector)

func _on_bakery_button_pressed() -> void:
	show_selector(bakery_item_selector)
