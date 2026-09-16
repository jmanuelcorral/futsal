shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 primary_color : source_color = vec4(0.090, 0.184, 0.302, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.098, 0.180, 0.263, 1.0);
uniform vec4 accent_color : source_color = vec4(0.933, 0.910, 0.847, 1.0);
uniform vec4 trim_color : source_color = vec4(0.933, 0.910, 0.847, 1.0);
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo_map = false;
uniform bool has_normal_map = false;
uniform bool has_roughness_map = false;
uniform bool has_ao_map = false;
uniform bool ao_uses_uv2 = false;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.0;
uniform float fabric_roughness : hint_range(0.0, 1.0) = 0.84;
uniform float fabric_normal_strength : hint_range(0.0, 2.0) = 0.6;

void fragment() {
	vec4 weights = max(COLOR, vec4(0.0));
	weights /= max(dot(weights, vec4(1.0)), 0.0001);
	vec3 fabric_color = primary_color.rgb * weights.r
		+ secondary_color.rgb * weights.g
		+ accent_color.rgb * weights.b
		+ trim_color.rgb * weights.a;
	vec3 fabric_detail = has_albedo_map ? texture(albedo_map, UV).rgb : vec3(1.0);
	ALBEDO = fabric_color * fabric_detail;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	ROUGHNESS = has_roughness_map
		? clamp(dot(texture(roughness_map, UV), roughness_channel) * fabric_roughness, 0.60, 1.0)
		: fabric_roughness;
	AO = has_ao_map ? dot(texture(ao_map, ao_uses_uv2 ? UV2 : UV), ao_channel) : 1.0;
	AO_LIGHT_AFFECT = ao_light_affect;
	if (has_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = fabric_normal_strength;
	}
}
