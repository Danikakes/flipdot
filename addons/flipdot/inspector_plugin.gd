## Flipdot — EditorInspectorPlugin
## Shows the Flipdot panel at the top of the inspector for FlipdotPlayer nodes.
## Hides the raw export vars to avoid duplication.
@tool
extends EditorInspectorPlugin

const FlipdotScript := preload("res://addons/flipdot/flipdot_player.gd")

const OWNED_PROPS := ["target", "stop_motion_enabled", "max_fps", "interpolation_override"]

# ---------------------------------------------------------------------------
func _can_handle(object: Object) -> bool:
	return object.get_script() == FlipdotScript

func _parse_begin(object: Object) -> void:
	add_custom_control(_build_panel(object))

func _parse_property(
	_object: Object, _type: Variant.Type, name: String,
	_hint: PropertyHint, _hint_string: String,
	_usage: PropertyUsageFlags, _wide: bool
) -> bool:
	return name in OWNED_PROPS

# ---------------------------------------------------------------------------
func _build_panel(node: Object) -> Control:
	var enabled: bool        = node.get("stop_motion_enabled")
	var fps:     int         = node.get("max_fps")
	var interp:  int         = node.get("interpolation_override")
	var tgt: AnimationPlayer = node.get("target")

	var root := VBoxContainer.new()
	root.name = "FlipdotPanel"
	root.add_theme_constant_override("separation", 2)

	# ── Header ───────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Flipdot"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header.add_child(title)

	var toggle := CheckButton.new()
	toggle.text = "On" if enabled else "Off"
	toggle.button_pressed = enabled
	toggle.tooltip_text = "Toggle stop motion playback"
	header.add_child(toggle)

	root.add_child(HSeparator.new())

	# ── Target row ───────────────────────────────────────────────────────────
	var target_row := HBoxContainer.new()
	root.add_child(target_row)

	var target_lbl := Label.new()
	target_lbl.text = "Target"
	target_lbl.tooltip_text = "AnimationPlayer to control. Auto-uses parent if left empty."
	target_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(target_lbl)

	var target_info := Label.new()
	target_info.name = "TargetInfo"
	target_info.add_theme_font_size_override("font_size", 11)
	target_info.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	target_info.text = _target_text(node, tgt)
	target_row.add_child(target_info)

	root.add_child(HSeparator.new())

	# ── Grid: label | control ────────────────────────────────────────────────
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	var fps_lbl := Label.new()
	fps_lbl.text = "Max FPS"
	fps_lbl.tooltip_text = "Animations update at most this many times per second"
	fps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(fps_lbl)

	var fps_spin := SpinBox.new()
	fps_spin.min_value = 1
	fps_spin.max_value = 60
	fps_spin.step = 1
	fps_spin.value = fps
	fps_spin.suffix = "fps"
	fps_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_spin.editable = enabled
	grid.add_child(fps_spin)

	var interp_lbl := Label.new()
	interp_lbl.text = "Interpolation"
	interp_lbl.tooltip_text = (
		"Interpolation mode applied to all tracks while active.\n"
		+ "Nearest = discrete, no blending (classic stop motion look).\n"
		+ "Restored when disabled."
	)
	interp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(interp_lbl)

	var interp_opt := OptionButton.new()
	interp_opt.add_item("Nearest", 0)
	interp_opt.add_item("Linear",  1)
	interp_opt.add_item("Cubic",   2)
	interp_opt.selected = clampi(interp, 0, 2)
	interp_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interp_opt.disabled = not enabled
	grid.add_child(interp_opt)

	root.add_child(HSeparator.new())

	# ── Status ───────────────────────────────────────────────────────────────
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if enabled else Color(0.55, 0.55, 0.55))
	status.text = _make_status(node, enabled, fps, interp)
	root.add_child(status)

	root.add_child(HSeparator.new())

	# ── Wiring ───────────────────────────────────────────────────────────────
	var on_change := func(
		_unused, n: Object,
		t: CheckButton, s: SpinBox, o: OptionButton, sl: Label
	) -> void:
		var en: bool = t.button_pressed
		var f:  int  = int(s.value)
		var iv: int  = o.selected
		n.set("stop_motion_enabled",    en)
		n.set("max_fps",                f)
		n.set("interpolation_override", iv)
		t.text     = "On" if en else "Off"
		s.editable = en
		o.disabled = not en
		sl.text    = _make_status(n, en, f, iv)
		sl.add_theme_color_override("font_color",
			Color(0.4, 0.9, 0.4) if en else Color(0.55, 0.55, 0.55))

	toggle.toggled.connect(on_change.bind(node, toggle, fps_spin, interp_opt, status))
	fps_spin.value_changed.connect(on_change.bind(node, toggle, fps_spin, interp_opt, status))
	interp_opt.item_selected.connect(on_change.bind(node, toggle, fps_spin, interp_opt, status))

	return root

# ---------------------------------------------------------------------------
static func _target_text(node: Object, tgt: AnimationPlayer) -> String:
	if is_instance_valid(tgt):
		return tgt.name
	# Check if parent will be auto-used
	var n := node as Node
	if is_instance_valid(n) and n.get_parent() is AnimationPlayer:
		return "%s (auto)" % n.get_parent().name
	return "none — set Target"

static func _make_status(node: Object, enabled: bool, fps: int, interp: int) -> String:
	var tgt := node.get("target") as AnimationPlayer
	if not is_instance_valid(tgt):
		var n := node as Node
		if is_instance_valid(n) and n.get_parent() is AnimationPlayer:
			tgt = n.get_parent() as AnimationPlayer
	var count: int = tgt.get_animation_list().size() if is_instance_valid(tgt) else 0
	var names := ["nearest", "linear", "cubic"]
	if enabled:
		return "Active  |  %d fps  |  %s  |  %d animation(s)" % [
			fps, names[clampi(interp, 0, 2)], count
		]
	return "%d animation(s) — off" % count
