shader_type canvas_item;

// Nutzer-Wunsch: Unten an den Saeulenfuessen etwas dunkler, nach oben
// (Richtung Mitte der Hintergrund-Ebene) weich auslaufend.

uniform vec4 dark_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Wie dunkel es ganz unten wird (0 = gar nicht, 1 = voll dark_color).
uniform float strength : hint_range(0.0, 1.0) = 0.6;
// Ab welcher Hoehe (0 = oben, 1 = unten) die Abdunklung beginnt.
uniform float fade_start : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float a = smoothstep(fade_start, 1.0, UV.y) * strength;
	COLOR = vec4(dark_color.rgb, a);
}
