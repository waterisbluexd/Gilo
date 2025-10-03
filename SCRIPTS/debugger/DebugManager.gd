extends Node

# References to things you want to debug
var camera: Camera3D
var camera_pivot: Node3D
# Add more as needed

# Registration functions
func register_camera(cam: Camera3D):
	camera = cam
	ConsoleCapture.console_log("Camera registered to DebugManager")

func register_player(cp: Node3D):
	camera_pivot = cp
	ConsoleCapture.console_log("Player registered to DebugManager")
