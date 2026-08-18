shader_type canvas_item;

// Frosted-glass panel: blurred backbuffer + tint + rounded corners + a thin
// bright border, all drawn in one shader rather than a StyleBoxFlat +
// separate blur layer — the rounded-corner clip and the blur need to share
// the exact same shape, and Godot has no built-in way to clip one sibling
// node's content to another's rounded corners. `rect_size` must be kept in
// sync with the node's actual pixel size (see UITheme.make_glass_panel,
// which wires this to the node's own `resized` signal) since a canvas_item
// shader has no built-in way to read its own node's size.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.06, 0.09, 0.14, 0.6);
uniform vec4 border_color : source_color = vec4(0.2, 0.88, 0.98, 0.85);
uniform float border_width : hint_range(0.0, 6.0) = 1.5;
uniform float corner_radius : hint_range(0.0, 64.0) = 16.0;
uniform float blur_amount : hint_range(0.0, 8.0) = 3.0;
uniform vec2 rect_size = vec2(200.0, 100.0);

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = (UV - 0.5) * rect_size;
	float d = sd_round_box(px, rect_size * 0.5, corner_radius);

	vec4 blurred = vec4(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 offset = vec2(float(x), float(y)) * blur_amount * SCREEN_PIXEL_SIZE;
			blurred += textureLod(screen_texture, SCREEN_UV + offset, 3.0);
			total += 1.0;
		}
	}
	blurred /= total;

	vec3 tinted = mix(blurred.rgb, tint.rgb, tint.a);

	float aa = max(fwidth(d), 0.001);
	float inside_mask = 1.0 - smoothstep(-aa, aa, d);
	float border_mask = smoothstep(-border_width - aa, -border_width + aa, d) * inside_mask;

	vec3 color = mix(tinted, border_color.rgb, border_mask * border_color.a);
	COLOR = vec4(color, inside_mask);
}
