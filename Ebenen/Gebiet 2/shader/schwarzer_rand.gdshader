shader_type canvas_item;

// Nutzer-Wunsch: Bild laeuft an den Raendern ins komplette Schwarz aus, wie in
// Hollow Knight / Blasphemous (unten unter dem Boden am staerksten, oben und
// seitlich schwaecher). Liegt als Vollbild-ColorRect ueber dem Spiel, aber
// unter dem HUD. Die Kante ist leicht unregelmaessig, damit es nicht wie ein
// gerader Balken aussieht - weich, nie pixelig.

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Wie weit das Schwarz von jedem Rand ins Bild reicht (Anteil der Bildhoehe
// bzw. -breite). 0 = aus.
uniform float bottom_size : hint_range(0.0, 0.6) = 0.2;
uniform float top_size : hint_range(0.0, 0.6) = 0.2;
uniform float side_size : hint_range(0.0, 0.6) = 0.1;
// Wie stark jeder Rand maximal abdunkelt (1 = komplett schwarz am Rand).
uniform float bottom_strength : hint_range(0.0, 1.0) = 1.0;
uniform float top_strength : hint_range(0.0, 1.0) = 0.85;
uniform float side_strength : hint_range(0.0, 1.0) = 0.7;
// Anteil der Randzone, der ganz aussen voll schwarz bleibt, bevor es ausblendet.
uniform float solid_part : hint_range(0.0, 0.9) = 0.3;
// Unregelmaessige Kante: Staerke und Groesse der Wellen.
uniform float edge_noise : hint_range(0.0, 0.3) = 0.05;
uniform float edge_noise_scale : hint_range(0.5, 20.0) = 5.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float band(float dist, float size, float strength) {
	if (size <= 0.0001) {
		return 0.0;
	}
	// dist = Abstand zum Rand (0 = am Rand). Aussen voll, nach innen weich aus.
	return (1.0 - smoothstep(size * solid_part, size, dist)) * strength;
}

void fragment() {
	float n = (value_noise(UV * vec2(edge_noise_scale * 1.8, edge_noise_scale)) - 0.5) * 2.0 * edge_noise;
	float a = band(1.0 - UV.y + n, bottom_size, bottom_strength);
	a = max(a, band(UV.y + n, top_size, top_strength));
	a = max(a, band(UV.x + n, side_size, side_strength));
	a = max(a, band(1.0 - UV.x + n, side_size, side_strength));
	COLOR = vec4(color.rgb, a * color.a);
}
