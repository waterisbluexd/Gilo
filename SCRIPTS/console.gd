extends RichTextLabel

# Node references - adjust these paths according to your scene structure
@onready var camera_3d: Camera3D = $"../../../../../Pixelated/Main/SubViewportContainer/SubViewport/CameraPivot/Camera3D"
@onready var camera_pivot: Node3D = $"../../../../../Pixelated/Main/SubViewportContainer/SubViewport/CameraPivot"

# Try to find chunk terrain automatically
var chunk_terrain: ChunkPixelTerrain
var update_timer: float = 0.0
var update_interval: float = 0.1  # Update UI 10 times per second

func _ready():
	_find_chunk_terrain()
	
	# Set up the RichTextLabel for better formatting
	bbcode_enabled = true
	fit_content = true

func _find_chunk_terrain():
	# Search for ChunkPixelTerrain in the scene tree
	chunk_terrain = _search_for_chunk_terrain(get_tree().current_scene)
	if chunk_terrain:
		print("UI connected to chunk terrain system")
	else:
		print("UI: ChunkPixelTerrain not found")

func _search_for_chunk_terrain(node: Node) -> ChunkPixelTerrain:
	# Check if this node is ChunkPixelTerrain
	if node is ChunkPixelTerrain or (node.get_script() and node.get_script().get_global_name() == "ChunkPixelTerrain"):
		return node
	
	# Search children
	for child in node.get_children():
		var result = _search_for_chunk_terrain(child)
		if result:
			return result
	
	return null

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		update_ui_info()

func update_ui_info():
	var info_text = ""
	
	# Camera information
	if camera_3d and camera_pivot:
		var camera_zoom = camera_3d.size if camera_3d.projection == Camera3D.PROJECTION_ORTHOGONAL else camera_3d.fov
		var camera_pos = camera_pivot.global_position
		var camera_rot = rad_to_deg(camera_pivot.rotation.y)
		
		info_text += "[color=cyan][b]CAMERA INFO[/b][/color]\n"
		if camera_3d.projection == Camera3D.PROJECTION_ORTHOGONAL:
			info_text += "Zoom: %.2f\n" % camera_zoom
		else:
			info_text += "FOV: %.1f°\n" % camera_zoom
		info_text += "Position: X=%.1f, Y=%.1f, Z=%.1f\n" % [camera_pos.x, camera_pos.y, camera_pos.z]
		info_text += "Rotation Y: %.0f°\n" % camera_rot
		
		# Movement info if camera pivot has the movement functions
		if camera_pivot.has_method("is_moving") and camera_pivot.has_method("get_current_speed"):
			var is_moving = camera_pivot.is_moving()
			var current_speed = camera_pivot.get_current_speed()
			var is_sprinting = camera_pivot.get("is_sprinting") if "is_sprinting" in camera_pivot else false
			
			info_text += "Moving: %s\n" % ("Yes" if is_moving else "No")
			if is_moving:
				info_text += "Speed: %.1f%s\n" % [current_speed, " (Sprint)" if is_sprinting else ""]
		
		info_text += "\n"
	else:
		info_text += "[color=red]Camera nodes not found![/color]\n"
		info_text += "Check paths in script.\n\n"
	
	# Chunk system information
	if chunk_terrain:
		info_text += "[color=lime][b]CHUNK SYSTEM[/b][/color]\n"
		
		# Get current chunk position
		var current_chunk = Vector2i.ZERO
		if camera_pivot:
			current_chunk = chunk_terrain.world_to_chunk(camera_pivot.global_position)
		
		info_text += "Current Chunk: X=%d, Y=%d\n" % [current_chunk.x, current_chunk.y]
		info_text += "Loaded Chunks: %d\n" % chunk_terrain.get_loaded_chunk_count()
		info_text += "Loading Chunks: %d\n" % chunk_terrain.get_loading_chunk_count()
		
		# Performance stats if available
		if chunk_terrain.has_method("get_performance_stats"):
			var stats = chunk_terrain.get_performance_stats()
			if stats.has("multithreading_enabled"):
				info_text += "Multithreading: %s\n" % ("On" if stats.multithreading_enabled else "Off")
			if stats.has("thread_count"):
				info_text += "Threads: %d\n" % stats.thread_count
		
		info_text += "\n"
	else:
		info_text += "[color=yellow]Chunk system not found[/color]\n\n"
	
	# Controls help
	info_text += "[color=gray][b]CONTROLS[/b][/color]\n"
	info_text += "[color=gray]WASD: Move\n"
	info_text += "Q/E: Rotate Camera\n"
	info_text += "Shift: Sprint\n"
	info_text += "R: Reset Position\n"
	info_text += "T: Toggle Smooth Movement\n"
	info_text += "F5: Save Chunks\n"
	info_text += "F6: Clear Chunks[/color]"
	
	text = info_text
