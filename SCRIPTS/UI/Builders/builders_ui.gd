extends Control

# Openers
@onready var castle_panel_button: Button = $HBoxContainer/Castle_Panel/Castle_Panel_Button
@onready var crafts_panel_button: Button = $HBoxContainer/Crafts_Panel/Crafts_Panel_Button
@onready var house_panel_button: Button = $HBoxContainer/House_Panel/House_Panel_Button

# Selectors
@onready var castle_select: Control = $Element_Panel/Castle_Select
@onready var house_select: Control = $Element_Panel/House_Select
@onready var crafts_select: Control = $Element_Panel/Crafts_Select  # Added if you have this

# Array to store all selectors
var selectors: Array[Control] = []

func _ready() -> void:
	selectors = [castle_select, house_select, crafts_select]
	
	hide_all_selectors()

	castle_select.visible = true

func hide_all_selectors() -> void:
	for selector in selectors:
		if selector:  # Check if selector exists
			selector.visible = false

func show_selector(selector_to_show: Control) -> void:
	hide_all_selectors()
	selector_to_show.visible = true

func _on_castle_panel_button_pressed() -> void:
	show_selector(castle_select)

func _on_house_panel_button_pressed() -> void:
	show_selector(house_select)

func _on_crafts_panel_button_pressed() -> void:
	show_selector(crafts_select)
