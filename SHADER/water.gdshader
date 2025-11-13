shader_type spatial;
render_mode blend_mix, depth_prepass_alpha,cull_back, diffuse_toon, specular_toon;

// Albedo color control
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Alpha scissor threshold
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// Metallic and roughness
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

// Texture (optional)
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	// Sample the texture
	vec4 albedo_tex = texture(texture_albedo, UV);
	
	// Apply albedo color
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	
	// Set alpha and alpha scissor threshold
	ALPHA = albedo.a * albedo_tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	
	// Set material properties
	METALLIC = metallic;
	ROUGHNESS = roughness;
}