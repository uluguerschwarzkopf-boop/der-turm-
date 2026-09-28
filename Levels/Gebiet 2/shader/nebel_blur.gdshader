shader_type canvas_item;
render_mode unshaded;

// Weicher, kaltblauer Nebel. Er liest das Bild DAHINTER und zeichnet es
// dort, wo er dicht ist, weich und blau - bis es an dichten Stellen fast
// verschwindet. Wo kein Nebel ist, bleibt alles scharf und unveraendert.
//
// unshaded: Das Bild dahinter ist schon abgedunkelt und darf nicht ein
// zweites Mal durch "Darkness" laufen. fog_color ist die echte Endfarbe.
//
// Wichtig bei mehreren Nebellagen: vor jeder Lage ein BackBufferCopy-Node,
// sonst sieht die zweite Lage nicht, was zwischen den Lagen gezeichnet wurde.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec4 fog_color : source_color = vec4(0.12, 0.17, 0.3, 1.0);
// Wie stark der Nebel an seinen dichtesten Stellen zudeckt (1 = komplett)
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;
// Wie stark das Bild dahinter weichgezeichnet wird (Mip-Stufen)
uniform float blur_strength : hint_range(0.0, 6.0) = 3.0;
// Wie stark das Bild dahinter ins Kaltblaue gezogen wird
uniform float cool_tint : hint_range(0.0, 1.0) = 0.5;
// Hoeher = weniger Nebel, mehr Luecken. 0.3 = fast ueberall, 0.6 = nur Fetzen
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float softness : hint_range(0.01, 0.6) = 0.3;

uniform float noise_scale : hint_range(0.5, 12.0) = 2.5;
uniform vec2 drift = vec2(0.006, 0.0015);
// 0 = ueberall gleich, 1 = nur unten
uniform float bottom_bias : hint_range(0.0, 1.0) = 0.3;
// weiche Raender der Flaeche
uniform float edge_fade : hint_range(0.0, 0.4) = 0.12;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// y gestaucht, damit die Schwaden breit und flach liegen wie echter Bodennebel
	vec2 p = UV * noise_scale * vec2(1.0, 0.45) + TIME * drift;
	float n = fbm(p);

	float f = smoothstep(coverage, coverage + softness, n);
	f *= mix(1.0, smoothstep(0.0, 1.0, UV.y), bottom_bias);

	float e = smoothstep(0.0, edge_fade, UV.x) * smoothstep(0.0, edge_fade, 1.0 - UV.x)
	        * smoothstep(0.0, edge_fade, UV.y) * smoothstep(0.0, edge_fade, 1.0 - UV.y);
	f *= e;

	vec3 behind = textureLod(screen_tex, SCREEN_UV, f * blur_strength).rgb;
	// Bild dahinter ins Kaltblaue ziehen, ohne die Helligkeit zu verlieren
	float l = dot(behind, vec3(0.2126, 0.7152, 0.0722));
	vec3 cooled = mix(behind, vec3(l) * vec3(0.7, 0.85, 1.35), cool_tint * f);

	COLOR = vec4(mix(cooled, fog_color.rgb, f * max_alpha), 1.0);
}
