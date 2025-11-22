shader_type spatial;
render_mode depth_prepass_alpha, depth_draw_opaque, unshaded, cull_disabled;

varying vec3 world_pos;

uniform sampler2D noiseTexture : filter_linear, repeat_enable;
uniform bool isSoft = false;
uniform float speed : hint_range(0.0, 1.0) = 0.1;
uniform float brightness: hint_range(0.0, 2.0) = 1.0;
uniform float threshold : hint_range(0.0, 2.0) = 0.5;
uniform float fluffiness : hint_range(0.0, 2.0) = 0.5;
uniform float tile_size : hint_range(10.0, 10000.0) = 2000.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Use world position directly for seamless tiling
	vec2 world_uv = world_pos.xz / tile_size;

	// Sample noise with time animation - texture repeats automatically
	vec4 noise1 = texture(noiseTexture, world_uv + TIME * 2.5 * speed / 10.0);
	vec4 noise2 = texture(noiseTexture, world_uv + TIME * (2.5 + fluffiness * 3.0) * speed / 10.0);
	vec4 combinedNoise = noise1 + noise2;

	if (isSoft == true) {
		combinedNoise.a = combinedNoise.r;
		vec3 smoothed = smoothstep(threshold - 0.3, threshold + 0.3, combinedNoise).rgb;
		ALBEDO = smoothed * brightness * cloud_color;
		ALPHA = smoothstep(threshold - 0.3, threshold + 0.3, combinedNoise).a;
	}
	else {
		ALBEDO = combinedNoise.rgb * brightness * cloud_color;
		if (combinedNoise.r < threshold) {
			ALPHA = 0.0;
		}
		else {
			ALPHA = 1.0;
		}
	}

	// Ensure alpha is properly clamped
	ALPHA = clamp(ALPHA, 0.0, 1.0);
}