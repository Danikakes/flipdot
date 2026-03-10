## FlipdotPlayer
## Add as a child of any AnimationPlayer to apply stop motion playback.
## If no target is set it automatically uses the parent node.
## Works in the editor (@tool) and at runtime with no extra setup.
@tool
@icon("icon.svg")
extends Node
class_name FlipdotPlayer

## The AnimationPlayer to control. Leave empty to auto-use the parent.
@export var target: AnimationPlayer:
	set(v):
		if is_node_ready():
			_deactivate()
		target = v
		if is_node_ready() and stop_motion_enabled:
			_activate()

## Enable or disable stop motion.
@export var stop_motion_enabled: bool = true:
	set(v):
		stop_motion_enabled = v
		if is_node_ready():
			_apply_mode()

## Maximum animation updates per second.
@export_range(1, 60, 1) var max_fps: int = 12

## Interpolation mode applied to all tracks while active. Restored on disable.
@export_enum("Nearest", "Linear", "Cubic") var interpolation_override: int = 0:
	set(v):
		interpolation_override = v
		if is_node_ready() and stop_motion_enabled and is_instance_valid(_driving_mixer):
			_restore_interp()
			_apply_interp()

# ---------------------------------------------------------------------------
var _time_acc:      float           = 0.0
var _orig_mode:     int             = -1
var _saved_interp:  Dictionary      = {}
# The mixer actually being controlled — an AnimationTree if one drives the target,
# otherwise the target AnimationPlayer itself.
var _driving_mixer: AnimationMixer  = null

# ---------------------------------------------------------------------------
func _ready() -> void:
	if not is_instance_valid(target) and get_parent() is AnimationPlayer:
		target = get_parent() as AnimationPlayer
	_apply_mode()

func _exit_tree() -> void:
	_deactivate()

func _process(delta: float) -> void:
	if not stop_motion_enabled or not is_instance_valid(_driving_mixer):
		_time_acc = 0.0
		return
	if not _mixer_is_active(_driving_mixer):
		_time_acc = 0.0
		return
	var frame_time := 1.0 / maxi(1, max_fps)
	_time_acc += delta
	while _time_acc >= frame_time:
		_time_acc -= frame_time
		_driving_mixer.advance(frame_time)

# ---------------------------------------------------------------------------
func _apply_mode() -> void:
	if stop_motion_enabled:
		_activate()
	else:
		_deactivate()

func _activate() -> void:
	if not is_instance_valid(target):
		return
	# Prefer controlling an AnimationTree that drives the target — it sits above
	# the AnimationPlayer in the pipeline, so that's where MANUAL mode belongs.
	_driving_mixer = _find_driving_mixer()
	_orig_mode = _driving_mixer.callback_mode_process
	_driving_mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_time_acc = 0.0
	_apply_interp()

func _deactivate() -> void:
	_restore_interp()
	if is_instance_valid(_driving_mixer) and _orig_mode >= 0:
		_driving_mixer.callback_mode_process = _orig_mode as AnimationMixer.AnimationCallbackModeProcess
	_driving_mixer = null
	_orig_mode = -1
	_time_acc = 0.0

# ---------------------------------------------------------------------------
# Returns the AnimationTree whose anim_player points at target, if one exists,
# otherwise returns target itself.
func _find_driving_mixer() -> AnimationMixer:
	if get_tree():
		var tree := _find_anim_tree_for(get_tree().root, target)
		if tree:
			return tree
	return target

static func _find_anim_tree_for(node: Node, player: AnimationPlayer) -> AnimationTree:
	if node is AnimationTree:
		var tree := node as AnimationTree
		if not tree.anim_player.is_empty() and tree.get_node_or_null(tree.anim_player) == player:
			return tree
	for child in node.get_children():
		var result := _find_anim_tree_for(child, player)
		if result:
			return result
	return null

static func _mixer_is_active(mixer: AnimationMixer) -> bool:
	if mixer is AnimationPlayer:
		return (mixer as AnimationPlayer).is_playing()
	if mixer is AnimationTree:
		return (mixer as AnimationTree).active
	return false

# ---------------------------------------------------------------------------
func _apply_interp() -> void:
	if not is_instance_valid(target):
		return
	var mode := _idx_to_interp(interpolation_override)
	_saved_interp.clear()
	for anim_name: StringName in target.get_animation_list():
		var anim := target.get_animation(anim_name)
		if not anim:
			continue
		for i in anim.get_track_count():
			if _track_supports_interp(anim.track_get_type(i)):
				var key := "%s|%d" % [anim_name, i]
				_saved_interp[key] = anim.track_get_interpolation_type(i)
				anim.track_set_interpolation_type(i, mode)

func _restore_interp() -> void:
	if not is_instance_valid(target):
		_saved_interp.clear()
		return
	for key: String in _saved_interp:
		var parts := key.split("|")
		if parts.size() < 2:
			continue
		var anim_name: String = parts[0]
		var track_idx: int    = int(parts[1])
		if not target.has_animation(anim_name):
			continue
		var anim := target.get_animation(anim_name)
		if anim and track_idx < anim.get_track_count():
			anim.track_set_interpolation_type(track_idx, _saved_interp[key])
	_saved_interp.clear()

# ---------------------------------------------------------------------------
static func _track_supports_interp(t: Animation.TrackType) -> bool:
	return t in [
		Animation.TYPE_VALUE,
		Animation.TYPE_POSITION_3D,
		Animation.TYPE_ROTATION_3D,
		Animation.TYPE_SCALE_3D,
		Animation.TYPE_BLEND_SHAPE,
	]

static func _idx_to_interp(idx: int) -> Animation.InterpolationType:
	match idx:
		0: return Animation.INTERPOLATION_NEAREST
		1: return Animation.INTERPOLATION_LINEAR
		2: return Animation.INTERPOLATION_CUBIC
		_: return Animation.INTERPOLATION_NEAREST
