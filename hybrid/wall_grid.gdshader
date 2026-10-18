shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 wall_color : source_color = vec4(0.22, 0.39, 0.53, 1.0);
varying vec3 surface_point;
varying vec3 surface_normal;
void vertex() {
	surface_point = VERTEX;
	surface_normal = NORMAL;
}
void fragment() {
	vec3 n = abs(normalize(surface_normal));
	vec2 uv = n.x > n.y && n.x > n.z ? surface_point.yz : (n.y > n.z ? surface_point.xz : surface_point.xy);
	vec2 edge = abs(fract(uv + 0.5) - 0.5);
	vec2 width = max(fwidth(uv), vec2(0.001));
	float line = 1.0 - min(smoothstep(0.008, 0.008 + width.x, edge.x), smoothstep(0.008, 0.008 + width.y, edge.y));
	float shade = dot(n, vec3(0.95, 0.60, 0.78));
	ALBEDO = wall_color.rgb * shade * mix(1.0, 0.55, line);
}
