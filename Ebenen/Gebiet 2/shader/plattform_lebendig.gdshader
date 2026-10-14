shader_type canvas_item;

// Nutzer-Wunsch: Die Lianen unter den Plattform-Bloecken wackeln subtil, als
// waeren sie eine lebendige Masse. Ausserdem leuchtet die helle Oberkante der
// Tiles auf, wenn der Spieler darueber laeuft.
//
// Liegt als Material auf den einzelnen Tiles von "Bloecke.png" (im TileSet),
// nicht auf der ganzen TileMap - so bleiben alle anderen Tiles unberuehrt.

// --- Lianen ---
// Maske im selben Aufbau wie Bloecke.png: Rot = wie stark ein Pixel schwingt
// (0 = starr, 1 = volle Bewegung). Wird per Skript aus der Grafik erzeugt.
uniform sampler2D sway_mask : filter_nearest, repeat_disable;
// Maximaler Ausschlag der Lianenspitzen in Pixeln.
uniform float sway_px : hint_range(0.0, 4.0) = 1.2;
// Sekunden fuer eine Schwingung.
uniform float sway_period : hint_range(0.5, 12.0) = 3.6;
// Wie unterschiedlich benachbarte Lianen schwingen (0 = alle im Gleichtakt).
uniform float sway_phase_spread : hint_range(0.0, 2.0) = 0.07;
// Nutzer-Wunsch: Bewegung wie in "Haengende Masse schwingen-Sheet.png":
// eine ruhige Links-Rechts-Welle in ganzen Pixelschritten.
// 0 = nur die eine ruhige Welle, 1 = zweite, unruhigere Welle voll dazu.
uniform float sway_wildness : hint_range(0.0, 1.0) = 0.0;
// An = Verschiebung auf ganze Pixel runden (sauberer Pixel-Look).
uniform bool sway_pixel_snap = true;

// --- Leuchtende Oberkante ---
// Fuss-Position des Spielers in Weltkoordinaten (setzt plattform_leuchten.gd).
uniform vec2 player_feet = vec2(-99999.0, -99999.0);
// 0 = aus, 1 = an. Wird vom Skript weich ein-/ausgeblendet (z. B. im Sprung aus).
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
// Wie weit um die Fuesse herum es leuchtet (Pixel).
uniform float glow_radius : hint_range(4.0, 120.0) = 30.0;
uniform float glow_strength : hint_range(0.0, 6.0) = 1.8;
uniform vec4 glow_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
// Ab welcher Helligkeit ein Pixel als "Oberkante" gilt. Der Tile-Koerper liegt
// darunter (gemessen: Kante ca. 0.40-0.54, Koerper meist unter 0.22).
uniform float glow_min_luma : hint_range(0.0, 1.0) = 0.27;

varying vec2 world_pos;
// COLOR wird unten ueberschrieben, deshalb das Modulate aus vertex() mitnehmen.
varying vec4 modulate;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	modulate = COLOR;
}

void fragment() {
	// Lianen: seitlich verschieben, gewichtet mit der Maske. Zwei ueberlagerte
	// Wellen, damit es organisch statt mechanisch wirkt.
	float w = texture(sway_mask, UV).r;
	float ph = world_pos.x * sway_phase_spread;
	float t = TIME * TAU / max(sway_period, 0.01);
	float s = mix(sin(t + ph), sin(t + ph) * 0.7 + sin(t * 1.63 + ph * 1.7 + 1.3) * 0.3, sway_wildness);
	float shift = s * sway_px * w;
	if (sway_pixel_snap) {
		shift = round(shift);
	}
	vec2 uv = UV - vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0);
	vec4 c = texture(TEXTURE, uv);

	// Oberkante: helle Pixel nahe an den Fuessen des Spielers aufhellen.
	float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	float edge = smoothstep(glow_min_luma, glow_min_luma + 0.12, luma);
	float near = 1.0 - smoothstep(0.0, glow_radius, distance(world_pos, player_feet));
	c.rgb += glow_color.rgb * edge * near * near * glow_strength * glow_amount;

	COLOR = c * modulate;
}
