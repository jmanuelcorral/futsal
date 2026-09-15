shader_type spatial;
render_mode diffuse_burley;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 meters = (UV - 0.5) * vec2(48.0, 28.0);
	float row = floor(meters.y / 0.21);
	float stagger = hash(vec2(row, 5.0)) * 2.4;
	vec2 plank = vec2((meters.x + stagger) / 2.4, meters.y / 0.21);
	float shade = hash(floor(plank));
	// --- Juntas con anchura adaptativa por derivadas ---
	// fwidth(plank) da el tamaño de píxel en espacio-tablón.
	// sw como umbral bajo de smoothstep garantiza ≥1 px de ancho por junta,
	// eliminando el parpadeo al mover la cámara sin borrar las líneas de cerca.
	vec2 seam = min(fract(plank), 1.0 - fract(plank));
	float pw = max(fwidth(plank.x), fwidth(plank.y));
	float sw = max(pw * 1.6, 0.0035);
	float joint = 1.0 - smoothstep(0.0, sw, min(seam.x, seam.y * 0.28));

	// --- Veta de madera con fade derivativo automático ---
	// K = 50 → período 12.6 cm (escala de fibra de madera dura real).
	// grain_fade → 0 cuando la frecuencia supera π rad/px (medio ciclo/píxel),
	// eliminando el shimmer en distancia sin suprimir la veta en primer plano.
	const float K = 50.0;
	float grain_raw = sin(meters.y * K + sin(meters.x * 0.85 + row * 0.71) * 1.15);
	float grain_px = length(vec2(dFdx(meters.y * K), dFdy(meters.y * K)));
	float grain_fade = clamp((PI - grain_px) / PI, 0.0, 1.0);
	float grain = grain_raw * grain_fade;

	vec3 wood = mix(vec3(0.49, 0.31, 0.16), vec3(0.64, 0.45, 0.25), shade);
	wood *= 1.0 + grain * 0.022 - joint * 0.09;
	float court = step(abs(meters.x), 20.045) * step(abs(meters.y), 10.045);
	ALBEDO    = mix(vec3(0.013, 0.055, 0.074), pow(wood, vec3(2.2)), court);
	ROUGHNESS = mix(0.82, clamp(0.33 + shade * 0.09, 0.33, 0.42), court);
	METALLIC  = 0.0;
	SPECULAR  = 0.28;
}
