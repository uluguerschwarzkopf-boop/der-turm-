shader_type canvas_item;

// Nutzer-Wunsch: Statischer Schwarz-Verlauf nur auf dem Unterboden (bewegt sich
// nicht mit der Kamera). Oben an den Steinen leicht wellig und durchsichtig,
// nach unten wird er weich komplett schwarz - wie in Hollow Knight/Blasphemous.
// Liegt als ColorRect in der Welt über den Boden-Tiles.

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Ab welcher Höhe (0 = Oberkante des Rechtecks, 1 = Unterkante) es voll schwarz ist.
uniform float solid_from : hint_range(0.0, 1.0) = 0.55;
// Wie stark es ganz oben schon abdunkelt (0 = gar nicht).
uniform float top_strength : hint_range(0.0, 1.0) = 0.0;
// Wellige Oberkante: Höhe der Wellen (Anteil der Rechteckhöhe) und Breite.
uniform float wave_amount : hint_range(0.0, 0.5) = 0.12;
// Pixel pro Welle (in Weltpixeln, gemessen über die Rechteckbreite).
uniform float wave_width : hint_range(4.0, 200.0) = 40.0;
// Breite des Rechtecks in Weltpixeln (wird vom Editor nicht automatisch geliefert).
uniform float rect_width = 3200.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float x = UV.x * rect_width / wave_width;
	float wave = (noise1(x) * 0.65 + noise1(x * 2.3 + 7.1) * 0.35 - 0.5) * 2.0 * wave_amount;
	float y = UV.y + wave;
	float a = mix(top_strength, 1.0, smoothstep(0.0, solid_from, y));
	COLOR = vec4(color.rgb, clamp(a, 0.0, 1.0) * color.a);
}
