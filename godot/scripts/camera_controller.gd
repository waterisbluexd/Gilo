extends Camera3D

@export var target := Vector3.ZERO
@export var base_size := 10.0                   # ortho size (world units visible vertically) at zoom 1
@export var distance := 80.0                    # camera distance along its view axis (ortho: only affects clipping)
@export_range(0.0, 90.0) var default_yaw_deg := 45.0
@export_range(0.0, 90.0) var default_pitch_deg := 30.0
@export var min_pitch_deg := 10.0
@export var max_pitch_deg := 81.0
@export var min_zoom := 0.15
@export var max_zoom := 24.0
@export var orbit_speed := 0.01                 # radians per pixel (same as the demo)
@export var wheel_zoom_step := 1.12
@export var invert_orbit := false
@export var keyboard_controls := true
@export var key_pan_speed := 0.9                # screen-heights per second at zoom 1
@export var smoothing := 0.0                    # 0 = instant (like the demo); ~12 = soft
@export var snap_to_pixels := true              # stops sub-pixel shimmer on a low-res pixel-art viewport

var yaw := 0.0
var pitch := 0.0
var zoom := 1.0
var _t_target: Vector3
var _t_yaw: float
var _t_pitch: float
var _t_zoom: float
var _home: Vector3
var _touches := {}                              # finger index -> position

func _ready() -> void:
	_home = target
	projection = Camera3D.PROJECTION_ORTHOGONAL
	near = 0.1
	far = maxf(far, distance * 4.0)
	reset_view()
	_apply(1.0)

func reset_view() -> void:
	_t_yaw = deg_to_rad(default_yaw_deg)
	_t_pitch = deg_to_rad(default_pitch_deg)
	_t_zoom = 1.0
	_t_target = _home
	if smoothing <= 0.0:
		yaw = _t_yaw; pitch = _t_pitch; zoom = _t_zoom; target = _t_target

# ---------- helpers ----------
func _world_per_pixel() -> float:
	var h := get_viewport().get_visible_rect().size.y
	return (base_size / zoom) / maxf(h, 1.0)

func _pan_pixels(delta_px: Vector2) -> void:
	var upp := (base_size / _t_zoom) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var b := Basis.from_euler(Vector3(-_t_pitch, _t_yaw, 0.0))
	_t_target += (-b.x * delta_px.x + b.y * delta_px.y) * upp   # grab-the-map feel

func _orbit_pixels(delta_px: Vector2) -> void:
	var s := -orbit_speed if not invert_orbit else orbit_speed
	_t_yaw += delta_px.x * s
	_t_pitch = clampf(_t_pitch + delta_px.y * orbit_speed, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

func _zoom_by(f: float) -> void:
	_t_zoom = clampf(_t_zoom * f, min_zoom, max_zoom)

# ---------- input ----------
func _unhandled_input(event: InputEvent) -> void:
	# mouse
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var pan := (m.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 or (m.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0 \
			or ((m.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and m.shift_pressed)
		if pan:
			_pan_pixels(m.relative)
		elif (m.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_orbit_pixels(m.relative)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(pow(wheel_zoom_step, mb.factor if mb.factor > 0.0 else 1.0))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / pow(wheel_zoom_step, mb.factor if mb.factor > 0.0 else 1.0))
	# trackpad
	elif event is InputEventMagnifyGesture:
		_zoom_by((event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		_pan_pixels(-(event as InputEventPanGesture).delta * 8.0)
	# touch: 1 finger orbit, 2 fingers pinch-zoom + pan (same as the demo)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed: _touches[st.index] = st.position
		else: _touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index): return
		var prev: Vector2 = _touches[sd.index]
		if _touches.size() == 1:
			_orbit_pixels(sd.relative)
		elif _touches.size() == 2:
			var other: Vector2
			for k in _touches.keys():
				if k != sd.index: other = _touches[k]
			var d0 := prev.distance_to(other)
			var d1 := sd.position.distance_to(other)
			if d0 > 0.0: _zoom_by(d1 / d0)
			_pan_pixels(sd.relative * 0.5)
		_touches[sd.index] = sd.position
	# keys
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R or event.keycode == KEY_HOME:
			reset_view()

func _process(delta: float) -> void:
	if keyboard_controls:
		var v := Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_up", &"ui_down"))
		if Input.is_key_pressed(KEY_A): v.x -= 1.0
		if Input.is_key_pressed(KEY_D): v.x += 1.0
		if Input.is_key_pressed(KEY_W): v.y -= 1.0
		if Input.is_key_pressed(KEY_S): v.y += 1.0
		if v != Vector2.ZERO:
			var h := get_viewport().get_visible_rect().size.y
			_pan_pixels(-v.normalized() * key_pan_speed * h * delta)
		if Input.is_key_pressed(KEY_Q): _t_yaw += delta * 1.5
		if Input.is_key_pressed(KEY_E): _t_yaw -= delta * 1.5
	_apply(1.0 if smoothing <= 0.0 else 1.0 - exp(-smoothing * delta))

func _apply(k: float) -> void:
	yaw = lerp_angle(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	zoom = lerpf(zoom, _t_zoom, k)
	target = target.lerp(_t_target, k)
	size = base_size / zoom
	var b := Basis.from_euler(Vector3(-pitch, yaw, 0.0))   # YXZ: yaw around Y, pitch down
	var pos := target + b.z * distance
	if snap_to_pixels:
		var upp := _world_per_pixel()
		var local := b.inverse() * pos
		local.x = roundf(local.x / upp) * upp
		local.y = roundf(local.y / upp) * upp
		pos = b * local
	global_transform = Transform3D(b, pos)
