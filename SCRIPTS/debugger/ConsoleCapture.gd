# ConsoleCapture.gd
extends Node

var messages: Array[Dictionary] = []
var max_messages: int = 100

enum MessageType {
	PRINT,
	WARNING,
	ERROR
}

signal message_added(message: Dictionary)

func _ready():
	# Note: Godot doesn't provide a way to intercept print() directly
	# You'll need to use console_log() explicitly in your code
	pass

func console_log(text: String, type: MessageType = MessageType.PRINT):
	var timestamp = Time.get_time_string_from_system()
	var message = {
		"text": text,
		"type": type,
		"timestamp": timestamp,
		"color": get_color_for_type(type)
	}
	
	messages.append(message)
	if messages.size() > max_messages:
		messages.pop_front()
	
	# Still output to Godot console
	match type:
		MessageType.PRINT:
			print("[%s] %s" % [timestamp, text])
		MessageType.WARNING:
			push_warning("[%s] %s" % [timestamp, text])
		MessageType.ERROR:
			push_error("[%s] %s" % [timestamp, text])
	
	emit_signal("message_added", message)

func log_warning(text: String):
	console_log(text, MessageType.WARNING)

func log_error(text: String):
	console_log(text, MessageType.ERROR)

func get_all_messages() -> Array[Dictionary]:
	return messages

func clear_messages():
	messages.clear()
	emit_signal("message_added", {"text": "Console cleared", "type": MessageType.PRINT, "timestamp": Time.get_time_string_from_system(), "color": Color.GRAY})

func get_color_for_type(type: MessageType) -> Color:
	match type:
		MessageType.PRINT:
			return Color.WHITE
		MessageType.WARNING:
			return Color.YELLOW
		MessageType.ERROR:
			return Color.RED
	return Color.WHITE

func get_messages_as_text() -> String:
	var output = ""
	for msg in messages:
		output += "[%s] %s\n" % [msg.timestamp, msg.text]
	return output

# Convenience method for quick migration
func p(text: String):
	"""Shorthand for console_log - use ConsoleCapture.p() instead of print()"""
	console_log(str(text))
