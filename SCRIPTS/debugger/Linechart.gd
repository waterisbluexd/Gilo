@tool
extends Control

## --- User-Configurable Properties ---
@export_group("Appearance")
@export var background_color: Color = Color(0.08, 0.0, 0.0, 0.54)
@export var grid_color: Color = Color(0.17, 0.13, 0.12, 1.0)
@export var line_width: float = 1.0
@export var antialiasing: bool = true
@export var show_legend: bool = true
@export var legend_position_right: bool = true  # Place on right side
@export var legend_outside: bool = true  # Place legend outside graph area

@export_group("Grid")
@export var grid_subdivisions: Vector2i = Vector2i(10, 5)
@export var show_labels: bool = true  # Show Y-axis labels
@export var label_color: Color = Color(0.6, 0.65, 0.7, 1.0)

@export_group("Font")
@export var custom_font: Font  # Drag & drop a font resource here
@export var font_size: int = 10

@export_group("Data")
@export var history_size: int = 120:
	set(value):
		history_size = max(1, value)
		for key in datasets:
			var data = datasets[key].points
			if data.size() > history_size:
				datasets[key].points = data.slice(data.size() - history_size)
		queue_redraw()

@export var y_min: float = 0.0
@export var y_max: float = 250.0
@export var auto_scale_y: bool = true
@export var padding: float = 40.0  # Space for labels

## --- Internal Variables ---
var datasets = {}
var font: Font
var actual_y_min: float = 0.0
var actual_y_max: float = 100.0


func _ready():
	# Use custom font if provided, otherwise use fallback
	if custom_font:
		font = custom_font
	else:
		font = ThemeDB.fallback_font


func _draw():
	var rect_size = get_rect().size
	
	# Draw background
	draw_rect(Rect2(Vector2.ZERO, rect_size), background_color, true)
	
	# Calculate drawable area (with padding for labels)
	var draw_area = Rect2(
		Vector2(padding, padding * 0.5),
		Vector2(rect_size.x - padding * 1.5, rect_size.y - padding)
	)
	
	# Auto-scale Y axis if enabled
	if auto_scale_y:
		calculate_auto_scale()
	else:
		actual_y_min = y_min
		actual_y_max = y_max
	
	# Draw grid
	draw_grid(draw_area)
	
	# Draw Y-axis labels
	if show_labels:
		draw_y_labels(draw_area)
	
	# Draw datasets
	draw_datasets(draw_area)
	
	# Draw legend
	if show_legend:
		draw_legend()


func draw_grid(area: Rect2):
	# Vertical grid lines
	if grid_subdivisions.x > 0:
		var x_step = area.size.x / grid_subdivisions.x
		for i in range(grid_subdivisions.x + 1):
			var x = area.position.x + i * x_step
			draw_line(
				Vector2(x, area.position.y),
				Vector2(x, area.position.y + area.size.y),
				grid_color,
				1.0
			)
	
	# Horizontal grid lines
	if grid_subdivisions.y > 0:
		var y_step = area.size.y / grid_subdivisions.y
		for i in range(grid_subdivisions.y + 1):
			var y = area.position.y + i * y_step
			draw_line(
				Vector2(area.position.x, y),
				Vector2(area.position.x + area.size.x, y),
				grid_color,
				1.0
			)


func draw_y_labels(area: Rect2):
	if grid_subdivisions.y <= 0:
		return
	
	var y_step = area.size.y / grid_subdivisions.y
	var value_step = (actual_y_max - actual_y_min) / grid_subdivisions.y
	
	for i in range(grid_subdivisions.y + 1):
		var y = area.position.y + area.size.y - (i * y_step)
		var value = actual_y_min + (i * value_step)
		
		# Format value nicely
		var label_text = "%.1f" % value if value < 100 else "%.0f" % value
		
		# Draw label with font size
		var label_pos = Vector2(5, y + 5)
		draw_string(font, label_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)


func draw_datasets(area: Rect2):
	for key in datasets:
		var data = datasets[key]
		var points_data = data.points
		var line_color = data.color
		var filled = data.get("filled", false)
		
		if points_data.size() < 2:
			continue
		
		# Build line points
		var line_points = PackedVector2Array()
		line_points.resize(points_data.size())
		
		for i in range(points_data.size()):
			var value = points_data[i]
			var x = area.position.x + (float(i) / max(1, history_size - 1)) * area.size.x
			var y = area.position.y + remap(value, actual_y_min, actual_y_max, area.size.y, 0)
			y = clamp(y, area.position.y, area.position.y + area.size.y)
			line_points[i] = Vector2(x, y)
		
		# Draw filled area under line if enabled
		if filled and line_points.size() > 1:
			var fill_points = PackedVector2Array()
			fill_points.append(Vector2(line_points[0].x, area.position.y + area.size.y))
			fill_points.append_array(line_points)
			fill_points.append(Vector2(line_points[-1].x, area.position.y + area.size.y))
			
			var fill_color = line_color
			fill_color.a = 0.2
			draw_colored_polygon(fill_points, fill_color)
		
		# Draw line
		draw_polyline(line_points, line_color, line_width, antialiasing)


func draw_legend():
	if datasets.is_empty():
		return
	
	var rect_size = get_rect().size
	var line_height = 16
	var legend_bg_padding = 5
	var legend_width = 90.0
	
	# Calculate legend height
	var legend_height = datasets.size() * line_height + legend_bg_padding * 2
	
	# Position legend (top-right by default)
	var pos: Vector2
	if legend_outside:
		# Place above the graph
		pos = Vector2(rect_size.x - legend_width - 10, -legend_height - 5)
	elif legend_position_right:
		# Top-right corner inside graph
		pos = Vector2(rect_size.x - legend_width - 10, 10)
	else:
		# Top-left corner
		pos = Vector2(10, 10)
	
	# Draw clean semi-transparent background
	var legend_rect = Rect2(pos, Vector2(legend_width, legend_height))
	draw_rect(legend_rect, Color(0.08, 0.1, 0.12, 0.85), true)
	draw_rect(legend_rect, Color(0.2, 0.22, 0.25, 0.6), false, 1.0)
	
	# Draw legend entries - CLEAN, no values shown
	var y_offset = pos.y + legend_bg_padding + 3
	for key in datasets:
		var data = datasets[key]
		var color = data.color
		
		# Draw color indicator (small filled square)
		var box_size = 8
		var box_pos = Vector2(pos.x + legend_bg_padding, y_offset + 3)
		draw_rect(Rect2(box_pos, Vector2(box_size, box_size)), color, true)
		
		# Draw dataset name only (no values)
		var text_pos = Vector2(pos.x + legend_bg_padding + box_size + 4, y_offset + 11)
		draw_string(font, text_pos, key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.87, 0.9))
		
		y_offset += line_height


func calculate_auto_scale():
	var min_val = INF
	var max_val = -INF
	
	for key in datasets:
		for value in datasets[key].points:
			min_val = min(min_val, value)
			max_val = max(max_val, value)
	
	if min_val != INF and max_val != -INF:
		# Add 10% padding
		var range_val = max_val - min_val
		actual_y_min = min_val - range_val * 0.1
		actual_y_max = max_val + range_val * 0.1
	else:
		actual_y_min = y_min
		actual_y_max = y_max


## --- Public API Methods ---
func add_dataset(name: String, color: Color, filled: bool = false):
	"""Add a new dataset to track"""
	if not datasets.has(name):
		datasets[name] = {
			"points": PackedFloat32Array(),
			"color": color,
			"filled": filled
		}
	else:
		push_warning("Dataset '%s' already exists." % name)


func add_point(dataset_name: String, value: float):
	"""Add a data point to a dataset (auto-create if missing)"""
	if not datasets.has(dataset_name):
		# Create dataset with random color if it doesn't exist
		var random_color = Color(randf(), randf(), randf())
		add_dataset(dataset_name, random_color)
	
	var data = datasets[dataset_name].points
	data.push_back(value)
	if data.size() > history_size:
		data.remove_at(0)
	queue_redraw()


func clear_dataset(dataset_name: String):
	"""Clear all points from a dataset"""
	if datasets.has(dataset_name):
		datasets[dataset_name].points.clear()
		queue_redraw()


func remove_dataset(dataset_name: String):
	"""Remove a dataset completely"""
	if datasets.has(dataset_name):
		datasets.erase(dataset_name)
		queue_redraw()


func clear_all():
	"""Clear all datasets"""
	for key in datasets:
		datasets[key].points.clear()
	queue_redraw()


func set_y_range(new_min: float, new_max: float):
	"""Manually set Y-axis range"""
	y_min = new_min
	y_max = new_max
	auto_scale_y = false
	queue_redraw()


func get_dataset_current_value(dataset_name: String) -> float:
	"""Get the most recent value from a dataset"""
	if datasets.has(dataset_name):
		var points = datasets[dataset_name].points
		if points.size() > 0:
			return points[-1]
	return 0.0
