extends Resource
class_name BuildingData

@export var name: String = "Building"
@export var size: Vector2 = Vector2(4, 4)
@export var color: Color = Color.WHITE
@export var prefab: PackedScene  # Optional: your actual building scene
@export var cost: int = 100
@export var category: String = "Basic"
