@tool
extends Control

# --- SCENE SETUP ---
# Drag and drop your RealtimeGraph node here in the inspector.
@export var graph: Node

## --- CONFIGURATION ---
@export_group("What to Monitor")
@export var show_fps: bool = true
@export var show_frame_time: bool = true
@export var show_physics_fps: bool = true
@export var show_memory: bool = true
@export var show_video_memory: bool = true

@export_group("Appearance")
@export var fps_color: Color = Color("66a1ff") # Light Blue
@export var frame_time_color: Color = Color("55d47e") # Green
@export var physics_fps_color: Color = Color("ffeb66") # Yellow
@export var memory_color: Color = Color("ff66b2") # Pink
@export var video_memory_color: Color = Color("ff8c66") # Orange-Red


func _ready():
	if not is_instance_valid(graph):
		push_error("Graph node is not assigned in the MemoryMonitor script.")
		return
	
	# Add only the datasets you want to monitor
	if show_fps:
		graph.add_dataset("FPS", fps_color)
	if show_frame_time:
		graph.add_dataset("Frame Time", frame_time_color)
	if show_physics_fps:
		graph.add_dataset("Physics FPS", physics_fps_color)
	if show_memory:
		graph.add_dataset("Allocated Memory", memory_color, true)
	if show_video_memory:
		graph.add_dataset("Video Memory", video_memory_color)


func _process(delta):
	if not is_instance_valid(graph):
		return
	
	var bytes_to_mb = 1024.0 * 1024.0
	
	# FPS
	if show_fps:
		var fps = Performance.get_monitor(Performance.TIME_FPS)
		graph.add_point("FPS", fps)
	
	# Frame Time (in milliseconds)
	if show_frame_time:
		var frame_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		graph.add_point("Frame Time", frame_time)
	
	# Physics FPS
	if show_physics_fps:
		var physics_fps = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		graph.add_point("Physics FPS", physics_fps)
	
	# Allocated Memory (Static Memory)
	if show_memory:
		var mem_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
		var mem_mb = float(mem_bytes) / bytes_to_mb
		graph.add_point("Allocated Memory", mem_mb)
	
	# Video Memory (VRAM)
	if show_video_memory:
		var video_mem_bytes = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		var video_mem_mb = float(video_mem_bytes) / bytes_to_mb
		graph.add_point("Video Memory", video_mem_mb)
