shader_type canvas_item;
render_mode blend_add, unshaded;

// Statische, weiche Lichtbahnen, die schraeg von oben einfallen.
// Die Bahnen stehen fest - nur die Gesamthelligkeit atmet ganz leicht.

uniform vec4 ray_color : source_color = vec4(0.3, 0.42, 0.75, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.22;
// Schraege: 0 = senkrecht, positiv = nach rechts unten
uniform float slant : hint_range(-1.0, 1.0) = 0.35;
// Anzahl moeglicher Bahnen ueber die Breite
uniform float ray_count : hint_range(1.0, 20.0) = 6.0;
// Anteil der Bahnen, die leuchten
uniform float ray_chance : hint_range(0.0, 1.0) = 0.55;
uniform float ray_width : hint_range(0.05, 1.0) = 0.5;
// Wie weit die Bahnen nach unten reichen (1 = bis ganz unten)
uniform float reach : hint_range(0.1, 1.0) = 0.85;
// Atmen: Staerke (0 = ganz statisch) und Tempo
uniform float breathe_amount : hint_range(0.0, 0.5) = 0.08;
uniform float breathe_speed : hint_range(0.0, 1.0) = 0.12;

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float beam_at(float x) {
	float band = x * ray_count;
	float id = floor(band);
	float f = fract(band);
	float w = ray_width * (0.5 + hash1(id + 1.7));
	float d = abs(f - 0.5) / max(w * 0.5, 0.001);
	// weicher, gaussfoermiger Querschnitt
	float b = exp(-d * d * 2.5);
	b *= step(hash1(id + 9.3), ray_chance);
	// jede Bahn eigene, feste Grundhelligkeit
	return b * (0.6 + 0.4 * hash1(id + 4.1));
}

void fragment() {
	float x = UV.x - UV.y * slant;
	float beam = beam_at(x);

	float v = (1.0 - smoothstep(0.0, reach, UV.y)) * smoothstep(0.0, 0.08, UV.y);
	float side = smoothstep(0.0, 0.15, UV.x) * smoothstep(0.0, 0.15, 1.0 - UV.x);
	float breathe = 1.0 + breathe_amount * sin(TIME * breathe_speed * 6.2832);

	float a = clamp(beam * v * side * breathe, 0.0, 1.0);
	COLOR = vec4(ray_color.rgb, a * intensity);
}
