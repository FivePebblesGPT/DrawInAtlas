extends Node

const TOGGLE_FULLSCREEN_ACTION: StringName = &"toggle_fullscreen"
const RELOAD_SCENE_ACTION: StringName = &"reload_scene"
const FULLSCREEN_MODE = Window.MODE_FULLSCREEN

func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_FULLSCREEN_ACTION):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed(RELOAD_SCENE_ACTION):
		print("reloading scene")
		var err: Error = get_tree().reload_current_scene()
		if err != OK:
			push_warning("Reload failed: %s" % err)
		get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	if get_window().mode == FULLSCREEN_MODE:
		get_window().mode = Window.MODE_WINDOWED
	else:
		get_window().mode = FULLSCREEN_MODE
	print("toggled fullscreen")
