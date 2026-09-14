@tool
extends Control

const LOCAL_PATH = "user://notes_workspace_data.json"

var folders_vbox: VBoxContainer

# The Data Structure
var folders_data: Array = []

# Tracks which LineEdit is currently being edited
var active_edit: LineEdit = null
var active_label: Label = null

# Folder scope popup menu
var scope_menu: PopupMenu
var popup_target_index: int = -1

# Variables for the folder delete confirmation dialog
var delete_dialog: ConfirmationDialog
var pending_delete_index: int = -1

# Variables for the block delete confirmation dialog
var delete_block_dialog: ConfirmationDialog
var pending_delete_block_folder: int = -1
var pending_delete_block_index: int = -1

func _ready() -> void:
	name = "NotesG"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	_load_data()
	_build_ui()
	_rebuild_ui()

# ==========================================
# GLOBAL PATH HELPER
# ==========================================
func _get_global_path() -> String:
	var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return docs_dir.path_join("easynotes_global.json")

# ==========================================
# UI CONSTRUCTION
# ==========================================
func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 5)
	add_child(main_vbox)
	
	# --- Top Bar ---
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 5)
	main_vbox.add_child(top_bar)
	
	var add_new_folder_lbl = RichTextLabel.new()
	add_new_folder_lbl.bbcode_enabled = true
	add_new_folder_lbl.text = "[font_size=28]+[/font_size]            Create a New Folder"
	add_new_folder_lbl.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
	add_new_folder_lbl.fit_content = true
	add_new_folder_lbl.scroll_active = false
	add_new_folder_lbl.custom_minimum_size.y = 36
	add_new_folder_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_new_folder_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_new_folder_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	
	add_new_folder_lbl.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_add_btn_pressed()
	)
	top_bar.add_child(add_new_folder_lbl)
	
	# --- Folder Container ---
	folders_vbox = VBoxContainer.new()
	folders_vbox.add_theme_constant_override("separation", 5)
	main_vbox.add_child(folders_vbox)
	
	# --- Scope Popup Menu ---
	scope_menu = PopupMenu.new()
	scope_menu.add_radio_check_item("Make Local", 0)
	scope_menu.add_radio_check_item("Make Global", 1)
	scope_menu.add_separator()
	scope_menu.add_item("Delete Folder", 2)
	scope_menu.id_pressed.connect(_on_scope_menu_pressed)
	
	var editor_root = EditorInterface.get_base_control()
	if editor_root:
		editor_root.add_child(scope_menu)
	else:
		add_child(scope_menu)
	
	# --- Folder Confirmation Dialog ---
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete Folder"
	delete_dialog.dialog_text = "Are you sure you want to delete this folder?\nThis action cannot be undone."
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	delete_dialog.canceled.connect(_on_delete_canceled)
	add_child(delete_dialog)
	
	# --- Block Confirmation Dialog ---
	delete_block_dialog = ConfirmationDialog.new()
	delete_block_dialog.title = "Delete Block"
	delete_block_dialog.dialog_text = "Are you sure you want to delete this code block?\nThis action cannot be undone."
	delete_block_dialog.confirmed.connect(_on_delete_block_confirmed)
	delete_block_dialog.canceled.connect(_on_delete_block_canceled)
	add_child(delete_block_dialog)

# ==========================================
# DATA MANAGEMENT (SAVE / LOAD)
# ==========================================
func _save_data() -> void:
	var local_folders: Array = []
	var global_folders: Array = []
	
	for folder in folders_data:
		var scope = folder.get("scope", "local")
		if scope == "global":
			global_folders.append(folder)
		else:
			local_folders.append(folder)
	
	var local_file = FileAccess.open(LOCAL_PATH, FileAccess.WRITE)
	if local_file:
		local_file.store_string(JSON.stringify(local_folders, "\t"))
		local_file.close()
	
	var global_path = _get_global_path()
	var global_file = FileAccess.open(global_path, FileAccess.WRITE)
	if global_file:
		global_file.store_string(JSON.stringify(global_folders, "\t"))
		global_file.close()

func _load_data() -> void:
	folders_data = []
	
	# 1. Load local folders
	if FileAccess.file_exists(LOCAL_PATH):
		var file = FileAccess.open(LOCAL_PATH, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			var local_arr = json.data
			if local_arr is Array:
				for folder in local_arr:
					folder["scope"] = "local"
					folders_data.append(folder)
	
	# 2. Load global folders
	var global_path = _get_global_path()
	if FileAccess.file_exists(global_path):
		var file = FileAccess.open(global_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			var global_arr = json.data
			if global_arr is Array:
				for folder in global_arr:
					folder["scope"] = "global"
					folders_data.append(folder)
	
	# 3. Migration
	for folder in folders_data:
		if not folder.has("blocks"):
			var old_code = folder.get("code", "")
			var old_notes = folder.get("notes", "")
			var old_notes_open = folder.get("notes_open", false)
			folder["blocks"] = [{
				"code": old_code,
				"notes": old_notes,
				"notes_open": old_notes_open
			}]
			folder.erase("code")
			folder.erase("notes")
			folder.erase("notes_open")
		if not folder.has("scope"):
			folder["scope"] = "local"

# ==========================================
# UI REBUILDING
# ==========================================
func _rebuild_ui() -> void:
	for child in folders_vbox.get_children():
		child.queue_free()
		
	for i in range(folders_data.size()):
		if i > 0:
			var separator_margin = MarginContainer.new()
			separator_margin.add_theme_constant_override("margin_top", 8)
			separator_margin.add_theme_constant_override("margin_bottom", 8)
			
			var sep = HSeparator.new()
			var sep_style = StyleBoxLine.new()
			sep_style.color = Color(0.4, 0.4, 0.4, 0.5)
			sep_style.thickness = 1
			sep.add_theme_stylebox_override("separator", sep_style)
			
			separator_margin.add_child(sep)
			folders_vbox.add_child(separator_margin)
		
		_create_folder_ui(folders_data[i], i)

func _create_folder_ui(data: Dictionary, index: int) -> void:
	var folder_container = VBoxContainer.new()
	folder_container.name = "FolderContainer_" + str(index)
	folder_container.add_theme_constant_override("separation", 5)
	folders_vbox.add_child(folder_container)
	
	# --- Folder Row ---
	var folder_row = HBoxContainer.new()
	folder_row.add_theme_constant_override("separation", 5)
	folder_container.add_child(folder_row)
	
	# Folder Icon
	var folder_icon = TextureRect.new()
	var custom_folder_texture = load("res://addons/NotesG/folderIcon.svg") 
	if custom_folder_texture:
		folder_icon.texture = custom_folder_texture
	else:
		var editor_theme = EditorInterface.get_editor_theme()
		if editor_theme:
			folder_icon.texture = editor_theme.get_icon("Folder", "EditorIcons")
	folder_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	folder_row.add_child(folder_icon)
	
	# Display Label
	var folder_label = Label.new()
	folder_label.text = data.get("name", "Codefolder " + str(index + 1))
	folder_label.tooltip_text = folder_label.text + "\n(Right-click for options)"
	folder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	folder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART 
	folder_label.mouse_filter = Control.MOUSE_FILTER_STOP 
	folder_row.add_child(folder_label)
	
	# Edit Field
	var folder_edit = LineEdit.new()
	folder_edit.text = folder_label.text
	folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_edit.visible = false
	folder_row.add_child(folder_edit)
	
	folder_label.gui_input.connect(_on_label_gui_input.bind(folder_label, folder_edit, index))
	folder_edit.text_submitted.connect(_on_edit_submitted)
	
	# =======================================================
	# Globe Icon (Custom SVG - NOW FIXED SIZE)
	# =======================================================
	var globe_icon = TextureRect.new()
	var custom_globe_texture = load("res://addons/NotesG/globe.svg")
	
	if custom_globe_texture:
		globe_icon.texture = custom_globe_texture
	else:
		var editor_theme = EditorInterface.get_editor_theme()
		if editor_theme:
			globe_icon.texture = editor_theme.get_icon("Script", "EditorIcons")
		push_warning("Custom globe icon not found at res://addons/NotesG/globe.svg")
	
	globe_icon.custom_minimum_size = Vector2(16, 16)
	globe_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	globe_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	globe_icon.tooltip_text = "This folder is Global (shared between all projects)"
	globe_icon.visible = (data.get("scope", "local") == "global")
	folder_row.add_child(globe_icon)
	# =======================================================
	
	# Arrow Button
	var arrow_btn = Button.new()
	arrow_btn.text = "⌄" if data.get("folder_open", false) else "‹"
	arrow_btn.flat = true
	arrow_btn.focus_mode = Control.FOCUS_NONE
	arrow_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	arrow_btn.toggle_mode = true
	arrow_btn.button_pressed = data.get("folder_open", false)
	folder_row.add_child(arrow_btn)
	
	# Delete Folder Button
	var delete_btn = Button.new()
	delete_btn.text = "X"
	delete_btn.flat = true
	delete_btn.focus_mode = Control.FOCUS_NONE
	delete_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	delete_btn.add_theme_font_size_override("font_size", 12)
	delete_btn.custom_minimum_size = Vector2(25, 25)
	delete_btn.tooltip_text = "Delete Folder"
	delete_btn.pressed.connect(_on_delete_pressed.bind(index))
	folder_row.add_child(delete_btn)
	
	# =======================================================
	# BLOCKS CONTAINER
	# =======================================================
	var blocks_vbox = VBoxContainer.new()
	blocks_vbox.add_theme_constant_override("separation", 5)
	blocks_vbox.visible = data.get("folder_open", false)
	folder_container.add_child(blocks_vbox)
	
	var blocks = data.get("blocks", [])
	for b_idx in range(blocks.size()):
		var block_ui = _create_block_ui(blocks[b_idx], index, b_idx)
		blocks_vbox.add_child(block_ui)
	
	# --- Add Block Button ---
	var add_block_btn = Button.new()
	add_block_btn.text = "+"
	add_block_btn.flat = true
	add_block_btn.focus_mode = Control.FOCUS_NONE
	add_block_btn.tooltip_text = "Add new code block"
	add_block_btn.add_theme_font_size_override("font_size", 24)
	add_block_btn.custom_minimum_size = Vector2(36, 36)
	add_block_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	
	var block_hover = StyleBoxFlat.new()
	block_hover.bg_color = Color("1B1F24")
	block_hover.corner_radius_top_left = 20
	block_hover.corner_radius_top_right = 20
	block_hover.corner_radius_bottom_left = 20
	block_hover.corner_radius_bottom_right = 20
	add_block_btn.add_theme_stylebox_override("hover", block_hover)
	
	var block_pressed = block_hover.duplicate()
	block_pressed.bg_color = Color("2A3038")
	add_block_btn.add_theme_stylebox_override("pressed", block_pressed)
	
	add_block_btn.pressed.connect(_on_add_block_pressed.bind(index))
	blocks_vbox.add_child(add_block_btn)
	# =======================================================
	
	# --- Folder Toggle Logic ---
	arrow_btn.toggled.connect(func(is_pressed):
		data["folder_open"] = is_pressed
		if is_pressed:
			arrow_btn.text = "⌄"
			blocks_vbox.visible = true
		else:
			arrow_btn.text = "‹"
			blocks_vbox.visible = false
		_save_data()
	)

# ==========================================
# SCOPE POPUP MENU LOGIC
# ==========================================
func _open_scope_menu(index: int) -> void:
	popup_target_index = index
	var folder = folders_data[index]
	var current_scope = folder.get("scope", "local")
	
	scope_menu.set_item_checked(scope_menu.get_item_index(0), current_scope == "local")
	scope_menu.set_item_checked(scope_menu.get_item_index(1), current_scope == "global")
	
	var mouse_pos = DisplayServer.mouse_get_position()
	scope_menu.popup(Rect2i(mouse_pos, Vector2i.ZERO))

func _on_scope_menu_pressed(id: int) -> void:
	if popup_target_index < 0 or popup_target_index >= folders_data.size():
		popup_target_index = -1
		return
	
	match id:
		0:  # Make Local
			folders_data[popup_target_index]["scope"] = "local"
			_save_data()
			_rebuild_ui()
		1:  # Make Global
			folders_data[popup_target_index]["scope"] = "global"
			_save_data()
			_rebuild_ui()
		2:  # Delete Folder
			_on_delete_pressed(popup_target_index)
	
	popup_target_index = -1

# ==========================================
# BLOCK CREATION (Code Box + Notes Box)
# ==========================================
func _create_block_ui(block_data: Dictionary, folder_index: int, block_index: int) -> Control:
	var block_container = VBoxContainer.new()
	block_container.add_theme_constant_override("separation", 5)
	
	# =======================================================
	# THE CODE BLACK BOX
	# =======================================================
	var code_box_panel = PanelContainer.new()
	block_container.add_child(code_box_panel)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color("22272F")
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	code_box_panel.add_theme_stylebox_override("panel", bg_style)
	
	var code_margin = MarginContainer.new()
	code_margin.add_theme_constant_override("margin_left", 10)
	code_margin.add_theme_constant_override("margin_right", 10)
	code_margin.add_theme_constant_override("margin_top", 6)
	code_margin.add_theme_constant_override("margin_bottom", 6)
	code_box_panel.add_child(code_margin)
	
	var code_input = TextEdit.new()
	code_input.text = block_data.get("code", "")
	code_input.placeholder_text = "Code"
	code_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY 
	code_input.scroll_fit_content_height = true 
	code_input.custom_minimum_size.y = 30 
	
	code_input.add_theme_color_override("font_placeholder_color", Color("9BB2DB", 0.4))
	code_input.add_theme_color_override("font_color", Color("9BB2DB"))
	
	var empty_style = StyleBoxEmpty.new()
	empty_style.content_margin_right = 100 
	code_input.add_theme_stylebox_override("normal", empty_style)
	code_input.add_theme_stylebox_override("focus", empty_style) 
	
	var highlighter = null
	var script_editor = EditorInterface.get_script_editor()
	if script_editor:
		var current_editor = script_editor.get_current_editor()
		if current_editor:
			var base_editor = current_editor.get_base_editor()
			if base_editor is CodeEdit and base_editor.syntax_highlighter:
				highlighter = base_editor.syntax_highlighter
	if highlighter:
		code_input.syntax_highlighter = highlighter.duplicate()
	
	code_margin.add_child(code_input)
	
	code_input.text_changed.connect(func():
		block_data["code"] = code_input.text
		_save_data()
	)
	
	# --- Buttons inside Code Box ---
	var button_hbox = HBoxContainer.new()
	button_hbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	button_hbox.size_flags_vertical = Control.SIZE_SHRINK_END
	button_hbox.add_theme_constant_override("separation", 5)
	
	var send_btn = Button.new()
	send_btn.text = "↩"
	send_btn.tooltip_text = "Send code to the currently open script"
	send_btn.flat = true
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	send_btn.custom_minimum_size = Vector2(30, 25)
	send_btn.pressed.connect(func():
		_send_to_script_editor(code_input.text)
	)
	button_hbox.add_child(send_btn)
	
	var delete_block_btn = Button.new()
	delete_block_btn.text = "X"
	delete_block_btn.tooltip_text = "Delete this code block"
	delete_block_btn.flat = true
	delete_block_btn.focus_mode = Control.FOCUS_NONE
	delete_block_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	delete_block_btn.add_theme_font_size_override("font_size", 12)
	delete_block_btn.custom_minimum_size = Vector2(30, 25)
	delete_block_btn.pressed.connect(_on_delete_block_pressed.bind(folder_index, block_index))
	button_hbox.add_child(delete_block_btn)
	
	# =======================================================
	# THE NOTES BLACK BOX
	# =======================================================
	var notes_box_panel = PanelContainer.new()
	notes_box_panel.visible = block_data.get("notes_open", false)
	notes_box_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	block_container.add_child(notes_box_panel)
	
	var notes_bg_style = StyleBoxFlat.new()
	notes_bg_style.bg_color = Color("22272F")
	notes_bg_style.corner_radius_top_left = 4
	notes_bg_style.corner_radius_top_right = 4
	notes_bg_style.corner_radius_bottom_left = 4
	notes_bg_style.corner_radius_bottom_right = 4
	notes_box_panel.add_theme_stylebox_override("panel", notes_bg_style)
	
	var notes_margin = MarginContainer.new()
	notes_margin.add_theme_constant_override("margin_left", 10)
	notes_margin.add_theme_constant_override("margin_right", 10)
	notes_margin.add_theme_constant_override("margin_top", 6)
	notes_margin.add_theme_constant_override("margin_bottom", 6)
	notes_box_panel.add_child(notes_margin)
	
	var notes_vbox = VBoxContainer.new()
	notes_vbox.add_theme_constant_override("separation", 2)
	notes_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	notes_margin.add_child(notes_vbox)
	
	var notes_title = Label.new()
	notes_title.text = "Notes"
	notes_title.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	notes_title.add_theme_color_override("font_color", Color("9BB2DB"))
	
	var bold_font = FontVariation.new()
	bold_font.base_font = notes_title.get_theme_font("font")
	bold_font.variation_embolden = 1.0 
	notes_title.add_theme_font_override("font", bold_font)
	
	notes_vbox.add_child(notes_title)
	
	var notes_input = TextEdit.new()
	notes_input.text = block_data.get("notes", "")
	notes_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY 
	notes_input.scroll_fit_content_height = true 
	notes_input.custom_minimum_size.y = 40 
	notes_input.add_theme_color_override("font_color", Color("9BB2DB"))
	
	var notes_empty_style = StyleBoxEmpty.new()
	notes_input.add_theme_stylebox_override("normal", notes_empty_style)
	notes_input.add_theme_stylebox_override("focus", notes_empty_style) 
	
	notes_vbox.add_child(notes_input)
	
	notes_input.text_changed.connect(func():
		block_data["notes"] = notes_input.text
		_save_data()
	)
	
	notes_box_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not notes_input.has_focus():
				notes_input.grab_focus()
				var last_line = notes_input.get_line_count() - 1
				notes_input.set_caret_line(last_line)
				notes_input.set_caret_column(notes_input.get_line(last_line).length())
				notes_box_panel.accept_event()
	)
	
	var toggle_notes_btn = Button.new()
	toggle_notes_btn.text = "⌄" if block_data.get("notes_open", false) else "‹"
	toggle_notes_btn.tooltip_text = "Toggle notes box"
	toggle_notes_btn.flat = true
	toggle_notes_btn.focus_mode = Control.FOCUS_NONE
	toggle_notes_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	toggle_notes_btn.custom_minimum_size = Vector2(30, 25)
	toggle_notes_btn.toggle_mode = true
	toggle_notes_btn.button_pressed = block_data.get("notes_open", false)
	
	toggle_notes_btn.toggled.connect(func(is_pressed):
		block_data["notes_open"] = is_pressed
		if is_pressed:
			toggle_notes_btn.text = "⌄"
			notes_box_panel.visible = true
		else:
			toggle_notes_btn.text = "‹"
			notes_box_panel.visible = false
		_save_data()
	)
	button_hbox.add_child(toggle_notes_btn)
	
	code_box_panel.add_child(button_hbox)
	
	return block_container

# ==========================================
# ADD NEW FOLDER
# ==========================================
func _on_add_btn_pressed() -> void:
	_commit_active_edit()
	
	folders_data.append({
		"name": "Codefolder " + str(folders_data.size() + 1),
		"folder_open": false,
		"scope": "local",
		"blocks": [
			{"code": "", "notes": "", "notes_open": false}
		]
	})
	
	_save_data()
	_rebuild_ui()

# ==========================================
# ADD NEW BLOCK TO A FOLDER
# ==========================================
func _on_add_block_pressed(folder_index: int) -> void:
	_commit_active_edit()
	
	if folder_index < 0 or folder_index >= folders_data.size():
		return
	
	if not folders_data[folder_index].has("blocks"):
		folders_data[folder_index]["blocks"] = []
	
	folders_data[folder_index]["blocks"].append({
		"code": "",
		"notes": "",
		"notes_open": false
	})
	
	_save_data()
	_rebuild_ui()

# ==========================================
# DELETE FOLDER LOGIC
# ==========================================
func _on_delete_pressed(index: int) -> void:
	pending_delete_index = index
	delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if pending_delete_index >= 0 and pending_delete_index < folders_data.size():
		folders_data.remove_at(pending_delete_index)
		_save_data()
		_rebuild_ui()
	pending_delete_index = -1

func _on_delete_canceled() -> void:
	pending_delete_index = -1

# ==========================================
# DELETE BLOCK LOGIC
# ==========================================
func _on_delete_block_pressed(folder_index: int, block_index: int) -> void:
	pending_delete_block_folder = folder_index
	pending_delete_block_index = block_index
	delete_block_dialog.popup_centered()

func _on_delete_block_confirmed() -> void:
	if pending_delete_block_folder >= 0 and pending_delete_block_folder < folders_data.size():
		var folder = folders_data[pending_delete_block_folder]
		if folder.has("blocks"):
			if pending_delete_block_index >= 0 and pending_delete_block_index < folder["blocks"].size():
				folder["blocks"].remove_at(pending_delete_block_index)
				_save_data()
				_rebuild_ui()
	pending_delete_block_folder = -1
	pending_delete_block_index = -1

func _on_delete_block_canceled() -> void:
	pending_delete_block_folder = -1
	pending_delete_block_index = -1

# ==========================================
# EDITING LOGIC (RENAMING + RIGHT-CLICK)
# ==========================================
func _on_label_gui_input(event: InputEvent, label: Label, edit: LineEdit, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_commit_active_edit()
			label.visible = false
			edit.visible = true
			edit.text = label.text
			edit.grab_focus()
			edit.select_all()
			active_edit = edit
			active_label = label
			edit.set_meta("folder_index", index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_scope_menu(index)

func _on_edit_submitted(_new_text: String) -> void:
	_commit_active_edit()

func _commit_active_edit() -> void:
	if not active_edit or not active_label:
		return
	if active_edit.text.strip_edges() != "":
		active_label.text = active_edit.text
		active_label.tooltip_text = active_edit.text + "\n(Right-click for options)"
		if active_edit.has_meta("folder_index"):
			var idx = active_edit.get_meta("folder_index")
			if idx < folders_data.size():
				folders_data[idx]["name"] = active_edit.text
				_save_data()
				
	active_edit.visible = false
	active_label.visible = true
	active_edit = null
	active_label = null

# ==========================================
# GLOBAL INPUT (Click-Outside Detection)
# ==========================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if active_edit and active_edit.visible:
			var mouse_pos = active_edit.get_local_mouse_position()
			var is_inside = Rect2(Vector2.ZERO, active_edit.size).has_point(mouse_pos)
			if not is_inside:
				_commit_active_edit()
		
		var focused_control = get_viewport().gui_get_focus_owner()
		if focused_control is TextEdit:
			var mouse_pos_txt = focused_control.get_local_mouse_position()
			var is_inside_txt = Rect2(Vector2.ZERO, focused_control.size).has_point(mouse_pos_txt)
			
			var is_inside_panel = false
			var parent = focused_control.get_parent()
			while parent:
				if parent is PanelContainer:
					var panel_rect = parent.get_global_rect()
					is_inside_panel = panel_rect.has_point(event.position)
					break
				parent = parent.get_parent()
				
			if not is_inside_txt and not is_inside_panel:
				focused_control.release_focus()

# ==========================================
# SEND TO SCRIPT LOGIC
# ==========================================
func _send_to_script_editor(text_to_insert: String) -> void:
	var script_editor = EditorInterface.get_script_editor()
	if not script_editor:
		return
		
	var current_editor = script_editor.get_current_editor()
	if not current_editor:
		return
		
	var base_editor = current_editor.get_base_editor()
	
	if base_editor is CodeEdit:
		base_editor.insert_text_at_caret(text_to_insert)
		base_editor.grab_focus()