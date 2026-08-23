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
const VIGNETTE_SHADER_PATH: String = "res://assets/shaders/vignette.gdshader"

## Bumped from the old 6px clubhouse-chrome radius — current game UI reads as
## soft/rounded "glass" chips rather than sharp-cornered panels; this one
## constant now drives every stock StyleBoxFlat panel/button in the theme.
const CORNER_RADIUS: int = 16

# "Racing Elegance" palette — AJ, reverting the "Neon Downs" cyan/magenta
# night-broadcast reskin: "ditch the neon, make it look more appealing to a
# boomer." Deep clubhouse green panels + warm brass/gold primary accent +
# traditional burgundy secondary/negative accent, closer to a real Kentucky-
# Derby-clubhouse look than a cyberpunk HUD. Every call site still reads
# UITheme.COLOR_GOLD / COLOR_MAROON (kept as the constant NAMES across BOTH
# reskins so nothing downstream ever had to change) — only the actual Color
# values move, so the whole game re-skins from these four lines without
# touching Button/Label/RaceTrack3D call sites individually.
const COLOR_BG: Color = Color(0.035, 0.058, 0.043)
const COLOR_PANEL: Color = Color(0.067, 0.098, 0.074)
const COLOR_PANEL_LIGHT: Color = Color(0.11, 0.155, 0.117)
const COLOR_GOLD: Color = Color(0.75, 0.6, 0.24)
const COLOR_GOLD_BRIGHT: Color = Color(0.94, 0.8, 0.42)
const COLOR_CREAM: Color = Color(0.93, 0.9, 0.82)
const COLOR_MAROON: Color = Color(0.58, 0.14, 0.15)
const COLOR_MAROON_LIGHT: Color = Color(0.76, 0.28, 0.24)

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

	# PopupMenu (the dropdown list Godot opens for every OptionButton — bet
	# type/amount in BettingUI, track theme/camera mode in Settings) was
	# completely unstyled before this: arguably the single highest-visibility
	# "unstyled default widget" moment in the whole game, since it fires on an
	# ordinary core-loop action (picking a bet type) rather than a rarely
	# opened dialog, and previously popped up as Godot's stock light-gray
	# system menu regardless of everything else on screen being themed.
	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = COLOR_PANEL
	popup_panel.border_color = COLOR_GOLD
	popup_panel.set_border_width_all(2)
	popup_panel.set_corner_radius_all(10)
	popup_panel.content_margin_left = 6.0
	popup_panel.content_margin_right = 6.0
	popup_panel.content_margin_top = 8.0
	popup_panel.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "PopupMenu", popup_panel)

	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = COLOR_PANEL_LIGHT
	popup_hover.border_color = COLOR_GOLD_BRIGHT
	popup_hover.set_border_width_all(1)
	popup_hover.set_corner_radius_all(6)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)

	var popup_separator := StyleBoxFlat.new()
	popup_separator.bg_color = Color(COLOR_GOLD, 0.35)
	popup_separator.content_margin_top = 1.0
	popup_separator.content_margin_bottom = 1.0
	theme.set_stylebox("separator", "PopupMenu", popup_separator)
	theme.set_stylebox("labeled_separator_left", "PopupMenu", popup_separator)
	theme.set_stylebox("labeled_separator_right", "PopupMenu", popup_separator)

	theme.set_font("font", "PopupMenu", body_font)
	theme.set_font_size("font_size", "PopupMenu", 19)
	theme.set_color("font_color", "PopupMenu", COLOR_CREAM)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_GOLD_BRIGHT)
	theme.set_color("font_accelerator_color", "PopupMenu", COLOR_GOLD)
	theme.set_color("font_disabled_color", "PopupMenu", Color(COLOR_CREAM, 0.35))
	theme.set_color("font_separator_color", "PopupMenu", Color(COLOR_GOLD, 0.6))
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_constant("item_start_padding", "PopupMenu", 10)
	theme.set_constant("item_end_padding", "PopupMenu", 10)

	# Sliders (Settings' volume controls) were previously left completely
	# unstyled — Godot's stock gray track/circle-grabber sitting inside this
	# otherwise fully dark-neon-themed dialog was one of the more obvious
	# "default engine widget" tells, the same category of problem the
	# TitleScreen polish pass fixed for HSeparator/Button.
	var slider_grabber: GradientTexture2D = _grabber_icon(COLOR_GOLD_BRIGHT)
	for variant in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", variant, _panel_style(COLOR_PANEL, COLOR_PANEL_LIGHT, 1))
		theme.set_stylebox("grabber_area", variant, _panel_style(COLOR_GOLD, COLOR_GOLD, 0))
		theme.set_stylebox("grabber_area_highlight", variant, _panel_style(COLOR_GOLD_BRIGHT, COLOR_GOLD_BRIGHT, 0))
		theme.set_icon("grabber", variant, slider_grabber)
		theme.set_icon("grabber_highlight", variant, slider_grabber)
		theme.set_icon("grabber_disabled", variant, slider_grabber)

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

	# "PrimaryButton" — a single standout call-to-action style (TitleScreen's
	# "Play Now", and anywhere else with exactly one dominant action). A
	# solid bright fill instead of the plain Button's dark-panel-with-border
	# reads as the obvious thing to press; dark text on the bright fill
	# (rather than the usual cream) keeps it legible against COLOR_GOLD's high
	# luminance. Previously every menu button used the identical plain Button
	# style, which is exactly the "five identical slabs, no hierarchy" look
	# that reads as an unfinished placeholder menu.
	theme.set_type_variation("PrimaryButton", "Button")
	var primary_normal: StyleBoxFlat = _panel_style(COLOR_GOLD, COLOR_GOLD_BRIGHT, 2)
	primary_normal.shadow_size = 16
	var primary_hover: StyleBoxFlat = _panel_style(COLOR_GOLD_BRIGHT, Color.WHITE, 2)
	primary_hover.shadow_size = 20
	theme.set_stylebox("normal", "PrimaryButton", primary_normal)
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	theme.set_stylebox("pressed", "PrimaryButton", _panel_style(COLOR_GOLD.darkened(0.15), COLOR_GOLD_BRIGHT, 3))
	theme.set_stylebox("focus", "PrimaryButton", _panel_style(Color(0, 0, 0, 0), Color.WHITE, 2))
	theme.set_font("font", "PrimaryButton", heading_font)
	theme.set_font_size("font_size", "PrimaryButton", 24)
	theme.set_color("font_color", "PrimaryButton", COLOR_BG)
	theme.set_color("font_hover_color", "PrimaryButton", COLOR_BG)
	theme.set_color("font_pressed_color", "PrimaryButton", COLOR_BG)

	# "GhostButton" — the quiet secondary-navigation counterpart (Stable,
	# Settings, Credits): a mostly-transparent fill and a thin low-alpha
	# border so it recedes behind PrimaryButton instead of competing with it
	# at equal visual weight. Uses _quiet_style, NOT _panel_style — a real
	# screenshot of this (see screenshot_capture.gd dev tool) caught that
	# _panel_style bakes in a shadow/glow unconditionally, so the first
	# version of this "quiet" style still glowed like every other lit-HUD
	# button and barely read as de-emphasized at all.
	theme.set_type_variation("GhostButton", "Button")
	theme.set_stylebox("normal", "GhostButton", _quiet_style(Color(COLOR_PANEL, 0.2), Color(COLOR_GOLD, 0.3), 1))
	theme.set_stylebox("hover", "GhostButton", _quiet_style(Color(COLOR_PANEL_LIGHT, 0.4), Color(COLOR_GOLD, 0.7), 1))
	theme.set_stylebox("pressed", "GhostButton", _quiet_style(Color(COLOR_PANEL_LIGHT.darkened(0.25), 0.55), COLOR_GOLD, 2))
	theme.set_stylebox("focus", "GhostButton", _quiet_style(Color(0, 0, 0, 0), COLOR_GOLD_BRIGHT, 2))
	theme.set_font("font", "GhostButton", body_font)
	theme.set_font_size("font_size", "GhostButton", 18)
	theme.set_color("font_color", "GhostButton", Color(COLOR_CREAM, 0.65))
	theme.set_color("font_hover_color", "GhostButton", COLOR_GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "GhostButton", COLOR_GOLD)

	# "QuietButton" — for a single de-emphasized action pulled OUT of a menu
	# card entirely (currently just TitleScreen's Exit to Desktop). The old
	# approach (reusing "MaroonButton", the same bold solid-fill/glow style
	# used for genuine warnings elsewhere) defeated the whole point of
	# separating it from the main card — a real screenshot showed it as the
	# single LOUDEST element on the screen, competing with PrimaryButton
	# instead of receding. This is _quiet_style with a maroon tint instead of
	# gold, so it still reads as "leave/danger" via color alone, just quietly.
	theme.set_type_variation("QuietButton", "Button")
	theme.set_stylebox("normal", "QuietButton", _quiet_style(Color(COLOR_MAROON, 0.12), Color(COLOR_MAROON, 0.4), 1))
	theme.set_stylebox("hover", "QuietButton", _quiet_style(Color(COLOR_MAROON, 0.3), COLOR_MAROON_LIGHT, 1))
	theme.set_stylebox("pressed", "QuietButton", _quiet_style(Color(COLOR_MAROON, 0.45), COLOR_MAROON, 2))
	theme.set_stylebox("focus", "QuietButton", _quiet_style(Color(0, 0, 0, 0), COLOR_MAROON_LIGHT, 2))
	theme.set_font("font", "QuietButton", body_font)
	theme.set_font_size("font_size", "QuietButton", 16)
	theme.set_color("font_color", "QuietButton", Color(COLOR_CREAM, 0.55))
	theme.set_color("font_hover_color", "QuietButton", COLOR_MAROON_LIGHT)
	theme.set_color("font_pressed_color", "QuietButton", COLOR_MAROON)

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

## Flat counterpart to _panel_style with NO glow/shadow at all — for anything
## that's actually meant to recede (GhostButton/QuietButton) rather than read
## as lit HUD glass. _panel_style's shadow is unconditional, which is exactly
## why the first version of GhostButton/Exit-to-Desktop still looked as loud
## as every other button despite a lower-alpha fill/border (confirmed via a
## real screenshot, not assumed) — a glow is a glow regardless of how
## transparent the fill under it is.
static func _quiet_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb

## A small solid-fill circle used as a Slider's grabber handle (Godot draws
## the grabber from a plain icon/Texture2D, not a StyleBox, unlike the rest of
## this theme) — GradientTexture2D with a very tight center-to-edge falloff
## reads as a crisp anti-aliased dot rather than a soft glow blob, keeping it
## a genuinely different visual role from _build_glow_blob's ambient-light
## use of the same resource type.
static func _grabber_icon(color: Color, diameter: float = 18.0) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.82, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(diameter)
	texture.height = int(diameter)
	return texture

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

## A full-screen cinematic vignette + faint scanline/grain overlay (see
## assets/shaders/vignette.gdshader) — call once per screen that wants the
## "broadcast night" atmosphere this game's identity is built around
## (currently TitleScreen; safe to reuse on TrackLobby/RaceTrack3D later).
## Unlike make_glass_panel this never reads the screen texture — it only
## darkens/textures whatever is already drawn beneath it — so the caller can
## freely place it above background art/glows and below foreground UI
## without it blurring anything. Caller just add_child()s the result at the
## point in the tree where that layering is correct.
static func make_vignette_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = COLOR_BG
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = load(VIGNETTE_SHADER_PATH)
	mat.set_shader_parameter("edge_color", COLOR_BG)
	mat.set_shader_parameter("rect_size", Vector2(1600.0, 900.0))
	overlay.material = mat
	overlay.resized.connect(func(): mat.set_shader_parameter("rect_size", overlay.size))

	return overlay
