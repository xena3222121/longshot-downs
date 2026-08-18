extends Node

## Autoload singleton (registered in project.godot). Builds one global Theme
## resource at startup and applies it via get_window().theme, so every
## Control in the game (TitleScreen, BettingUI, FinishPodium, credits
## dialogs, ...) picks up consistent fonts/colors/button chrome
## automatically instead of each screen hand-rolling its own look. Built in
## code rather than as a checked-in .tres — a set of constants here is much
## easier to tune than hand-editing a giant serialized resource, and mirrors
## how the rest of this project builds UI procedurally rather than in the
## editor (see BettingUI/FinishPodium).
##
## Deliberately no class_name — see Bankroll.gd for why.

const FONT_PATH: String = "res://assets/fonts/PlayfairDisplay-Variable.ttf"
const GLASS_SHADER_PATH: String = "res://assets/shaders/glass_panel.gdshader"

## Bumped from the old 6px clubhouse-chrome radius — current game UI reads as
## soft/rounded "glass" chips rather than sharp-cornered panels; this one
## constant now drives every stock StyleBoxFlat panel/button in the theme.
const CORNER_RADIUS: int = 16

# "Neon Downs" palette: near-black glass panels + electric cyan primary
# accent + magenta secondary/negative accent — a night-race broadcast HUD
# feel rather than the old daytime clubhouse look. Every call site still
# reads UITheme.COLOR_GOLD / COLOR_MAROON (kept as the constant NAMES so nothing
# downstream had to change) — only the actual Color values moved from
# brass/maroon to cyan/magenta, so the whole game re-skins from these four
# lines without touching Button/Label/RaceTrack3D call sites individually.
const COLOR_BG: Color = Color(0.016, 0.024, 0.043)
const COLOR_PANEL: Color = Color(0.043, 0.067, 0.106)
const COLOR_PANEL_LIGHT: Color = Color(0.071, 0.106, 0.161)
const COLOR_GOLD: Color = Color(0.184, 0.878, 0.976)
const COLOR_GOLD_BRIGHT: Color = Color(0.588, 0.976, 1.0)
const COLOR_CREAM: Color = Color(0.859, 0.925, 0.965)
const COLOR_MAROON: Color = Color(0.847, 0.184, 0.616)
const COLOR_MAROON_LIGHT: Color = Color(0.949, 0.353, 0.741)

func _ready() -> void:
	get_window().theme = build_theme()

static func build_theme() -> Theme:
	var theme := Theme.new()
	var base_font: FontFile = load(FONT_PATH)
	var body_font: FontVariation = _weighted_font(base_font, 500)
	var heading_font: FontVariation = _weighted_font(base_font, 800, 2)
	var eyebrow_font: FontVariation = _weighted_font(base_font, 700, 6)

	theme.default_font = body_font
	theme.default_font_size = 20

	theme.set_font("font", "Label", body_font)
	theme.set_font_size("font_size", "Label", 20)
	theme.set_color("font_color", "Label", COLOR_CREAM)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.5))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_font("font", "Button", body_font)
	theme.set_font_size("font_size", "Button", 22)
	theme.set_color("font_color", "Button", COLOR_CREAM)
	theme.set_color("font_hover_color", "Button", COLOR_GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "Button", COLOR_GOLD)
	theme.set_color("font_disabled_color", "Button", Color(COLOR_CREAM, 0.35))
	theme.set_stylebox("normal", "Button", _panel_style(COLOR_PANEL, COLOR_GOLD, 2))
	theme.set_stylebox("hover", "Button", _panel_style(COLOR_PANEL_LIGHT, COLOR_GOLD_BRIGHT, 2))
	theme.set_stylebox("pressed", "Button", _panel_style(COLOR_PANEL_LIGHT.darkened(0.25), COLOR_GOLD, 3))
	theme.set_stylebox("disabled", "Button", _panel_style(COLOR_PANEL.darkened(0.4), COLOR_GOLD.darkened(0.5), 1))
	theme.set_stylebox("focus", "Button", _panel_style(Color(0, 0, 0, 0), COLOR_GOLD_BRIGHT, 2))

	for variant in ["CheckButton", "OptionButton"]:
		theme.set_font("font", variant, body_font)
		theme.set_font_size("font_size", variant, 20)
		theme.set_color("font_color", variant, COLOR_CREAM)
		theme.set_color("font_hover_color", variant, COLOR_GOLD_BRIGHT)
		theme.set_color("font_pressed_color", variant, COLOR_GOLD)
		theme.set_stylebox("normal", variant, _panel_style(COLOR_PANEL, COLOR_GOLD, 2))
		theme.set_stylebox("hover", variant, _panel_style(COLOR_PANEL_LIGHT, COLOR_GOLD_BRIGHT, 2))
		theme.set_stylebox("pressed", variant, _panel_style(COLOR_PANEL_LIGHT.darkened(0.25), COLOR_GOLD, 3))
		theme.set_stylebox("focus", variant, _panel_style(Color(0, 0, 0, 0), COLOR_GOLD_BRIGHT, 2))

	theme.set_stylebox("panel", "Panel", _panel_style(COLOR_PANEL, COLOR_GOLD, 2))
	theme.set_stylebox("panel", "PanelContainer", _panel_style(COLOR_PANEL, COLOR_GOLD, 2))

	theme.set_font("font", "AcceptDialog", body_font)
	theme.set_font_size("font_size", "AcceptDialog", 20)
	theme.set_color("font_color", "AcceptDialog", COLOR_CREAM)
	theme.set_stylebox("panel", "AcceptDialog", _panel_style(COLOR_BG.lightened(0.05), COLOR_GOLD, 3))
	theme.set_font("title_font", "AcceptDialog", heading_font)
	theme.set_font_size("title_font_size", "AcceptDialog", 26)
	theme.set_color("title_color", "AcceptDialog", COLOR_GOLD)

	theme.set_font_size("font_size", "OptionButton", 20)

	# A distinct "heading" style variant — request via Control.theme_type_variation
	# = "HeadingLabel" for titles/section headers (e.g. TitleScreen's big
	# "LONGSHOT DOWNS", or FinishPodium's banner), so the same theme covers
	# both body text and display headings without every heading needing a
	# manual per-instance font override.
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font("font", "HeadingLabel", heading_font)
	theme.set_font_size("font_size", "HeadingLabel", 48)
	theme.set_color("font_color", "HeadingLabel", COLOR_GOLD)
	theme.set_color("font_outline_color", "HeadingLabel", Color(0.0, 0.0, 0.0, 0.6))
	theme.set_constant("outline_size", "HeadingLabel", 4)

	# A tiny label variant for eyebrow/kicker text (bet-type chips, HUD
	# labels, section eyebrows) — wide-tracked all-caps micro-labels are a
	# current HUD-design staple; this variant exists so any Label can opt
	# into that look via theme_type_variation instead of hand-rolling font
	# overrides per instance.
	theme.set_type_variation("EyebrowLabel", "Label")
	theme.set_font("font", "EyebrowLabel", eyebrow_font)
	theme.set_font_size("font_size", "EyebrowLabel", 13)
	theme.set_color("font_color", "EyebrowLabel", COLOR_GOLD)

	theme.set_type_variation("MaroonButton", "Button")
	theme.set_stylebox("normal", "MaroonButton", _panel_style(COLOR_MAROON, COLOR_GOLD, 2))
	theme.set_stylebox("hover", "MaroonButton", _panel_style(COLOR_MAROON_LIGHT, COLOR_GOLD_BRIGHT, 2))
	theme.set_stylebox("pressed", "MaroonButton", _panel_style(COLOR_MAROON_LIGHT.darkened(0.25), COLOR_GOLD, 3))
	theme.set_font("font", "MaroonButton", body_font)
	theme.set_font_size("font_size", "MaroonButton", 22)
	theme.set_color("font_color", "MaroonButton", COLOR_CREAM)
	theme.set_color("font_hover_color", "MaroonButton", COLOR_GOLD_BRIGHT)

	return theme

## `glyph_spacing` adds extra tracking between characters (in pixels, at the
## font's base size) — a few pixels of positive tracking on wide-tracked
## all-caps display/eyebrow text is a current HUD-design staple; 0 leaves
## body text at its natural spacing.
static func _weighted_font(base: FontFile, weight: int, glyph_spacing: int = 0) -> FontVariation:
	var variant := FontVariation.new()
	variant.base_font = base
	variant.variation_opentype = {"wght": weight}
	if glyph_spacing != 0:
		variant.set_spacing(TextServer.SPACING_GLYPH, glyph_spacing)
	return variant

## Theme styleboxes alone only flat-swap colors on hover/press — no motion,
## which reads as static/cheap next to real motion feedback. Call once per
## constructed Button (TitleScreen/BettingUI/FinishPodium all do) to add a
## gentle hover scale-up and a snappy press-squash-then-pop-back, scaling
## from the button's own center rather than its top-left corner (Control's
## default pivot) — kept in sync via `resized` since a button's final size
## isn't known until its container lays it out, after construction.
static func add_button_juice(button: Button) -> void:
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(func():
		_tween_scale(button, Vector2(1.045, 1.045), 0.12, Tween.TRANS_SINE, Tween.EASE_OUT)
	)
	button.mouse_exited.connect(func():
		_tween_scale(button, Vector2.ONE, 0.12, Tween.TRANS_SINE, Tween.EASE_OUT)
	)
	button.button_down.connect(func():
		_tween_scale(button, Vector2(0.94, 0.96), 0.06, Tween.TRANS_SINE, Tween.EASE_OUT)
	)
	button.button_up.connect(func():
		var target: Vector2 = Vector2(1.045, 1.045) if button.is_hovered() else Vector2.ONE
		_tween_scale(button, target, 0.18, Tween.TRANS_BACK, Tween.EASE_OUT)
	)

static func _tween_scale(node: Control, target: Vector2, duration: float, trans: Tween.TransitionType, ease: Tween.EaseType) -> void:
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "scale", target, duration).set_trans(trans).set_ease(ease)

## The border color doubles as a soft outer glow (StyleBoxFlat's shadow is
## just a blurred copy of the box, so tinting it the same as the border reads
## as neon light spilling off the edge rather than a generic drop-shadow) —
## the single biggest lever for making flat 2D panels/buttons read as lit
## HUD glass instead of the old matte clubhouse chrome.
static func _panel_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	sb.shadow_color = Color(border, 0.35)
	sb.shadow_size = 8
	return sb

## Real frosted-glass panel — blurs whatever's behind it (the 3D racetrack,
## another panel, whatever) rather than faking depth with an opaque tint, via
## assets/shaders/glass_panel.gdshader. Distinct from the plain StyleBoxFlat
## panels above (which AcceptDialog/Button/etc. use through the Theme system
## — Window-based popups like AcceptDialog can't carry a CanvasItem shader
## material at all) — call this directly wherever a hand-built Control tree
## (BettingUI, BroadcastHUD, FinishPodium) wants the blurred-glass look.
## `size` seeds the shader's rect_size uniform immediately; the `resized`
## connection keeps it correct if the panel's size changes after the caller
## sets custom_minimum_size/anchors (its final size isn't known until a
## parent container lays it out, same reason add_button_juice defers its own
## pivot_offset to `resized` instead of setting it once up front).
static func make_glass_panel(size: Vector2, corner_radius: float = CORNER_RADIUS, tint: Color = Color(COLOR_PANEL, 0.6), border: Color = COLOR_GOLD) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = size
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = load(GLASS_SHADER_PATH)
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("corner_radius", corner_radius)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("border_color", Color(border, 0.85))
	panel.material = mat

	panel.resized.connect(func(): mat.set_shader_parameter("rect_size", panel.size))
	return panel

## Content-sized variant of make_glass_panel: a bare PanelContainer with the
## glass shader attached, left for the caller to fill (typically via a
## MarginContainer) and let Godot's normal container layout size it —
## there's no need to pre-compute a size up front the way a fixed HUD strip
## (see BroadcastHUD's bottom bar) does. PanelContainer draws its own
## background exactly like a plain Panel, so the same shader-material
## approach applies unchanged; only its `panel` stylebox override (unused
## here) would conflict with a custom material, so callers must NOT also set
## a "panel" stylebox override on the returned container.
static func make_glass_panel_container(corner_radius: float = CORNER_RADIUS, tint: Color = Color(COLOR_PANEL, 0.6), border: Color = COLOR_GOLD) -> PanelContainer:
	var panel := PanelContainer.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(GLASS_SHADER_PATH)
	mat.set_shader_parameter("rect_size", Vector2(200.0, 100.0))
	mat.set_shader_parameter("corner_radius", corner_radius)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("border_color", Color(border, 0.85))
	panel.material = mat
	panel.resized.connect(func(): mat.set_shader_parameter("rect_size", panel.size))
	return panel
