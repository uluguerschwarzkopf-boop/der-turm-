shader_type canvas_item;

// Nutzer-Wunsch: Flagge schwingt ganz schwach nach links und rechts,
// man soll es nur leicht sehen.
// Die Oberkante (Aufhaengung) bleibt fest, nach unten hin waechst der
// Ausschlag. Per Shader statt Sprite-Animation, damit kein neues Spritesheet
// noetig ist und Staerke/Tempo im Inspektor einstellbar bleiben.

// Maximaler seitlicher Ausschlag an der Unterkante, in Pixeln der Grafik.
uniform float amplitude_px : hint_range(0.0, 4.0) = 1.0;
// Schwingungen pro Sekunde. Klein halten, sonst wirkt es hektisch.
uniform float speed : hint_range(0.0, 2.0) = 0.25;
// Wie stark die Welle nach unten zeitversetzt laeuft (0 = starres Pendeln).
uniform float wave : hint_range(0.0, 6.0) = 1.5;
// Bereich der Flagge in der Grafik (UV y, 0 = oben, 1 = unten).
// Standard passt zu backgroundmockupFlaggenew.png (Pixel 29 bis 100 von 256).
uniform float top_v : hint_range(0.0, 1.0) = 0.113;
uniform float bottom_v : hint_range(0.0, 1.0) = 0.395;

// COLOR ist in fragment() schon mit der Textur multipliziert,
// deshalb das Modulate aus vertex() mitnehmen.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	float t = clamp((UV.y - top_v) / max(bottom_v - top_v, 0.0001), 0.0, 1.0);
	// Quadratisch: oben fast still, unten am meisten Bewegung.
	float bend = t * t;
	float sway = sin(TIME * speed * TAU - t * wave);
	float offset = sway * amplitude_px * bend * TEXTURE_PIXEL_SIZE.x;
	COLOR = texture(TEXTURE, UV - vec2(offset, 0.0)) * modulate;
}
