shader_type canvas_item;
// Draws a colour-index texture (R = index 0..31, A = mask) through a per-scanline palette
// (32 x 320 texture, one row per Amiga video line) so Copper gradients work like on the real hardware.

uniform sampler2D palette : filter_nearest, repeat_disable;
uniform int line_offset = 40; // Amiga video line of viewport row 0

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	int idx = int(t.r * 255.0 + 0.5) & 31;
	int row = clamp(int(FRAGCOORD.y) + line_offset, 0, 319);
	vec3 c = texelFetch(palette, ivec2(idx, row), 0).rgb;
	COLOR = vec4(c * COLOR.rgb, t.a * COLOR.a);  // COLOR holds modulate on entry
}
