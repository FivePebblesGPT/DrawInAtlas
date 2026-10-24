extends Control

enum FileAction { SAVE, LOAD, RESET_SAMPLE, NEW_BOARD }
enum EditAction { UNDO, REDO, COPY, CUT, PASTE, SELECT_ALL, DELETE }
enum ViewAction { SIDEBAR, GRID, BACK }

@onready var _split: HSplitContainer = %WorkspaceSplit
@onready var _sidebar: Sidebar = %Sidebar
@onready var _editor: AtlasEditor = _split.get_node("Workspace")
@onready var _file_menu: PopupMenu = %File
@onready var _edit_menu: PopupMenu = %Edit
@onready var _view_menu: PopupMenu = %View

var _expanded_offset: int = 308


func _ready() -> void:
	_expanded_offset = _split.split_offsets[0]
	_sidebar.panel_toggled.connect(_on_panel_toggled)
	_split.dragged.connect(_on_sidebar_resized)
	_build_menus()
	_file_menu.id_pressed.connect(_on_file_menu)
	_edit_menu.id_pressed.connect(_on_edit_menu)
	_view_menu.id_pressed.connect(_on_view_menu)
	_edit_menu.about_to_popup.connect(_sync_menus)
	_view_menu.about_to_popup.connect(_sync_menus)
	_editor.edits.changed.connect(_sync_menus)
	_editor.canvas.selection_changed.connect(_sync_menus)
	_sync_menus()


func _build_menus() -> void:
	var modifier: int = KEY_MASK_META if OS.has_feature("macos") else KEY_MASK_CTRL
	_file_menu.add_item("New board…", FileAction.NEW_BOARD, modifier | KEY_N)
	_file_menu.add_item("Save campaign", FileAction.SAVE, modifier | KEY_S)
	_file_menu.add_item("Load campaign", FileAction.LOAD)
	_file_menu.add_separator()
	_file_menu.add_item("Reset sample campaign", FileAction.RESET_SAMPLE)
	_edit_menu.add_item("Undo", EditAction.UNDO, modifier | KEY_Z)
	_edit_menu.add_item("Redo", EditAction.REDO, modifier | KEY_MASK_SHIFT | KEY_Z)
	_edit_menu.add_separator()
	_edit_menu.add_item("Copy", EditAction.COPY, modifier | KEY_C)
	_edit_menu.add_item("Cut", EditAction.CUT, modifier | KEY_X)
	_edit_menu.add_item("Paste", EditAction.PASTE, modifier | KEY_V)
	_edit_menu.add_item("Select all artwork", EditAction.SELECT_ALL, modifier | KEY_A)
	_edit_menu.add_item("Delete selection", EditAction.DELETE, KEY_DELETE)
	_view_menu.add_check_item("Sidebar", ViewAction.SIDEBAR, modifier | KEY_B)
	_view_menu.add_check_item("Grid overlay", ViewAction.GRID)
	_view_menu.add_separator()
	_view_menu.add_item("Back to previous map", ViewAction.BACK)
	# Display accelerator hints; existing context-aware handlers retain text-input undo.
	%MenuBar.set_disable_shortcuts(true)


func _on_panel_toggled(expanded: bool) -> void:
	_split.dragging_enabled = expanded
	_split.dragger_visibility = (
		SplitContainer.DRAGGER_HIDDEN if expanded
		else SplitContainer.DRAGGER_HIDDEN_COLLAPSED
	)
	_split.split_offsets = PackedInt32Array([_expanded_offset if expanded else 0])
	_sync_menus()


func _on_sidebar_resized(offset: int) -> void:
	_expanded_offset = offset


func _on_file_menu(id: int) -> void:
	match id:
		FileAction.NEW_BOARD:
			_editor.open_board_dialog()
		FileAction.SAVE:
			_editor._on_save()
		FileAction.LOAD:
			_editor._on_load()
		FileAction.RESET_SAMPLE:
			_editor._on_sample()


func _on_edit_menu(id: int) -> void:
	match id:
		EditAction.UNDO:
			_editor._on_undo()
		EditAction.REDO:
			_editor._on_redo()
		EditAction.COPY:
			_editor.copy_selection()
		EditAction.CUT:
			_editor.cut_selection()
		EditAction.PASTE:
			_editor.paste_selection()
		EditAction.SELECT_ALL:
			_editor.select_all_artwork()
		EditAction.DELETE:
			_editor.delete_selection()


func _on_view_menu(id: int) -> void:
	match id:
		ViewAction.SIDEBAR:
			_sidebar.toggle_panel()
		ViewAction.GRID:
			_editor.set_grid_visible(not _editor.canvas.show_grid)
		ViewAction.BACK:
			_editor._on_back()
	_sync_menus()


func _sync_menus() -> void:
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.UNDO), not _editor.edits.can_undo())
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.REDO), not _editor.edits.can_redo())
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.COPY), not _editor.can_copy_selection())
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.CUT), not _editor.can_modify_selection())
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.DELETE), not _editor.can_modify_selection())
	_view_menu.set_item_checked(_view_menu.get_item_index(ViewAction.SIDEBAR), _sidebar.is_panel_expanded())
	_view_menu.set_item_checked(_view_menu.get_item_index(ViewAction.GRID), _editor.canvas.show_grid)
	_view_menu.set_item_disabled(_view_menu.get_item_index(ViewAction.GRID),
		_editor.canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS)
	_view_menu.set_item_disabled(_view_menu.get_item_index(ViewAction.BACK), _editor.history.is_empty())
