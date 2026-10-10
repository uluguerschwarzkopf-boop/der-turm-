shader_type canvas_item;

// ============================================================
// HINWEIS
// ============================================================

// Periodisches, diagonales Glänzen über der Kisten-Textur, wie bei
// Terraria-Items/Münzen - ein heller Streifen läuft in Abständen
// einmal diagonal über die Kiste und verschwindet wieder. Wird auf
// das AnimatedSprite2D der jeweiligen Kiste gelegt (siehe chest.gd,
// shine_enabled wird beim Öffnen automatisch ausgeschaltet). Die
// Farbe (shine_color) wird pro Kisten-Typ passend gesetzt (Gold/
// Silber/Bronze) - siehe die material-Overrides in den jeweiligen
// *_chest.tscn Dateien.

uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shine_width : hint_range(0.02, 1.0) = 0.16;
uniform float shine_interval : hint_range(0.5, 10.0) = 2.6;
uniform float shine_duration : hint_range(0.1, 5.0) = 0.7;
uniform bool shine_enabled = true;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = tex_color;

	if (!shine_enabled) {
		return;
	}

	float cycle_time = mod(TIME, shine_interval);

	if (cycle_time > shine_duration) {
		return;
	}

	float progress = cycle_time / shine_duration;

	// Diagonale Koordinate (oben-links -> unten-rechts).
	float diagonal = (UV.x + UV.y) * 0.5;

	// Position des wandernden Streifens, läuft leicht ausserhalb
	// der Textur los und endet leicht ausserhalb, damit er weich
	// rein- und rauslaeuft statt hart abzuschneiden.
	float band_position = mix(-shine_width, 1.0 + shine_width, progress);

	float distance_to_band = abs(diagonal - band_position);
	float intensity = smoothstep(shine_width, 0.0, distance_to_band);

	// Nur innerhalb der sichtbaren Kisten-Silhouette glänzen lassen.
	intensity *= tex_color.a;

	COLOR.rgb += shine_color.rgb * intensity * shine_color.a;
}
