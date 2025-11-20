shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque;

// Grid and cell controls
uniform float grid_size : hint_range(4.0, 128.0) = 32.0;

// Noise texture for foam animation
uniform sampler2D noise_texture : hint_default_white;
uniform vec2 noise_tiling = vec2(2.0, 2.0);
uniform float speed : hint_range(0.0, 1.0) = 0.1;
uniform float fluffiness : hint_range(0.0, 2.0) = 0.5;

// Foam appearance
uniform float foam_threshold : hint_range(0.0, 2.0) = 0.7;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.8;
uniform float foam_smoothness : hint_range(0.0, 0.5) = 0.1;

// Colors
uniform vec4 base_color : source_color = vec4(0.15, 0.35, 0.6, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);

// Overall opacity and alpha mask
uniform float overall_opacity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D alpha_mask : hint_default_white;

void fragment() {
    // Sample alpha mask
    float mask = texture(alpha_mask, UV).r;
    
    // Subdivide UVs into grid cells
    vec2 grid_uv = UV * grid_size;
    vec2 cell_id = floor(grid_uv);
    vec2 cell_uv = fract(grid_uv);
    
    // Base noise UV for this cell
    vec2 base_noise_uv = (cell_id / grid_size) * noise_tiling;
    
    // Sample noise twice with different speeds (like cloud shader)
    float noise1 = texture(noise_texture, base_noise_uv + TIME * 2.5 * speed / 10.0).r;
    float noise2 = texture(noise_texture, base_noise_uv + TIME * (2.5 + fluffiness * 3.0) * speed / 10.0).r;
    
    // Combine the two noise samples
    float combined_noise = noise1 + noise2;
    
    // Create foam highlights using smoothstep on combined noise
    float foam_mask = smoothstep(
        foam_threshold - foam_smoothness,
        foam_threshold + foam_smoothness,
        combined_noise
    );
    
    // Apply foam strength
    foam_mask *= foam_strength;
    
    // Mix base color with foam color
    vec3 final_color = mix(base_color.rgb, foam_color.rgb, foam_mask);
    
    // Calculate final alpha
    float final_alpha = base_color.a * overall_opacity * mask;
    
    // Output
    ALBEDO = final_color;
    ALPHA = final_alpha;
}