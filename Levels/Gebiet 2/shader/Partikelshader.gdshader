shader_type canvas_item;
render_mode blend_add, unshaded;

// Weiche, leuchtende Staubpunkte.

// Farbe: kaltes, blasses Blau
uniform vec4 glow_color : source_color = vec4(0.7, 0.82, 1.0, 1.0);
// Ueber 1.0 = hell genug, dass der Glow einen Schein legt
uniform float intensity : hint_range(0.0, 4.0) = 1.3;
// Groesse des hellen Kerns innerhalb des Punkts (0.1 = winzig, 1 = ganze Flaeche)
uniform float core : hint_range(0.05, 1.0) = 0.35;
uniform float flicker : hint_range(0.0, 1.0) = 0.35;
uniform float flicker_speed = 1.5;

varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.y * 29.0 + INSTANCE_CUSTOM.x * 7.0;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	// weicher Punkt: heller Kern, sanfter Hof
	float a = exp(-pow(d / core, 2.0) * 1.5) * (1.0 - smoothstep(0.7, 1.0, d));

	a *= 1.0 - flicker * (0.5 + 0.5 * sin(TIME * flicker_speed + seed));
	a *= COLOR.a;

	COLOR = vec4(glow_color.rgb * intensity, a);
}
