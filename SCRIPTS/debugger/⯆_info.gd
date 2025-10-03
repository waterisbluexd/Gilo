extends TabBar

# Label references (titles)
@onready var frame_per_second: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/Frame Per Second"
@onready var frame_time: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/Frame Time"
@onready var physics_frame_per_second: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/Physics Frame Per Second"

# Value labels (the actual numbers)
@onready var frame_per_second_show_value_label: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Frame Per Second_show value_label"
@onready var frame_time_show_value_label: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Frame Time_show value_lable"
@onready var physics_frame_per_second_show_value_label: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Physics Frame Per Second_show value_label"

# Line graph reference for fps
@onready var linegraph: Control = $MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/linegraph
@onready var linegraph_for_fps_graph_node: Control = $MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Performance_stats_panel/VBoxContainer/linegraph/linegraph_for_fps

# Line graph reference for memory
@onready var linegraph_for_memory: Control = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/linegraph_for_memory"
@onready var linegraph_for_memory_graph_node: Control = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/linegraph_for_memory/linegraph_for_memory2"

# Memory labels
@onready var allocated_memory: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/Allocated Memory"
@onready var free_memory: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/Free Memory"
@onready var video_memory: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Video Memory_show value_label"

@onready var allocated_memory_show_value_label: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Allocated Memory_show value_label"
@onready var free_memory_show_value_label: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Free Memory_show value_lable"
@onready var video_memory_show_value_label: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/Memory Section_panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Video Memory_show value_label"

# Update settings
var update_interval: float = 0.1  # Update every 0.1 seconds (10 times per second)
var time_since_update: float = 0.0

# System Info Section
@onready var os: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/OS"
@onready var cpu: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/CPU"
@onready var gpu: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/GPU"
@onready var resolution: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Panel/VBoxContainer/Resolution"
@onready var os_name: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/OS_name"
@onready var cpu_name: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/CPU_name"
@onready var gpu_name: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/GPU_name"
@onready var resolution_value: Label = $"MarginContainer/VBoxContainer/Panel/ScrollContainer/MarginContainer/VBoxContainer/System Info Section panel/VBoxContainer/HBoxContainer/Control/VBoxContainer/Resolution_value"


func _ready():
	# Setup both graphs
	setup_graphs()
	
	# Set initial label text for performance stats
	frame_per_second.text = "Frame Per Second [-FPS-]"
	frame_time.text = "Frame Time [-ms-]"
	physics_frame_per_second.text = "Physics Frame Per Second [-P_FPS-]"
	allocated_memory.text = "Allocated Memory (MB):"
	free_memory.text = "Free Memory:"
	video_memory.text = "Video Memory (MB):"
	
	# Set initial label text for system info
	os.text = "OS:"
	cpu.text = "CPU:"
	gpu.text = "GPU:"
	resolution.text = "Resolution:"
	
	# Populate system information from user's system
	populate_system_info()


func setup_graphs():
	"""Initialize both graphs with their respective datasets"""
	
	# TOP GRAPH - FPS Performance (3 datasets)
	linegraph_for_fps_graph_node.add_dataset("FPS", Color(0.3, 1.0, 0.3), true)
	linegraph_for_fps_graph_node.add_dataset("Frame Time", Color(1.0, 0.6, 0.2), false)
	linegraph_for_fps_graph_node.add_dataset("Physics FPS", Color(0.3, 0.8, 1.0), false)
	linegraph_for_fps_graph_node.set_y_range(0, 144)
	
	# BOTTOM GRAPH - Memory Usage (3 datasets)
	linegraph_for_memory_graph_node.add_dataset("Static (MB)", Color("66a1ff"), true)
	linegraph_for_memory_graph_node.add_dataset("Msg-Q (MB)", Color("55d47e"), false)
	linegraph_for_memory_graph_node.add_dataset("Video (MB)", Color("ff8c66"), false)
	linegraph_for_memory_graph_node.auto_scale_y = true


func _process(delta):
	# Update at fixed intervals instead of every frame for better readability
	time_since_update += delta
	
	if time_since_update >= update_interval:
		time_since_update = 0.0
		update_performance_stats()


func update_performance_stats():
	"""Update all performance statistics"""
	var bytes_to_mb = 1024.0 * 1024.0
	
	# === FPS METRICS ===
	var fps = Engine.get_frames_per_second()
	frame_per_second_show_value_label.text = str(fps)
	
	var frame_time_value = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	frame_time_show_value_label.text = "%.2f ms" % frame_time_value
	
	var physics_fps = Engine.physics_ticks_per_second
	physics_frame_per_second_show_value_label.text = str(physics_fps)
	
	# === MEMORY METRICS ===
	var static_mem = Performance.get_monitor(Performance.MEMORY_STATIC) / bytes_to_mb
	var msg_mem = Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX) / bytes_to_mb
	var video_mem = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / bytes_to_mb
	
	allocated_memory_show_value_label.text = "%.2f MB" % static_mem
	free_memory_show_value_label.text = "%.2f MB" % msg_mem
	video_memory_show_value_label.text = "%.2f MB" % video_mem
	
	# Color code FPS based on performance
	color_code_fps(fps)
	
	# === UPDATE TOP GRAPH (FPS) ===
	linegraph_for_fps_graph_node.add_point("FPS", fps)
	linegraph_for_fps_graph_node.add_point("Frame Time", frame_time_value)
	linegraph_for_fps_graph_node.add_point("Physics FPS", physics_fps)
	
	# === UPDATE BOTTOM GRAPH (MEMORY) ===
	linegraph_for_memory_graph_node.add_point("Static (MB)", static_mem)
	linegraph_for_memory_graph_node.add_point("Msg-Q (MB)", msg_mem)
	linegraph_for_memory_graph_node.add_point("Video (MB)", video_mem)


func color_code_fps(fps: float):
	"""Color the FPS value based on performance"""
	var color: Color
	if fps >= 60:
		color = Color.GREEN
	elif fps >= 30:
		color = Color.YELLOW
	else:
		color = Color.RED
	frame_per_second_show_value_label.add_theme_color_override("font_color", color)


func populate_system_info():
	"""Populate system information labels with actual hardware/OS details from user's system"""
	
	# Operating System - Gets the OS name (Windows, Linux, macOS, etc.)
	os_name.text = OS.get_name()
	
	# CPU Information - Gets processor name and core count
	var processor_name = OS.get_processor_name()
	var processor_count = OS.get_processor_count()
	cpu_name.text = "%s (%d cores)" % [processor_name, processor_count]
	
	# GPU Information - Gets the video adapter/graphics card name
	gpu_name.text = RenderingServer.get_video_adapter_name()
	
	# Screen Resolution - Gets the current display resolution
	var screen_size = DisplayServer.screen_get_size()
	resolution_value.text = "%d x %d" % [screen_size.x, screen_size.y]
