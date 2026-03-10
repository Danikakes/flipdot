## StopMotionInspectorPlugin
## Adds a stop motion control panel at the TOP of the inspector
## whenever an AnimationPlayer node is selected.
@tool
extends EditorInspectorPlugin

## Emitted when the user changes any setting in the panel.
signal settings_changed(player: AnimationPlayer, enabled: bool, fps: int, interp: int)

# We need a reference back to the EditorPlugin so we can read live state
# (e.g. whether stop motion is already active for this player).
# Set by plugin.gd immediately after instantiation.
var main_plugin: EditorPlugin = null

# ---------------------------------------------------------------------------
func _can_handle(object: Object) -> bool:
	return object is AnimationPlayer

func _parse_begin(object: Object) -> void:
	var player := object as AnimationPlayer
	var panel := _build_panel(player)
	add_custom_control(panel)

# ---------------------------------------------------------------------------
func _build_panel(player: AnimationPlayer) -> Control:
	var enabled: bool = player.get_meta("stop_motion_enabled", false)
	var fps: int      = player.get_meta("stop_motion_fps",     12)
	var interp: int   = player.get_meta("stop_motion_interp",  0)

	var root := VBoxContainer.new()
	root.name = "StopMotionPanel"
	root.add_theme_constant_override("separation", 2)

	# ── Header: title + toggle on one line ──────────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Flipdot"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header.add_child(title)

	var toggle := CheckButton.new()
	toggle.name = "EnableToggle"
	toggle.text = "On" if enabled else "Off"
	toggle.button_pressed = enabled
	toggle.tooltip_text = "Toggle stop motion playback for this AnimationPlayer"
	header.add_child(toggle)

	root.add_child(HSeparator.new())

	# ── Grid: two-column label | control ────────────────────────────────────
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	# Row: Max FPS
	var fps_lbl := Label.new()
	fps_lbl.text = "Max FPS"
	fps_lbl.tooltip_text = "Animations update at most this many times per second"
	fps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(fps_lbl)

	var fps_spin := SpinBox.new()
	fps_spin.name = "FpsSpin"
	fps_spin.min_value = 1
	fps_spin.max_value = 60
	fps_spin.step = 1
	fps_spin.value = fps
	fps_spin.suffix = "fps"
	fps_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_spin.editable = enabled
	grid.add_child(fps_spin)

	# Row: Interpolation
	var interp_lbl := Label.new()
	interp_lbl.text = "Interpolation"
	interp_lbl.tooltip_text = (
		"Interpolation mode applied to all animation tracks while active.\n"
		+ "Nearest = discrete, no blending (classic stop motion look).\n"
		+ "Original track settings are restored when disabled."
	)
	interp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(interp_lbl)

	var interp_opt := OptionButton.new()
	interp_opt.name = "InterpOption"
	interp_opt.add_item("Nearest", 0)
	interp_opt.add_item("Linear",  1)
	interp_opt.add_item("Cubic",   2)
	interp_opt.selected = clampi(interp, 0, 2)
	interp_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interp_opt.disabled = not enabled
	grid.add_child(interp_opt)

	root.add_child(HSeparator.new())

	# ── Status line ──────────────────────────────────────────────────────────
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if enabled else Color(0.55, 0.55, 0.55))
	status_label.text = _make_status(player, enabled, fps, interp)
	root.add_child(status_label)

	# AnimationTree notice — populated deferred once scene is ready
	var tree_label := Label.new()
	tree_label.name = "TreeLabel"
	tree_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree_label.add_theme_font_size_override("font_size", 11)
	tree_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	tree_label.visible = false
	root.add_child(tree_label)

	root.add_child(HSeparator.new())

	# ── Signal wiring ────────────────────────────────────────────────────────
	var emit := func(
		_unused,
		p: AnimationPlayer,
		t: CheckButton,
		s: SpinBox,
		o: OptionButton,
		sl: Label
	) -> void:
		var en: bool = t.button_pressed
		var f: int   = int(s.value)
		var iv: int  = o.selected
		t.text       = "On" if en else "Off"
		s.editable   = en
		o.disabled   = not en
		sl.text      = _make_status(p, en, f, iv)
		sl.add_theme_color_override("font_color",
			Color(0.4, 0.9, 0.4) if en else Color(0.55, 0.55, 0.55))
		settings_changed.emit(p, en, f, iv)

	toggle.toggled.connect(
		emit.bind(player, toggle, fps_spin, interp_opt, status_label))
	fps_spin.value_changed.connect(
		emit.bind(player, toggle, fps_spin, interp_opt, status_label))
	interp_opt.item_selected.connect(
		emit.bind(player, toggle, fps_spin, interp_opt, status_label))

	_check_anim_tree_deferred.call_deferred(player, tree_label)

	return root

# ---------------------------------------------------------------------------
func _check_anim_tree_deferred(player: AnimationPlayer, label: Label) -> void:
	if not is_instance_valid(player) or not is_instance_valid(label):
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return
	var tree := _find_anim_tree_for(scene_root, player)
	if tree:
		label.text = "AnimationTree detected — will control tree playback"
		label.visible = true

# ---------------------------------------------------------------------------
static func _make_status(
	player: AnimationPlayer,
	enabled: bool,
	fps: int,
	interp: int
) -> String:
	var anim_count: int = player.get_animation_list().size()
	var interp_names := ["nearest", "linear", "cubic"]
	if enabled:
		return "Active  |  %d fps  |  interp: %s  |  %d animation(s)" % [
			fps, interp_names[clampi(interp, 0, 2)], anim_count
		]
	return "%d animation(s) — stop motion off" % anim_count

static func _find_anim_tree_for(root: Node, player: AnimationPlayer) -> AnimationTree:
	if root is AnimationTree:
		var tree := root as AnimationTree
		if not tree.anim_player.is_empty():
			if tree.get_node_or_null(tree.anim_player) == player:
				return tree
	for child in root.get_children():
		var result := _find_anim_tree_for(child, player)
		if result:
			return result
	return null
