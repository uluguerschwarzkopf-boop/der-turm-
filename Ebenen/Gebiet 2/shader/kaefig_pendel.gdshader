shader_type canvas_item;

// Nutzer-Wunsch: Die haengenden Kaefige im Vordergrund pendeln ganz leicht.
//
// Enthaelt denselben Look/Blur wie ebene_look.gdshader, damit die Kaefige
// weiter weichgezeichnet bleiben (vorher lag ebene_look auf dem Sprite).
//
// Pendeln: Die Pixel werden seitlich verschoben, je weiter unten, desto mehr.
// Die Aufhaengung oben bleibt fest. Bei so kleinen Ausschlaegen sieht das wie
// eine echte Drehung um den Aufhaengepunkt aus.
// Die Grafik enthaelt zwei Kaefige. split_u trennt sie, damit jeder fuer sich
// starr pendelt und beide nicht im Gleichtakt schwingen.

// --- Look (wie ebene_look) ---
uniform float brightness : hint_range(0.0, 6.0) = 1.0;
uniform float saturation : hint_range(0.0, 1.5) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
// Blur-Radius in Pixeln der Grafik. 0 = scharf.
uniform float blur_radius : hint_range(0.0, 4.0) = 0.0;
// 0 = scharf, 1 = voll geblurt.
uniform float blur_mix : hint_range(0.0, 1.0) = 1.0;

// --- Pendeln ---
// Maximaler Ausschlag am unteren Ende, in Pixeln der Grafik.
uniform float swing_px : hint_range(0.0, 4.0) = 0.6;
// Sekunden fuer eine komplette Schwingung (hin und zurueck).
uniform float period : hint_range(0.5, 20.0) = 5.0;
// Aufhaengepunkt und unteres Ende (UV y, 0 = oben, 1 = unten).
// Standard passt zu backgroundmockupVordergrund2.png (Pixel 9 bis 121 von 256).
uniform float pivot_v : hint_range(0.0, 1.0) = 0.035;
uniform float bottom_v : hint_range(0.0, 1.0) = 0.475;
// Trennlinie zwischen linkem und rechtem Kaefig (UV x).
uniform float split_u : hint_range(0.0, 1.0) = 0.5;
// Rechter Kaefig: andere Startphase und etwas anderer Takt.
uniform float right_phase : hint_range(0.0, 6.3) = 2.2;
uniform float right_speed : hint_range(0.5, 2.0) = 1.13;

void fragment() {
	bool right = UV.x >= split_u;
	float spd = right ? right_speed : 1.0;
	float ph = right ? right_phase : 0.0;
	// 0 an der Aufhaengung, 1 am unteren Ende
	float t = clamp((UV.y - pivot_v) / max(bottom_v - pivot_v, 0.0001), 0.0, 1.2);
	float s = sin(TIME * TAU / max(period, 0.01) * spd + ph);
	vec2 uv = UV - vec2(swing_px * s * t * TEXTURE_PIXEL_SIZE.x, 0.0);

	vec4 sharp = texture(TEXTURE, uv);
	vec4 c = sharp;
	if (blur_radius > 0.01 && blur_mix > 0.001) {
		// 5x5 Gauss, vormultipliziert, damit transparente Raender nicht dunkel ausfransen.
		// Direkt hier statt in einer Funktion: TEXTURE als Funktionsargument
		// erzeugt im Headless-Test einen Shader-Compiler-Fehler.
		vec4 acc = vec4(0.0);
		float wsum = 0.0;
		for (int x = -2; x <= 2; x++) {
			for (int y = -2; y <= 2; y++) {
				float w = exp(-float(x * x + y * y) / 3.0);
				vec4 smp = texture(TEXTURE, uv + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * blur_radius);
				acc.rgb += smp.rgb * smp.a * w;
				acc.a += smp.a * w;
				wsum += w;
			}
		}
		vec3 rgb = acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0);
		c = mix(sharp, vec4(rgb, acc.a / wsum), blur_mix);
	}

	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	c.rgb = mix(vec3(l), c.rgb, saturation);
	c.rgb = mix(c.rgb, vec3(l) * tint.rgb * 1.6, tint_amount);
	c.rgb *= brightness;

	COLOR = c;
}
