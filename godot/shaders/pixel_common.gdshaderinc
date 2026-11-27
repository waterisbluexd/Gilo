uniform sampler2D palette_tex : source_color, filter_nearest; 
uniform vec3 seed_off = vec3(0.0);   
uniform float pixel_world = 0.03;    

const float BAY[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0);

float h3(ivec3 p) {
	uint n = uint(p.x) * 73856093u ^ uint(p.y) * 19349663u ^ uint(p.z) * 83492791u;
	n = (n ^ (n >> 15u)) * 2246822519u;
	return float((n ^ (n >> 13u)) & 4095u) / 4095.0;
}

float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	ivec3 b = ivec3(i);
	float a = mix(h3(b), h3(b + ivec3(1, 0, 0)), f.x);
	float c = mix(h3(b + ivec3(0, 1, 0)), h3(b + ivec3(1, 1, 0)), f.x);
	float d = mix(h3(b + ivec3(0, 0, 1)), h3(b + ivec3(1, 0, 1)), f.x);
	float e = mix(h3(b + ivec3(0, 1, 1)), h3(b + ivec3(1, 1, 1)), f.x);
	return mix(mix(a, c, f.y), mix(d, e, f.y), f.z);
}

vec3 pal_col(int pm, float shade, vec2 fc) {
	float bay = BAY[int(mod(fc.y, 4.0)) * 4 + int(mod(fc.x, 4.0))] / 16.0;
	int lv = int(clamp(floor(clamp(shade, 0.0, 1.0) * 4.0 + (bay - 0.5) * 0.22 + 0.5), 0.0, 4.0));
	return texelFetch(palette_tex, ivec2(lv, pm), 0).rgb;
}

float fd(float freq) {
	return 1.0 - smoothstep(0.15, 0.5, pixel_world * freq);
}
