shader_type canvas_item;

// Full-screen cinematic vignette + faint scanline/grain texture for the
// "broadcast night" atmosphere (matches BroadcastHUD/FinishPodium's existing
// neon-downs identity). Self-contained — unlike glass_panel.gdshader this
// never reads screen_texture, since it sits UNDER foreground UI and must
// never blur anything drawn on top of it; it only darkens/textures whatever
// this CanvasItem's own quad would otherwise draw (see UITheme.make_vignette_overlay,
// which attaches this to a plain ColorRect and keeps rect_size in sync via
// the node's own `resized` signal, same pattern as the glass panel).

uniform vec4 edge_color : source_color = vec4(0.016, 0.024, 0.043, 1.0);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float scanline_strength : hint_range(0.0, 0.2) = 0.035;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.02;
uniform vec2 rect_size = vec2(1600.0, 900.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered = (UV - 0.5) * 2.0;
	centered.x *= rect_size.x / max(rect_size.y, 1.0);
	float dist = length(centered);
	float vignette = smoothstep(0.55, 1.35, dist) * vignette_strength;

	float scanline = sin(FRAGCOORD.y * 1.5) * 0.5 + 0.5;
	float grain = hash(FRAGCOORD.xy + fract(TIME * 60.0)) - 0.5;

	float alpha = clamp(vignette + scanline * scanline_strength + grain * grain_strength, 0.0, 1.0);
	COLOR = vec4(edge_color.rgb, alpha);
}
