extends SceneTree

## Dev tool, not part of the game: run with
##   godot --headless --path . --script res://scripts/tools/generate_crowd_billboard.gd
## Generates a transparent-background crowd-card PNG for RaceTrack3D's
## billboard crowd (see _build_spectators) — replacing individual capsule
## "people" with camera-facing cutout cards showing many painted people each,
## the same trick real film/broadcast productions use for background crowds.
##
## Pure Image pixel drawing (same reasoning as generate_achievement_icons.gd:
## no dependency on font/theme/SubViewport rendering actually working
## correctly, unverifiable visually in this environment anyway) rather than a
## sourced photo crowd-cutout — this project has no reliable way to confirm a
## found image's license/alpha-channel quality without downloading and
## inspecting several candidates, and a procedural card is a fully clean,
## zero-risk substitute: at the distance this game's broadcast camera ever
## sees the grandstand from, a real photo crowd card and a painted one read
## almost identically anyway (both dissolve into "a mass of small colored
## blobs"). If a real photo card is ever sourced later, it's a drop-in
## replacement for this same file path — nothing else needs to change.

const OUT_PATH: String = "res://assets/textures/crowd_billboard.png"
const WIDTH: int = 1024
const HEIGHT: int = 320
const ROWS: int = 5 # back-of-card (small, high) to front-of-card (large, low)

const SKIN_TONES: Array[Color] = [
	Color(0.94, 0.76, 0.62), Color(0.82, 0.6, 0.44), Color(0.62, 0.42, 0.28),
	Color(0.45, 0.3, 0.2), Color(0.3, 0.2, 0.14),
]
const CLOTHING_COLORS: Array[Color] = [
	Color(0.3, 0.28, 0.32), Color(0.22, 0.24, 0.28), Color(0.35, 0.3, 0.25),
	Color(0.28, 0.22, 0.2), Color(0.25, 0.28, 0.24), Color(0.32, 0.32, 0.34),
	Color(0.45, 0.15, 0.15), Color(0.15, 0.25, 0.45), Color(0.4, 0.38, 0.1),
]

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1129 # fixed seed — deterministic output, re-running this tool doesn't churn the committed PNG for no reason

	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0)) # fully transparent — this is a cutout card, not a rectangle

	for row in range(ROWS):
		# Row 0 = furthest back (small heads, high on the card, i.e. low Y).
		# Row ROWS-1 = front row (large heads, near the card's bottom edge).
		var t: float = float(row) / float(max(ROWS - 1, 1))
		var head_radius: float = lerp(7.0, 20.0, t)
		var row_center_y: float = lerp(HEIGHT * 0.22, HEIGHT * 0.86, t)
		var shoulder_width: float = head_radius * 2.2
		var shoulder_height: float = head_radius * 1.6

		var x: float = -head_radius * rng.randf_range(0.0, 1.0)
		while x < WIDTH + head_radius:
			var jitter_y: float = rng.randf_range(-head_radius * 0.4, head_radius * 0.4)
			var cx: float = x
			var cy: float = row_center_y + jitter_y

			var clothing: Color = CLOTHING_COLORS[rng.randi() % CLOTHING_COLORS.size()]
			_fill_ellipse(image, cx, cy + head_radius * 1.5, shoulder_width * 0.5, shoulder_height * 0.5, clothing)

			var skin: Color = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
			_fill_ellipse(image, cx, cy, head_radius, head_radius, skin)

			x += head_radius * rng.randf_range(1.7, 2.6) # organic spacing, not a perfect uniform grid

	var err: Error = image.save_png(OUT_PATH)
	print("generate_crowd_billboard: save_png -> %s (err=%s)" % [OUT_PATH, err])
	quit()

## Filled ellipse via a local bounding-box scan (not a full-image scan per
## shape) — same "loop only the pixels that could possibly be inside" idiom
## as generate_achievement_icons.gd's concentric rings, just elliptical
## instead of circular so heads/shoulders aren't perfectly round.
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
