#console_panel.gd 
extends Panel

@onready var console_box: RichTextLabel = $HBoxContainer/Panel/MarginContainer/VBoxContainer/Console_box
@onready var console_command_box: LineEdit = $HBoxContainer/Panel/MarginContainer/VBoxContainer/HBoxContainer/Consle_command_box

# Settings
var auto_scroll: bool = true
var max_lines: int = 500


func _ready():
	# Setup console output
	console_box.bbcode_enabled = true
	console_box.scroll_following = true
	
	# Connect to ConsoleCapture
	ConsoleCapture.message_added.connect(_on_message_added)
	
	# Load existing messages
	load_existing_messages()
	
	# Connect command input
	console_command_box.text_submitted.connect(_on_command_submitted)
	
	# Welcome message
	ConsoleCapture.console_log("=== Console Ready ===")


func load_existing_messages():
	"""Load any messages that were logged before this UI was ready"""
	console_box.clear()
	for msg in ConsoleCapture.get_all_messages():
		add_message_to_display(msg)


func _on_message_added(message: Dictionary):
	add_message_to_display(message)


func add_message_to_display(message: Dictionary):
	var color = message.color as Color
	var timestamp = message.timestamp
	var text = message.text
	
	# Format with BBCode for colors
	var formatted = "[color=#%s][%s] %s[/color]\n" % [
		color.to_html(false),
		timestamp,
		text
	]
	
	console_box.append_text(formatted)
	
	# Limit line count to prevent memory issues
	if console_box.get_line_count() > max_lines:
		# Remove oldest lines (this is a simple approach)
		var text_content = console_box.get_parsed_text()
		var lines = text_content.split("\n")
		lines = lines.slice(lines.size() - max_lines, lines.size())
		console_box.clear()
		console_box.append_text("\n".join(lines))
	
	# Auto scroll to bottom
	if auto_scroll:
		await get_tree().process_frame
		console_box.scroll_to_line(console_box.get_line_count())


func _on_command_submitted(command: String):
	if command.strip_edges().is_empty():
		return
	
	# Echo the command in the console
	ConsoleCapture.console_log("> " + command)
	
	# Process the command
	process_command(command)
	
	# Clear the input box
	console_command_box.clear()
	
	# Keep focus on input for next command
	console_command_box.grab_focus()


func process_command(command: String):
	var parts = command.split(" ", false)
	if parts.is_empty():
		return
	
	var cmd = parts[0].to_lower()
	var args = parts.slice(1, parts.size())
	
	match cmd:
		"clear":
			clear_console()
		
		"help":
			show_help()
		
		"camera":
			handle_camera_command(args)
		
		"test":
			ConsoleCapture.console_log("Test message!")
			ConsoleCapture.log_warning("Test warning!")
			ConsoleCapture.log_error("Test error!")
		
		"zoom":
			if args.size() > 0:
				var zoom_value = float(args[0])
				if DebugManager.camera:
					DebugManager.camera.set_zoom_level_debug(zoom_value)
					ConsoleCapture.console_log("Zoom set to: " + str(zoom_value))
				else:
					ConsoleCapture.log_error("Camera not found!")
			else:
				ConsoleCapture.log_warning("Usage: zoom <value>")
		
		"tp", "teleport":
			if args.size() >= 3:
				var x = float(args[0])
				var y = float(args[1])
				var z = float(args[2])
				if DebugManager.camera:
					DebugManager.camera.teleport_to(Vector3(x, y, z))
					ConsoleCapture.console_log("Teleported camera to: %s" % Vector3(x, y, z))
				else:
					ConsoleCapture.log_error("Camera not found!")
			else:
				ConsoleCapture.log_warning("Usage: tp <x> <y> <z>")
		
		_:
			ConsoleCapture.log_warning("Unknown command: '%s'. Type 'help' for available commands." % cmd)


func handle_camera_command(args: Array):
	"""Handle camera-specific commands"""
	if args.is_empty():
		ConsoleCapture.log_warning("Usage: camera <info|reset>")
		return
	
	var subcmd = args[0].to_lower()
	
	match subcmd:
		"info":
			if DebugManager.camera:
				var info = DebugManager.camera.get_debug_info()
				ConsoleCapture.console_log("=== Camera Info ===")
				for key in info.keys():
					ConsoleCapture.console_log("  %s: %s" % [key, str(info[key])])
			else:
				ConsoleCapture.log_error("Camera not found!")
		
		"reset":
			if DebugManager.camera:
				DebugManager.camera.reset_camera_position()
				ConsoleCapture.console_log("Camera position reset")
			else:
				ConsoleCapture.log_error("Camera not found!")
		
		_:
			ConsoleCapture.log_warning("Unknown camera command: '%s'" % subcmd)


func clear_console():
	"""Clear the console output"""
	console_box.clear()
	ConsoleCapture.console_log("Console cleared")


func show_help():
	"""Show available commands"""
	ConsoleCapture.console_log("=== Available Commands ===")
	ConsoleCapture.console_log("⯈  help - Show this help message")
	ConsoleCapture.console_log("⯈  clear - Clear console output")
	ConsoleCapture.console_log("⯈  test - Show test messages")
	ConsoleCapture.console_log("⯈  zoom <value> - Set camera zoom level")
	ConsoleCapture.console_log("⯈  tp <x> <y> <z> - Teleport camera to position")
	ConsoleCapture.console_log("⯈  camera info - Show camera debug info")
	ConsoleCapture.console_log("⯈  camera reset - Reset camera position")
