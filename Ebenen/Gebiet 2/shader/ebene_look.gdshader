shader_type canvas_item;

// Look einer einzelnen Parallax-Ebene: Helligkeit, Saettigung, Farbstich, Blur.
// Hintere Ebenen: dunkler Dunst, wenig Farbe, weich.
// Vordere Ebenen: Silhouetten, mehr Farbe, scharf.

// Gleicht die Abdunklung durch "Darkness" aus. Ersetzt das fruehere Modulate.
uniform float brightness : hint_range(0.0, 6.0) = 1.0;
// 0 = grau, 1 = Originalfarbe
uniform float saturation : hint_range(0.0, 1.5) = 1.0;
// Farbstich, z. B. kaltes Blau fuer Ferne
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
// Blur-Radius in Pixeln der Grafik. 0 = scharf.
uniform float blur_radius : hint_range(0.0, 4.0) = 0.0;
// 0 = scharf, 1 = voll geblurt. Fuer Zwischenstufen.
uniform float blur_mix : hint_range(0.0, 1.0) = 1.0;

vec4 sample_blur(sampler2D tex, vec2 uv, vec2 px, float r) {
	// 5x5 Gauss, vormultipliziert, damit transparente Raender nicht dunkel ausfransen
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = exp(-float(x * x + y * y) / 3.0);
			vec4 s = texture(tex, uv + vec2(float(x), float(y)) * px * r);
			acc.rgb += s.rgb * s.a * w;
			acc.a += s.a * w;
			wsum += w;
		}
	}
	vec3 rgb = acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0);
	return vec4(rgb, acc.a / wsum);
}

void fragment() {
	vec4 sharp = texture(TEXTURE, UV);
	vec4 c = sharp;
	if (blur_radius > 0.01 && blur_mix > 0.001) {
		vec4 soft = sample_blur(TEXTURE, UV, TEXTURE_PIXEL_SIZE, blur_radius);
		c = mix(sharp, soft, blur_mix);
	}

	float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	c.rgb = mix(vec3(l), c.rgb, saturation);
	c.rgb = mix(c.rgb, vec3(l) * tint.rgb * 1.6, tint_amount);
	c.rgb *= brightness;

	COLOR = c;
}
