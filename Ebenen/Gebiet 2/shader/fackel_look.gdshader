shader_type canvas_item;

// Nutzer-Wunsch: Der Fackelhalter soll mit der Säule verschmelzen (gleich dunkel
// wie die Säule), nur die Flamme leuchtet. Deshalb werden nur die warmen,
// hellen Flammen-Pixel aufgehellt; der dunkle Halter bleibt wie er ist und wird
// genauso abgedunkelt wie die Säulen-Ebene.

// Aufhellung der Flamme (gleicht die Abdunklung der Hintergrund-Ebene aus).
uniform float flame_boost : hint_range(0.0, 20.0) = 8.0;
// Faktor für den Halter (1 = wie die Säule).
uniform float holder_mult : hint_range(0.0, 3.0) = 1.0;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Flamme = rot deutlich stärker als blau (orange/gelb).
	float flame = smoothstep(0.12, 0.35, c.r - c.b);
	c.rgb *= mix(holder_mult, flame_boost, flame);
	COLOR = c * modulate;
}
