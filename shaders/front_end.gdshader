shader_type canvas_item;
// Front end screens: the texture holds palette indices (0..31), `palette` is a 32 x 1 colour strip
// that the fade engine rewrites while colours fade in and out.
uniform sampler2D palette : filter_nearest, repeat_disable;

void fragment() {
	int idx = int(texture(TEXTURE, UV).r * 255.0 + 0.5) & 31;
	COLOR = vec4(texelFetch(palette, ivec2(idx, 0), 0).rgb, 1.0);
}
