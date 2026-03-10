## Flipdot — EditorPlugin
@tool
extends EditorPlugin

var _inspector_plugin: EditorInspectorPlugin

func _enter_tree() -> void:
	var script := preload("res://addons/flipdot/flipdot_player.gd")
	add_custom_type("FlipdotPlayer", "Node", script, null)

	_inspector_plugin = load("res://addons/flipdot/inspector_plugin.gd").new()
	add_inspector_plugin(_inspector_plugin)

func _exit_tree() -> void:
	remove_custom_type("FlipdotPlayer")
	remove_inspector_plugin(_inspector_plugin)
	_inspector_plugin = null
