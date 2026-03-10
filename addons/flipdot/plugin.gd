## Stop Motion Interpolation — EditorPlugin
## Registers an EditorInspectorPlugin that adds stop motion controls
## at the top of the inspector when an AnimationPlayer is selected.
## All playback control is handled here; no extra nodes are added to the scene.
@tool
extends EditorPlugin

const META_ENABLED := "stop_motion_enabled"
const META_FPS     := "stop_motion_fps"
const META_INTERP  := "stop_motion_interp"

var _inspector_plugin: EditorInspectorPlugin

# --- Per-player runtime state ---
# Keyed by AnimationPlayer instance ID
var _mixers:         Dictionary = {}  # id → AnimationMixer being controlled (Tree or Player)
var _orig_modes:     Dictionary = {}  # id → original callback_mode_process
var _saved_interp:   Dictionary = {}  # id → { "anim|track": original_interp }
var _time_acc:       Dictionary = {}  # id → float accumulator

# ---------------------------------------------------------------------------
func _enter_tree() -> void:
	_inspector_plugin = load(
		"res://addons/stop_motion_interpolation/inspector_plugin.gd"
	).new()
	_inspector_plugin.main_plugin = self
	_inspector_plugin.settings_changed.connect(_on_settings_changed)
	add_inspector_plugin(_inspector_plugin)
	set_process(true)

func _exit_tree() -> void:
	remove_inspector_plugin(_inspector_plugin)
	_inspector_plugin = null
	# Restore all players that were left in manual mode
	for player_id in _mixers.keys():
		_restore_player(player_id)

# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var to_remove: Array = []

	for player_id in _mixers.keys():
		var mixer: AnimationMixer = _mixers.get(player_id)
		if not is_instance_valid(mixer):
			to_remove.append(player_id)
			continue

		var is_playing := _mixer_is_playing(mixer)
		if not is_playing:
			_time_acc[player_id] = 0.0
			continue

		# Find what FPS this player uses
		# We stored metadata on the AnimationPlayer, not the mixer (which may be AnimationTree)
		var player := _player_for_id(player_id)
		if not is_instance_valid(player):
			to_remove.append(player_id)
			continue

		var fps: int = player.get_meta(META_FPS, 12)
		var frame_time := 1.0 / maxi(1, fps)

		_time_acc[player_id] = _time_acc.get(player_id, 0.0) + delta
		while _time_acc[player_id] >= frame_time:
			_time_acc[player_id] -= frame_time
			mixer.advance(frame_time)

	for id in to_remove:
		_mixers.erase(id)
		_orig_modes.erase(id)
		_saved_interp.erase(id)
		_time_acc.erase(id)

# ---------------------------------------------------------------------------
# Called by the inspector panel whenever the user changes a setting.
# ---------------------------------------------------------------------------
func _on_settings_changed(
	player: AnimationPlayer,
	enabled: bool,
	fps: int,
	interp: int
) -> void:
	var id := player.get_instance_id()

	# Persist to metadata (survives scene save/load within the editor session)
	player.set_meta(META_ENABLED, enabled)
	player.set_meta(META_FPS, fps)
	player.set_meta(META_INTERP, interp)

	if enabled:
		_activate(player, fps, interp)
	else:
		_restore_player(id)

# ---------------------------------------------------------------------------
func _activate(player: AnimationPlayer, fps: int, interp: int) -> void:
	var id := player.get_instance_id()

	# If already active, just update settings
	if _mixers.has(id):
		# Re-apply interpolation with new setting
		_restore_interp_for(id, player)
		_apply_interp(id, player, interp)
		return

	# Find the driving mixer: prefer an AnimationTree that uses this player
	var mixer: AnimationMixer = _find_driving_mixer(player)
	_mixers[id] = mixer

	# Switch to manual process mode
	_orig_modes[id] = mixer.callback_mode_process
	mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_time_acc[id] = 0.0

	_apply_interp(id, player, interp)

func _restore_player(id: int) -> void:
	var mixer: AnimationMixer = _mixers.get(id)
	if is_instance_valid(mixer) and _orig_modes.has(id):
		mixer.callback_mode_process = _orig_modes[id]

	# Restore interpolation on the AnimationPlayer (always the source of Animation data)
	var player := _player_for_id(id)
	if is_instance_valid(player):
		_restore_interp_for(id, player)

	_mixers.erase(id)
	_orig_modes.erase(id)
	_saved_interp.erase(id)
	_time_acc.erase(id)

# ---------------------------------------------------------------------------
# Interpolation override — modifies Animation resource tracks, restores on disable.
# Works with both inline animations and AnimationLibrary imports because
# AnimationPlayer.get_animation_list() enumerates all regardless of source.
# ---------------------------------------------------------------------------
func _apply_interp(id: int, player: AnimationPlayer, interp: int) -> void:
	# interp: 0=nearest, 1=linear, 2=cubic
	var mode := _interp_idx_to_type(interp)
	var saved: Dictionary = {}

	for anim_name in player.get_animation_list():
		var anim: Animation = player.get_animation(anim_name)
		if not anim:
			continue
		for i in anim.get_track_count():
			if _track_supports_interp(anim.track_get_type(i)):
				var key := "%s|%d" % [anim_name, i]
				saved[key] = anim.track_get_interpolation_type(i)
				anim.track_set_interpolation_type(i, mode)

	_saved_interp[id] = saved

func _restore_interp_for(id: int, player: AnimationPlayer) -> void:
	var saved: Dictionary = _saved_interp.get(id, {})
	if saved.is_empty():
		return

	for key: String in saved:
		var parts := key.split("|")
		if parts.size() < 2:
			continue
		var anim_name: String = parts[0]
		var track_idx: int = int(parts[1])
		if not player.has_animation(anim_name):
			continue
		var anim: Animation = player.get_animation(anim_name)
		if anim and track_idx < anim.get_track_count():
			anim.track_set_interpolation_type(track_idx, saved[key])

	_saved_interp.erase(id)

# ---------------------------------------------------------------------------
# AnimationTree detection
# Scans the edited scene for an AnimationTree whose anim_player points at `player`.
# If found, we control the tree (which drives the player) instead of the player directly.
# ---------------------------------------------------------------------------
func _find_driving_mixer(player: AnimationPlayer) -> AnimationMixer:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root:
		var tree := _find_anim_tree_for(scene_root, player)
		if tree:
			return tree
	return player

static func _find_anim_tree_for(root: Node, player: AnimationPlayer) -> AnimationTree:
	if root is AnimationTree:
		var tree := root as AnimationTree
		if not tree.anim_player.is_empty():
			var target := tree.get_node_or_null(tree.anim_player)
			if target == player:
				return tree
	for child in root.get_children():
		var result := _find_anim_tree_for(child, player)
		if result:
			return result
	return null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _player_for_id(id: int) -> AnimationPlayer:
	# Walk active mixers to find the player with this ID.
	# The mixer could be an AnimationTree, so we look it up by the stored ID.
	# We need a way to get back to the AnimationPlayer node from its instance ID.
	# Use InstanceId → Object (Godot built-in)
	var obj := instance_from_id(id)
	if obj is AnimationPlayer:
		return obj as AnimationPlayer
	return null

static func _mixer_is_playing(mixer: AnimationMixer) -> bool:
	if mixer is AnimationPlayer:
		return (mixer as AnimationPlayer).is_playing()
	# AnimationTree: active means it's running
	if mixer is AnimationTree:
		return (mixer as AnimationTree).active
	return false

static func _track_supports_interp(t: Animation.TrackType) -> bool:
	return t in [
		Animation.TYPE_VALUE,
		Animation.TYPE_POSITION_3D,
		Animation.TYPE_ROTATION_3D,
		Animation.TYPE_SCALE_3D,
		Animation.TYPE_BLEND_SHAPE,
	]

static func _interp_idx_to_type(idx: int) -> Animation.InterpolationType:
	match idx:
		0: return Animation.INTERPOLATION_NEAREST
		1: return Animation.INTERPOLATION_LINEAR
		2: return Animation.INTERPOLATION_CUBIC
		_: return Animation.INTERPOLATION_NEAREST
