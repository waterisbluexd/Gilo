extends Camera3D

@export var snap := true

# Define zoom limits and zoom speed
@export var min_size: float = 40.97
@export var max_size: float = 100
var zoom_speed: float = 0.4

# Use the camera's current size as the initial zoom level
var zoom_level: float = self.size

func _ready():
	# Update zoom_level with the current size once the node is added to the scene
	zoom_level = self.size

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level += zoom_speed

		# Clamp zoom level within defined limits
		zoom_level = clamp(zoom_level, min_size, max_size)

		# Apply the zoom to the camera
		self.size = zoom_level
