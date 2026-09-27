extends RefCounted
## Writes the existing hi_4d.json schema. No scene/UI dependencies or world baking.
const AXES = ["X", "Y", "Z", "W"]
const PLANES = ["XY", "XZ", "XW", "YZ", "YW", "ZW"]

static func transform_fields(sources: Dictionary, group: bool) -> Dictionary:
	var settings := {}
	for component in ["position", "anchor", "scale"]:
		if group and component == "scale":
			settings.scale = sources["scale.0"]
			continue
		settings[component] = {}
		for i in range(4): settings[component][AXES[i]] = sources["%s.%d" % [component,i]]
	settings.rotation = {}
	for i in range(6): settings.rotation[PLANES[i]] = sources["angles.%d" % i]
	return settings

static func serialize_shape(geometry, shape_name: String, geometry_sources: Dictionary, group_sources: Dictionary, projection_sources: Dictionary) -> Dictionary:
	var vertices := []
	for v in geometry.vertices: vertices.append([v.x,v.y,v.z,v.w])
	var edges := []
	for e in geometry.edges: edges.append([e.x,e.y])
	var settings := transform_fields(geometry_sources,false)
	settings.projection = []
	for row in range(3):
		var values := []
		for col in range(4): values.append(projection_sources["projection.%d" % (row*4+col)])
		settings.projection.append(values)
	return {"name":shape_name,"vertices":vertices,"edges":edges,"faces":geometry.faces.duplicate(true),
		"procedural_defaults":{"geometry":settings,"group":transform_fields(group_sources,true)}}

static func save(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data,"  ")+"\n")
	file.flush()
	var error := file.get_error()
	file.close()
	return error
