extends RefCounted
## Whitelisted scalar math only: no strings, property access, objects, or scripts.
const FUNCTIONS = ["sin", "cos", "tan", "asin", "acos", "atan", "atan2", "abs", "sqrt", "pow", "exp", "log", "floor", "ceil", "round", "min", "max", "clamp", "lerp", "fmod", "sign", "deg_to_rad", "rad_to_deg"]
var expression := Expression.new()
var error := ""

func compile(source: String) -> bool:
	error = ""
	if source.length() > 512:
		error = "Expression is too long (512 characters maximum)."
		return false
	var whitespace := RegEx.new()
	whitespace.compile("\\s+")
	var clean := whitespace.sub(source, "", true)
	var tokens := RegEx.new()
	tokens.compile("(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[A-Za-z_][A-Za-z_0-9]*|[+*/%(),-]")
	var offset := 0
	for token in tokens.search_all(clean):
		if token.get_start() != offset:
			error = "Only scalar math expressions in t are allowed."
			return false
		offset = token.get_end()
		var text := token.get_string()
		if text[0].to_lower() >= "a" and text[0].to_lower() <= "z" or text.begins_with("_"):
			if text not in FUNCTIONS and text not in ["t", "PI", "TAU", "E"]:
				error = "Unknown name: " + text
				return false
	if offset != clean.length() or clean.is_empty():
		error = "Enter a number or a math expression in t."
		return false
	if expression.parse(clean, PackedStringArray(["t"])) != OK:
		error = expression.get_error_text()
		return false
	return true

func evaluate(time: float) -> Variant:
	var value = expression.execute([time], null, false, true)
	if expression.has_execute_failed() or not (value is float or value is int):
		error = "Expression must return a real number."
		return null
	if not is_finite(float(value)):
		error = "Result is not finite at t = %.3f." % time
		return null
	error = ""
	return float(value)
