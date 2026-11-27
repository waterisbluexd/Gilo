extends Panel

@onready var margin_container: MarginContainer = $MarginContainer
@onready var rich_text_label: RichTextLabel = $MarginContainer/RichTextLabel

const UPDATE_INTERVAL := 0.25

var update_timer := 0.0

func _ready() -> void:
	rich_text_label.bbcode_enabled = true
	_update_stats()

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0.0
		_update_stats()


func _update_stats() -> void:
	var fps := Engine.get_frames_per_second()
	var frame_time := 1000.0 / maxf(float(fps), 1.0)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var video_memory := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var static_memory := Performance.get_monitor(Performance.MEMORY_STATIC)

	rich_text_label.text = "[b]PERFORMANCE[/b]\n" \
		+ "FPS             %d  |  Frame time      %.2f ms\n" % [fps, frame_time] \
		+ "Primitives      %s\n" % _format_count(primitives) \
		+ "Objects         %s  |  Nodes           %s\n" % [
			_format_count(Performance.get_monitor(Performance.OBJECT_COUNT)),
			_format_count(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		] \
		+ "Resources       %s\n" % _format_count(
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
		) \
		+ "Static memory   %s  |  Video memory    %s" % [
			_format_bytes(static_memory),
			_format_bytes(video_memory),
		]


func _format_count(value: float) -> String:
	return "%.0f" % value


func _format_bytes(value: float) -> String:
	const KILOBYTE := 1024.0
	const MEGABYTE := KILOBYTE * 1024.0
	if value >= MEGABYTE:
		return "%.1f MB" % (value / MEGABYTE)
	return "%.0f KB" % (value / KILOBYTE)
