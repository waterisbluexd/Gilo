extends Label

enum EffectType {
	RAINBOW_FULL,      # Original - entire text changes color
	RAINBOW_INDIVIDUAL, # Each character cycles through rainbow
	WAVE,              # Wave pattern with colors
	SPARKLE,           # Random sparkle/twinkle effect
	PULSE,             # Pulsing scale and opacity
	GLITCH,            # Glitch/distortion effect
	TYPEWRITER,        # Typewriter effect with rainbow trail
	FIRE,              # Fire/flame effect
	NEON_FLICKER,      # Neon sign flickering
	MATRIX_RAIN,       # Matrix-style falling effect
	DISCO,             # Disco ball reflection effect
	PLAY_ALL           # Play all effects one by one
}

@export var effect_type: EffectType = EffectType.RAINBOW_FULL
@export var speed: float = 1.0
@export_range(1.0, 10.0) var effect_duration: float = 3.0  # Duration for each effect in PLAY_ALL mode

var hue: float = 0.0
var time: float = 0.0
var characters: Array = []
var character_labels: Array[Label] = []
var original_text: String = ""
var current_effect_index: int = 0
var effect_timer: float = 0.0
var typewriter_index: float = 0.0

func _ready() -> void:
	_setup_characters()

func _setup_characters() -> void:
	# Clear existing character labels
	for lbl in character_labels:
		lbl.queue_free()
	character_labels.clear()
	characters.clear()
	
	# Store original text
	original_text = text
	
	# Create array of characters
	for i in range(original_text.length()):
		characters.append(original_text[i])
	
	# Create individual labels for each character (for effects that need it)
	if effect_type != EffectType.RAINBOW_FULL:
		_create_character_labels()
	else:
		# Restore original text for rainbow full effect
		text = original_text

func _create_character_labels() -> void:
	# Hide main label text
	var temp_text = text
	text = ""
	
	# Get font and calculate character positions
	var font = get_theme_default_font()
	var font_size = get_theme_font_size("font_size")
	
	# Calculate total width for centering
	var total_width = font.get_string_size(original_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	
	# Calculate starting X position based on alignment
	var start_x = 0.0
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			start_x = (size.x - total_width) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			start_x = size.x - total_width
		HORIZONTAL_ALIGNMENT_LEFT:
			start_x = 0.0
	
	# If size is zero (auto-sizing), use parent size or default centering
	if size.x == 0 and horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		var parent_width = get_parent_area_size().x if get_parent() else 800
		start_x = (parent_width - total_width) / 2.0
	
	var x_offset = start_x
	
	for i in range(characters.size()):
		var char_label = Label.new()
		char_label.text = characters[i]
		char_label.add_theme_font_size_override("font_size", font_size)
		char_label.position = Vector2(x_offset, 0)
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(char_label)
		character_labels.append(char_label)
		
		# Calculate width for next character
		var char_width = font.get_string_size(characters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		x_offset += char_width

func _process(delta: float) -> void:
	time += delta
	
	# Handle PLAY_ALL mode
	if effect_type == EffectType.PLAY_ALL:
		effect_timer += delta
		if effect_timer >= effect_duration:
			effect_timer = 0.0
			current_effect_index = (current_effect_index + 1) % 11  # Cycle through 11 effects
			typewriter_index = 0.0  # Reset typewriter
		
		_apply_effect(current_effect_index, delta)
	else:
		_apply_effect(effect_type, delta)

func _apply_effect(effect_index: int, delta: float) -> void:
	match effect_index:
		EffectType.RAINBOW_FULL:
			_effect_rainbow_full(delta)
		EffectType.RAINBOW_INDIVIDUAL:
			_effect_rainbow_individual()
		EffectType.WAVE:
			_effect_wave()
		EffectType.SPARKLE:
			_effect_sparkle()
		EffectType.PULSE:
			_effect_pulse()
		EffectType.GLITCH:
			_effect_glitch()
		EffectType.TYPEWRITER:
			_effect_typewriter(delta)
		EffectType.FIRE:
			_effect_fire()
		EffectType.NEON_FLICKER:
			_effect_neon_flicker()
		EffectType.MATRIX_RAIN:
			_effect_matrix_rain()
		EffectType.DISCO:
			_effect_disco()

func _effect_rainbow_full(delta: float) -> void:
	# Original effect - entire text changes color
	hue = wrapf(hue + delta * speed, 0.0, 1.0)
	modulate = Color.from_hsv(hue, 1.0, 1.0)

func _effect_rainbow_individual() -> void:
	# Each character has its own color cycling through rainbow
	for i in range(character_labels.size()):
		var offset = float(i) / float(character_labels.size())
		var char_hue = wrapf(hue + offset, 0.0, 1.0)
		character_labels[i].modulate = Color.from_hsv(char_hue, 1.0, 1.0)
	hue = wrapf(hue + get_process_delta_time() * speed, 0.0, 1.0)

func _effect_wave() -> void:
	# Wave pattern with colors and vertical movement
	for i in range(character_labels.size()):
		var wave_offset = float(i) * 0.5
		var wave = sin(time * speed * 3.0 + wave_offset) * 10.0
		var char_hue = wrapf((time * speed + float(i) * 0.1), 0.0, 1.0)
		
		character_labels[i].position.y = wave
		character_labels[i].modulate = Color.from_hsv(char_hue, 0.8, 1.0)

func _effect_sparkle() -> void:
	# Random sparkle/twinkle effect like fairy lights
	for i in range(character_labels.size()):
		var sparkle_time = time * speed * 2.0 + float(i) * 0.3
		var brightness = abs(sin(sparkle_time + randf() * 0.5))
		var random_hue = fmod(float(i) * 0.137 + time * speed * 0.1, 1.0)
		
		var alpha = 0.4 + brightness * 0.6
		character_labels[i].modulate = Color.from_hsv(random_hue, 0.7, brightness)
		character_labels[i].modulate.a = alpha
		
		# Random scale variation
		var scale_factor = 0.9 + brightness * 0.2
		character_labels[i].scale = Vector2(scale_factor, scale_factor)

func _effect_pulse() -> void:
	# Pulsing scale and opacity
	for i in range(character_labels.size()):
		var char_offset = float(i) * 0.2
		var char_pulse = abs(sin(time * speed * 2.0 + char_offset))
		var char_scale = 0.8 + char_pulse * 0.4
		
		character_labels[i].scale = Vector2(char_scale, char_scale)
		character_labels[i].modulate = Color(char_pulse, char_pulse * 0.7, 1.0, 0.7 + char_pulse * 0.3)

func _effect_glitch() -> void:
	# Glitch/distortion effect with color shifts
	var font = get_theme_default_font()
	var font_size = get_theme_font_size("font_size")
	var total_width = font.get_string_size(original_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var start_x = _get_alignment_offset(total_width)
	
	for i in range(character_labels.size()):
		# Random glitch chance
		if randf() < 0.05 * speed:
			# Position glitch
			character_labels[i].position.x += randf_range(-5, 5)
			character_labels[i].position.y = randf_range(-3, 3)
			
			# Color glitch
			var glitch_color = Color(randf(), randf(), randf(), 1.0)
			character_labels[i].modulate = glitch_color
		else:
			# Smooth return to normal position
			var target_x = start_x
			for j in range(i):
				target_x += font.get_string_size(characters[j], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			
			character_labels[i].position.x = lerp(character_labels[i].position.x, target_x, 0.2)
			character_labels[i].position.y = lerp(character_labels[i].position.y, 0.0, 0.2)
			character_labels[i].modulate = lerp(character_labels[i].modulate, Color.WHITE, 0.1)

func _effect_typewriter(delta: float) -> void:
	# Typewriter effect with rainbow trail
	typewriter_index += delta * speed * 5.0
	
	for i in range(character_labels.size()):
		if i < int(typewriter_index):
			character_labels[i].visible = true
			var age = typewriter_index - float(i)
			var age_hue = wrapf(float(i) * 0.1 + time * 0.5, 0.0, 1.0)
			character_labels[i].modulate = Color.from_hsv(age_hue, 0.8, 1.0)
			character_labels[i].scale = Vector2.ONE
		else:
			character_labels[i].visible = false
	
	# Reset when complete
	if typewriter_index >= characters.size() + 2:
		typewriter_index = 0.0

func _effect_fire() -> void:
	# Fire/flame effect with hot colors
	for i in range(character_labels.size()):
		var flicker = randf_range(0.7, 1.0)
		var flame_offset = sin(time * speed * 5.0 + float(i)) * 5.0
		
		# Fire colors: red to yellow
		var fire_hue = randf_range(0.0, 0.15)  # Red to yellow range
		var saturation = randf_range(0.8, 1.0)
		var brightness = flicker
		
		character_labels[i].position.y = flame_offset + randf_range(-2, 2)
		character_labels[i].modulate = Color.from_hsv(fire_hue, saturation, brightness)
		character_labels[i].modulate.a = flicker

func _effect_neon_flicker() -> void:
	# Neon sign flickering effect
	var main_flicker = 1.0
	if randf() < 0.02 * speed:
		main_flicker = randf_range(0.3, 0.7)
	
	var neon_hue = wrapf(time * speed * 0.3, 0.0, 1.0)
	var base_color = Color.from_hsv(neon_hue, 1.0, 1.0)
	
	for i in range(character_labels.size()):
		var char_flicker = 1.0
		if randf() < 0.03 * speed:
			char_flicker = randf_range(0.2, 0.9)
		
		var final_brightness = main_flicker * char_flicker
		character_labels[i].modulate = base_color * final_brightness
		
		# Glow effect with scale
		var glow = 1.0 + (final_brightness - 0.5) * 0.1
		character_labels[i].scale = Vector2(glow, glow)

func _effect_matrix_rain() -> void:
	# Matrix-style falling effect
	for i in range(character_labels.size()):
		var fall_speed = float(i % 3 + 1) * 50.0
		var y_pos = fmod(time * speed * fall_speed + float(i) * 30.0, 200.0) - 100.0
		
		character_labels[i].position.y = y_pos
		
		# Green matrix color with fade
		var fade = 1.0 - (y_pos + 100.0) / 200.0
		character_labels[i].modulate = Color(0.0, 1.0, 0.3, clamp(fade, 0.2, 1.0))
		
		# Leading character brighter
		if y_pos > -10 and y_pos < 10:
			character_labels[i].modulate = Color(0.5, 1.0, 0.5, 1.0)

func _effect_disco() -> void:
	# Disco ball reflection effect
	for i in range(character_labels.size()):
		var disco_time = time * speed * 3.0
		var angle = disco_time + float(i) * 0.5
		
		# Rotating color spots
		var hue1 = wrapf(angle * 0.3, 0.0, 1.0)
		var hue2 = wrapf(angle * 0.3 + 0.5, 0.0, 1.0)
		
		var spot = sin(angle) * 0.5 + 0.5
		var color = Color.from_hsv(hue1, 1.0, 1.0).lerp(Color.from_hsv(hue2, 1.0, 1.0), spot)
		
		character_labels[i].modulate = color
		
		# Disco scale pulse
		var scale_pulse = 0.9 + abs(sin(disco_time + float(i) * 0.3)) * 0.2
		character_labels[i].scale = Vector2(scale_pulse, scale_pulse)
		
		# Slight rotation effect
		character_labels[i].rotation = sin(disco_time + float(i)) * 0.1

func _get_alignment_offset(total_width: float) -> float:
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			if size.x == 0:
				var parent_width = get_parent_area_size().x if get_parent() else 800
				return (parent_width - total_width) / 2.0
			return (size.x - total_width) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			return size.x - total_width
	return 0.0

func _on_text_changed(new_text: String) -> void:
	text = new_text
	_setup_characters()
