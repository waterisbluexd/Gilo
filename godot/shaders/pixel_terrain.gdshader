shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/pixel_common.gdshaderinc"

uniform sampler2D height_tex : filter_nearest;                 
uniform sampler2D bio_tex : filter_linear, hint_default_black;  
uniform sampler2D road_tex : filter_linear, hint_default_black; 
uniform float world_size = 14.0;
uniform float cell_size = 0.02734375;
uniform int grid_n = 512;
uniform float height_max = 3.0;
uniform int rock_pal = 0;     
uniform float moss_amt = 0.15;
uniform float crack_amt = 0.22;
uniform vec3 light_dir = vec3(-0.52, 0.78, 0.34);

varying vec3 wpos;
varying vec3 wnrm;

vec3 surface_biome_col(float shade, vec2 fc, vec4 weights) {
	weights = max(weights, vec4(0.0));
	weights /= max(dot(weights, vec4(1.0)), 0.0001);
	return pal_col(3, shade, fc) * weights.r
		+ pal_col(4, shade, fc) * weights.g
		+ pal_col(6, shade, fc) * weights.b
		+ pal_col(2, shade, fc) * weights.a;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float shd(vec3 p, vec3 L) {
	for (int k = 1; k <= 12; k++) {
		float t = 0.08 * float(k) + 0.012 * float(k * k);
		vec3 q = p + L * t;
		ivec2 c = ivec2(floor(q.xz / cell_size + float(grid_n) * 0.5 + 0.5));
		if (c.x < 0 || c.y < 0 || c.x > grid_n || c.y > grid_n) break;
		if (texelFetch(height_tex, c, 0).r > q.y + 0.025) return 1.0;
	}
	return 0.0;
}

float crk(vec3 p, out bool deep) {
	deep = false;
	float cf = 1.0 - smoothstep(0.02, 0.08, pixel_world);
	if (crack_amt <= 0.0 || cf <= 0.0) return 0.0;
	vec3 w = vec3(vn(p * 1.25 + seed_off), vn(p * 1.25 + seed_off.yzx + 9.0), vn(p * 1.25 + seed_off.zxy + 5.0)) - 0.5;
	vec3 q = p + w * 0.85;
	float wv = 0.45 + 1.25 * vn(p * 2.8 + seed_off.zxy);
	float r1 = abs(vn(q * 1.45 + seed_off) * 2.0 - 1.0);
	float w1 = (0.032 + 0.048 * crack_amt) * wv * cf;
	if (r1 < w1) { deep = r1 < w1 * 0.38; return 0.48; }
	float d = 0.0;
	if (r1 < w1 * 1.8) d -= 0.08;
	if (r1 < w1 * 8.0) {
		float r2 = abs(vn(q * 4.1 + seed_off.yzx) * 2.0 - 1.0);
		if (r2 < (0.032 + 0.052 * crack_amt) * wv * cf) return 0.28;
		if (r1 < w1 * 14.0 && r2 < 0.32 && abs(vn(q * 8.8 + seed_off.zxy) * 2.0 - 1.0) < 0.05 + 0.05 * crack_amt) return 0.16;
	}
	return d;
}

int pick_mat(vec3 p, float ny, vec4 q, float terrace, float rd, out float wi, out int is_rock) {
	wi = 0.0;
	is_rock = 0;
	if (rd > 0.42 && ny > 0.58) { // switchback ramp / trail
		wi = 0.06 + (vn(vec3(p.x * 2.5 + seed_off.x, 0.0, p.z * 2.5 + seed_off.y)) - 0.5) * 0.08;
		return 2;
	}
	if (ny < 0.75) { // cliffs / steep faces
		is_rock = 1;
		return (q.x > q.y + 0.08 || terrace > 0.45) ? rock_pal : (rock_pal == 0 ? 1 : 0);
	}
	return 3;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 p = wpos;
	vec3 L = normalize(light_dir);
	vec2 uv = clamp(p.xz / world_size + 0.5, 0.001, 0.999);
	vec4 tb = texture(bio_tex, uv);
	vec4 q = vec4(tb.rgb, max(0.0, 1.0 - tb.r - tb.g - tb.b));
	float rd = texture(road_tex, uv).r;

	float wi;
	int is_rock;
	int pm = pick_mat(p, n.y, q, tb.a, rd, wi, is_rock);

	// hand-rolled light: key (Lambert) + sky fill + ray-marched heightfield shadow
	float ndl = max(dot(n, L), 0.0);
	float sky = (0.5 + 0.5 * n.y) * 0.24;
	float occ = shd(p + vec3(0.0, 0.025, 0.0), L) * 0.22;
	float shade = 0.24 + ndl * 0.68 + sky + wi - occ;
	shade += (vn(p * 7.5 + seed_off) - 0.5) * 0.09 * fd(7.5);
	shade += (vn(p * 20.0 + seed_off.yzx) - 0.5) * 0.05 * fd(20.0);

	if (is_rock == 1) {
		bool deep = false;
		float c = crk(p * 0.85, deep);
		if (deep) {
			ALBEDO = vec3(0.227, 0.208, 0.192);
		} else {
			shade -= c;
			if (moss_amt > 0.0 && c < 0.35) {
				float ms = n.y * 0.65 + (vn(p * 4.2 + seed_off.zxy) - 0.5) * 0.9 + (1.0 - min(1.0, p.y / max(0.5, height_max))) * 0.20;
				if (ms > 0.96 - moss_amt * 0.88) { pm = 4; shade += 0.05; }
			}
			ALBEDO = pal_col(pm, shade, FRAGCOORD.xy);
		}
	} else {
		ALBEDO = pm == 2
			? pal_col(pm, shade, FRAGCOORD.xy)
			: surface_biome_col(shade, FRAGCOORD.xy, COLOR);
	}
}
