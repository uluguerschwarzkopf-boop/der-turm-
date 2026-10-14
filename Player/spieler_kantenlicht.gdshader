shader_type canvas_item;

// Nutzer-Wunsch: Der Spieler wird leicht von oben angeleuchtet - eine helle
// Kante oben auf Kopf/Kapuze und Schultern (Rim Light statt schwarzer Outline).
// Ein Pixel wird aufgehellt, wenn direkt darüber (bzw. schräg darüber) kein
// Pixel der Figur ist. Funktioniert automatisch mit jeder Animation und
// auch gespiegelt.

// Farbe des Lichts (warm-rot passt zum Umhang; heller = stärker).
uniform vec4 rim_color : source_color = vec4(1.0, 0.55, 0.5, 1.0);
// Über 1 möglich: gleicht die Raum-Abdunklung ("Darkness") aus.
uniform float rim_boost : hint_range(0.0, 6.0) = 2.5;
// Wie stark die Kante aufgehellt wird (0 = aus).
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
// Wie viele Pixel tief das Licht von der Oberkante in die Figur reicht.
uniform int rim_depth : hint_range(1, 3) = 1;
// Anteil der seitlichen Kanten (0 = nur von oben).
uniform float side_amount : hint_range(0.0, 1.0) = 0.35;
// Zusätzliches leichtes Aufhellen der oberen Körperhälfte (weicher Verlauf).
uniform float top_glow : hint_range(0.0, 1.0) = 0.12;

// COLOR enthält in fragment() schon die Textur; Modulate deshalb aus vertex().
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

float alpha_at(sampler2D tex, vec2 uv) {
	return texture(tex, uv).a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float rim = 0.0;
		for (int i = 1; i <= 3; i++) {
			if (i > rim_depth) { break; }
			float above = alpha_at(TEXTURE, UV - vec2(0.0, px.y * float(i)));
			rim = max(rim, (1.0 - step(0.5, above)) * (1.0 - float(i - 1) * 0.35));
		}
		float left = 1.0 - step(0.5, alpha_at(TEXTURE, UV - vec2(px.x, 0.0)));
		float right = 1.0 - step(0.5, alpha_at(TEXTURE, UV + vec2(px.x, 0.0)));
		float up_side = 1.0 - step(0.5, alpha_at(TEXTURE, UV - vec2(px.x, px.y)));
		up_side = max(up_side, 1.0 - step(0.5, alpha_at(TEXTURE, UV + vec2(px.x, -px.y))));
		rim = max(rim, max(max(left, right), up_side) * side_amount);
		// Leichter Verlauf: oben in der Region etwas heller.
		float grad = (1.0 - UV.y) * top_glow;
		c.rgb += rim_color.rgb * rim * rim_strength * rim_boost * max(c.r, 0.25) + c.rgb * grad;
	}
	COLOR = c * modulate;
}
