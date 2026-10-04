shader_type canvas_item;

// --- Aussehen ---
uniform vec4 fog_color : source_color = vec4(0.42, 0.50, 0.66, 1.0);
// Hebt die Farbe an, um die Abdunklung durch das CanvasModulate auszugleichen.
// 1.0 = wie bisher, 3.0 = gut sichtbar trotz dunklem Raum.
uniform float brightness : hint_range(0.0, 8.0) = 1.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.40;
uniform int alpha_steps : hint_range(1, 8) = 3;

// --- Pixelraster: wie viele Nebel-Pixel über die Flaeche ---
uniform vec2 grid = vec2(192.0, 108.0);

// --- Form und Bewegung ---
uniform float noise_scale : hint_range(0.5, 12.0) = 3.0;
uniform vec2 drift = vec2(0.025, 0.006);
uniform float density : hint_range(0.0, 2.0) = 1.0;

// --- 0 = ueberall, 1 = nur unten ---
uniform float bottom_only : hint_range(0.0, 1.0) = 0.0;

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
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// 1) Koordinate aufs Pixelraster runden -> harte Kanten
	vec2 uv = floor(UV * grid) / grid;

	// 2) Rauschen, das ueber das feste Raster wandert
	vec2 p = uv * noise_scale + TIME * drift;
	float n = fbm(p) * density;

	// 3) Optional nach unten hin dichter
	float g = mix(1.0, smoothstep(0.15, 0.85, uv.y), bottom_only);

	// 4) Deckkraft in Stufen quantisieren -> Pixel-Art-Look
	float a = clamp(n * g, 0.0, 1.0);
	float s = float(alpha_steps);
	a = floor(a * s) / s;

	COLOR = vec4(fog_color.rgb * brightness, a * max_alpha);
}
