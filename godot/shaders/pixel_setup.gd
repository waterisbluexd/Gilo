# pixel_setup.gd  (Godot 4.3+)  -- attach to your root Node3D
# Scene layout:
#   SubViewportContainer (stretch = true, stretch_shrink = 3, texture_filter = Nearest)
#     SubViewport (msaa_3d = Disabled, screen_space_aa = Disabled)
#       WorldEnvironment (tonemap Linear, glow/fog/ssao OFF, background colour #222427)
#       Camera3D  (Orthogonal, size ~10, rotation_degrees = (-30, 45, 0))  -> child: MeshInstance3D + pixel_outline.gdshader
#       Terrain MeshInstance3D  (ShaderMaterial pixel_terrain.gdshader)
#       Props   (ShaderMaterial pixel_object.gdshader)
extends Node3D

const PALETTES := [
	["#56555a","#737177","#959291","#b9b6b0","#d8d5cf"], # 0 cool limestone
	["#5c5349","#7b6f61","#9e8e7b","#c2b29c","#dfd2be"], # 1 warm limestone
	["#6b5d38","#8d7946","#b39956","#d1b76a","#e8d284"], # 2 trail
	["#9e7f26","#bfa030","#d4b83e","#e3ca52","#f0dc72"], # 3 golden meadow
	["#2a5e1d","#3e7f24","#58a12e","#76c23b","#95dc4c"], # 4 moss / lime
	["#8f3a12","#b84f16","#d96918","#ee8524","#ffa338"], # 5 amber
	["#183d1c","#245824","#34762c","#489636","#62b644"], # 6 forest
	["#262426","#383538","#4d494d","#666166","#827c82"], # 7 cliff slate
	["#3a291b","#563d28","#755336","#946b46","#b3855b"], # 8 trunk
	["#b8b5ae","#cecbc4","#e3e0d9","#f2f0eb","#fcfbf8"], # 9 white plaster
	["#2c5a8c","#3a72ad","#4b8cc9","#67a5de","#8bc0f2"], # 10 blue trim
	["#5c3d28","#7a5236","#996846","#b88058","#d49a6e"], # 11 roof
	["#2a6f9e","#3a8cc0","#55a8d8","#7cc4ea","#b4e2f6"], # 12 water
]

@export var terrain_mat: ShaderMaterial
@export var prop_mats: Array[ShaderMaterial] = []
@export var windmill_blades: Node3D
@export var pixel_seed := 217605

func _ready() -> void:
	var img := Image.create(5, PALETTES.size(), false, Image.FORMAT_RGB8)
	for y in PALETTES.size():
		for x in 5:
			img.set_pixel(x, y, Color(PALETTES[y][x]))
	var tex := ImageTexture.create_from_image(img)
	var off := Vector3(fmod(pixel_seed * 0.137, 97.0), fmod(pixel_seed * 0.291, 89.0), fmod(pixel_seed * 0.373, 83.0))
	for m in [terrain_mat] + prop_mats:
		if m:
			m.set_shader_parameter("palette_tex", tex)
			m.set_shader_parameter("seed_off", off)

func _process(delta: float) -> void:
	if windmill_blades:  # sails face local +Z, spin about it
		windmill_blades.rotate_object_local(Vector3.BACK, delta * 0.9)
