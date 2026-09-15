shader_type spatial;
render_mode diffuse_burley;

varying vec3 local_point;
const float PHI = 1.618034;
const vec3 PATCHES[12] = {
	vec3(-1.0, PHI, 0.0), vec3(1.0, PHI, 0.0),
	vec3(-1.0, -PHI, 0.0), vec3(1.0, -PHI, 0.0),
	vec3(0.0, -1.0, PHI), vec3(0.0, 1.0, PHI),
	vec3(0.0, -1.0, -PHI), vec3(0.0, 1.0, -PHI),
	vec3(PHI, 0.0, -1.0), vec3(PHI, 0.0, 1.0),
	vec3(-PHI, 0.0, -1.0), vec3(-PHI, 0.0, 1.0)
};

void vertex() {
	local_point = VERTEX;
}

void fragment() {
	vec3 direction = normalize(local_point);
	float patch = 0.0;
	for (int i = 0; i < 12; i++) {
		vec3 axis = normalize(PATCHES[i]);
		float facing = dot(direction, axis);
		if (facing > 0.83) {
			vec3 right = normalize(cross(axis, vec3(0.0, 0.1, 1.0)));
			vec3 up = cross(right, axis);
			vec2 p = vec2(dot(direction, right), dot(direction, up)) / facing;
			float angle = atan(p.y, p.x) + 0.2;
			float sector = 6.2831853 / 5.0;
			float edge = cos(floor(0.5 + angle / sector) * sector - angle) * length(p);
			patch = max(patch, 1.0 - smoothstep(0.275, 0.29, edge));
		}
	}
	ALBEDO = mix(vec3(0.94, 0.92, 0.86), vec3(0.022, 0.032, 0.042), patch);
	ROUGHNESS = 0.68;
	SPECULAR = 0.25;
}
