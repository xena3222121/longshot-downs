extends SceneTree

## Dev tool, not part of the game: run with
##   godot --headless --path . --script res://scripts/tools/generate_podium_girls.gd
## Generates two flat cutout-card PNGs for FinishPodium's victory celebration
## (AJ: "bikini girls added into the victory sequence... the flat stuff") —
## same pure-Image-pixel-drawing technique as generate_crowd_billboard.gd/
## generate_achievement_icons.gd (no font/SubViewport rendering dependency,
## no license risk from a sourced photo), just an abstract blob-figure
## instead of a detailed model — this project's whole art style is already
## simple geometric primitives (ellipses/boxes), not detailed humanoid
## rendering anywhere (not even the jockeys are modeled), so a stylized
## cutout is the right fidelity level, not a corner cut.

const OUT_DIR: String = "res://assets/textures/"
const WIDTH: int = 220
const HEIGHT: int = 340

const SKIN_TONES: Array[Color] = [
	Color(0.94, 0.76, 0.62), Color(0.82, 0.6, 0.44), Color(0.55, 0.36, 0.24),
]

## Two distinct color schemes so the two flanking figures don't read as
## identical copy-pasted twins.
const VARIANTS: Array[Dictionary] = [
	{"file": "podium_girl_1.png", "bikini": Color(0.85, 0.15, 0.35), "hair": Color(0.2, 0.12, 0.08), "skin_index": 0},
	{"file": "podium_girl_2.png", "bikini": Color(0.15, 0.55, 0.75), "hair": Color(0.75, 0.55, 0.2), "skin_index": 1},
]

func _init() -> void:
	for variant in VARIANTS:
		_generate(variant)
	quit()

func _generate(variant: Dictionary) -> void:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0)) # transparent cutout, not a rectangle card

	var skin: Color = SKIN_TONES[variant.skin_index]
	var bikini: Color = variant.bikini
	var hair: Color = variant.hair
	var cx: float = WIDTH * 0.5

	# Legs (hip to ankle).
	_fill_ellipse(image, cx - 18.0, 250.0, 16.0, 70.0, skin)
	_fill_ellipse(image, cx + 18.0, 250.0, 16.0, 70.0, skin)

	# Torso.
	_fill_ellipse(image, cx, 170.0, 34.0, 55.0, skin)

	# Raised cheering arms — a simple angled chain of ellipses per arm
	# rather than a rotated rectangle, same "just stack circles/ellipses"
	# idiom generate_crowd_billboard.gd already uses for shoulders.
	for side in [-1.0, 1.0]:
		for t in range(4):
			var frac: float = float(t) / 3.0
			var ax: float = cx + side * lerp(30.0, 70.0, frac)
			var ay: float = lerp(150.0, 90.0, frac)
			_fill_ellipse(image, ax, ay, 11.0, 13.0, skin)

	# Bikini bottom + top — the actual garment shapes, drawn last so they
	# sit on top of the torso/leg skin underneath.
	_fill_ellipse(image, cx, 210.0, 30.0, 16.0, bikini)
	_fill_ellipse(image, cx - 20.0, 140.0, 15.0, 11.0, bikini)
	_fill_ellipse(image, cx + 20.0, 140.0, 15.0, 11.0, bikini)

	# Head + hair.
	_fill_ellipse(image, cx, 90.0, 26.0, 28.0, skin)
	_fill_ellipse(image, cx, 68.0, 30.0, 22.0, hair)
	_fill_ellipse(image, cx - 26.0, 95.0, 10.0, 30.0, hair)
	_fill_ellipse(image, cx + 26.0, 95.0, 10.0, 30.0, hair)

	var out_path: String = OUT_DIR + String(variant.file)
	var err: Error = image.save_png(out_path)
	print("generate_podium_girls: save_png -> %s (err=%s)" % [out_path, err])

## Same local-bounding-box filled-ellipse helper as generate_crowd_billboard.gd.
func _fill_ellipse(image: Image, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	var x0: int = int(floor(cx - rx))
	var x1: int = int(ceil(cx + rx))
	var y0: int = int(floor(cy - ry))
	var y1: int = int(ceil(cy + ry))
	for py in range(max(y0, 0), min(y1, HEIGHT)):
		for px in range(max(x0, 0), min(x1, WIDTH)):
			var nx: float = (float(px) + 0.5 - cx) / rx
			var ny: float = (float(py) + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				image.set_pixel(px, py, color)
