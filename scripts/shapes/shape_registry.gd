extends RefCounted
## Add one entry here after implementing a Shape4D-derived generator.
## IDs are stable cache keys; display names are independent UI labels.
const ENTRIES = [
	{"id": "tesseract", "name": "Tesseract (8-cell)", "script": preload("res://scripts/shapes/tesseract.gd")},
	{"id": "hypersphere", "name": "Hypersphere (sampled)", "script": preload("res://scripts/shapes/hypersphere.gd")},
	{"id": "simplex", "name": "5-cell (simplex)", "script": preload("res://scripts/shapes/simplex.gd")},
	{"id": "cell16", "name": "16-cell", "script": preload("res://scripts/shapes/cell16.gd")},
	{"id": "cell24", "name": "24-cell", "script": preload("res://scripts/shapes/cell24.gd")},
	{"id": "cell120", "name": "120-cell", "script": preload("res://scripts/shapes/cell120.gd")},
	{"id": "cell600", "name": "600-cell", "script": preload("res://scripts/shapes/cell600.gd")},
]
static func create(index: int):
	return ENTRIES[index]["script"].new()
