extends Node

## One-off capture for a Steam header-capsule PLACEHOLDER (460x215, the most
## commonly required store image) — a real, usable starting point built from
## this game's own actual logo lockup, not a text description of one. Renders
## the TitleScreen's title/ornaments/subtitle composed into the capsule's own
## aspect ratio at native size (not a downscaled crop of the full 1600x900
## window, which would make the wordmark too small to read at capsule size).
## Exact dimensions should be re-checked against Steamworks' own docs at
## actual upload time (see docs/STEAMWORKS_SETUP.md) — this is a placeholder
## to give AJ a real starting point, not a final asset.
## Must run with the REAL (non-headless) binary:
##   godotsteam.441.editor.windows64.exe --path . res://scenes/tools/screenshot_capture_capsule.tscn

const OUT_PATH: String = "C:/Users/AJ/AppData/Local/Temp/claude/C--Users-AJ/514d116b-01e6-4c8a-a131-267597d9b18a/scratchpad/capsule_460x215.png"
const CAPSULE_SIZE: Vector2i = Vector2i(460, 215)

func _ready() -> void:
	await get_tree().process_frame # let the engine finish its own initial setup first — see screenshot_capture.gd's note on this exact gotcha

	get_viewport().size = CAPSULE_SIZE
	get_window().size = CAPSULE_SIZE

	var bg := ColorRect.new()
	bg.color = UITheme.COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(bg)

	# A plain radial-gradient glow (not TitleScreen's own glow helper, which
	# assumes a much taller 1600x900 canvas) sized for this short/wide capsule.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UITheme.COLOR_GOLD, 0.35))
	gradient.set_color(1, Color(UITheme.COLOR_GOLD, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = gradient
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 512
	glow_tex.height = 512
	var glow_rect := TextureRect.new()
	glow_rect.texture = glow_tex
	glow_rect.size = Vector2(420.0, 420.0)
	glow_rect.position = Vector2(CAPSULE_SIZE.x * 0.5 - 210.0, -140.0)
	get_tree().root.add_child(glow_rect)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(center)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)
	center.add_child(content)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 10)
	content.add_child(title_row)

	for side in [0, 1]:
		var ornament := Label.new()
		ornament.text = "◆"
		ornament.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		ornament.add_theme_font_size_override("font_size", 20)
		title_row.add_child(ornament)
		if side == 0:
			var title := Label.new()
			title.theme_type_variation = "HeadingLabel"
			title.add_theme_font_size_override("font_size", 40)
			title.text = "LONGSHOT DOWNS"
			title_row.add_child(title)

	var subtitle := Label.new()
	subtitle.theme_type_variation = "EyebrowLabel"
	subtitle.text = "LIVE THOROUGHBRED RACING & WAGERING"
	subtitle.add_theme_font_size_override("font_size", 12)
	content.add_child(subtitle)

	await get_tree().process_frame
	await get_tree().process_frame

	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	print("screenshot_capture_capsule: save_png -> %s (err=%s, size=%s)" % [OUT_PATH, err, image.get_size()])
	get_tree().quit()
