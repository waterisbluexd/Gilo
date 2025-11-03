shader_type spatial;
render_mode depth_prepass_alpha, depth_draw_opaque, unshaded;

varying vec3 world_pos;

uniform sampler2D noiseTexture : filter_linear, repeat_enable;
uniform bool isSoft = false;
uniform float speed : hint_range(0.0, 1.0) = 0.1;
uniform float brightness: hint_range(0.0, 2.0) = 0.1;
uniform float threshold : hint_range(0.0, 2.0) = 0.1;
uniform float fluffiness : hint_range(0.0, 2.0) = 0.1;
uniform float tile_size : hint_range(10.0, 10000.0) = 2000.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Normalize world position to 0-1 range that repeats every tile_size units
	vec2 world_uv = fract(world_pos.xz / tile_size);

	// Sample noise with time animation
	vec4 noise1 = texture(noiseTexture, world_uv + TIME * 2.5 * speed / 10.0);
	vec4 noise2 = texture(noiseTexture, world_uv + TIME * (2.5 + fluffiness * 3.0) * speed / 10.0);
	vec4 combinedNoise = noise1 + noise2;

	if (isSoft == true) {
		combinedNoise.a = combinedNoise.r;
		ALBEDO = smoothstep(threshold - 0.3, threshold + 0.3, combinedNoise).rgb * brightness;
		ALPHA = smoothstep(threshold - 0.3, threshold + 0.3, combinedNoise).a;
	}
	else {
		ALBEDO = combinedNoise.rgb * brightness;
		if (combinedNoise.r < threshold) {
			ALPHA = 0.0;
		}
		else {
			ALPHA = 1.0;
		}
	}
}