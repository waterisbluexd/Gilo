// pixel_object.gdshader (Godot 4.3+) -- trees, shrubs, farm, windmill, tower, pond
// Bake the part index into vertex COLOR.r: 0 -> part 0, 0.5 -> part 1, 1.0 -> part 2
shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/pixel_common.gdshaderinc"

uniform ivec3 part_palette = ivec3(8, 4, 4); // palette row for part 0 / 1 / 2
uniform vec3 light_dir = vec3(-0.52, 0.78, 0.34);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	int part = int(COLOR.r * 2.0 + 0.5);
	int pm = part == 0 ? part_palette.x : (part == 1 ? part_palette.y : part_palette.z);

	float ndl = max(dot(n, normalize(light_dir)), 0.0);
	float shade = 0.26 + ndl * 0.68 + (0.5 + 0.5 * n.y) * 0.24;
	shade += (vn(wpos * 14.0 + seed_off) - 0.5) * 0.08 * fd(14.0);
	if (pm == 4 || pm == 5 || pm == 6) shade += (vn(wpos * 18.0 + seed_off.yzx) - 0.5) * 0.22 * fd(18.0);
	if (pm == 12) shade += (vn(vec3(wpos.x * 7.0, TIME * 0.7, wpos.z * 7.0)) - 0.5) * 0.5; // water shimmer
	ALBEDO = pal_col(pm, shade, FRAGCOORD.xy);
}
