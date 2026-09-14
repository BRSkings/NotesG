@tool
extends EditorPlugin

var workspace_ui: Control

func _enter_tree() -> void:
	var script = load("res://addons/NotesG/workspace_ui.gd")
	if script:
		workspace_ui = script.new()
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, workspace_ui)
	else:
		push_error("Failed to load workspace_ui.gd. Check for syntax errors in that file.")

func _exit_tree() -> void:
	if workspace_ui:
		remove_control_from_docks(workspace_ui)
		workspace_ui.queue_free()