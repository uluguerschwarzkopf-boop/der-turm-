shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 glow_color : source_color = vec4(1.0, 0.76, 0.40, 1.0);
uniform float pixel_size = 1.0;
uniform float dot_radius : hint_range(0.1, 1.0) = 0.45;
uniform int alpha_steps : hint_range(1, 6) = 2;
uniform float flicker : hint_range(0.0, 1.0) = 0.4;
uniform float flicker_speed = 5.0;

varying float seed;

void vertex() {
	// Zufallswert pro Partikel hier abgreifen und weiterreichen
	seed = INSTANCE_CUSTOM.y * 29.0 + INSTANCE_CUSTOM.x * 7.0;

	// Partikel-Mittelpunkt aufs Weltpixelraster runden
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	vec2 snapped = floor(origin / pixel_size + 0.5) * pixel_size;
	vec2 delta = snapped - origin;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(delta, 0.0, 0.0)).xy;
}

void fragment() {
	float d = length(UV - vec2(0.5));
	float a = 1.0 - smoothstep(dot_radius * 0.5, dot_radius, d);

	a *= 1.0 - flicker * (0.5 + 0.5 * sin(TIME * flicker_speed + seed));
	a *= COLOR.a;

	float s = float(alpha_steps);
	a = floor(a * s + 0.5) / s;

	COLOR = vec4(glow_color.rgb * COLOR.rgb, a);
} 
