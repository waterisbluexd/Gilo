shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Water appearance
uniform vec4 water_color : source_color = vec4(0.1, 0.3, 0.6, 1.0);
uniform vec4 deep_water_color : source_color = vec4(0.0, 0.1, 0.3, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);

// Foam/Edge settings
uniform float foam_distance : hint_range(0.0, 5.0) = 1.5;
uniform float foam_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float foam_smoothness : hint_range(0.001, 0.5) = 0.1;
uniform float edge_wave_speed : hint_range(0.0, 3.0) = 1.5;
uniform float edge_wave_scale : hint_range(0.1, 5.0) = 2.0;

// Visual properties
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

// Water mask - CRITICAL: controls where water is rendered
uniform sampler2D water_mask : hint_default_white;
uniform float mask_threshold : hint_range(0.0, 1.0) = 0.5;

// Simple noise function
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Smoother noise with interpolation
float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = noise(i);
    float b = noise(i + vec2(1.0, 0.0));
    float c = noise(i + vec2(0.0, 1.0));
    float d = noise(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise for more organic patterns
float fractal_noise(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 4; i++) {
        value += amplitude * smooth_noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

void fragment() {
    // CRITICAL: Sample the water mask first
    float mask = texture(water_mask, UV).r;
    
    // Discard pixels that aren't water (beach/land areas)
    if (mask < mask_threshold) {
        discard;
    }
    
    vec2 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
    float time = TIME * edge_wave_speed;
    
    // Calculate edge distance from mask (for foam)
    // Sample nearby mask pixels to detect edges
    float mask_edge = 0.0;
    float sample_offset = 0.02; // Adjust for edge detection sensitivity
    
    float m_up = texture(water_mask, UV + vec2(0.0, sample_offset)).r;
    float m_down = texture(water_mask, UV + vec2(0.0, -sample_offset)).r;
    float m_left = texture(water_mask, UV + vec2(-sample_offset, 0.0)).r;
    float m_right = texture(water_mask, UV + vec2(sample_offset, 0.0)).r;
    
    // Edge detected if any neighbor is below threshold
    if (m_up < mask_threshold || m_down < mask_threshold || 
        m_left < mask_threshold || m_right < mask_threshold) {
        mask_edge = 1.0;
    }
    
    // Animated foam pattern using fractal noise
    float foam_noise = fractal_noise(world_pos * edge_wave_scale + vec2(time * 0.3, time * 0.2));
    foam_noise += smooth_noise(world_pos * edge_wave_scale * 2.0 - vec2(time * 0.5, time * 0.4)) * 0.5;
    
    // Create foam at edges with animated threshold
    float foam_threshold = foam_cutoff + sin(time * 2.0) * 0.1;
    float foam = smoothstep(foam_threshold - foam_smoothness, 
                           foam_threshold + foam_smoothness, 
                           foam_noise);
    
    // Apply foam only at edges
    foam *= mask_edge;
    
    // Animate foam movement
    float foam_wave = sin(world_pos.x * 3.0 + time * 2.0) * 
                     cos(world_pos.y * 3.0 - time * 1.5) * 0.5 + 0.5;
    foam *= foam_wave * 0.5 + 0.5;
    
    // Base water color
    vec3 water_col = water_color.rgb;
    
    // Add foam color at edges
    vec3 final_color = mix(water_col, foam_color.rgb, foam);
    
    // Apply subtle color variation
    float color_variation = smooth_noise(world_pos * 0.5 + vec2(time * 0.1)) * 0.05;
    final_color += color_variation;
    
    ALBEDO = final_color;
    ROUGHNESS = roughness - foam * 0.3; // Foam is rougher
    METALLIC = metallic;
    SPECULAR = specular + foam * 0.2; // Foam is more specular
    ALPHA = 1.0; // Fully opaque
}