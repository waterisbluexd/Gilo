shader_type canvas_item;

uniform float tolerance : hint_range(0.0, 1.0) = 0.05;

uniform bool swap_1_enabled = true;
uniform vec4 color_to_swap_1 : source_color;
uniform vec4 new_color_1 : source_color;

uniform bool swap_2_enabled = false;
uniform vec4 color_to_swap_2 : source_color;
uniform vec4 new_color_2 : source_color;

uniform bool swap_3_enabled = false;
uniform vec4 color_to_swap_3 : source_color;
uniform vec4 new_color_3 : source_color;

void fragment() {
    vec4 original_color = texture(TEXTURE, UV);
    vec4 final_color = original_color;

    if (swap_1_enabled) {
        float distance_1 = distance(original_color.rgb, color_to_swap_1.rgb);
        if (distance_1 < tolerance) {
            final_color = vec4(new_color_1.rgb, original_color.a);
        }
    }

    if (swap_2_enabled && final_color == original_color) {
        float distance_2 = distance(original_color.rgb, color_to_swap_2.rgb);
        if (distance_2 < tolerance) {
            final_color = vec4(new_color_2.rgb, original_color.a);
        }
    }

    if (swap_3_enabled && final_color == original_color) {
        float distance_3 = distance(original_color.rgb, color_to_swap_3.rgb);
        if (distance_3 < tolerance) {
            final_color = vec4(new_color_3.rgb, original_color.a);
        }
    }

    COLOR = final_color;
}