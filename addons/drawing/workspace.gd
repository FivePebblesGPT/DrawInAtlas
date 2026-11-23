extends Control
## Shared Drawing shell; the host supplies Object Asset publication callbacks.
## No campaign, map, Atlas registry or history imports in this UI.

const CANVAS_SCRIPT: Script = preload("res://addons/drawing/canvas.gd")
const IMAGE_FRAME: Script = preload("res://addons/drawing/image_frame.gd")
const TOP_BAR_SCRIPT: Script = preload("res://addons/drawing/editor_top_bar.gd")
const DOCK_LAYOUT_SCRIPT: Script = preload("res://addons/drawing/dock_layout.gd")
const DOCK_DRAG_SCRIPT: Script = preload("res://addons/drawing/dock_drag.gd")
const FLOATING_HOST_SCRIPT: Script = preload("res://addons/drawing/floating_host.gd")
const DOCK_PERSISTENCE_SCRIPT: Script = preload("res://addons/drawing/dock_persistence.gd")
const DOCK_TOGGLE_SCRIPT: Script = preload("res://addons/drawing/dock_toggle.gd")
const DOCK_GROUP_MARKER_SCRIPT: Script = preload("res://addons/drawing/dock_group_marker.gd")
const WORKSPACE_PREFERENCES: Script = preload("res://addons/drawing/workspace_preferences.gd")
const COLOR_HISTORY_SETTINGS: Script = preload("res://addons/drawing/color_history_settings.gd")
const ASSET_BROWSER_SCRIPT: Script = preload("res://addons/drawing/asset_browser_panel.gd")
const ROOT_HISTORY: Script = preload("res://addons/drawing/object_root_history.gd")
const BRUSH_SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")
const BRUSH_PANEL_SCRIPT: Script = preload("res://addons/drawing/brush_panel.gd")
const ROW_EYE: int = 1
const ROW_LOCK: int = 2
# Largest compact built-in panel (Colors/History plus scrollbar) needs
# a stable floor. Otherwise floating a group shrinks the dock's intrinsic
# minimum and silently changes the canvas width without a splitter drag.
# The T-251 fixed left overlay gutter adds 34px to the original 192px
# minimum. Keep a constant floor independent of which panel is docked or floated.
const EXPANDED_DOCK_MIN_WIDTH: int = 226

signal object_tab_closed(session: DrawingObjectEditorSession)

var start_blank_document: bool = true
## One store per host Godot project (Drawing and Atlas have independent user:// roots).
## A harness can opt out before add_child(), or supply a private test file.
var layout_persistence_enabled: bool = true
## Peers registered before entering the tree participate in restore and recovery.
## The future Asset Browser can use this without this shell depending on it.
var initial_extra_panels: Dictionary = {} # Stable id -> Control
## Host-provided portable root is registered before dock settings recovery.
var initial_asset_browser_root: String = ""
var asset_browser: DrawingAssetBrowserPanel
var asset_browser_directory_dialog: FileDialog
var recent_objects_root_settings_path: String = "user://drawing-recent-objects-root-v1.json"
var _recent_objects_root: String = ""
var layout_panel_aliases: Dictionary = {} # Explicit old stable ID -> registered new ID
var layout_settings_path: String = "user://drawing-workspace-dock-v1.json"
var preferences_persistence_enabled: bool = true
var preferences_settings_path: String = "user://drawing-workspace-preferences-v1.json"
var recent_colors_settings_path: String = "user://drawing-recent-colors-v1.json"
var layout_recovery_status: String = "defaults" # defaults / loaded / repaired / invalid
var _layout_booted: bool = false
var _layout_save_pending: bool = false
var _saved_layout_width: int = 270
var _saved_layout_scroll: int = 0
var tabs: Array[Dictionary] = []
var active_tab: int = -1
var active_tool: String = "Brush"
var active_color: Color = Color(0.12, 0.20, 0.35)
var canvas: Control
var tab_bar: TabBar
var tabs_line: HBoxContainer
var show_document_tabs: bool = true
var tool_buttons: Dictionary = {}
var layers: Tree
var status: Label
var width_spin: SpinBox
var brush_preset_control: OptionButton
var brush_panel: DrawingBrushPanel
var selected_brush_preset: String = "hard"
var brush_width_value: float = 3.0
var brush_opacity_value: float = 1.0
var brush_hardness_overrides: Dictionary = {} # preset -> native hardness 0..1
var brush_density_overrides: Dictionary = {} # preset -> native dabs / actual radius, 1..8
var snap_toggle: CheckButton
var grid_dialog: ConfirmationDialog
var grid_fields: Array[SpinBox] = []
var image_frame_dialog: ConfirmationDialog
var image_frame_fields: Array[SpinBox] = []
var top_bar: HBoxContainer
var inspector: ScrollContainer
var dock_panel_gutter: MarginContainer
var dock_panels: VBoxContainer
var dock_rail: VBoxContainer
var dock_toggle_slot: HBoxContainer
var dock_toggle: Button
var dock_panel_menu: PopupMenu
var _dock_menu_panel_id: String = ""
var dock_group_menu: PopupMenu
var _dock_menu_group_id: String = ""
var dock_stash: VBoxContainer
var dock_flyout: PanelContainer
var dock_flyout_tabs: HBoxContainer
var dock_flyout_tab_scroll: ScrollContainer
var dock_flyout_body: VBoxContainer
var dock_rail_buttons: Dictionary = {} # UI buttons; membership always comes from dock_layout.
var dock_header_buttons: Dictionary = {}
var dock_tab_buttons: Dictionary = {}
var dock_tab_strips: Dictionary = {}
var dock_group_frames: Dictionary = {}
var dock_group_handles: Dictionary = {}
var dock_drag: DrawingDockDrag
var floating_hosts: Dictionary = {} # Container ID -> DrawingFloatingHost (real Control)
var _floating_serial: int = 0
var dock_drop_hint: ColorRect
var dock_drop_caption: Label
var dock_merge_outline: Panel
var _drag_candidate_kind: String = ""
var _drag_candidate_id: String = ""
var _drag_candidate_position: Vector2 = Vector2.ZERO
var _drag_pointer_position: Vector2 = Vector2.ZERO
var _suppress_drag_release: bool = false
var _drag_candidate_moved: bool = false
var _cross_source: String = "" # Pointer source: right dock or a floating host.
var _detach_preview: bool = false
var _detach_hint: PanelContainer
var _expanded_dock_width: int = 270
var _expanded_scroll: int = 0
var dock_layout: DrawingDockLayout
var dock_views: Dictionary = {} # Stable panel IDs -> existing Controls, never duplicated.
var dock_split: HSplitContainer
var selection_history_toggle: CheckButton
var history_label: Label
var history_list: ItemList
var _history_row_positions: Array[int] = []
var _rendering_history: bool = false
var history_undo: Button
var history_redo: Button
var _history_stamp: String = ""
var color_hex: LineEdit
var color_rgb: Array[SpinBox] = []
var color_edit_background: bool = false
var color_swatch_buttons: Array[Button] = []
var color_advanced: ColorPicker
var color_recent_buttons: Array[Button] = []
var color_top_strip: HBoxContainer
var color_picker_scroll: ScrollContainer
var foreground_button: Button
var background_button: Button
var color_background: Color = Color.WHITE
var recent_colors: Array[Color] = []
var _updating_color_widgets: bool = false
## A native picker/SpinBox can emit many color_changed events during one
## pointer/keyboard gesture. Show each RGBA8 preview, but commit exactly the
## previous settled pigment to recents when the gesture ends.
var _color_edit_pending: bool = false
var _color_edit_background: bool = false
var _color_edit_original: Color = Color.TRANSPARENT
var _color_edit_pointer_down: bool = false
var _color_edit_text: Control
var _color_edit_ignore_until_release: bool = false
## After a lost release or OS focus loss, discard stale picker signals until
## the next deliberate press, which must be able to start a fresh gesture.
var _color_edit_recover_on_press: bool = false
var _color_write_suspended: bool = false
var preferences_dialog: AcceptDialog
var open_dialog: FileDialog
var save_dialog: FileDialog
var new_counter: int = 0
## Application preference; existing selection entries survive toggling it off.
var record_selection_history: bool = false
var _before_gesture: DrawingHistoryContext
var _last_selection_context: DrawingHistoryContext
var _restoring_context: bool = false
## Internal clipboard: active raster layer only, independent from OS formats.
var drawing_clipboard: DrawingClipboard
var _paste_serial: int = 0
var selection_mode_control: OptionButton
var text_dialog: ConfirmationDialog
var text_edit: TextEdit
var text_font: OptionButton
var text_size: SpinBox
var text_angle: SpinBox
var text_alignment: OptionButton
var text_color: ColorPickerButton
var text_target: String = ""
var text_position: Vector2i = Vector2i.ZERO
var layer_icons: Dictionary = {} # Imported SVG textures cached once per workspace.
var layer_search: LineEdit
var layer_rename_dialog: ConfirmationDialog
var layer_rename_field: LineEdit
var layer_page: int = 0
var layer_page_label: Label
var object_open_dialog: FileDialog
var close_dialog: ConfirmationDialog
var rename_dialog: ConfirmationDialog
var rename_field: LineEdit
var frame_dialog: ConfirmationDialog
var frame_fields: Array[SpinBox] = []
var variant_dialog: ConfirmationDialog
var variant_name: LineEdit
var _closing_index: int = -1
var _close_after_save: bool = false
## Only the standalone top-level Drawing window owns the process quit policy.
## Embedded Atlas workspaces must leave their host's window handling intact.
var _window_quit_guard_enabled: bool = false
var _old_auto_accept_quit: bool = true
var _window_quit_requested: bool = false
var _local_save_as: bool = false
## FileDialog and the hosted Object-variant dialog complete asynchronously.
## Freeze the initiating tab/document/session so a later callback cannot
## write the currently selected *different* tab to the chosen destination.
var _save_dialog_target: Dictionary = {}
var _variant_dialog_target: Dictionary = {}
var _authoring_dialog_targets: Dictionary = {}
const ROW_PAGE: int = 200



func _ready() -> void:
	if get_parent() == get_tree().root and "--verify-native-extension" in OS.get_cmdline_user_args():
		get_tree().quit(preload("res://addons/drawing/native_extension_probe.gd").run())
		return
	_recent_objects_root = ROOT_HISTORY.read_file(recent_objects_root_settings_path)
	_load_preferences()
	_load_color_history()
	_build_interface()
	if not initial_asset_browser_root.is_empty():
		show_asset_browser(initial_asset_browser_root)
	_restore_workspace_layout()
	if start_blank_document:
		new_drawing()
	# The OS close button bypasses File > Close Tab. Only the standalone root
	# installs this gate; the Atlas host owns its own application lifecycle.
	if get_parent() == get_tree().root:
		_old_auto_accept_quit = get_tree().auto_accept_quit
		get_tree().auto_accept_quit = false
		_window_quit_guard_enabled = true


func _build_interface() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	top_bar = TOP_BAR_SCRIPT.new() as HBoxContainer
	root.add_child(top_bar)
	# Ordinary documents and portable Object sources have independent commands.
	# The same canonical workspace is embedded by standalone Drawing and Atlas.
	top_bar.add_menu_spec("File", ["New  Ctrl+N", "Open…  Ctrl+O", "Save  Ctrl+S",
		"Save As…  Ctrl+Shift+S", "Close Tab  Ctrl+W"],
		[Callable(self, "new_drawing"), Callable(self, "_ask_open"),
		Callable(self, "_save"), Callable(self, "_ask_save"),
		Callable(self, "_request_close_current")])
	top_bar.add_menu_spec("Object", ["New Source", "Open Source…", "Rename Source…",
		"Save Source As…", "Browse Sources…"],
		[Callable(self, "new_object"), Callable(self, "_ask_open_object"),
		Callable(self, "_ask_rename_object"), Callable(self, "_ask_save"),
		Callable(self, "_show_asset_browser_empty")])
	top_bar.add_menu_spec("Edit", ["Undo  Ctrl+Z", "Redo  Ctrl+Y",
		"Preferences…", "Copy  Ctrl+C", "Cut  Ctrl+X",
		"Paste  Ctrl+V", "Delete selected pixels  Del"],
		[Callable(self, "_undo"), Callable(self, "_redo"),
		Callable(self, "_show_preferences"), Callable(self, "_copy_selection"),
		Callable(self, "_cut_selection"), Callable(self, "_paste_selection"),
		Callable(self, "_delete_selection")])
	top_bar.add_menu_spec("View", ["Zoom in", "Zoom out", "Reset view",
		"Show grid", "Grid spacing and origin…", "Pixel grid at high zoom"],
		[func() -> void: _zoom(1.25), func() -> void: _zoom(0.8),
		func() -> void: _reset_view(), Callable(self, "_toggle_grid"),
		Callable(self, "_ask_grid_settings"), Callable(self, "_toggle_pixel_grid")])
	top_bar.add_menu_spec("Image", ["Rasterize text layer", "Object frame…",
		"Drawing image frame…"],
		[Callable(self, "_rasterize_text"), Callable(self, "_ask_object_frame"),
		Callable(self, "_ask_image_frame")])
	top_bar.add_menu_spec("Layers", ["Add group", "Add raster layer",
		"Remove selected", "Toggle visibility", "Toggle lock", "Rename…",
		"Move up", "Move down", "Indent into previous group", "Outdent from group"],
		[Callable(self, "_add_group"), Callable(self, "_add_layer"),
		Callable(self, "_remove_layer"), Callable(self, "_toggle_visibility"),
		Callable(self, "_toggle_layer_lock"), Callable(self, "_ask_layer_rename"),
		Callable(self, "_move_selected_layer").bind(-1),
		Callable(self, "_move_selected_layer").bind(1),
		Callable(self, "_indent_selected_layer"), Callable(self, "_outdent_selected_layer")])
	top_bar.add_menu_spec("Select", ["Rectangle selection", "Move selected pixels",
		"Drop moved pixels  Enter", "Cancel floating Move  Esc",
		"Deselect  Ctrl+D", "Replace", "Add", "Subtract", "Intersect"],
		[Callable(self, "_change_tool").bind("Select"),
		Callable(self, "_change_tool").bind("Move"),
		Callable(self, "_drop_floating_move"), Callable(self, "_cancel_floating_move"),
		Callable(self, "_deselect"), Callable(self, "_set_selection_mode").bind("Replace"),
		Callable(self, "_set_selection_mode").bind("Add"),
		Callable(self, "_set_selection_mode").bind("Subtract"),
		Callable(self, "_set_selection_mode").bind("Intersect")])
	top_bar.add_menu_spec("Window", ["Minimize/expand panel dock", "Reset panel width",
		"Show document tabs", "Next tab  Ctrl+Tab", "Previous tab  Ctrl+Shift+Tab",
		"Float selected dock group", "Show hidden floating panels", "Reset workspace layout",
		"Asset Browser…"],
		[Callable(self, "_toggle_dock"), Callable(self, "_reset_dock_width"),
		Callable(self, "_toggle_document_tabs"), Callable(self, "_cycle_tab").bind(1),
		Callable(self, "_cycle_tab").bind(-1),
		Callable(self, "_float_selected_dock_group"), Callable(self, "show_hidden_floating_hosts"),
		Callable(self, "reset_workspace_layout"), Callable(self, "_ask_asset_browser")])
	top_bar.set_menu_checked("Window", 2, show_document_tabs)
	top_bar.add_menu_spec("Help", ["About Drawing workspace"],
		[Callable(self, "_show_about_workspace")])
	width_spin = SpinBox.new()
	width_spin.min_value = 1
	width_spin.max_value = 96
	width_spin.value = brush_width_value
	width_spin.prefix = "Brush px"
	width_spin.tooltip_text = "Stroke width in Drawing pixels (wheel or [ / ] keys; Shift+wheel scrolls options)"
	width_spin.custom_minimum_size.x = 170
	width_spin.value_changed.connect(_set_brush_width)
	width_spin.gui_input.connect(func(event: InputEvent) -> void:
		top_bar.consume_option_wheel(event, width_spin))
	brush_preset_control = OptionButton.new()
	brush_preset_control.name = "BrushPreset"
	brush_preset_control.tooltip_text = "Native brush preset (also used by Eraser); width is set in Brush px"
	brush_preset_control.custom_minimum_size.x = 140
	for index: int in range(BRUSH_SETTINGS.PRESETS.size()):
		brush_preset_control.add_item(BRUSH_SETTINGS.NAMES[index])
		brush_preset_control.set_item_metadata(index, BRUSH_SETTINGS.PRESETS[index])
		brush_preset_control.get_popup().set_item_tooltip(index, BRUSH_SETTINGS.DESCRIPTIONS[index])
	brush_preset_control.item_selected.connect(func(index: int) -> void:
		_select_brush_preset(str(brush_preset_control.get_item_metadata(index))))
	brush_preset_control.gui_input.connect(func(event: InputEvent) -> void:
		top_bar.consume_option_wheel(event, brush_preset_control))
	snap_toggle = CheckButton.new()
	snap_toggle.text = "Snap (8 px)"
	snap_toggle.tooltip_text = "Snap only Drawing edit tools; grid visibility is separate (View menu)"
	snap_toggle.toggled.connect(_set_snap_enabled)
	selection_mode_control = OptionButton.new()
	selection_mode_control.tooltip_text = "Marquee combine mode; select without changing document pixels"
	for option: String in ["Replace", "Add", "Subtract", "Intersect"]:
		selection_mode_control.add_item(option)
	selection_mode_control.item_selected.connect(func(index: int) -> void:
		_set_selection_mode(selection_mode_control.get_item_text(index)))
	# Inactive options also need an owner before their tool is first selected.
	for option: Control in [brush_preset_control, width_spin, snap_toggle, selection_mode_control]:
		top_bar._unused_options.add_child(option)
	_refresh_tool_options()
	tabs_line = HBoxContainer.new()
	tabs_line.name = "DocumentTabs"
	tab_bar = TabBar.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.tab_changed.connect(_activate)
	tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	tab_bar.tab_close_pressed.connect(_request_close_tab)
	tab_bar.clip_tabs = true
	tabs_line.add_child(tab_bar)
	dock_split = HSplitContainer.new()
	dock_split.name = "WorkspaceSplit"
	dock_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock_split.dragged.connect(_on_dock_split_dragged)
	dock_split.resized.connect(_apply_saved_dock_geometry)
	dock_split.resized.connect(_layout_dock_toggle)
	root.add_child(dock_split)
	var edit_region: HBoxContainer = HBoxContainer.new()
	edit_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_split.add_child(edit_region)
	var rail: VBoxContainer = VBoxContainer.new()
	rail.name = "ToolRail"
	# Keep the tool rail compact; the SVGs are 16px and do not need 44px-wide buttons.
	rail.custom_minimum_size.x = 42
	edit_region.add_child(rail)
	for name: String in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]:
		var button: Button = Button.new()
		button.name = name + "Tool"
		button.icon = load("res://addons/drawing/icons/%s.svg" % name.to_lower()) as Texture2D
		button.tooltip_text = "Drawing tool: " + name
		button.custom_minimum_size = Vector2(34, 34)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# Button defaults to left icon alignment even with no label: the glyph
		# otherwise sits several pixels left of the visual button center.
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.pressed.connect(_change_tool.bind(name))
		tool_buttons[name] = button
		rail.add_child(button)
	# Document tabs consume only the editing viewport, not the full tool rail
	# or the independent right-side panel dock.
	var editor_column: VBoxContainer = VBoxContainer.new()
	editor_column.name = "EditorContent"
	editor_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit_region.add_child(editor_column)
	editor_column.add_child(tabs_line)
	_refresh_tool_buttons()
	canvas = CANVAS_SCRIPT.new() as Control
	canvas.clip_strokes_to_image_frame = true
	# Explicit opt-in: translucent grid lines alter framebuffer colors and
	# should not be mistaken for texture filtering or removable paint pixels.
	top_bar.set_menu_checked("View", 5, canvas.show_pixel_grid)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(125, 190)
	canvas.gesture_started.connect(_gesture_started)
	canvas.gesture_committed.connect(_canvas_changed)
	canvas.selection_changed.connect(_selection_changed)
	canvas.canvas_error.connect(_show_error)
	canvas.view_changed.connect(_update_status)
	canvas.cursor_moved.connect(_update_status)
	canvas.resized.connect(_update_status)
	canvas.resized.connect(_maybe_fit_image_frame)
	canvas.resized.connect(_layout_dock_flyout)
	canvas.text_requested.connect(_edit_text_at)
	canvas.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_update_status())
	editor_column.add_child(canvas)
	canvas.color_rgba = _pack_color(active_color)
	canvas.brush_width = brush_width_value
	canvas.brush_preset = selected_brush_preset
	canvas.brush_opacity = brush_opacity_value
	canvas.brush_hardness = _selected_brush_hardness()
	canvas.brush_density = _selected_brush_density()
	brush_preset_control.select(BRUSH_SETTINGS.PRESETS.find(selected_brush_preset))
	inspector = ScrollContainer.new()
	inspector.name = "PanelDock"
	inspector.custom_minimum_size.x = EXPANDED_DOCK_MIN_WIDTH
	inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inspector.follow_focus = true
	dock_split.add_child(inspector)
	inspector.resized.connect(_layout_dock_toggle)
	inspector.item_rect_changed.connect(_layout_dock_toggle)
	dock_layout = DOCK_LAYOUT_SCRIPT.new() as DrawingDockLayout
	dock_layout.create_container("right")
	dock_drag = DOCK_DRAG_SCRIPT.new(dock_layout) as DrawingDockDrag
	_make_dock_hint()
	_make_detach_hint()
	dock_stash = VBoxContainer.new()
	dock_stash.name = "DockViewStorage"
	dock_stash.visible = false
	add_child(dock_stash)
	# Keep the edge toggle inside the dock without covering scrolling controls.
	# The right-side gutter matches the outer window edge, not the canvas seam.
	dock_panel_gutter = MarginContainer.new()
	dock_panel_gutter.name = "DockPanelGutter"
	dock_panel_gutter.add_theme_constant_override("margin_right", 34)
	dock_panel_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_child(dock_panel_gutter)
	dock_panels = VBoxContainer.new()
	dock_panels.name = "DockPanels"
	dock_panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_panel_gutter.add_child(dock_panels)
	dock_rail = VBoxContainer.new()
	dock_rail.name = "DockIconRail"
	dock_rail.custom_minimum_size.x = 48
	dock_rail.visible = false
	inspector.add_child(dock_rail)
	_make_dock_flyout()
	_make_dock_toggle()
	_make_dock_panel_menu()
	_make_dock_group_menu()
	brush_panel = BRUSH_PANEL_SCRIPT.new() as DrawingBrushPanel
	assert(dock_layout.register_panel("brushes"))
	assert(dock_layout.attach_panel("brushes", "right", "brushes"))
	dock_views["brushes"] = brush_panel
	dock_stash.add_child(brush_panel)
	brush_panel.preset_selected.connect(_select_brush_preset)
	brush_panel.width_changed.connect(_set_brush_width)
	brush_panel.opacity_changed.connect(_set_brush_opacity)
	brush_panel.hardness_changed.connect(_set_brush_hardness)
	brush_panel.density_changed.connect(_set_brush_density)
	brush_panel.reset_requested.connect(_reset_selected_brush)
	brush_panel.display(selected_brush_preset, brush_width_value,
		brush_opacity_value, _selected_brush_hardness(), _selected_brush_density())
	var color_pane: VBoxContainer = _add_dock_section("Colors")
	_build_color_controls(color_pane)
	var layer_pane: VBoxContainer = _add_dock_section("Layers")
	# Do not let six layer actions force a minimum 300px dock on small
	# windows; wrap secondary actions within the existing dock width.
	var layer_actions: HFlowContainer = HFlowContainer.new()
	layer_pane.add_child(layer_actions)
	for entry: Dictionary in [{"label": "+ Group", "handler": Callable(self, "_add_group")},
		{"label": "+ Layer", "handler": Callable(self, "_add_layer")},
		{"label": "↑", "handler": Callable(self, "_move_selected_layer").bind(-1)},
		{"label": "↓", "handler": Callable(self, "_move_selected_layer").bind(1)},
		{"label": "↳", "handler": Callable(self, "_indent_selected_layer")},
		{"label": "↰", "handler": Callable(self, "_outdent_selected_layer")}] :
		var action: Button = Button.new()
		action.text = entry["label"]
		action.tooltip_text = {"↑": "Move selected row up", "↓": "Move selected row down",
			"↳": "Indent into preceding group", "↰": "Outdent beside parent"}.get(
			entry["label"], entry["label"])
		action.pressed.connect(entry["handler"])
		layer_actions.add_child(action)
	layer_search = LineEdit.new()
	layer_search.placeholder_text = "Find layers and text labels…"
	layer_search.text_changed.connect(func(_value: String) -> void:
		layer_page = 0
		_refresh_layers())
	layer_pane.add_child(layer_search)
	var pages: HBoxContainer = HBoxContainer.new()
	layer_pane.add_child(pages)
	for entry: Dictionary in [{"text": "‹", "dir": -1}, {"text": "›", "dir": 1}]:
		var page_button: Button = Button.new()
		page_button.text = entry["text"]
		page_button.pressed.connect(_change_layer_page.bind(entry["dir"]))
		pages.add_child(page_button)
	layer_page_label = Label.new()
	pages.add_child(layer_page_label)
	for icon_name: String in ["layer_visible", "layer_hidden", "layer_unlocked", "layer_locked"]:
		layer_icons[icon_name] = load("res://addons/drawing/icons/%s.svg" % icon_name) as Texture2D
	layers = Tree.new()
	layers.hide_root = true
	# Fixed viewport for the tree: the dock scrolls as a whole, and the tree
	# keeps its own row scrolling without expanding indefinitely.
	layers.custom_minimum_size.y = 230
	layers.item_selected.connect(_layer_selected)
	# Tree.button_clicked is not emitted reliably for synthetic and some
	# forwarded GUI pointer sequences; resolve the row/icon on mouse-down.
	layers.gui_input.connect(_layer_tree_input)
	layer_pane.add_child(layers)
	layer_rename_dialog = ConfirmationDialog.new()
	layer_rename_dialog.title = "Rename layer or group"
	add_child(layer_rename_dialog)
	layer_rename_field = LineEdit.new()
	layer_rename_field.max_length = 128
	layer_rename_dialog.add_child(layer_rename_field)
	layer_rename_dialog.confirmed.connect(_confirm_layer_rename)
	layer_rename_dialog.canceled.connect(_cancel_authoring_dialog.bind("layer_rename"))
	var history_pane: VBoxContainer = _add_dock_section("History")
	var history_actions: HBoxContainer = HBoxContainer.new()
	history_pane.add_child(history_actions)
	history_undo = Button.new()
	history_undo.text = "↶ Undo"
	history_undo.pressed.connect(_undo)
	history_actions.add_child(history_undo)
	history_redo = Button.new()
	history_redo.text = "↷ Redo"
	history_redo.pressed.connect(_redo)
	history_actions.add_child(history_redo)
	history_label = Label.new()
	history_actions.add_child(history_label)
	history_list = ItemList.new()
	history_list.custom_minimum_size.y = 128
	history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_list.allow_reselect = true
	history_list.item_selected.connect(_history_item_selected)
	history_pane.add_child(history_list)
	preferences_dialog = AcceptDialog.new()
	preferences_dialog.title = "Drawing preferences"
	add_child(preferences_dialog)
	var preferences_content: VBoxContainer = VBoxContainer.new()
	preferences_dialog.add_child(preferences_content)
	selection_history_toggle = CheckButton.new()
	selection_history_toggle.text = "Record selection changes in Undo History"
	selection_history_toggle.tooltip_text = "Application preference (default OFF); never changes artwork or its saved state"
	selection_history_toggle.button_pressed = record_selection_history
	selection_history_toggle.toggled.connect(_selection_history_preference_changed)
	preferences_content.add_child(selection_history_toggle)
	for panel_id: String in initial_extra_panels:
		var view: Control = initial_extra_panels[panel_id] as Control
		if view != null and not dock_views.has(panel_id) and dock_layout.register_panel(panel_id):
			if dock_layout.attach_panel(panel_id, "right", panel_id):
				dock_views[panel_id] = view
				dock_stash.add_child(view)
	_render_dock()
	resized.connect(_clamp_floating_hosts)
	status = Label.new()
	status.name = "WorkspaceStatus"
	status.text = "Ready"
	# Status contains unbounded cursor/asset IDs; never let it force the whole
	# workspace wider than a narrow window.
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(status)
	var about: AcceptDialog = AcceptDialog.new()
	about.name = "WorkspaceAbout"
	about.title = "Drawing workspace"
	about.dialog_text = "Independent Drawing / Object Editor workspace.\nHelp: File, Object, Edit, View, Image, Layers, Select, Window."
	add_child(about)
	open_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	open_dialog.title = "Open Drawing document or raster image (not an Object source)"
	open_dialog.filters = PackedStringArray(["*.drawing ; Drawing documents",
		"*.png ; PNG images", "*.webp ; WebP images", "*.jpg, *.jpeg ; JPEG images"])
	open_dialog.file_selected.connect(_open_file)
	save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.file_selected.connect(_save_dialog_selected)
	save_dialog.canceled.connect(_save_dialog_cancelled)
	object_open_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	object_open_dialog.title = "Open portable Object source in its own editor tab"
	object_open_dialog.file_selected.connect(_open_object_file)
	asset_browser_directory_dialog = FileDialog.new()
	asset_browser_directory_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	asset_browser_directory_dialog.access = FileDialog.ACCESS_FILESYSTEM
	asset_browser_directory_dialog.title = "Choose existing project Objects/ directory (not the project root)"
	asset_browser_directory_dialog.dir_selected.connect(_chosen_objects_root)
	add_child(asset_browser_directory_dialog)
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "Unsaved Object/Drawing changes"
	close_dialog.dialog_text = "Save changes before closing this tab?"
	add_child(close_dialog)
	close_dialog.confirmed.connect(func() -> void:
		close_dialog.hide()
		call_deferred("_save_and_close"))
	close_dialog.canceled.connect(_cancel_pending_close)
	close_dialog.add_button("Discard", false, "discard")
	close_dialog.custom_action.connect(func(action: String) -> void:
		if action == "discard":
			close_dialog.hide()
			_close_index(_closing_index))
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.title = "Object source name"
	add_child(rename_dialog)
	rename_field = LineEdit.new()
	rename_field.custom_minimum_size.x = 310
	rename_dialog.add_child(rename_field)
	rename_dialog.confirmed.connect(_confirm_object_rename)
	rename_dialog.canceled.connect(_cancel_authoring_dialog.bind("object_rename"))
	frame_dialog = ConfirmationDialog.new()
	frame_dialog.title = "Object-local origin and bounds"
	add_child(frame_dialog)
	var frame_grid: GridContainer = GridContainer.new()
	frame_grid.columns = 2
	frame_dialog.add_child(frame_grid)
	for entry: Dictionary in [{"label": "Origin X", "nonnegative": false},
		{"label": "Origin Y", "nonnegative": false},
		{"label": "Bounds X", "nonnegative": false},
		{"label": "Bounds Y", "nonnegative": false},
		{"label": "Bounds width", "nonnegative": true},
		{"label": "Bounds height", "nonnegative": true}]:
		var field_label: Label = Label.new()
		field_label.text = entry["label"]
		frame_grid.add_child(field_label)
		var field: SpinBox = SpinBox.new()
		field.step = 1.0
		field.min_value = 0 if entry["nonnegative"] else -1000000000
		field.max_value = 1000000000
		field.custom_minimum_size.x = 240
		frame_grid.add_child(field)
		frame_fields.append(field)
	var frame_info: Label = Label.new()
	frame_info.text = "Empty bounds = unrestricted sparse canvas; guides never clip pixels."
	frame_dialog.add_child(frame_info)
	frame_dialog.confirmed.connect(_confirm_object_frame)
	frame_dialog.canceled.connect(_cancel_authoring_dialog.bind("object_frame"))
	grid_dialog = ConfirmationDialog.new()
	grid_dialog.title = "Drawing grid (view only)"
	add_child(grid_dialog)
	var grid_form: GridContainer = GridContainer.new()
	grid_form.columns = 2
	grid_dialog.add_child(grid_form)
	for label_text: String in ["Spacing (source px)", "Grid origin X", "Grid origin Y"]:
		var field_label: Label = Label.new()
		field_label.text = label_text
		grid_form.add_child(field_label)
		var field: SpinBox = SpinBox.new()
		field.min_value = 2 if grid_fields.is_empty() else -1000000000
		field.max_value = 4096 if grid_fields.is_empty() else 1000000000
		field.step = 1
		field.custom_minimum_size.x = 185
		grid_form.add_child(field)
		grid_fields.append(field)
	grid_dialog.confirmed.connect(_confirm_grid)
	grid_dialog.canceled.connect(_cancel_authoring_dialog.bind("grid"))
	image_frame_dialog = ConfirmationDialog.new()
	image_frame_dialog.title = "Standalone image frame — guide, not crop"
	add_child(image_frame_dialog)
	var image_form: GridContainer = GridContainer.new()
	image_form.columns = 2
	image_frame_dialog.add_child(image_form)
	for label_text: String in ["Image left X", "Image top Y", "Width (px)", "Height (px)"]:
		var field_label: Label = Label.new()
		field_label.text = label_text
		image_form.add_child(field_label)
		var field: SpinBox = SpinBox.new()
		field.min_value = 1 if image_frame_fields.size() >= 2 else -1000000000
		field.max_value = 1000000 if image_frame_fields.size() >= 2 else 1000000000
		field.step = 1
		field.custom_minimum_size.x = 185
		image_form.add_child(field)
		image_frame_fields.append(field)
	image_frame_dialog.confirmed.connect(_confirm_image_frame)
	image_frame_dialog.canceled.connect(_cancel_authoring_dialog.bind("image_frame"))
	variant_dialog = ConfirmationDialog.new()
	variant_dialog.title = "Save Object as independent asset"
	add_child(variant_dialog)
	var variant_form: VBoxContainer = VBoxContainer.new()
	variant_dialog.add_child(variant_form)
	var destination: Label = Label.new()
	destination.text = "Target: campaign/Objects/<new asset ID>/v000001.drawing"
	variant_form.add_child(destination)
	variant_name = LineEdit.new()
	variant_name.placeholder_text = "New Object name"
	variant_name.custom_minimum_size.x = 400
	variant_form.add_child(variant_name)
	variant_dialog.confirmed.connect(_variant_dialog_confirmed)
	variant_dialog.canceled.connect(_variant_dialog_cancelled)
	_build_text_dialog()


## Register one existing panel Control against the T-078 model; no parallel ownership list.
func _add_dock_section(title: String) -> VBoxContainer:
	var panel_id: String = title.to_lower()
	assert(dock_layout.register_panel(panel_id))
	assert(dock_layout.attach_panel(panel_id, "right", panel_id))
	var section: VBoxContainer = VBoxContainer.new()
	section.name = title
	dock_views[panel_id] = section
	dock_stash.add_child(section)
	return section


## The flyout belongs to the drawing canvas's Control tree. It is not a
## Window, and is not a child of either split pane's layout containers.
func _make_dock_flyout() -> void:
	dock_flyout = PanelContainer.new()
	dock_flyout.name = "DockGroupFlyout"
	dock_flyout.mouse_filter = Control.MOUSE_FILTER_STOP
	dock_flyout.visible = false
	canvas.add_child(dock_flyout)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "FlyoutColumn"
	dock_flyout.add_child(column)
	var strip_row: HBoxContainer = HBoxContainer.new()
	strip_row.name = "FlyoutTabBar"
	column.add_child(strip_row)
	var close: Button = Button.new()
	close.name = "CloseFlyout"
	close.text = "×"
	close.custom_minimum_size = Vector2(40, 40)
	close.tooltip_text = "Close panel flyout"
	close.focus_mode = Control.FOCUS_ALL
	close.pressed.connect(func() -> void:
		dock_layout.close_flyout("right")
		_render_dock())
	strip_row.add_child(close)
	dock_flyout_tab_scroll = ScrollContainer.new()
	dock_flyout_tab_scroll.name = "FlyoutTabScroll"
	dock_flyout_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dock_flyout_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock_flyout_tab_scroll.custom_minimum_size.y = 43
	dock_flyout_tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(dock_flyout_tab_scroll)
	strip_row.move_child(close, 1) # Compact close affordance at the far edge.
	dock_flyout_tabs = HBoxContainer.new()
	dock_flyout_tabs.name = "FlyoutTabs"
	dock_flyout_tab_scroll.add_child(dock_flyout_tabs)
	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.name = "FlyoutScroll"
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.follow_focus = true
	column.add_child(body_scroll)
	dock_flyout_body = VBoxContainer.new()
	dock_flyout_body.name = "FlyoutBody"
	dock_flyout_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(dock_flyout_body)
	_layout_dock_flyout()


func _layout_dock_flyout() -> void:
	if dock_flyout == null or canvas == null:
		return
	var width: float = minf(276.0, maxf(120.0, canvas.size.x - 12.0))
	dock_flyout.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dock_flyout.position = Vector2(canvas.size.x - width - 4.0, 4.0)
	dock_flyout.size = Vector2(width, maxf(100.0, canvas.size.y - 8.0))


func _dock_icon(panel_id: String) -> Texture2D:
	return DrawingDockIcons.for_panel(panel_id)


## The same half-circle belongs to the dock in both states. The minimized
## rail owns a real VBox slot; the expanded dock overlays its left gutter.
func _make_dock_toggle() -> void:
	dock_toggle_slot = HBoxContainer.new()
	dock_toggle_slot.name = "DockToggleSlot"
	dock_toggle_slot.custom_minimum_size = Vector2(48, 56)
	# In flow, but flush against the dock's outer edge rather than inset left.
	dock_toggle_slot.alignment = BoxContainer.ALIGNMENT_END
	dock_rail.add_child(dock_toggle_slot)
	dock_toggle = DOCK_TOGGLE_SCRIPT.new() as Button
	dock_toggle.name = "DockEdgeToggle"
	dock_toggle.tooltip_text = "Minimize right dock to icon rail"
	dock_toggle.pressed.connect(_toggle_dock)
	dock_toggle_slot.add_child(dock_toggle)
	# DockEdgeToggle's own _ready establishes focus/vector styling; the
	# rail state is in flow, and must not retain its previous top-level mode.
	dock_toggle.top_level = false
	call_deferred("_layout_dock_toggle")


func _place_dock_toggle(minimized: bool) -> void:
	var was_focused: bool = dock_toggle.has_focus()
	if minimized:
		if dock_toggle.get_parent() != dock_toggle_slot:
			dock_toggle.top_level = false
			dock_toggle.reparent(dock_toggle_slot, false)
		dock_toggle.top_level = false
		dock_toggle_slot.show()
	else:
		dock_toggle_slot.hide()
		if dock_toggle.get_parent() != inspector:
			dock_toggle.reparent(inspector, false)
		dock_toggle.top_level = true
	_layout_dock_toggle()
	if was_focused:
		# Moving a focused Button between parents drops Godot's GUI focus.
		# Restore it after the new parent becomes visible this frame.
		dock_toggle.call_deferred("grab_focus")


func _layout_dock_toggle() -> void:
	if dock_toggle == null or inspector == null or not inspector.is_inside_tree():
		return
	if dock_toggle.get_parent() == dock_toggle_slot:
		# HBoxContainer determines the button's actual placement; the VBox
		# slot displaces the first panel icon rather than covering it.
		return
	# This top-level Control stays INSIDE PanelDock at its outer (right)
	# boundary in both states. The right gutter keeps scrolling controls
	# outside its fixed pointer target.
	var dock_bounds: Rect2 = inspector.get_global_rect()
	dock_toggle.global_position = Vector2(dock_bounds.end.x - dock_toggle.size.x,
		dock_bounds.position.y)


## One stable panel icon across expanded dock and minimized rail. Pointer
## gestures use the same 7px drag threshold as the transactional dock planner.
func _panel_button(panel_id: String, rail_button: bool) -> Button:
	var button: Button = Button.new()
	button.name = ("Rail_" if rail_button else "Edge_") + panel_id
	button.icon = _dock_icon(panel_id)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(42, 42)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = ("Toggle group flyout: " if rail_button else "Select/collapse group: ") + panel_id.capitalize()
	button.tooltip_text += "; right-click or Shift+F10 for menu; drag to arrange"
	button.toggle_mode = true
	var group: Dictionary = dock_layout.group_info(dock_layout.group_of(panel_id))
	button.button_pressed = (dock_layout.container_info("right")["flyout_group"] == dock_layout.group_of(panel_id)
		and group["active"] == panel_id) if rail_button else (group["active"] == panel_id)
	button.pressed.connect(_rail_panel_pressed.bind(panel_id) if rail_button else _expanded_panel_pressed.bind(panel_id))
	button.gui_input.connect(_dock_drag_press.bind(DrawingDockDrag.PANEL, panel_id))
	# Keyboard users can find both the panel name and current state.
	for property: Dictionary in button.get_property_list():
		if property["name"] == "accessibility_name":
			button.set("accessibility_name", panel_id.capitalize() + " panel")
			break
	return button


## Match expanded/floating panel icon identity in minimized flyouts. The
## flyout's transient selection is independent of persisted group collapse.
func _flyout_panel_button(panel_id: String, active: bool) -> Button:
	var tab: Button = Button.new()
	tab.name = "Tab_" + panel_id
	tab.icon = _dock_icon(panel_id)
	tab.expand_icon = true
	tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.custom_minimum_size = Vector2(42, 42)
	tab.focus_mode = Control.FOCUS_ALL
	tab.tooltip_text = panel_id.capitalize() + " panel; right-click or Shift+F10 for menu; drag to reorder or split"
	tab.toggle_mode = true
	tab.button_pressed = active
	for property: Dictionary in tab.get_property_list():
		if property["name"] == "accessibility_name":
			tab.set("accessibility_name", panel_id.capitalize() + " panel")
			break
	tab.pressed.connect(_flyout_tab_pressed.bind(panel_id))
	tab.gui_input.connect(_dock_drag_press.bind(DrawingDockDrag.PANEL, panel_id))
	return tab


func _ignore_dock_icon_activation() -> bool:
	# Godot's Button.pressed can arrive before or after the workspace's mouse
	# release. The moved flag survives until the next deferred frame, so a
	# release that ended a drag can never turn into a collapse or flyout click.
	return _drag_candidate_moved or _suppress_drag_release or dock_drag.is_dragging()


func _expanded_panel_pressed(panel_id: String) -> void:
	if _ignore_dock_icon_activation():
		return
	var group_id: String = dock_layout.group_of(panel_id)
	var group: Dictionary = dock_layout.group_info(group_id)
	if group.is_empty():
		return
	if group["active"] == panel_id and not bool(group["collapsed"]):
		if dock_layout.set_group_collapsed(group_id, true):
			_render_dock("edge:" + panel_id)
		return
	# A collapsed active tab expands; an inactive tab selects and expands.
	if group["active"] != panel_id:
		dock_layout.select_panel(panel_id)
	if bool(group["collapsed"]):
		dock_layout.set_group_collapsed(group_id, false)
	_render_dock("edge:" + panel_id)


func _rail_panel_pressed(panel_id: String) -> void:
	if _ignore_dock_icon_activation():
		return
	if dock_layout.activate_from_rail("right", panel_id):
		_render_dock("rail:" + panel_id)


## The owner-specified three-dots action is on RMB, not a permanently
## occupying toolbar button; menu actions target the clicked panel (including
## inactive tabs), never the group's currently active panel by accident.
func _make_dock_panel_menu() -> void:
	dock_panel_menu = PopupMenu.new()
	dock_panel_menu.name = "DockPanelContextMenu"
	dock_panel_menu.add_item("Move panel left", 0)
	dock_panel_menu.add_item("Move panel right", 1)
	dock_panel_menu.add_separator()
	dock_panel_menu.add_item("Split panel into group", 2)
	dock_panel_menu.add_item("Float this panel", 3)
	dock_panel_menu.id_pressed.connect(_dock_panel_menu_action)
	add_child(dock_panel_menu)


## One popup serves every marker. Enablement is calculated from the model at
## opening time; a previously rendered group ID cannot mutate a new owner.
func _make_dock_group_menu() -> void:
	dock_group_menu = PopupMenu.new()
	dock_group_menu.name = "DockGroupContextMenu"
	for entry: String in ["Move group up", "Move group down", "Merge group into previous", "Merge group into next",
		"Split active panel into group", "Float whole group"]:
		dock_group_menu.add_item(entry)
	dock_group_menu.id_pressed.connect(_dock_group_menu_action)
	add_child(dock_group_menu)


func _show_dock_group_menu(group_id: String, point: Vector2) -> void:
	if _dock_group_position(group_id) < 0:
		return
	var groups: Array = dock_layout.container_info("right")["groups"]
	var index: int = _dock_group_position(group_id)
	var group: Dictionary = dock_layout.group_info(group_id)
	_dock_menu_group_id = group_id
	for action: int in range(4):
		var unavailable: bool = (index == 0) if action % 2 == 0 else (index >= groups.size() - 1)
		dock_group_menu.set_item_disabled(action, unavailable)
	dock_group_menu.set_item_disabled(4, group["panels"].size() <= 1)
	dock_group_menu.position = Vector2i(point.round())
	dock_group_menu.popup()


func _dock_group_menu_action(action_id: int) -> void:
	var group_id: String = _dock_menu_group_id
	if _dock_group_position(group_id) < 0:
		return
	match action_id:
		0, 1, 2, 3:
			_dock_arrange_action([5, 6, 7, 8][action_id], group_id)
		4:
			if dock_layout.group_info(group_id)["panels"].size() > 1:
				_dock_arrange_action(4, group_id)
		5:
			_float_source(DrawingDockDrag.GROUP, group_id)


func _show_dock_panel_menu(panel_id: String, point: Vector2) -> void:
	var group_id: String = dock_layout.group_of(panel_id)
	var group: Dictionary = dock_layout.group_info(group_id)
	if group.is_empty() or dock_layout.owner_of(panel_id) != "right":
		return
	_dock_menu_panel_id = panel_id
	var index: int = group["panels"].find(panel_id)
	dock_panel_menu.set_item_disabled(dock_panel_menu.get_item_index(0), index <= 0)
	dock_panel_menu.set_item_disabled(dock_panel_menu.get_item_index(1), index >= group["panels"].size() - 1)
	dock_panel_menu.set_item_disabled(dock_panel_menu.get_item_index(2), group["panels"].size() <= 1)
	# PopupMenu is a Window: position is a screen coordinate, not a child of
	# the scrolled tab strip. The menu clamps to the visible desktop itself.
	dock_panel_menu.position = Vector2i(point.round())
	dock_panel_menu.popup()


func _dock_panel_menu_action(action_id: int) -> void:
	var panel_id: String = _dock_menu_panel_id
	var group_id: String = dock_layout.group_of(panel_id)
	var group: Dictionary = dock_layout.group_info(group_id)
	if group.is_empty() or dock_layout.owner_of(panel_id) != "right":
		return
	var index: int = group["panels"].find(panel_id)
	var target: Dictionary = {}
	match action_id:
		0:
			if index > 0:
				target = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": index - 1}
		1:
			if index + 1 < group["panels"].size():
				target = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": index + 2}
		2:
			if group["panels"].size() > 1:
				target = {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": _dock_group_position(group_id) + 1}
		3:
			_float_source(DrawingDockDrag.PANEL, panel_id)
			return
	if not target.is_empty():
		_dock_apply(DrawingDockDrag.PANEL, panel_id, target,
			"rail:" + panel_id if bool(dock_layout.container_info("right")["minimized"]) else "edge:" + panel_id)


func _focused_dock_panel() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	for panel_id: String in dock_tab_buttons:
		if dock_tab_buttons[panel_id] == focused:
			return panel_id
	for panel_id: String in dock_rail_buttons:
		if dock_rail_buttons[panel_id] == focused:
			return panel_id
	if focused != null and focused.get_parent() == dock_flyout_tabs and focused.name.begins_with("Tab_"):
		return String(focused.name).trim_prefix("Tab_")
	return ""


func _group_collapse_pressed(group_id: String) -> void:
	if _ignore_dock_icon_activation():
		return
	var group: Dictionary = dock_layout.group_info(group_id)
	if not group.is_empty() and dock_layout.set_group_collapsed(group_id, not bool(group["collapsed"])):
		_render_dock("group:" + group_id)


func _flyout_tab_pressed(panel_id: String) -> void:
	var info: Dictionary = dock_layout.container_info("right")
	var group_id: String = dock_layout.group_of(panel_id)
	var open: bool = bool(info["minimized"]) and group_id == String(info["flyout_group"])
	var active: bool = open and String(dock_layout.group_info(group_id)["active"]) == panel_id
	var current_tab: Button = dock_flyout_tabs.get_node_or_null("Tab_" + panel_id) as Button
	if _ignore_dock_icon_activation() or not open or active:
		# Button toggles *before* the pressed callback. Restore the model's
		# pressed state on active/no-op clicks and suppressed drag releases.
		if current_tab != null:
			current_tab.set_pressed_no_signal(active)
		return
	if dock_layout.select_panel(panel_id):
		_render_dock("tab:" + panel_id)


func _restore_dock_focus(key: String) -> void:
	var target: Button = null
	if key.begins_with("rail:"):
		target = dock_rail_buttons.get(key.trim_prefix("rail:")) as Button
	elif key.begins_with("group:"):
		target = dock_header_buttons.get(key.trim_prefix("group:")) as Button
	elif key.begins_with("drag-group:"):
		target = dock_group_handles.get(key.trim_prefix("drag-group:")) as Button
	elif key.begins_with("edge:"):
		target = find_child("Edge_" + key.trim_prefix("edge:"), true, false) as Button
	elif key.begins_with("tab:"):
		target = dock_flyout_tabs.find_child("Tab_" + key.trim_prefix("tab:"), false, false) as Button
	if target != null and target.is_visible_in_tree():
		target.grab_focus()


func _render_dock(focus_key: String = "") -> void:
	# Reparent the actual panel controls rather than building shadow copies.
	# This also works after T-080 changes model group membership externally.
	for view: Control in dock_views.values():
		if view.get_parent() != dock_stash:
			view.reparent(dock_stash)
	for parent: Node in [dock_panels, dock_rail, dock_flyout_tabs]:
		for child: Node in parent.get_children():
			if child == dock_toggle_slot:
				continue
			parent.remove_child(child)
			child.queue_free()
	var info: Dictionary = dock_layout.container_info("right")
	var minimized: bool = bool(info["minimized"])
	var flyout_group_id: String = String(info["flyout_group"])
	for child: Node in dock_flyout_body.get_children():
		if child is Control and dock_views.values().has(child):
			(child as Control).reparent(dock_stash)
		else:
			dock_flyout_body.remove_child(child)
			child.queue_free()
	dock_rail_buttons.clear()
	dock_header_buttons.clear()
	dock_tab_buttons.clear()
	dock_tab_strips.clear()
	dock_group_frames.clear()
	dock_group_handles.clear()
	if not minimized:
		for group: Dictionary in info["groups"]:
			var visible_members: Array[String] = []
			for panel_id: String in group["panels"]:
				if dock_views.has(panel_id) and dock_layout.rail_icons("right").any(func(e: Dictionary) -> bool: return e["panel"] == panel_id):
					visible_members.append(panel_id)
			if visible_members.is_empty():
				continue
			var group_id: String = String(group["id"])
			var frame: VBoxContainer = VBoxContainer.new()
			frame.name = "Group_" + group_id
			dock_panels.add_child(frame)
			dock_group_frames[group_id] = frame
			# One compact, common-height row; the marker is not a group title.
			var bar: HBoxContainer = HBoxContainer.new()
			bar.name = "GroupBar"
			bar.add_theme_constant_override("separation", 2)
			frame.add_child(bar)
			var marker: DrawingDockGroupMarker = DOCK_GROUP_MARKER_SCRIPT.new() as DrawingDockGroupMarker
			marker.name = "GroupMarker_" + group_id
			marker.collapsed = bool(group["collapsed"])
			marker.tooltip_text = ("Expand " if marker.collapsed else "Collapse ") + group_id.capitalize() + \
				" group; drag whole group; right-click or Shift+F10 for group menu; Ctrl+Alt+Shift+Up/Down to reorder"
			for property: Dictionary in marker.get_property_list():
				if property["name"] == "accessibility_name":
					marker.set("accessibility_name", group_id.capitalize() + " group marker")
					break
			marker.pressed.connect(_group_collapse_pressed.bind(group_id))
			marker.gui_input.connect(_dock_drag_press.bind(DrawingDockDrag.GROUP, group_id))
			bar.add_child(marker)
			dock_header_buttons[group_id] = marker
			dock_group_handles[group_id] = marker
			# Horizontal overflow stays in the icon strip, never expands the dock.
			var tab_scroll: ScrollContainer = ScrollContainer.new()
			tab_scroll.name = "TabStripScroll_" + group_id
			tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			tab_scroll.custom_minimum_size.y = 45
			bar.add_child(tab_scroll)
			dock_tab_strips[group_id] = tab_scroll
			var tabs_row: HBoxContainer = HBoxContainer.new()
			tabs_row.name = "TabStrip_" + group_id
			tab_scroll.add_child(tabs_row)
			for panel_id: String in visible_members:
				var edge: Button = _panel_button(panel_id, false)
				tabs_row.add_child(edge)
				dock_tab_buttons[panel_id] = edge
			if not bool(group["collapsed"]):
				var active_id: String = String(group["active"])
				if visible_members.has(active_id):
					var panel_view: Control = dock_views[active_id] as Control
					panel_view.reparent(frame)
			frame.add_child(HSeparator.new())
	else:
		for entry: Dictionary in dock_layout.rail_icons("right"):
			if bool(entry["separator_before"]):
				var separator: HSeparator = HSeparator.new()
				separator.name = "GroupSeparator"
				separator.custom_minimum_size.y = 6
				dock_rail.add_child(separator)
			var panel_id: String = String(entry["panel"])
			var icon: Button = _panel_button(panel_id, true)
			dock_rail_buttons[panel_id] = icon
			dock_rail.add_child(icon)
		if not flyout_group_id.is_empty():
			var group: Dictionary = dock_layout.group_info(flyout_group_id)
			for panel_id: String in group["panels"]:
				if not dock_views.has(panel_id):
					continue
				dock_flyout_tabs.add_child(_flyout_panel_button(panel_id, panel_id == String(group["active"])))
			if dock_views.has(String(group["active"])):
				(dock_views[String(group["active"])] as Control).reparent(dock_flyout_body)
	inspector.custom_minimum_size.x = 48 if minimized else EXPANDED_DOCK_MIN_WIDTH
	dock_panels.visible = not minimized
	dock_panel_gutter.visible = not minimized
	dock_rail.visible = minimized
	dock_flyout.visible = minimized and not flyout_group_id.is_empty()
	if dock_toggle != null:
		_place_dock_toggle(minimized)
		dock_toggle.set("minimized", minimized)
		dock_toggle.tooltip_text = "Expand right dock (also in Window menu)" if minimized else "Minimize right dock to icon rail (also in Window menu)"
		dock_toggle.queue_redraw()
	_layout_dock_toggle()
	_layout_dock_flyout()
	_render_floating_hosts()
	if not focus_key.is_empty():
		call_deferred("_restore_dock_focus", focus_key)
	_schedule_layout_save()


## T-081: instantiate a single Control host for a whole group, using the same
## model transaction as T-080. Mouse drag from a dock to a host is T-082.
func float_group(group_id: String) -> String:
	if dock_layout.group_info(group_id).is_empty():
		return ""
	return _float_source(DrawingDockDrag.GROUP, group_id)


## A canvas drop creates the destination only after the pointer release.
## Creating it during preview would invalidate DrawingDockDrag's baseline.
func _float_source(kind: String, source_id: String, at: Vector2 = Vector2(-1, -1)) -> String:
	if kind == DrawingDockDrag.PANEL and dock_layout.owner_of(source_id).is_empty():
		return ""
	if kind == DrawingDockDrag.GROUP and dock_layout.group_info(source_id).is_empty():
		return ""
	_floating_serial += 1
	var host_id: String = "float-%d" % _floating_serial
	while not dock_layout.container_info(host_id).is_empty():
		_floating_serial += 1
		host_id = "float-%d" % _floating_serial
	if not dock_layout.create_container(host_id, DrawingDockLayout.FLOATING):
		return ""
	var group_move: Dictionary = {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": 0}
	var began: bool = dock_drag.begin_panel(source_id) if kind == DrawingDockDrag.PANEL else dock_drag.begin_group(source_id)
	if not began or not dock_drag.preview(group_move) or not dock_drag.commit():
		dock_drag.cancel()
		dock_layout.remove_empty_container(host_id)
		return ""
	var host: DrawingFloatingHost = FLOATING_HOST_SCRIPT.new() as DrawingFloatingHost
	host.setup(host_id, dock_layout, dock_drag, dock_views, dock_stash, self)
	add_child(host)
	host.layout_changed.connect(_render_dock)
	host.hide_requested.connect(hide_floating_host)
	host.state_changed.connect(_schedule_layout_save)
	floating_hosts[host_id] = host
	# Stagger independent hosts, then clamp their full frame to the client area.
	var shift: float = float(_floating_serial - 1) * 26.0
	host.set_host_rect(Rect2(Vector2(74 + shift, 64 + shift) if at.x < 0.0 else at - Vector2(145, 35), Vector2(310, 365)))
	_render_dock()
	host.raise_host()
	return host_id


func move_group_to_floating(group_id: String, host_id: String) -> bool:
	if not floating_hosts.has(host_id):
		return false
	# One-group host: an explicit transfer into an occupied host merges tabs.
	var target_groups: Array = dock_layout.container_info(host_id)["groups"]
	if target_groups.size() != 1:
		return false
	var target_group: Dictionary = target_groups[0]
	if not dock_drag.begin_group(group_id) or not dock_drag.preview({"kind": DrawingDockDrag.MERGE_GROUP,
		"group": target_group["id"], "index": target_group["panels"].size()}):
		dock_drag.cancel()
		return false
	if not dock_drag.commit():
		return false
	_render_dock()
	return true


func hide_floating_host(host_id: String) -> void:
	var host: DrawingFloatingHost = floating_hosts.get(host_id) as DrawingFloatingHost
	if host != null:
		host.hide()
		_schedule_layout_save()


func show_floating_host(host_id: String) -> void:
	var host: DrawingFloatingHost = floating_hosts.get(host_id) as DrawingFloatingHost
	if host != null:
		host.show()
		host.clamp_to_client()
		host.raise_host()
		_schedule_layout_save()


func show_hidden_floating_hosts() -> void:
	# Window menu recovery: hiding never changes group ownership or view state.
	for host_id: String in floating_hosts:
		show_floating_host(host_id)


func _float_selected_dock_group() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	var group_id: String = ""
	for panel_id: String in dock_tab_buttons:
		if focus == dock_tab_buttons[panel_id]:
			group_id = dock_layout.group_of(panel_id)
	for panel_id: String in dock_rail_buttons:
		if focus == dock_rail_buttons[panel_id]:
			group_id = dock_layout.group_of(panel_id)
	for id: String in dock_group_handles:
		if focus == dock_group_handles[id]:
			group_id = id
	if group_id.is_empty():
		var groups: Array = dock_layout.container_info("right")["groups"]
		if not groups.is_empty():
			group_id = groups[0]["id"]
	if not group_id.is_empty():
		float_group(group_id)


func _clamp_floating_hosts() -> void:
	for host: DrawingFloatingHost in floating_hosts.values():
		host.clamp_to_client()


func _render_floating_hosts() -> void:
	for host: DrawingFloatingHost in floating_hosts.values():
		host.render()


## Drag/drop uses a single model transaction. The UI never mutates group arrays.
func _make_dock_hint() -> void:
	dock_drop_hint = ColorRect.new()
	dock_drop_hint.name = "DockInsertionHint"
	dock_drop_hint.color = Color(0.19, 0.78, 0.95, 0.87)
	dock_drop_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_drop_hint.top_level = true
	dock_drop_hint.z_index = 100
	dock_drop_hint.visible = false
	add_child(dock_drop_hint)
	# The exact insertion line is retained for keyboard/pointer parity. A separate
	# outlined strip and text tell users whether this will merge, reorder or split.
	dock_merge_outline = Panel.new()
	dock_merge_outline.name = "DockMergeTargetOutline"
	dock_merge_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_merge_outline.top_level = true
	dock_merge_outline.z_index = 99
	var outline_style: StyleBoxFlat = StyleBoxFlat.new()
	outline_style.bg_color = Color(0.08, 0.72, 0.48, 0.12)
	outline_style.border_color = Color(0.18, 0.88, 0.57, 0.96)
	outline_style.set_border_width_all(2)
	dock_merge_outline.add_theme_stylebox_override("panel", outline_style)
	dock_merge_outline.visible = false
	add_child(dock_merge_outline)
	dock_drop_caption = Label.new()
	dock_drop_caption.name = "DockDropCaption"
	dock_drop_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_drop_caption.top_level = true
	dock_drop_caption.z_index = 110
	dock_drop_caption.add_theme_font_size_override("font_size", 13)
	var caption_style: StyleBoxFlat = StyleBoxFlat.new()
	caption_style.bg_color = Color(0.08, 0.13, 0.19, 0.95)
	caption_style.set_content_margin_all(5.0)
	dock_drop_caption.add_theme_stylebox_override("normal", caption_style)
	dock_drop_caption.visible = false
	add_child(dock_drop_caption)


func _dock_drag_press(event: InputEvent, kind: String, source_id: String) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			if kind == DrawingDockDrag.PANEL:
				_show_dock_panel_menu(source_id, button.global_position)
			elif kind == DrawingDockDrag.GROUP:
				_show_dock_group_menu(source_id, button.global_position)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			# The OS may have dropped the last release. A fresh press begins
			# a new independent icon/group gesture, not the old canceled one.
			_suppress_drag_release = false
			_drag_candidate_kind = kind
			_drag_candidate_id = source_id
			_drag_candidate_moved = false
			_drag_candidate_position = button.global_position


## Godot 4.8 beta's TabBar close icon is drawn by the theme, but forwarded
## viewport mouse events do not consistently emit tab_close_pressed. Route the
## close-glyph rectangle explicitly before TabBar processes the click; keep the
## built-in signal for native OS events and keyboard/accessibility consumers.
func _tab_close_hit(position: Vector2) -> int:
	if not show_document_tabs or tab_bar == null or not tab_bar.is_visible_in_tree():
		return -1
	var local: Vector2 = tab_bar.get_global_transform_with_canvas().affine_inverse() * position
	if not Rect2(Vector2.ZERO, tab_bar.size).has_point(local):
		return -1
	# With clip_tabs, Godot returns the same offscreen origin for multiple
	# hidden tabs. Their stale rectangles can overlap a visible close glyph;
	# ask the TabBar which tab is *actually* rendered at this pointer first.
	var index: int = tab_bar.get_tab_idx_at_point(local)
	if index < 0 or index >= tab_bar.tab_count:
		return -1
	var tab: Rect2 = tab_bar.get_tab_rect(index)
	if tab.size.x < 32.0:
		return -1
	var close: Rect2 = Rect2(tab.end.x - 30.0, tab.position.y, 28.0, tab.size.y)
	return index if close.has_point(local) else -1


func _input(event: InputEvent) -> void:
	_track_color_input(event)
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			var close_index: int = _tab_close_hit(click.position)
			if close_index >= 0:
				_request_close_tab(close_index)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if dock_drag.is_dragging() or not _drag_candidate_id.is_empty():
			_suppress_drag_release = not _drag_candidate_id.is_empty()
			_cancel_cross_drop(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if dock_drag.is_dragging() or not _drag_candidate_id.is_empty():
			return
		# Shift+F10 / Menu opens the focused panel's or group's menu
		# without changing the active tab or its collapsed state.
		if event.keycode == KEY_MENU or (event.keycode == KEY_F10 and event.shift_pressed):
			var focused: Control = get_viewport().gui_get_focus_owner()
			for group_id: String in dock_group_handles:
				if focused == dock_group_handles[group_id]:
					_show_dock_group_menu(group_id, focused.get_global_rect().get_center())
					get_viewport().set_input_as_handled()
					return
			var menu_panel: String = _focused_dock_panel()
			if not menu_panel.is_empty():
				var control: Control = get_viewport().gui_get_focus_owner()
				_show_dock_panel_menu(menu_panel, control.get_global_rect().get_center())
				get_viewport().set_input_as_handled()
				return
		if _dock_keyboard_command(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and not bool(event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# Docked icons, group markers, rail and flyout tabs share this source.
		# A motion without the held button proves mouse-up was missed, even
		# when neither window nor application lost focus. Abandon the preview
		# and fence a possible late release before it can detach the source.
		if not _drag_candidate_id.is_empty() or (_cross_source == "right" and dock_drag.is_dragging()):
			_drag_candidate_moved = true
			_suppress_drag_release = true
			_cancel_cross_drop(true)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and not _drag_candidate_id.is_empty() and bool(event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_pointer_position = event.global_position
		if event.global_position.distance_to(_drag_candidate_position) >= 7.0:
			_drag_candidate_moved = true
			if not dock_drag.is_dragging():
				begin_cross_drag("right", _drag_candidate_kind, _drag_candidate_id)
		if dock_drag.is_dragging() and _cross_source == "right":
			_preview_cross_drop(event.global_position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		# Deferred reset accommodates either GUI-signal/input ordering on the
		# release frame; a dragged icon must not toggle its collapsed state.
		call_deferred("_reset_dock_pointer_gesture")
		if _suppress_drag_release:
			_suppress_drag_release = false
			get_viewport().set_input_as_handled()
			return
		if dock_drag.is_dragging() and _cross_source == "right":
			_commit_cross_drop(event.global_position, "right")
			get_viewport().set_input_as_handled()
		else:
			_drag_candidate_id = ""
			_drag_candidate_kind = ""


func _reset_dock_pointer_gesture() -> void:
	_drag_candidate_moved = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _window_quit_guard_enabled:
		_request_window_quit()
		return
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _color_edit_pending:
			if _color_edit_pointer_down:
				_cancel_interrupted_color_pointer()
			else:
				# Typed/keyboard edits have no held pointer to abandon.
				_finish_color_edit()
		if dock_drag != null and (dock_drag.is_dragging() or not _drag_candidate_id.is_empty()):
			_suppress_drag_release = not _drag_candidate_id.is_empty()
			_cancel_cross_drop(true)


func _process(delta: float) -> void:
	# Scroll the group dock while holding a tab/group near its top or bottom.
	# This makes offscreen targets reachable without abandoning the transaction.
	if dock_drag == null or not dock_drag.is_dragging():
		return
	var grip_drag: bool = _grip_redock_active()
	var over_host: DrawingFloatingHost = null if grip_drag else _topmost_host(_drag_pointer_position)
	if not grip_drag:
		var tab_strips_to_check: Array[ScrollContainer] = []
		if over_host != null:
			for tab_strip: ScrollContainer in over_host.tab_strips.values():
				tab_strips_to_check.append(tab_strip)
		elif dock_flyout.visible:
			tab_strips_to_check.append(dock_flyout_tab_scroll)
		else:
			for tab_strip: ScrollContainer in dock_tab_strips.values():
				tab_strips_to_check.append(tab_strip)
		for tab_strip: ScrollContainer in tab_strips_to_check:
			if not tab_strip.get_global_rect().has_point(_drag_pointer_position):
				continue
			var bounds_x: Rect2 = tab_strip.get_global_rect()
			var direction_x: int = -1 if _drag_pointer_position.x < bounds_x.position.x + 22.0 else \
				1 if _drag_pointer_position.x > bounds_x.end.x - 22.0 else 0
			if direction_x != 0:
				var before_x: int = tab_strip.scroll_horizontal
				tab_strip.scroll_horizontal += roundi(float(direction_x) * 310.0 * delta)
				if before_x != tab_strip.scroll_horizontal:
					_preview_cross_drop(_drag_pointer_position)
			break
	var scroll_target: ScrollContainer = inspector if over_host == null else over_host._scroll
	if not scroll_target.get_global_rect().has_point(_drag_pointer_position):
		return
	var bounds: Rect2 = scroll_target.get_global_rect()
	var direction: int = 0
	if _drag_pointer_position.y < bounds.position.y + 30.0:
		direction = -1
	elif _drag_pointer_position.y > bounds.end.y - 30.0:
		direction = 1
	if direction == 0:
		return
	var before: int = scroll_target.scroll_vertical
	scroll_target.scroll_vertical += roundi(float(direction) * 420.0 * delta)
	if scroll_target.scroll_vertical != before:
		if grip_drag:
			var source_host: DrawingFloatingHost = floating_hosts[_cross_source]
			_preview_grip_redock(_cross_source, String(source_host.group_handles.keys()[0]), _drag_pointer_position)
		else:
			_preview_cross_drop(_drag_pointer_position)


func _cancel_dock_drag() -> void:
	_cancel_cross_drop()


func begin_cross_drag(source_container: String, kind: String, source_id: String) -> bool:
	if dock_drag.is_dragging() or not _cross_source.is_empty():
		return false
	if source_container != "right" and not floating_hosts.has(source_container):
		return false
	if kind == DrawingDockDrag.PANEL:
		if dock_layout.owner_of(source_id) != source_container:
			return false
	elif kind == DrawingDockDrag.GROUP:
		var group: Dictionary = dock_layout.group_info(source_id)
		if group.is_empty() or dock_layout.owner_of(String(group["panels"][0])) != source_container:
			return false
	else:
		return false
	var started: bool = dock_drag.begin_panel(source_id) if kind == DrawingDockDrag.PANEL else dock_drag.begin_group(source_id)
	if started:
		_cross_source = source_container
	return started


## A normal floating grip drag can redock without Shift. Unlike tab dragging,
## the source host follows the pointer over the canvas, so its tall rectangle
## must not occlude underlying dock hit tests. Preview never changes ownership.
func _grip_redock_active() -> bool:
	if not floating_hosts.has(_cross_source):
		return false
	var host: DrawingFloatingHost = floating_hosts[_cross_source]
	return is_instance_valid(host) and host._gesture == "move" and not host.group_handles.is_empty()


func _preview_grip_redock(source_host_id: String, group_id: String, point: Vector2) -> bool:
	if not floating_hosts.has(source_host_id) or not (inspector.get_global_rect().has_point(point) or \
		(dock_flyout.visible and dock_flyout.get_global_rect().has_point(point))):
		if _cross_source == source_host_id and _grip_redock_active():
			_cancel_cross_drop()
		return false
	# _dock_target_at uses drag.source_kind to decide group vs. tab drops.
	# Begin the transaction before asking it for a target, not afterward.
	if _cross_source.is_empty() and not begin_cross_drag(source_host_id, DrawingDockDrag.GROUP, group_id):
		return false
	if _cross_source != source_host_id or dock_drag.source_kind() != DrawingDockDrag.GROUP:
		return false
	var hit: Dictionary = _dock_target_at(point)
	_clear_drop_hints()
	if hit.is_empty() or not dock_drag.preview(hit["target"]):
		return false
	_drag_pointer_position = point
	_show_dock_drop_hint(hit, dock_drop_hint)
	return true


func _commit_grip_redock(source_host_id: String, point: Vector2) -> bool:
	if _cross_source != source_host_id:
		return false
	var host: DrawingFloatingHost = floating_hosts.get(source_host_id) as DrawingFloatingHost
	var group_id: String = String(host.group_handles.keys()[0]) if host != null and not host.group_handles.is_empty() else ""
	var valid: bool = not group_id.is_empty() and _preview_grip_redock(source_host_id, group_id, point)
	var committed: bool = valid and dock_drag.commit()
	_cancel_cross_drop()
	if committed:
		_reap_empty_hosts()
		_render_dock()
	return committed


func _topmost_host(point: Vector2) -> DrawingFloatingHost:
	var best: DrawingFloatingHost = null
	for host: DrawingFloatingHost in floating_hosts.values():
		if not is_instance_valid(host) or not host.is_visible_in_tree() or not host.get_global_rect().has_point(point):
			continue
		if best == null or host.get_index() > best.get_index():
			best = host
	return best


func _clear_drop_hints() -> void:
	if dock_drop_hint != null:
		dock_drop_hint.visible = false
	if dock_drop_caption != null:
		dock_drop_caption.visible = false
	if dock_merge_outline != null:
		dock_merge_outline.visible = false
	if _detach_hint != null:
		_detach_hint.visible = false
	for host: DrawingFloatingHost in floating_hosts.values():
		if is_instance_valid(host) and host._hint != null:
			host._hint.visible = false


func _preview_cross_drop(point: Vector2) -> void:
	_drag_pointer_position = point
	_clear_drop_hints()
	_detach_preview = false
	if not dock_drag.is_dragging() or _cross_source.is_empty():
		return
	var host: DrawingFloatingHost = _topmost_host(point)
	var hit: Dictionary = {}
	if host != null:
		hit = host._target_at(point)
	elif inspector.get_global_rect().has_point(point) or (dock_flyout.visible and dock_flyout.get_global_rect().has_point(point)):
		hit = _dock_target_at(point)
	if not hit.is_empty() and dock_drag.preview(hit["target"]):
		var marker: ColorRect = dock_drop_hint if host == null else host._hint
		_show_dock_drop_hint(hit, marker, host)
		return
	# Canvas release is an explicit detach action; the model remains untouched
	# until release, and invalid regions clear any previously valid target.
	dock_drag.preview({})
	if host == null and canvas.get_global_rect().has_point(point):
		_detach_preview = true
		_detach_hint.global_position = point - Vector2(115, 22)
		_detach_hint.visible = true


func _commit_cross_drop(point: Vector2, source_container: String) -> bool:
	if source_container != _cross_source or not dock_drag.is_dragging():
		_cancel_cross_drop()
		return false
	_preview_cross_drop(point)
	var kind: String = dock_drag.source_kind()
	var source_id: String = _drag_candidate_id
	if source_container != "right":
		var source_host: DrawingFloatingHost = floating_hosts.get(source_container) as DrawingFloatingHost
		if source_host != null:
			source_id = source_host._candidate_id
	var detach: bool = _detach_preview
	var committed: bool = false
	if detach:
		dock_drag.cancel()
		committed = not _float_source(kind, source_id, point).is_empty()
	else:
		committed = dock_drag.commit()
	_cancel_cross_drop()
	if committed:
		_reap_empty_hosts()
		_render_dock()
	return committed


func _reap_empty_hosts() -> void:
	for host_id: String in floating_hosts.keys():
		if not (dock_layout.container_info(host_id)["groups"] as Array).is_empty():
			continue
		if dock_layout.remove_empty_container(host_id):
			var host: DrawingFloatingHost = floating_hosts[host_id]
			floating_hosts.erase(host_id)
			host.queue_free()


func _cancel_cross_drop(suppress_release: bool = false) -> void:
	var old_source: String = _cross_source
	_cross_source = ""
	if suppress_release and old_source != "right" and floating_hosts.has(old_source):
		var host: DrawingFloatingHost = floating_hosts[old_source]
		# Cancellation initiated by the window must not let a later release
		# fire Button.pressed on the original source tab.
		host._suppress_release = true
		host._candidate_id = ""
		host._candidate_kind = ""
	_drag_candidate_kind = ""
	_drag_candidate_id = ""
	_detach_preview = false
	if dock_drag != null:
		dock_drag.cancel()
	_clear_drop_hints()


func _make_detach_hint() -> void:
	_detach_hint = PanelContainer.new()
	_detach_hint.name = "FloatingDetachPreview"
	_detach_hint.top_level = true
	_detach_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detach_hint.z_index = 105
	var caption: Label = Label.new()
	caption.text = "Release to float panels"
	_detach_hint.add_child(caption)
	_detach_hint.visible = false
	add_child(_detach_hint)


func _dock_group_position(group_id: String) -> int:
	var groups: Array = dock_layout.container_info("right")["groups"]
	for i: int in range(groups.size()):
		if groups[i]["id"] == group_id:
			return i
	return -1


func _dock_target(group_id: String, index: int, as_tabs: bool) -> Dictionary:
	return {"kind": DrawingDockDrag.MERGE_GROUP if dock_drag.source_kind() == DrawingDockDrag.GROUP else DrawingDockDrag.TAB_SLOT,
		"group": group_id, "index": index}


func _dock_target_at(position: Vector2) -> Dictionary:
	var info: Dictionary = dock_layout.container_info("right")
	var groups: Array = info["groups"]
	if dock_flyout.visible and dock_flyout_tab_scroll.get_global_rect().has_point(position):
		var open_group: String = String(info["flyout_group"])
		if not open_group.is_empty():
			return _dock_tab_target(open_group, position, dock_flyout_tabs, dock_flyout_tab_scroll)
	if bool(info["minimized"]):
		if not inspector.get_global_rect().has_point(position):
			return {}
		for entry: Dictionary in dock_layout.rail_icons("right"):
			var panel_id: String = String(entry["panel"])
			var button: Button = dock_rail_buttons.get(panel_id) as Button
			if button != null and button.get_global_rect().has_point(position):
				var group_id: String = String(entry["group"])
				var members: Array = dock_layout.group_info(group_id)["panels"]
				var slot: int = members.find(panel_id) + (1 if position.y >= button.get_global_rect().get_center().y else 0)
				var edge_y: float = button.get_global_rect().position.y if position.y < button.get_global_rect().get_center().y else button.get_global_rect().end.y
				return {"target": _dock_target(group_id, slot, true), "rect": Rect2(button.global_position.x, edge_y - 2, button.size.x, 4)}
		for idx: int in range(groups.size() + 1):
			var y: float = _dock_group_gap_y(idx)
			if absf(y - position.y) <= 16.0:
				return {"target": {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": idx},
					"rect": Rect2(inspector.global_position.x, y - 2, inspector.size.x, 4)}
		return {}
	if not inspector.get_global_rect().has_point(position):
		return {}
	# A long final group may extend past the ScrollContainer clip even at
	# maximum scroll. Reserve the visible bottom edge for an after-last-group
	# insertion, otherwise a group drag incorrectly merges into that group.
	var scroll_bar: VScrollBar = inspector.get_v_scroll_bar()
	var bottom_scroll: float = maxf(0.0, scroll_bar.max_value - scroll_bar.page)
	if dock_drag.is_dragging() and not groups.is_empty() and bottom_scroll > 0.0 and 		inspector.scroll_vertical >= roundi(bottom_scroll) - 2 and 		position.y >= inspector.get_global_rect().end.y - 16.0:
		return _dock_group_gap(groups.size(), inspector.get_global_rect().end.y - 4.0)
	for group_index: int in range(groups.size()):
		var group_id: String = String(groups[group_index]["id"])
		var frame: VBoxContainer = dock_group_frames.get(group_id) as VBoxContainer
		if frame == null or not frame.get_global_rect().has_point(position):
			continue
		var frame_rect: Rect2 = frame.get_global_rect()
		if position.y < frame_rect.position.y + 12.0:
			return _dock_group_gap(group_index, frame_rect.position.y)
		if position.y > frame_rect.end.y - 12.0:
			return _dock_group_gap(group_index + 1, frame_rect.end.y)
		var strip: ScrollContainer = dock_tab_strips.get(group_id) as ScrollContainer
		if strip != null and strip.get_global_rect().has_point(position):
			var tabs_row: HBoxContainer = strip.get_child(0) as HBoxContainer
			return _dock_tab_target(group_id, position, tabs_row, strip)
		# Passing over an expanded panel body is not an icon-proximity merge.
		# A panel must explicitly enter the visible icon strip or a group gap.
		if dock_drag.source_kind() == DrawingDockDrag.PANEL:
			return {}
		return {"target": _dock_target(group_id, dock_layout.group_info(group_id)["panels"].size(), false),
			"rect": Rect2(frame_rect.position, Vector2(frame_rect.size.x, minf(frame_rect.size.y, 44.0)))}
	if groups.is_empty():
		return _dock_group_gap(0, dock_panels.global_position.y)
	var first: VBoxContainer = dock_group_frames.get(String(groups[0]["id"])) as VBoxContainer
	var last: VBoxContainer = dock_group_frames.get(String(groups[-1]["id"])) as VBoxContainer
	if first != null and position.y <= first.global_position.y:
		return _dock_group_gap(0, first.global_position.y)
	if last != null and position.y >= last.get_global_rect().end.y:
		return _dock_group_gap(groups.size(), last.get_global_rect().end.y)
	return {}


func _dock_tab_target(group_id: String, position: Vector2, row: HBoxContainer, viewport: ScrollContainer) -> Dictionary:
	var members: Array = dock_layout.group_info(group_id)["panels"]
	var index: int = members.size()
	var indicator_x: float = viewport.get_global_rect().end.x - 3.0
	for panel_index: int in range(members.size()):
		var button: Control = row.get_node_or_null(("Tab_" if row == dock_flyout_tabs else "Edge_") + String(members[panel_index])) as Control
		if button == null:
			continue
		var rect: Rect2 = button.get_global_rect()
		if position.x < rect.get_center().x:
			index = panel_index
			indicator_x = rect.position.x
			break
		indicator_x = rect.end.x
	indicator_x = clampf(indicator_x, viewport.global_position.x + 2.0, viewport.get_global_rect().end.x - 3.0)
	return {"target": _dock_target(group_id, index, true),
		"rect": Rect2(indicator_x - 2.0, viewport.global_position.y, 4.0, viewport.size.y)}


func _dock_group_gap(index: int, y: float) -> Dictionary:
	return {"target": {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": index},
		"rect": Rect2(inspector.global_position.x + 4.0, y - 2.0, inspector.size.x - 8.0, 4.0)}


func _dock_group_gap_y(index: int) -> float:
	var groups: Array = dock_layout.container_info("right")["groups"]
	if groups.is_empty():
		return dock_rail.global_position.y
	if index < groups.size():
		var first_id: String = String(groups[index]["panels"][0])
		var button: Button = dock_rail_buttons.get(first_id) as Button
		if button != null:
			return button.get_global_rect().position.y
	var last_id: String = String(groups[-1]["panels"][-1])
	var last_button: Button = dock_rail_buttons.get(last_id) as Button
	return last_button.get_global_rect().end.y if last_button != null else dock_rail.get_global_rect().end.y


## UI-only visual semantics; DrawingDockDrag still validates/commits the
## unchanged target dictionary on a snapshot. Only icon proximity can merge.
func _drop_hint_mode(target: Dictionary) -> String:
	var kind: String = String(target.get("kind", ""))
	if kind == DrawingDockDrag.GROUP_SLOT:
		return "split" if dock_drag.source_kind() == DrawingDockDrag.PANEL else "move_group"
	if kind == DrawingDockDrag.TAB_SLOT or kind == DrawingDockDrag.MERGE_GROUP:
		if dock_drag.source_kind() == DrawingDockDrag.GROUP:
			return "merge_group"
		var source_group: String = dock_layout.group_of(_dragged_panel_id())
		return "reorder" if source_group == String(target.get("group", "")) else "merge_panel"
	return ""


func _dragged_panel_id() -> String:
	if _cross_source == "right":
		return _drag_candidate_id
	if floating_hosts.has(_cross_source):
		return String((floating_hosts[_cross_source] as DrawingFloatingHost)._candidate_id)
	return ""


func _show_dock_drop_hint(hit: Dictionary, marker: ColorRect, host: DrawingFloatingHost = null) -> void:
	var target: Dictionary = hit["target"]
	var mode: String = _drop_hint_mode(target)
	var rect: Rect2 = hit["rect"]
	marker.global_position = rect.position
	marker.size = rect.size
	marker.color = Color(0.95, 0.65, 0.19, 0.96) if mode == "split" or mode == "move_group" else \
		Color(0.18, 0.88, 0.57, 0.96) if mode == "merge_panel" or mode == "merge_group" else \
		Color(0.19, 0.78, 0.95, 0.96)
	marker.visible = true
	var label: String = ""
	match mode:
		"split": label = "Split panel into new group"
		"move_group": label = "Move whole group"
		"merge_panel": label = "Group panel with " + String(target["group"]).capitalize()
		"merge_group": label = "Merge whole group into " + String(target["group"]).capitalize()
		"reorder": label = "Reorder panel"
	if not label.is_empty():
		dock_drop_caption.text = label
		dock_drop_caption.reset_size()
		var viewport_rect: Rect2 = get_viewport_rect()
		dock_drop_caption.global_position = Vector2(
			clampf(rect.position.x - dock_drop_caption.size.x - 4.0, 2.0,
				maxf(2.0, viewport_rect.size.x - dock_drop_caption.size.x - 2.0)),
			clampf(rect.position.y - dock_drop_caption.size.y - 4.0, 2.0,
				maxf(2.0, viewport_rect.size.y - dock_drop_caption.size.y - 2.0)))
		dock_drop_caption.visible = true
	if mode == "merge_panel" or mode == "merge_group":
		var group_id: String = String(target["group"])
		var strip: ScrollContainer = (dock_tab_strips.get(group_id) as ScrollContainer) if host == null else \
			(host.tab_strips.get(group_id) as ScrollContainer)
		if host == null and dock_flyout.visible and group_id == String(dock_layout.container_info("right")["flyout_group"]):
			strip = dock_flyout_tab_scroll
		if strip != null:
			dock_merge_outline.global_position = strip.get_global_rect().position
			dock_merge_outline.size = strip.get_global_rect().size
			dock_merge_outline.visible = true


func _preview_dock_target(position: Vector2) -> void:
	var hit: Dictionary = _dock_target_at(position)
	if hit.is_empty() or not dock_drag.preview(hit["target"]):
		_clear_drop_hints()
		return
	_clear_drop_hints()
	_show_dock_drop_hint(hit, dock_drop_hint)


func _dock_apply(source_kind: String, source_id: String, destination: Dictionary, focus_key: String = "") -> bool:
	var started: bool = dock_drag.begin_panel(source_id) if source_kind == DrawingDockDrag.PANEL else dock_drag.begin_group(source_id)
	if not started or not dock_drag.preview(destination):
		dock_drag.cancel()
		return false
	if not dock_drag.commit():
		return false
	_render_dock(focus_key)
	return true


func _dock_arrange_action(action_id: int, group_id: String) -> void:
	var groups: Array = dock_layout.container_info("right")["groups"]
	var group_index: int = _dock_group_position(group_id)
	if group_index < 0:
		return
	var group: Dictionary = dock_layout.group_info(group_id)
	var panel_id: String = String(group["active"])
	var panel_index: int = group["panels"].find(panel_id)
	var destination: Dictionary = {}
	var source_kind: String = DrawingDockDrag.PANEL
	var source_id: String = panel_id
	match action_id:
		0: # Move active tab left.
			if panel_index > 0:
				destination = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": panel_index - 1}
		1:
			if panel_index < group["panels"].size() - 1:
				destination = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": panel_index + 2}
		2, 3:
			var neighbor: int = group_index + (-1 if action_id == 2 else 1)
			if neighbor >= 0 and neighbor < groups.size():
				var other: Dictionary = groups[neighbor]
				destination = {"kind": DrawingDockDrag.TAB_SLOT, "group": other["id"],
					"index": other["panels"].size() if action_id == 2 else 0}
		4:
			destination = {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": group_index + 1}
		5, 6:
			source_kind = DrawingDockDrag.GROUP
			source_id = group_id
			var new_index: int = group_index + (-1 if action_id == 5 else 2)
			if new_index >= 0 and new_index <= groups.size():
				destination = {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": new_index}
		7, 8:
			source_kind = DrawingDockDrag.GROUP
			source_id = group_id
			var neighbor: int = group_index + (-1 if action_id == 7 else 1)
			if neighbor >= 0 and neighbor < groups.size():
				var other: Dictionary = groups[neighbor]
				destination = {"kind": DrawingDockDrag.MERGE_GROUP, "group": other["id"], "index": other["panels"].size()}
		9, 10:
			for host_id: String in floating_hosts:
				var host: DrawingFloatingHost = floating_hosts[host_id]
				if host.visible:
					source_kind = DrawingDockDrag.PANEL if action_id == 9 else DrawingDockDrag.GROUP
					source_id = panel_id if action_id == 9 else group_id
					var existing: Dictionary = dock_layout.container_info(host_id)["groups"][0]
					destination = {"kind": DrawingDockDrag.TAB_SLOT if action_id == 9 else DrawingDockDrag.MERGE_GROUP,
						"group": existing["id"], "index": existing["panels"].size()}
					break
	if not destination.is_empty():
		_dock_apply(source_kind, source_id, destination,
			"drag-group:" + group_id if source_kind == DrawingDockDrag.GROUP else "edge:" + panel_id)


func _dock_keyboard_command(event: InputEventKey) -> bool:
	if not event.ctrl_pressed or not event.alt_pressed:
		return false
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	var kind: String = ""
	var panel_id: String = ""
	for key: String in dock_tab_buttons:
		if focused == dock_tab_buttons[key]:
			kind = DrawingDockDrag.PANEL
			panel_id = key
	for key: String in dock_rail_buttons:
		if focused == dock_rail_buttons[key]:
			kind = DrawingDockDrag.PANEL
			panel_id = key
	if focused.name.begins_with("Tab_") and focused.get_parent() == dock_flyout_tabs:
		kind = DrawingDockDrag.PANEL
		panel_id = String(focused.name).trim_prefix("Tab_")
	if kind == DrawingDockDrag.PANEL:
		var group_id: String = dock_layout.group_of(panel_id)
		var group: Dictionary = dock_layout.group_info(group_id)
		var index: int = group["panels"].find(panel_id)
		var destination: Dictionary = {}
		match event.keycode:
			KEY_LEFT:
				if index > 0:
					destination = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": index - 1}
			KEY_RIGHT:
				if index + 1 < group["panels"].size():
					destination = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": index + 2}
			KEY_S:
				destination = {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": _dock_group_position(group_id) + 1}
			KEY_UP, KEY_DOWN:
				var groups: Array = dock_layout.container_info("right")["groups"]
				var next_index: int = _dock_group_position(group_id) + (-1 if event.keycode == KEY_UP else 1)
				if next_index >= 0 and next_index < groups.size():
					var next_group: Dictionary = groups[next_index]
					destination = {"kind": DrawingDockDrag.TAB_SLOT, "group": next_group["id"],
						"index": next_group["panels"].size() if event.keycode == KEY_UP else 0}
		if not destination.is_empty():
			_dock_apply(DrawingDockDrag.PANEL, panel_id, destination, "rail:" + panel_id if bool(dock_layout.container_info("right")["minimized"]) else "edge:" + panel_id)
		return not destination.is_empty()
	if event.shift_pressed and (event.keycode == KEY_UP or event.keycode == KEY_DOWN):
		for group_id: String in dock_group_handles:
			if focused == dock_group_handles[group_id]:
				var group_index: int = _dock_group_position(group_id)
				var count: int = dock_layout.container_info("right")["groups"].size()
				var target_index: int = group_index - 1 if event.keycode == KEY_UP else group_index + 2
				if target_index >= 0 and target_index <= count:
					_dock_apply(DrawingDockDrag.GROUP, group_id, {"kind": DrawingDockDrag.GROUP_SLOT,
						"container": "right", "index": target_index}, "drag-group:" + group_id)
				return true
	return false


func _restore_expanded_scroll() -> void:
	inspector.scroll_vertical = _expanded_scroll


func _make_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog: FileDialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.drawing ; Drawing document"])
	dialog.size = Vector2i(850, 540)
	add_child(dialog)
	return dialog


## Foreground and background are separately editable pigments, never a color-swap shortcut.
## PhotoCraft's distinct color targets inform the interaction; this remains a native Godot layout.
func _build_color_controls(parent: VBoxContainer) -> void:
	# One shared view is reparented through dock, flyout and floating hosts.
	# The owner's concept keeps edited FG/BG, swap and vertical recents on ONE
	# compact row; no restore-previous swatches or extra Recent heading.
	color_top_strip = HBoxContainer.new()
	color_top_strip.name = "PigmentsAndRecent"
	color_top_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_top_strip.add_theme_constant_override("separation", 5)
	parent.add_child(color_top_strip)
	var roles: HBoxContainer = HBoxContainer.new()
	roles.name = "PigmentRoles"
	roles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roles.size_flags_stretch_ratio = 1.0
	roles.add_theme_constant_override("separation", 1)
	color_top_strip.add_child(roles)
	for role: String in ["Foreground", "Swap", "Background"]:
		var button: Button = Button.new()
		button.focus_mode = Control.FOCUS_ALL
		if role == "Swap":
			button.name = "SwapPigments"
			button.text = "⇄"
			button.custom_minimum_size = Vector2(18, 52)
			button.tooltip_text = "Swap foreground and background"
			button.pressed.connect(_swap_colors)
		else:
			button.name = role + "Pigment"
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(32, 52)
			button.tooltip_text = "Edit " + role.to_lower() + " color"
			button.pressed.connect(_color_swatch_pressed.bind(role))
			color_swatch_buttons.append(button)
			if role == "Foreground":
				foreground_button = button
			else:
				background_button = button
		roles.add_child(button)
	var recents: HBoxContainer = HBoxContainer.new()
	recents.name = "RecentBars"
	recents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recents.size_flags_stretch_ratio = 1.0
	recents.add_theme_constant_override("separation", 2)
	color_top_strip.add_child(recents)
	for index: int in range(6):
		var sample: Button = Button.new()
		sample.name = "Recent_%d" % index
		sample.custom_minimum_size = Vector2(10, 52)
		sample.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sample.focus_mode = Control.FOCUS_ALL
		sample.tooltip_text = "Apply recent color to the edited role"
		sample.pressed.connect(_use_recent_color.bind(index))
		recents.add_child(sample)
		color_recent_buttons.append(sample)
		color_swatch_buttons.append(sample)
	# The native picker remains inline and scrollable inside the same view.
	color_picker_scroll = ScrollContainer.new()
	color_picker_scroll.name = "InlinePickerViewport"
	color_picker_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	color_picker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	color_picker_scroll.follow_focus = true
	color_picker_scroll.gui_input.connect(_scroll_inline_picker_wheel)
	parent.add_child(color_picker_scroll)
	color_advanced = ColorPicker.new()
	color_advanced.name = "InlineColorPicker"
	color_advanced.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	color_advanced.focus_mode = Control.FOCUS_ALL
	color_advanced.color_changed.connect(_on_picker_color_changed)
	color_picker_scroll.add_child(color_advanced)
	# Keep the exact canonical input below the native picker. It remains
	# reachable by scrolling but no longer splits the owner's FG/BG/recents
	# strip from the picker square.
	var exact_row: HBoxContainer = HBoxContainer.new()
	exact_row.name = "ExactColorEntry"
	parent.add_child(exact_row)
	var defaults: Button = Button.new()
	defaults.name = "DefaultPigments"
	defaults.text = "◩"
	defaults.custom_minimum_size.x = 28
	defaults.tooltip_text = "Default black foreground / white background"
	defaults.pressed.connect(_reset_colors)
	exact_row.add_child(defaults)
	color_hex = LineEdit.new()
	color_hex.placeholder_text = "#RRGGBBAA"
	color_hex.tooltip_text = "Edit selected pigment as #RRGGBB or #RRGGBBAA"
	color_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_hex.text_submitted.connect(func(_text: String) -> void: _commit_hex())
	color_hex.focus_exited.connect(_commit_hex)
	exact_row.add_child(color_hex)
	var rgba: GridContainer = GridContainer.new()
	rgba.name = "ExactRGBA8"
	rgba.columns = 2
	parent.add_child(rgba)
	for channel: String in ["R", "G", "B", "A"]:
		var spin: SpinBox = SpinBox.new()
		spin.min_value = 0
		spin.max_value = 255
		spin.step = 1
		spin.rounded = true
		spin.custom_minimum_size.x = 70
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.prefix = channel
		spin.tooltip_text = "%s channel (0–255) for selected pigment" % channel
		spin.value_changed.connect(_commit_rgb)
		rgba.add_child(spin)
		color_rgb.append(spin)
	_refresh_color_controls()

## The inner ScrollContainer owns horizontal overflow, but Godot's native
## ColorPicker stops plain wheel events before the host sees them. Relay only
## vertical wheel events to the current dock/flyout/floating ScrollContainer;
## leave pointer clicks, focus and modifier gestures to the native picker.
func _scroll_inline_picker_wheel(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if not wheel.pressed or wheel.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if wheel.shift_pressed or wheel.ctrl_pressed or wheel.alt_pressed or wheel.meta_pressed:
		return
	var ancestor: Node = color_picker_scroll.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			var scroll: ScrollContainer = ancestor as ScrollContainer
			if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
				var limit: float = maxf(0.0, scrollbar.max_value - scrollbar.page)
				if limit > 0.0:
					var step: int = maxi(24, roundi(scroll.size.y / 8.0 * maxf(wheel.factor, 1.0)))
					scroll.scroll_vertical = clampi(scroll.scroll_vertical +
						(-step if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else step), 0, roundi(limit))
					color_picker_scroll.accept_event()
					return
		ancestor = ancestor.get_parent()


func _style_swatch(button: Button, value: Color, caption: String, selected: bool = false) -> void:
	button.text = caption
	var style: StyleBoxFlat = StyleBoxFlat.new()
	# Show the actual RGB channels even for zero-alpha pigments. The native
	# picker and RGBA tooltip expose opacity without losing hidden RGB identity.
	style.bg_color = Color(value.r, value.g, value.b, 1.0)
	style.set_border_width_all(2 if selected else 1)
	style.border_color = Color(0.27, 0.65, 1.0) if selected else Color(0.35, 0.35, 0.35)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, style)
	var ink: Color = Color.BLACK if Color(value.r, value.g, value.b, 1.0).get_luminance() > 0.6 else Color.WHITE
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)


func _edited_color() -> Color:
	return color_background if color_edit_background else active_color


func _refresh_color_controls() -> void:
	if color_hex == null:
		return
	_updating_color_widgets = true
	var selected: Color = _edited_color()
	color_hex.text = "#" + selected.to_html(true).to_upper()
	var channels: Array[int] = [roundi(selected.r * 255.0), roundi(selected.g * 255.0),
		roundi(selected.b * 255.0), roundi(selected.a * 255.0)]
	for index: int in range(color_rgb.size()):
		color_rgb[index].set_value_no_signal(channels[index])
	_style_swatch(foreground_button, active_color, "FG", not color_edit_background)
	_style_swatch(background_button, color_background, "BG", color_edit_background)
	foreground_button.tooltip_text = "Edit foreground #" + active_color.to_html(true).to_upper()
	background_button.tooltip_text = "Edit background #" + color_background.to_html(true).to_upper()
	var visible_colors: Array[Color] = _visible_recent_colors()
	for index: int in range(color_recent_buttons.size()):
		var button: Button = color_recent_buttons[index]
		button.visible = index < visible_colors.size()
		if button.visible:
			_style_swatch(button, visible_colors[index], "")
			button.tooltip_text = "Apply #" + visible_colors[index].to_html(true).to_upper() + " to " + ("BG" if color_edit_background else "FG")
	if color_advanced != null:
		color_advanced.color = selected
	_updating_color_widgets = false


## An exact identity for display filtering and deduplication. RGBA is straight,
## so even zero-alpha RGB remains meaningful and does not get premultiplied away.
## Restore state before widgets and the brush canvas exist. Palette state is
## deliberately separate from project artwork and Undo/Redo serialization.
func _load_color_history() -> void:
	if not preferences_persistence_enabled:
		return
	var restored: Dictionary = COLOR_HISTORY_SETTINGS.read_file(recent_colors_settings_path)
	if restored.is_empty():
		return
	active_color = restored["foreground"]
	color_background = restored["background"]
	color_edit_background = restored["editing_background"]
	recent_colors = restored["recent"]


func _save_color_history() -> void:
	if preferences_persistence_enabled and not _color_write_suspended:
		COLOR_HISTORY_SETTINGS.save_file(recent_colors_settings_path, active_color,
			color_background, color_edit_background, recent_colors)


func _canonical_color(value: Color) -> Color:
	return Color8(clampi(roundi(value.r * 255.0), 0, 255),
		clampi(roundi(value.g * 255.0), 0, 255),
		clampi(roundi(value.b * 255.0), 0, 255),
		clampi(roundi(value.a * 255.0), 0, 255))


func _visible_recent_colors() -> Array[Color]:
	var available: Array[Color] = []
	var used: Dictionary = {_pack_color(active_color): true, _pack_color(color_background): true}
	for item: Color in recent_colors:
		var key: int = _pack_color(item)
		if not used.has(key):
			available.append(item)
			used[key] = true
	return available


func _remember_recent(value: Color) -> void:
	var canonical: Color = _canonical_color(value)
	var key: int = _pack_color(canonical)
	for index: int in range(recent_colors.size() - 1, -1, -1):
		if _pack_color(recent_colors[index]) == key:
			recent_colors.remove_at(index)
	recent_colors.push_front(canonical)
	if recent_colors.size() > 6:
		recent_colors.resize(6)


func _set_foreground(value: Color, record_recent: bool = true) -> void:
	var canonical: Color = _canonical_color(value)
	if _updating_color_widgets or _pack_color(active_color) == _pack_color(canonical):
		return
	if record_recent:
		_remember_recent(active_color)
	active_color = canonical
	if canvas != null:
		canvas.color_rgba = _pack_color(canonical)
	_refresh_color_controls()
	if record_recent:
		_save_color_history()


func _set_background(value: Color, record_recent: bool = true) -> void:
	var canonical: Color = _canonical_color(value)
	if _updating_color_widgets or _pack_color(color_background) == _pack_color(canonical):
		return
	if record_recent:
		_remember_recent(color_background)
	color_background = canonical
	# Background is a UI pigment, not a paint target or document operation.
	_refresh_color_controls()
	if record_recent:
		_save_color_history()


func _set_selected_color(value: Color) -> void:
	if color_edit_background:
		_set_background(value)
	else:
		_set_foreground(value)


func _on_picker_color_changed(value: Color) -> void:
	if _color_edit_ignore_until_release or _updating_color_widgets:
		return
	if _color_edit_pending:
		if _color_edit_background:
			_set_background(value, false)
		else:
			_set_foreground(value, false)
	else:
		# The picker may also be changed by an accessibility action or script
		# without a captured pointer/key event: a single signal is one edit.
		_set_selected_color(value)


func _begin_color_edit() -> void:
	if _color_edit_pending:
		return
	_color_edit_pending = true
	_color_edit_background = color_edit_background
	_color_edit_original = _edited_color()


func _finish_color_edit() -> void:
	if not _color_edit_pending:
		return
	var ending: Color = color_background if _color_edit_background else active_color
	_color_edit_pending = false
	_color_edit_pointer_down = false
	_color_edit_text = null
	if _pack_color(ending) != _pack_color(_color_edit_original):
		_remember_recent(_color_edit_original)
		_refresh_color_controls()
		_save_color_history()


func _cancel_color_edit() -> void:
	if not _color_edit_pending:
		return
	var original: Color = _color_edit_original
	var background: bool = _color_edit_background
	_color_edit_ignore_until_release = _color_edit_pointer_down
	_color_edit_pending = false
	_color_edit_pointer_down = false
	_color_edit_text = null
	if background:
		_set_background(original, false)
	else:
		_set_foreground(original, false)
	_refresh_color_controls()


func _color_input_target(position: Vector2) -> bool:
	if color_advanced != null and color_advanced.is_visible_in_tree() and color_advanced.get_global_rect().has_point(position):
		return true
	for spin: SpinBox in color_rgb:
		if spin.is_visible_in_tree() and spin.get_global_rect().has_point(position):
			return true
	return false


func _is_color_input_focus(control: Control) -> bool:
	if control == null:
		return false
	if color_advanced != null and (control == color_advanced or color_advanced.is_ancestor_of(control)):
		return true
	for spin: SpinBox in color_rgb:
		if control == spin or spin.is_ancestor_of(control):
			return true
	return false


func _end_cancelled_color_pointer() -> void:
	_color_edit_ignore_until_release = false
	_color_edit_recover_on_press = false


func _cancel_interrupted_color_pointer() -> void:
	# The mouse release might never arrive. Roll back the live preview, keep
	# rejecting stale native ColorPicker events, but let a fresh press recover.
	_cancel_color_edit()
	_color_edit_recover_on_press = true


func _track_color_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			if _color_edit_recover_on_press:
				_end_cancelled_color_pointer()
			if _color_edit_pending and not _color_edit_pointer_down:
				_finish_color_edit()
			if _color_input_target(button.position):
				_begin_color_edit()
				_color_edit_pointer_down = true
		elif _color_edit_ignore_until_release:
			call_deferred("_end_cancelled_color_pointer")
		elif _color_edit_pointer_down:
			# Native ColorPicker changes its value during GUI dispatch, after
			# _input(). Finish after that last release-frame color_changed.
			call_deferred("_finish_color_edit")
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _color_edit_pointer_down and not bool(motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_cancel_interrupted_color_pointer()
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		var focused: Control = get_viewport().gui_get_focus_owner()
		if key.pressed and key.keycode == KEY_ESCAPE and _color_edit_pending:
			_cancel_color_edit()
			get_viewport().set_input_as_handled()
			return
		if key.pressed and _is_color_input_focus(focused):
			if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_TAB:
				call_deferred("_finish_color_edit")
			elif not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
				_begin_color_edit()
				if focused is LineEdit and _color_edit_text != focused:
					_color_edit_text = focused
					if not focused.focus_exited.is_connected(_finish_color_edit):
						focused.focus_exited.connect(_finish_color_edit)
		elif not key.pressed and _color_edit_pending and not _color_edit_pointer_down and _color_edit_text == null:
			call_deferred("_finish_color_edit")


func _swap_colors() -> void:
	_finish_color_edit()
	_color_write_suspended = true
	var former: Color = active_color
	_set_foreground(color_background)
	_set_background(former)
	_color_write_suspended = false
	_refresh_color_controls()
	_save_color_history()


func _reset_colors() -> void:
	_finish_color_edit()
	_color_write_suspended = true
	_set_foreground(Color.BLACK)
	_set_background(Color.WHITE)
	_color_write_suspended = false
	_refresh_color_controls()
	_save_color_history()


func _color_swatch_pressed(role: String) -> void:
	_finish_color_edit()
	match role:
		"Foreground": color_edit_background = false
		"Background": color_edit_background = true
	_refresh_color_controls()
	_save_color_history()


func _use_recent_color(index: int) -> void:
	_finish_color_edit()
	var visible_colors: Array[Color] = _visible_recent_colors()
	if index >= 0 and index < visible_colors.size():
		_set_selected_color(visible_colors[index])


## Color.html_is_valid also permits bare/abbreviated hex; the Colors editor
## promises exactly six or eight digit channels with an explicit leading #.
func _valid_color_hex(value: String) -> bool:
	if not value.begins_with("#") or value.length() not in [7, 9]:
		return false
	for index: int in range(1, value.length()):
		if "0123456789abcdefABCDEF".find(value.substr(index, 1)) < 0:
			return false
	return true


func _commit_hex() -> void:
	_finish_color_edit()
	if color_hex == null:
		return
	var value: String = color_hex.text.strip_edges()
	if _valid_color_hex(value):
		_set_selected_color(Color.html(value))
	_refresh_color_controls()


func _commit_rgb(_value: float) -> void:
	if _updating_color_widgets or color_rgb.size() != 4:
		return
	_on_picker_color_changed(Color8(int(color_rgb[0].value), int(color_rgb[1].value),
		int(color_rgb[2].value), int(color_rgb[3].value)))


func _refresh_history() -> void:
	if history_list == null or active_tab < 0:
		return
	var document: DrawingDocument = current_document()
	var stamp: String = "%s:%d:%d:%s" % [str(document.get_instance_id()),
		document.history_position(), document.history_length(), str(document.external_history)]
	if stamp == _history_stamp:
		return
	_history_stamp = stamp
	_rendering_history = true
	history_list.clear()
	_history_row_positions.clear()
	history_undo.disabled = document.external_history or not document.can_undo()
	history_redo.disabled = document.external_history or not document.can_redo()
	history_label.text = "%d / %d" % [document.history_position(), document.history_length()]
	if document.external_history:
		history_list.add_item("History owned by host")
	else:
		var total: int = document.history_length()
		var first: int = clampi(document.history_position() - 32, 0, maxi(0, total - 64))
		if first == 0:
			history_list.add_item("0 · Initial state")
			_history_row_positions.append(0)
		var labels: Array[String] = document.history_summaries(first, 64)
		for index: int in range(labels.size()):
			var position: int = first + index + 1
			history_list.add_item("%d · %s" % [position, labels[index]])
			_history_row_positions.append(position)
		var row: int = _history_row_positions.find(document.history_position())
		if row >= 0:
			history_list.select(row)
	_rendering_history = false


func _history_item_selected(row: int) -> void:
	if _rendering_history or active_tab < 0 or row < 0 or row >= _history_row_positions.size():
		return
	var target: int = _history_row_positions[row]
	var document: DrawingDocument = current_document()
	if target == document.history_position():
		return
	# History list rows bypass the Undo/Redo buttons. A jump would revise the
	# source beneath detached Brush input and silently discard its queued edits.
	if not _can_persist_or_close("History navigation"):
		var current_row: int = _history_row_positions.find(document.history_position())
		_rendering_history = true
		if current_row >= 0:
			history_list.select(current_row)
		else:
			history_list.deselect_all()
		_rendering_history = false
		return
	while document.history_position() > target:
		var result: DrawingResult = document.undo()
		if not result.ok:
			_show_error(result.message)
			break
		_restore_context(result.value as DrawingHistoryContext)
	while document.history_position() < target:
		var result: DrawingResult = document.redo()
		if not result.ok:
			_show_error(result.message)
			break
		_restore_context(result.value as DrawingHistoryContext)
	_after_edit()


func _pack_color(value: Color) -> int:
	return clampi(roundi(value.r * 255.0), 0, 255) | (clampi(roundi(value.g * 255.0), 0, 255) << 8) | (clampi(roundi(value.b * 255.0), 0, 255) << 16) | (clampi(roundi(value.a * 255.0), 0, 255) << 24)


func current_object() -> DrawingObjectEditorSession:
	return tabs[active_tab].get("object") as DrawingObjectEditorSession if active_tab >= 0 else null


func current_document() -> DrawingDocument:
	return tabs[active_tab]["document"] as DrawingDocument if active_tab >= 0 else null


func current_layer() -> String:
	# Empty for selected groups: their contents remain visible but drawing into
	# a previously selected raster must never happen silently.
	return String(tabs[active_tab]["layer"]) if active_tab >= 0 else ""


func selected_layer_node() -> String:
	return String(tabs[active_tab].get("selected_node", current_layer())) if active_tab >= 0 else ""


func new_drawing() -> void:
	if not _can_persist_or_close("New"):
		return
	new_counter += 1
	var document: DrawingDocument = DrawingDocument.new()
	document.record_selection_history = record_selection_history
	var group: DrawingResult = document.create_layer(DrawingLayerNode.GROUP, "Group 1")
	var raster: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1", String(group.value))
	tabs.append({"document": document, "path": "", "title": "Untitled %d" % new_counter,
		"layer": raster.value, "selected_node": raster.value, "saved": -1, "frame": IMAGE_FRAME.DEFAULT_BOUNDS,
		"saved_frame": IMAGE_FRAME.DEFAULT_BOUNDS,
		"frame_dirty": false, "fit_pending": true})
	tab_bar.add_tab("Untitled %d *" % new_counter)
	_activate(tabs.size() - 1)


## Atlas host opens a captured, detached Object Asset draft through this API.
## The very same Drawing canvas, text editor and layer panel edit the object.
func attach_object_session(session: DrawingObjectEditorSession) -> DrawingResult:
	if not _can_persist_or_close("Open Object"):
		return DrawingResult.failure("STROKE_PENDING", "Finish the pending stroke before opening another document")
	if session == null or session.document == null:
		return DrawingResult.failure("OBJECT", "Missing Object Editor session")
	session.document.record_selection_history = record_selection_history
	var layer: String = _first_editable(session.document, DrawingDocument.ROOT_ID)
	var tab_name: String = "Object: " + session.name
	tabs.append({"document": session.document, "object": session,
		"path": "", "title": tab_name, "layer": layer, "selected_node": layer})
	tab_bar.add_tab(tab_name)
	_activate(tabs.size() - 1)
	return DrawingResult.success(active_tab)


## Standalone authoring uses ordinary portable .drawing assets; no Atlas
## instance can be rebound by this local-file publisher.
func new_object() -> void:
	if not _can_persist_or_close("New Object"):
		return
	new_counter += 1
	var document: DrawingDocument = DrawingDocument.new()
	var group: DrawingResult = document.create_layer(DrawingLayerNode.GROUP, "Group 1")
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1", String(group.value))
	var session: DrawingObjectEditorSession = DrawingObjectEditorSession.new(document, "", 0,
		"New object %d" % new_counter)
	session.save_publisher = _local_publish.bind(false)
	session.save_as_publisher = _local_publish.bind(true)
	attach_object_session(session)
	tabs[active_tab]["local_object"] = true
	tabs[active_tab]["layer"] = layer.value
	tabs[active_tab]["selected_node"] = layer.value
	canvas.layer_id = String(layer.value)
	_update_status()


func _ask_asset_browser() -> void:
	# Existing Window command remains a shortcut to the discoverable browser.
	_show_asset_browser_empty()


func _ensure_asset_browser() -> bool:
	if asset_browser != null:
		return true
	asset_browser = ASSET_BROWSER_SCRIPT.new() as DrawingAssetBrowserPanel
	asset_browser.open_requested.connect(_open_object_file)
	asset_browser.choose_root_requested.connect(_choose_objects_root)
	asset_browser.recent_root_requested.connect(_use_recent_objects_root)
	if not dock_layout.register_panel("asset_browser") or \
			not dock_layout.attach_panel("asset_browser", "right", "asset_browser"):
		asset_browser.queue_free()
		asset_browser = null
		return false
	dock_views["asset_browser"] = asset_browser
	dock_stash.add_child(asset_browser)
	asset_browser.set_recent_root(_recent_objects_root)
	return true


func _show_asset_browser_empty() -> void:
	if _ensure_asset_browser():
		_render_dock()
		call_deferred("_reveal_asset_browser")
		# The browser owns the explanation and root-chooser buttons. No file is
		# scanned and no previously remembered Atlas project is silently opened.


func _reveal_asset_browser() -> void:
	if asset_browser != null and asset_browser.is_visible_in_tree() and \
			inspector != null and inspector.is_ancestor_of(asset_browser):
		inspector.ensure_control_visible(asset_browser.choose_root_button)


func _choose_objects_root() -> void:
	asset_browser_directory_dialog.popup_centered_ratio(0.7)


func _chosen_objects_root(path: String) -> void:
	if not show_asset_browser(path):
		return
	# Only a successful, explicit directory choice updates recent-root history.
	if ROOT_HISTORY.save_file(recent_objects_root_settings_path, path.simplify_path()):
		_recent_objects_root = path.simplify_path()
		asset_browser.set_recent_root(_recent_objects_root)
	else:
		_show_error("Objects/ opened, but the last-used folder preference could not be saved")


func _use_recent_objects_root() -> void:
	if _recent_objects_root.is_empty():
		_show_error("No previously chosen Objects/ folder; choose one first")
		return
	# The user must explicitly invoke this action, including after relaunch.
	show_asset_browser(_recent_objects_root)


## Standalone and Atlas share the dock peer. Only the user-chosen directory
## (or the host-provided initial_asset_browser_root) is ever scanned.
func show_asset_browser(objects_root: String) -> bool:
	if not _ensure_asset_browser():
		return false
	var result: DrawingResult = asset_browser.set_objects_root(objects_root)
	_render_dock()
	if result.ok:
		call_deferred("_reveal_asset_browser")
	if not result.ok:
		_show_error("Cannot open Object source folder: " + result.message +
			". Select an existing absolute Objects/ directory, not a .drawing file or project root.")
	return result.ok


func _ask_open_object() -> void:
	if _can_persist_or_close("Open Object"):
		object_open_dialog.popup_centered()


func _open_object_file(path: String) -> void:
	if not _can_persist_or_close("Open Object"):
		return
	var opened: DrawingResult = DrawingObjectEditorFile.open(path)
	if not opened.ok:
		_show_error(opened.message)
		return
	var data: Dictionary = opened.value
	var session: DrawingObjectEditorSession = DrawingObjectEditorSession.new(data["document"],
		data["source_id"], data["source_revision"], data["name"], "", "",
		data["origin"], data["bounds"])
	session.save_publisher = _local_publish.bind(false)
	session.save_as_publisher = _local_publish.bind(true)
	attach_object_session(session)
	tabs[active_tab]["local_object"] = true
	tabs[active_tab]["path"] = path
	_update_status()


func _local_publish(session: DrawingObjectEditorSession, as_variant: bool) -> DrawingResult:
	var index: int = _find_object_tab(session)
	if index < 0:
		return DrawingResult.failure("TAB", "Object Editor tab was closed")
	var path: String = String(tabs[index].get("_target_path", tabs[index].get("path", "")))
	if path.is_empty() or (as_variant and path == tabs[index].get("path", "")):
		return DrawingResult.failure("PATH", "Choose a different target path for Save As")
	var source: DrawingDocument = session.document
	if as_variant:
		var copied: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(),
			source.tile_stride, source.density_numerator, source.density_denominator)
		for node_id: String in source.list_children():
			var exported: DrawingResult = source.export_subtree(node_id)
			if not exported.ok:
				return exported
			var imported: DrawingResult = copied.import_subtree(exported.value, DrawingDocument.ROOT_ID)
			if not imported.ok:
				return imported
		source = copied
	var written: DrawingResult = DrawingObjectEditorFile.save(source, path, session.name,
		session.origin, session.bounds, 1 if as_variant else session.source_revision + 1)
	if not written.ok:
		return written
	var reopened: DrawingResult = DrawingObjectEditorFile.open(path)
	if not reopened.ok:
		return reopened
	if asset_browser != null:
		asset_browser.notify_source_published(path)
	tabs[index]["path"] = path
	tabs[index].erase("_target_path")
	var snapshot: Dictionary = reopened.value
	snapshot["detach_origin"] = true
	return DrawingResult.success(snapshot)


func _find_object_tab(session: DrawingObjectEditorSession) -> int:
	for index: int in range(tabs.size()):
		if tabs[index].get("object") == session:
			return index
	return -1


func _ask_rename_object() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		_show_error("Select an Object Editor tab")
		return
	rename_field.text = session.name
	_capture_authoring_dialog_target("object_rename")
	rename_dialog.popup_centered()


func _rename_object() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	# A changed source label must not be staged under unpublished paint.
	# Equivalent text is harmless (e.g. confirming an already-open dialog).
	if rename_field.text.strip_edges() != session.name and not _can_persist_or_close("Rename Object"):
		return
	var changed: DrawingResult = session.set_name(rename_field.text)
	if changed.ok:
		_update_status()
	else:
		_show_error(changed.message)


func _ask_object_frame() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		_show_error("Select an Object Editor tab")
		return
	var values: Array[int] = [session.origin.x, session.origin.y,
		session.bounds.position.x, session.bounds.position.y,
		session.bounds.size.x, session.bounds.size.y]
	for index: int in range(frame_fields.size()):
		frame_fields[index].value = values[index]
	_capture_authoring_dialog_target("object_frame")
	frame_dialog.popup_centered()


func _change_object_frame() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	var origin: Vector2i = Vector2i(int(frame_fields[0].value), int(frame_fields[1].value))
	var bounds: Rect2i = Rect2i(int(frame_fields[2].value), int(frame_fields[3].value),
		int(frame_fields[4].value), int(frame_fields[5].value))
	# Object source context may not be rewritten while detached Brush input
	# still targets its captured document and authoring metadata.
	if (origin != session.origin or bounds != session.bounds) and not _can_persist_or_close("Change Object Frame"):
		return
	var changed: DrawingResult = session.set_frame(origin, bounds)
	if not changed.ok:
		_show_error(changed.message)
		return
	canvas.asset_origin = session.origin
	canvas.asset_bounds = session.bounds
	canvas.queue_redraw()
	_update_status()


func _save_as_named_object() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	var title: String = variant_name.text.strip_edges()
	if title.is_empty() or title.length() > 128 or "\n" in title or "\r" in title:
		_show_error("Choose a 1–128 character Object Asset name")
		return
	# A rejected Save As must not leave its proposed name on a private draft.
	# Authorize before staging, then restore the prior target on any failed
	# publication (including a malformed or stale source snapshot).
	if not _can_persist_or_close("Save Object As"):
		return
	var previous_variant_name: String = session.variant_name
	session.variant_name = title
	if not _publish_object(true):
		session.variant_name = previous_variant_name


## Do not serialize or close a still-unpublished stroke. Rejection is
## intentional: synchronous draining on Save would stall the input loop.
## The user can Save or Close again after normal frame-budgeted commit.
func _can_persist_or_close(action: String) -> bool:
	if not canvas.has_pending_stroke():
		return true
	if _close_after_save:
		_cancel_pending_close()
	_show_error("Stroke still processing; %s after the stroke finishes" % action)
	return false


## Close the standalone window through the same per-tab Save/Discard/Cancel
## decisions as File > Close Tab. Never silently discard unpublished strokes.
func _request_window_quit() -> void:
	if _window_quit_requested:
		return
	if not _can_persist_or_close("Close Window"):
		return
	_window_quit_requested = true
	_advance_window_quit()


func _advance_window_quit() -> void:
	if not _window_quit_requested:
		return
	if not _can_persist_or_close("Close Window"):
		return
	if tabs.is_empty():
		_window_quit_requested = false
		if _window_quit_guard_enabled:
			get_tree().quit()
		return
	# Closing the last tab preserves the current selection until each previous
	# dirty tab receives its own explicit Save/Discard/Cancel decision.
	_request_close_tab(tabs.size() - 1)


func _request_close_current() -> void:
	_request_close_tab(active_tab)


func _request_close_tab(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	if not _can_persist_or_close("Close Tab"):
		return
	if index == active_tab and canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	_closing_index = index
	_close_after_save = false
	var session: DrawingObjectEditorSession = tabs[index].get("object") as DrawingObjectEditorSession
	if session != null and session.is_dirty() or (session == null and
		((tabs[index]["document"] as DrawingDocument).is_dirty() or
		bool(tabs[index].get("frame_dirty", false)))):
		if DisplayServer.get_name() == "headless":
			close_dialog.show()
		else:
			close_dialog.popup_centered()
	else:
		_close_index(index)


func _cancel_pending_close() -> void:
	_closing_index = -1
	_close_after_save = false
	_local_save_as = false
	_window_quit_requested = false


func _save_and_close() -> void:
	if _closing_index < 0:
		return
	if _closing_index != active_tab and not _can_persist_or_close("Save and Close"):
		_cancel_pending_close()
		return
	_close_after_save = true
	_activate(_closing_index)
	_save()


func _close_index(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	if not _can_persist_or_close("Close Tab"):
		return
	var session: DrawingObjectEditorSession = tabs[index].get("object") as DrawingObjectEditorSession
	if session != null:
		object_tab_closed.emit(session)
	tabs.remove_at(index)
	tab_bar.remove_tab(index)
	_closing_index = -1
	_close_after_save = false
	active_tab = -1
	if tabs.is_empty():
		canvas.document = null
		canvas.layer_id = ""
		layers.clear()
		status.text = "No document open"
	else:
		_activate(mini(index, tabs.size() - 1))
	if _window_quit_requested:
		# Let dialog signals and tab changes settle before advancing to the
		# next tab; a cancelled prompt revokes the quit request immediately.
		call_deferred("_advance_window_quit")


func _close_if_saved() -> void:
	if not _close_after_save or _closing_index != active_tab:
		return
	var session: DrawingObjectEditorSession = current_object()
	if session == null or not session.is_dirty():
		if not current_document().is_dirty() and not bool(tabs[active_tab].get("frame_dirty", false)):
			_close_index(active_tab)


func _sync_object_tab() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	tabs[active_tab]["document"] = session.document
	tabs[active_tab]["title"] = "Object: " + session.name
	var selected: String = current_layer()
	if not session.document.has_node(selected) and not session.document.has_node(selected_layer_node()):
		tabs[active_tab]["layer"] = _first_editable(session.document, DrawingDocument.ROOT_ID)
		tabs[active_tab]["selected_node"] = current_layer()
	canvas.document = session.document
	canvas.layer_id = current_layer()
	canvas.asset_origin = session.origin
	canvas.asset_bounds = session.bounds
	_after_edit()


## TabBar emits tab_changed synchronously, including for programmatic selection.
## Preserve existing idle same-tab refresh behavior, but never reset the
## Canvas session while unpublished Brush work belongs to the current tab.
func _activate(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	if index == active_tab and canvas.has_pending_stroke():
		return
	if active_tab >= 0 and index != active_tab and not _can_persist_or_close("Switch Tab"):
		# Restore the UI's selection; the resulting tab_changed is a no-op.
		tab_bar.current_tab = active_tab
		return
	if active_tab >= 0 and active_tab < tabs.size() and active_tab != index:
		tabs[active_tab]["camera"] = canvas.camera
		tabs[active_tab]["zoom"] = canvas.zoom
	active_tab = index
	tab_bar.current_tab = index
	canvas.document = current_document()
	var chosen: String = selected_layer_node()
	if not current_document().has_node(chosen):
		chosen = _first_editable(current_document(), DrawingDocument.ROOT_ID)
		tabs[active_tab]["selected_node"] = chosen
		tabs[active_tab]["layer"] = chosen
	canvas.layer_id = current_layer()
	var object_session: DrawingObjectEditorSession = current_object()
	canvas.asset_origin = object_session.origin if object_session != null else Vector2i.ZERO
	canvas.asset_bounds = object_session.bounds if object_session != null else Rect2i()
	canvas.image_bounds = tabs[index].get("frame", Rect2i()) as Rect2i
	canvas.show_grid = bool(tabs[index].get("show_grid", false))
	canvas.snap_to_grid = bool(tabs[index].get("snap", false))
	canvas.grid_spacing = int(tabs[index].get("grid_spacing", 8))
	canvas.grid_origin = tabs[index].get("grid_origin", Vector2i.ZERO) as Vector2i
	snap_toggle.set_pressed_no_signal(canvas.snap_to_grid)
	snap_toggle.text = "Snap (%d px)" % canvas.grid_spacing
	top_bar.set_menu_checked("View", 3, canvas.show_grid)
	canvas.camera = tabs[index].get("camera", Vector2.ZERO) as Vector2
	canvas.zoom = float(tabs[index].get("zoom", 4.0))
	canvas.selected = Rect2i()
	canvas.session = null
	canvas.queue_redraw()
	_refresh_layers()
	_last_selection_context = _capture_context()
	_maybe_fit_image_frame()
	_update_status()


func _flatten_layer_ids(parent: String, depth: int, output: Array[Dictionary]) -> void:
	for node_id: String in current_document().list_children(parent):
		var info: Dictionary = current_document().node_metadata(node_id)
		output.append({"id": node_id, "depth": depth, "info": info})
		if info["kind"] == DrawingLayerNode.GROUP:
			_flatten_layer_ids(node_id, depth + 1, output)


func _refresh_layers() -> void:
	layers.clear()
	var root: TreeItem = layers.create_item()
	if current_document() == null:
		return
	var all_rows: Array[Dictionary] = []
	_flatten_layer_ids(DrawingDocument.ROOT_ID, 0, all_rows)
	var matches: Array[Dictionary] = []
	var query: String = layer_search.text.strip_edges().to_lower()
	for row: Dictionary in all_rows:
		var info: Dictionary = row["info"]
		var content: String = ""
		if info["kind"] == DrawingLayerNode.TEXT and not query.is_empty():
			var preview: DrawingLayerNode = current_document().inspect_node(row["id"])
			content = preview.text_value
		if query.is_empty() or String(info["name"]).to_lower().contains(query) or content.to_lower().contains(query):
			matches.append(row)
	var page_count: int = maxi(1, ceili(float(matches.size()) / ROW_PAGE))
	layer_page = clampi(layer_page, 0, page_count - 1)
	layer_page_label.text = "%d/%d · %d" % [layer_page + 1, page_count, matches.size()]
	layer_page_label.tooltip_text = "%d matching layers/labels" % matches.size()
	var first: int = layer_page * ROW_PAGE
	for index: int in range(first, mini(first + ROW_PAGE, matches.size())):
		var row: Dictionary = matches[index]
		var info: Dictionary = row["info"]
		var item: TreeItem = layers.create_item(root)
		var kind_marker: String = "▸ " if info["kind"] == DrawingLayerNode.GROUP else ("T " if info["kind"] == DrawingLayerNode.TEXT else "◉ ")
		item.set_text(0, "  ".repeat(mini(int(row["depth"]), 12)) + kind_marker + info["name"])
		item.set_tooltip_text(0, "%s · %s%s" % [info["name"], info["kind"],
			" · inherited visibility/lock applies" if int(row["depth"]) > 0 else ""])
		item.set_metadata(0, row["id"])
		item.add_button(0, layer_icons["layer_visible"] if info["visible"] else layer_icons["layer_hidden"], ROW_EYE,
			false, "Hide this row/group" if info["visible"] else "Show this row/group")
		item.add_button(0, layer_icons["layer_locked"] if info["locked"] else layer_icons["layer_unlocked"], ROW_LOCK,
			false, "Unlock this row/group" if info["locked"] else "Lock this row/group")
		if row["id"] == selected_layer_node():
			item.select(0)
			layers.scroll_to_item(item)


func _change_layer_page(direction: int) -> void:
	layer_page = maxi(0, layer_page + direction)
	_refresh_layers()


func _select_layer_node(node_id: String, record_context: bool = true) -> void:
	if active_tab < 0 or not current_document().has_node(node_id):
		return
	# Programmatic restoration may emit another Tree selection callback;
	# do not erase the actionable pending-stroke error for that harmless event.
	if node_id == selected_layer_node() and canvas.has_pending_stroke():
		return
	# Switching source layers invalidates a queued Brush stroke even without
	# changing document pixels. Restore the Tree selection if a click is refused.
	if node_id != selected_layer_node() and not _can_persist_or_close("Change Layer"):
		var item: TreeItem = layers.get_root().get_first_child() if layers.get_root() != null else null
		while item != null:
			if String(item.get_metadata(0)) == selected_layer_node():
				item.select(0)
				break
			item = item.get_next()
		return
	var before: DrawingHistoryContext = _capture_context() if record_context else null
	var kind: String = String(current_document().node_metadata(node_id).get("kind", ""))
	tabs[active_tab]["selected_node"] = node_id
	tabs[active_tab]["layer"] = node_id if kind in [DrawingLayerNode.RASTER, DrawingLayerNode.TEXT] else ""
	canvas.layer_id = current_layer()
	if record_context:
		_record_selection_context(before)
	_update_status()


func _layer_selected() -> void:
	var selected_item: TreeItem = layers.get_selected()
	if selected_item != null:
		_select_layer_node(String(selected_item.get_metadata(0)))


## Keyboard-accessible row actions operate only when the layer Tree has focus;
## dock shortcuts and application-wide undo keep their existing ownership.
func _layer_tree_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		var row: TreeItem = layers.get_item_at_position(mouse.position)
		var action: int = layers.get_button_id_at_position(mouse.position)
		if row == null or action not in [ROW_EYE, ROW_LOCK]:
			return
		# Defer tree rebuild until the GUI dispatch finishes: never free its
		# currently hit-tested TreeItem while Godot is processing that event.
		call_deferred("_apply_row_icon_action", String(row.get_metadata(0)), action)
		layers.accept_event()
		return
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo or not (key.ctrl_pressed or key.meta_pressed) or not key.alt_pressed:
		return
	match key.keycode:
		KEY_UP: _move_selected_layer(-1)
		KEY_DOWN: _move_selected_layer(1)
		KEY_LEFT: _outdent_selected_layer()
		KEY_RIGHT: _indent_selected_layer()
		KEY_L: _toggle_layer_lock()
		KEY_V: _toggle_visibility()
		KEY_R: _ask_layer_rename()
		_: return
	layers.accept_event()


func _apply_row_icon_action(node_id: String, id: int) -> void:
	if active_tab < 0 or not current_document().has_node(node_id):
		return
	if id == ROW_EYE:
		_set_row_visibility(node_id)
	elif id == ROW_LOCK:
		_set_row_lock(node_id)


## Group: append inside. Layer/text: insert immediately above that sibling.
## This policy is the same for +Layer and +Group, including root siblings.
func _insertion_target() -> Dictionary:
	var chosen: String = selected_layer_node()
	var info: Dictionary = current_document().node_metadata(chosen)
	if info.is_empty():
		return {"parent": DrawingDocument.ROOT_ID, "index": current_document().list_children().size()}
	if info["kind"] == DrawingLayerNode.GROUP:
		return {"parent": chosen, "index": current_document().list_children(chosen).size()}
	var parent_id: String = info["parent"]
	return {"parent": parent_id, "index": current_document().list_children(parent_id).find(chosen) + 1}


func _create_selected_layer(kind: String) -> void:
	if active_tab < 0 or not _can_persist_or_close("Add Layer"):
		return
	var target: Dictionary = _insertion_target()
	var before: DrawingHistoryContext = _capture_context()
	var name: String = ("Group " if kind == DrawingLayerNode.GROUP else "Layer ") + \
		str(current_document().layer_count() + 1)
	var added: DrawingResult = current_document().create_layer(kind, name,
		String(target["parent"]), "", int(target["index"]), true)
	if not added.ok:
		_show_error(added.message)
		return
	_select_layer_node(String(added.value), false)
	current_document().annotate_latest_gesture(before, _capture_context())
	_reveal_selected_layer()
	_after_edit()


func _add_group() -> void:
	_create_selected_layer(DrawingLayerNode.GROUP)


func _add_layer() -> void:
	_create_selected_layer(DrawingLayerNode.RASTER)


func _reveal_selected_layer() -> void:
	if active_tab < 0:
		return
	# A new/moved item must not disappear behind an old filter/page.
	if not layer_search.text.is_empty():
		layer_search.text = ""
	var rows: Array[Dictionary] = []
	_flatten_layer_ids(DrawingDocument.ROOT_ID, 0, rows)
	for index: int in range(rows.size()):
		if rows[index]["id"] == selected_layer_node():
			layer_page = index / ROW_PAGE
			break


func _apply_structure(result: DrawingResult, before: DrawingHistoryContext,
		reveal: bool = false) -> void:
	if not result.ok:
		_show_error(result.message)
		return
	# If a group visibility/lock edit occurs mid-gesture the previously
	# detached preview is stale; cancel it before refreshing the compositor.
	canvas.cancel_gesture()
	current_document().annotate_latest_gesture(before, _capture_context())
	if reveal:
		_reveal_selected_layer()
	_after_edit()


func _set_row_visibility(node_id: String) -> void:
	if active_tab < 0 or not _can_persist_or_close("Change Layer Visibility"):
		return
	var info: Dictionary = current_document().node_metadata(node_id)
	if info.is_empty():
		return
	var before: DrawingHistoryContext = _capture_context()
	_apply_structure(current_document().set_visibility(node_id, not bool(info["visible"]), true), before)


func _set_row_lock(node_id: String) -> void:
	if active_tab < 0 or not _can_persist_or_close("Change Layer Lock"):
		return
	var info: Dictionary = current_document().node_metadata(node_id)
	if info.is_empty():
		return
	var before: DrawingHistoryContext = _capture_context()
	_apply_structure(current_document().set_locked(node_id, not bool(info["locked"]), true), before)


func _toggle_layer_lock() -> void:
	_set_row_lock(selected_layer_node())


func _move_selected_layer(direction: int) -> void:
	if active_tab < 0 or not _can_persist_or_close("Reorder Layer"):
		return
	var node_id: String = selected_layer_node()
	var info: Dictionary = current_document().node_metadata(node_id)
	if info.is_empty():
		return
	var siblings: Array[String] = current_document().list_children(info["parent"])
	var index: int = siblings.find(node_id)
	if index + direction < 0 or index + direction >= siblings.size():
		return
	var before: DrawingHistoryContext = _capture_context()
	_apply_structure(current_document().reorder(node_id, info["parent"], index + direction, true), before, true)


func _indent_selected_layer() -> void:
	if active_tab < 0 or not _can_persist_or_close("Indent Layer"):
		return
	var node_id: String = selected_layer_node()
	var info: Dictionary = current_document().node_metadata(node_id)
	if info.is_empty():
		return
	var siblings: Array[String] = current_document().list_children(info["parent"])
	var index: int = siblings.find(node_id)
	if index <= 0 or current_document().node_metadata(siblings[index - 1]).get("kind") != DrawingLayerNode.GROUP:
		_show_error("Indent requires a preceding sibling group")
		return
	var target: String = siblings[index - 1]
	var before: DrawingHistoryContext = _capture_context()
	_apply_structure(current_document().reorder(node_id, target,
		current_document().list_children(target).size(), true), before, true)


func _outdent_selected_layer() -> void:
	if active_tab < 0 or not _can_persist_or_close("Outdent Layer"):
		return
	var node_id: String = selected_layer_node()
	var info: Dictionary = current_document().node_metadata(node_id)
	if info.is_empty() or info["parent"] == DrawingDocument.ROOT_ID:
		return
	var parent_id: String = info["parent"]
	var grandparent: String = current_document().node_metadata(parent_id)["parent"]
	var after_parent: int = current_document().list_children(grandparent).find(parent_id) + 1
	var before: DrawingHistoryContext = _capture_context()
	_apply_structure(current_document().reorder(node_id, grandparent, after_parent, true), before, true)


func _ask_layer_rename() -> void:
	if active_tab < 0:
		return
	var info: Dictionary = current_document().node_metadata(selected_layer_node())
	if info.is_empty():
		return
	layer_rename_field.text = info["name"]
	_capture_authoring_dialog_target("layer_rename")
	layer_rename_dialog.popup_centered(Vector2i(340, 110))
	layer_rename_field.select_all()
	layer_rename_field.grab_focus()


func _commit_layer_rename() -> void:
	if active_tab < 0 or not _can_persist_or_close("Rename Layer"):
		return
	var name: String = layer_rename_field.text.strip_edges()
	if name.is_empty():
		_show_error("Layer name cannot be empty")
		return
	if current_document().node_metadata(selected_layer_node()).get("name") == name:
		return
	var before: DrawingHistoryContext = _capture_context()
	_apply_structure(current_document().rename_layer(selected_layer_node(), name, true), before, true)


func _build_text_dialog() -> void:
	text_dialog = ConfirmationDialog.new()
	text_dialog.title = "Editable text (one element per layer)"
	text_dialog.size = Vector2i(470, 350)
	add_child(text_dialog)
	var form: VBoxContainer = VBoxContainer.new()
	text_dialog.add_child(form)
	var font_label: Label = Label.new()
	font_label.text = "Bundled Lato · OFL 1.1"
	form.add_child(font_label)
	text_font = OptionButton.new()
	for entry: String in ["Regular", "Bold", "Italic"]:
		text_font.add_item(entry)
	form.add_child(text_font)
	text_edit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(420, 110)
	form.add_child(text_edit)
	var controls: HBoxContainer = HBoxContainer.new()
	form.add_child(controls)
	text_size = SpinBox.new()
	text_size.min_value = 6
	text_size.max_value = 256
	text_size.value = 24
	text_size.prefix = "Size"
	controls.add_child(text_size)
	text_angle = SpinBox.new()
	text_angle.min_value = -360
	text_angle.max_value = 360
	text_angle.prefix = "Angle °"
	controls.add_child(text_angle)
	text_alignment = OptionButton.new()
	for name: String in ["left", "center", "right"]:
		text_alignment.add_item(name.capitalize())
	controls.add_child(text_alignment)
	text_color = ColorPickerButton.new()
	text_color.text = "Color"
	form.add_child(text_color)
	text_dialog.confirmed.connect(_confirm_text)
	text_dialog.canceled.connect(_cancel_authoring_dialog.bind("text"))


func _edit_text_at(point: Vector2i) -> void:
	if active_tab < 0:
		return
	var node: DrawingLayerNode = current_document().inspect_node(current_layer())
	text_target = current_layer() if node != null and node.kind == DrawingLayerNode.TEXT else ""
	text_position = point
	var existing: DrawingTextElement = node.text_element if not text_target.is_empty() else null
	text_edit.text = existing.content if existing != null else ""
	text_font.select(["lato-regular-v1", "lato-bold-v1", "lato-italic-v1"].find(existing.font_id) if existing != null else 0)
	text_size.value = existing.font_size if existing != null else 24
	text_angle.value = rad_to_deg(existing.angle) if existing != null else 0.0
	text_alignment.select(["left", "center", "right"].find(existing.alignment) if existing != null else 0)
	text_color.color = Color8(32, 40, 64) if existing == null else Color(
		float(existing.color_rgba & 255) / 255.0,
		float((existing.color_rgba >> 8) & 255) / 255.0,
		float((existing.color_rgba >> 16) & 255) / 255.0,
		float((existing.color_rgba >> 24) & 255) / 255.0)
	if existing != null:
		text_position = existing.position
	_capture_authoring_dialog_target("text")
	text_dialog.popup_centered()
	text_edit.grab_focus()


func _commit_text_dialog() -> void:
	if active_tab < 0 or not _can_persist_or_close("Commit Text"):
		return
	var document: DrawingDocument = current_document()
	var draft: DrawingTextElement = DrawingTextElement.new()
	draft.content = text_edit.text
	draft.font_id = ["lato-regular-v1", "lato-bold-v1", "lato-italic-v1"][text_font.selected]
	draft.position = text_position
	draft.font_size = int(text_size.value)
	draft.angle = deg_to_rad(text_angle.value)
	draft.alignment = ["left", "center", "right"][text_alignment.selected]
	draft.color_rgba = _pack_color(text_color.color)
	var selected_node: DrawingLayerNode = document.inspect_node(current_layer())
	var parent: String = selected_node.parent_id if selected_node != null else DrawingDocument.ROOT_ID
	var before: DrawingHistoryContext = _capture_context()
	var committed: DrawingResult = document.commit_text(text_target, draft, document.revision, parent)
	if not committed.ok:
		_show_error(committed.message)
		return
	# Text creation is also a structural row insertion. Keep the selected Tree
	# row and paint target in sync, including Object Editor tabs; otherwise a
	# subsequent Tree rebuild can silently retarget the old raster layer.
	_select_layer_node(String(committed.value), false)
	document.annotate_latest_gesture(before, _capture_context())
	_reveal_selected_layer()
	_after_edit()


func _rasterize_text() -> void:
	if active_tab < 0 or not _can_persist_or_close("Rasterize Text"):
		return
	var before: DrawingHistoryContext = _capture_context()
	var converted: DrawingResult = current_document().rasterize_text(current_layer(), current_document().revision)
	if not converted.ok:
		_show_error(converted.message)
		return
	current_document().annotate_latest_gesture(before, _capture_context())
	_after_edit()


func _remove_layer() -> void:
	if active_tab < 0 or not _can_persist_or_close("Remove Layer"):
		return
	var node_id: String = selected_layer_node()
	var info: Dictionary = current_document().node_metadata(node_id)
	if info.is_empty():
		return
	var siblings: Array[String] = current_document().list_children(info["parent"])
	var index: int = siblings.find(node_id)
	var replacement: String = ""
	if siblings.size() > 1:
		replacement = siblings[mini(index + 1, siblings.size() - 1)]
		if replacement == node_id:
			replacement = siblings[index - 1]
	else:
		replacement = info["parent"] if info["parent"] != DrawingDocument.ROOT_ID else ""
	var before: DrawingHistoryContext = _capture_context()
	var removed: DrawingResult = current_document().remove_subtree(node_id, true)
	if removed.ok:
		if not replacement.is_empty():
			_select_layer_node(replacement, false)
		else:
			tabs[active_tab]["selected_node"] = ""
			tabs[active_tab]["layer"] = ""
			canvas.layer_id = ""
	_apply_structure(removed, before, true)


func _toggle_visibility() -> void:
	_set_row_visibility(selected_layer_node())


func _change_tool(name: String) -> void:
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	active_tool = name
	canvas.tool = name
	_refresh_tool_buttons()
	_refresh_tool_options()
	_update_status()


func _refresh_tool_buttons() -> void:
	for name: String in tool_buttons:
		(tool_buttons[name] as Button).set_pressed_no_signal(name == active_tool)


## One brush settings authority for panel, compact toolbar and Canvas. Changing
## these is application state, not a document edit or a mutation to an active
## native/queued stroke (those settings are captured at pointer-down).
func _selected_brush_hardness() -> float:
	return float(brush_hardness_overrides.get(selected_brush_preset,
		BRUSH_SETTINGS.default_hardness(selected_brush_preset)))


func _selected_brush_density() -> float:
	return float(brush_density_overrides.get(selected_brush_preset,
		BRUSH_SETTINGS.default_density(selected_brush_preset)))


func _show_brush_settings() -> void:
	if brush_panel != null:
		brush_panel.display(selected_brush_preset, brush_width_value,
			brush_opacity_value, _selected_brush_hardness(), _selected_brush_density())


func _save_workspace_preferences() -> void:
	if preferences_persistence_enabled and _layout_booted:
		WORKSPACE_PREFERENCES.save_file(preferences_settings_path, record_selection_history,
			{"preset": selected_brush_preset, "width": brush_width_value,
			"opacity": brush_opacity_value, "hardness": brush_hardness_overrides,
			"density": brush_density_overrides})


func _select_brush_preset(preset: String) -> void:
	if not BRUSH_SETTINGS.PRESETS.has(preset):
		return
	selected_brush_preset = preset
	if canvas != null:
		canvas.brush_preset = preset
		canvas.brush_hardness = _selected_brush_hardness()
		canvas.brush_density = _selected_brush_density()
	if brush_preset_control != null:
		brush_preset_control.select(BRUSH_SETTINGS.PRESETS.find(preset))
	_show_brush_settings()
	_save_workspace_preferences()


func _set_brush_width(px: float) -> void:
	brush_width_value = clampf(px, 1.0, 96.0)
	if canvas != null:
		canvas.brush_width = brush_width_value
	if width_spin != null:
		width_spin.set_value_no_signal(brush_width_value)
	_show_brush_settings()
	_save_workspace_preferences()


func _set_brush_opacity(ratio: float) -> void:
	brush_opacity_value = clampf(ratio, 0.0, 1.0)
	if canvas != null:
		canvas.brush_opacity = brush_opacity_value
	_show_brush_settings()
	_save_workspace_preferences()


func _set_brush_hardness(ratio: float) -> void:
	brush_hardness_overrides[selected_brush_preset] = clampf(ratio, 0.0, 1.0)
	if canvas != null:
		canvas.brush_hardness = _selected_brush_hardness()
	_show_brush_settings()
	_save_workspace_preferences()


func _set_brush_density(dabs_per_radius: float) -> void:
	if not is_finite(dabs_per_radius) or dabs_per_radius < BRUSH_SETTINGS.DENSITY_MIN \
			or dabs_per_radius > BRUSH_SETTINGS.DENSITY_MAX:
		return
	brush_density_overrides[selected_brush_preset] = dabs_per_radius
	if canvas != null:
		canvas.brush_density = _selected_brush_density()
	_show_brush_settings()
	_save_workspace_preferences()


func _reset_selected_brush() -> void:
	brush_hardness_overrides.erase(selected_brush_preset)
	brush_density_overrides.erase(selected_brush_preset)
	_set_brush_width(3.0)
	_set_brush_opacity(1.0)
	if canvas != null:
		canvas.brush_hardness = _selected_brush_hardness()
		canvas.brush_density = _selected_brush_density()
	_show_brush_settings()
	_save_workspace_preferences()


func _refresh_tool_options() -> void:
	if top_bar == null:
		return
	var controls: Array[Control] = []
	if active_tool in ["Brush", "Eraser"]:
		controls.append(brush_preset_control)
		controls.append(width_spin)
	if active_tool in ["Brush", "Eraser", "Select", "Move", "Text"]:
		controls.append(snap_toggle)
	if active_tool == "Select":
		controls.append(selection_mode_control)
	top_bar.set_tool_controls(active_tool, controls)


func _set_selection_mode(mode: String) -> void:
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	canvas.selection_mode = mode
	for index: int in range(selection_mode_control.item_count):
		if selection_mode_control.get_item_text(index) == mode:
			selection_mode_control.select(index)
			break
	_update_status()


func _drop_floating_move() -> void:
	if canvas.has_floating_move():
		canvas.confirm_floating_move()


func _cancel_floating_move() -> void:
	if canvas.has_floating_move():
		canvas.cancel_gesture()
		_before_gesture = null
		_update_status()


func _deselect() -> void:
	if active_tab >= 0:
		# Clear Selection changes the mask captured by an in-flight stroke.
		# Refuse instead of letting Canvas cancel the unpublished transaction.
		if canvas.selection_mask.enabled and not _can_persist_or_close("Clear Selection"):
			return
		if canvas.has_floating_move() and not canvas.confirm_floating_move():
			return
		canvas.clear_selection()


func _capture_selection_clipboard() -> DrawingResult:
	if active_tab < 0 or not canvas.selected.has_area():
		return DrawingResult.failure("SELECTION", "Select an area before copying pixels")
	var metadata: Dictionary = current_document().node_metadata(current_layer())
	if metadata.get("kind", "") != DrawingLayerNode.RASTER:
		return DrawingResult.failure("LAYER", "Clipboard copies the active raster layer only")
	return DrawingClipboard.capture(current_document(), current_layer(), canvas.selected,
		canvas.selection_mask)


func _copy_selection() -> void:
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	var capture: DrawingResult = _capture_selection_clipboard()
	if not capture.ok:
		_show_error(capture.message)
		return
	drawing_clipboard = capture.value as DrawingClipboard
	_paste_serial = 0
	_update_status()


## All content shortcuts use the same one-gesture history/context path.
func _commit_clipboard_edit(edit: DrawingEditSession,
		next_selection: DrawingSelection = null) -> void:
	if edit.change_count() == 0:
		edit.cancel()
		_before_gesture = null
		return
	var result: DrawingResult = edit.commit()
	if not result.ok:
		_before_gesture = null
		_show_error(result.message)
		return
	if next_selection != null:
		canvas.set_selection_mask(next_selection, false)
	_canvas_changed(result)


func _delete_selection() -> void:
	# T-253 opt-in whole-command trace; the graphical witness separately
	# measures input dispatch through the first updated OS framebuffer.
	var trace_start_us: int = Time.get_ticks_usec() if OS.has_environment(
		"DRAWING_T253_PROFILE") else 0
	if not _can_persist_or_close("Delete Pixels"):
		return
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	if active_tab < 0 or not canvas.selected.has_area():
		return
	var started: DrawingResult = current_document().begin_edit(current_layer(), current_document().revision)
	if not started.ok:
		_show_error(started.message)
		return
	_before_gesture = _capture_context()
	var trace_begin_us: int = Time.get_ticks_usec() if trace_start_us > 0 else 0
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var staged: DrawingResult = edit.clear_rect(canvas.selected, canvas.selection_mask)
	if not staged.ok:
		edit.cancel()
		_before_gesture = null
		_show_error(staged.message)
		return
	var trace_stage_us: int = Time.get_ticks_usec() if trace_start_us > 0 else 0
	_commit_clipboard_edit(edit)
	if trace_start_us > 0:
		var finished_us: int = Time.get_ticks_usec()
		print("T253_DELETE_PHASE: preflight_us=%d stage_us=%d commit_ui_us=%d total_us=%d tiles=%d" % [
			trace_begin_us - trace_start_us, trace_stage_us - trace_begin_us,
			finished_us - trace_stage_us, finished_us - trace_start_us,
			current_document().tile_keys(current_layer()).size()])


func _cut_selection() -> void:
	if not _can_persist_or_close("Cut Pixels"):
		return
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	var captured: DrawingResult = _capture_selection_clipboard()
	if not captured.ok:
		_show_error(captured.message)
		return
	var started: DrawingResult = current_document().begin_edit(current_layer(), current_document().revision)
	if not started.ok:
		_show_error(started.message)
		return
	_before_gesture = _capture_context()
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var staged: DrawingResult = edit.clear_rect(canvas.selected, canvas.selection_mask)
	if not staged.ok:
		edit.cancel()
		_before_gesture = null
		_show_error(staged.message)
		return
	drawing_clipboard = captured.value as DrawingClipboard
	_paste_serial = 0
	_commit_clipboard_edit(edit)


func _paste_selection() -> void:
	if not _can_persist_or_close("Paste Pixels"):
		return
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	if drawing_clipboard == null or active_tab < 0:
		_show_error("Copy pixels from a selection before pasting")
		return
	var started: DrawingResult = current_document().begin_edit(current_layer(), current_document().revision)
	if not started.ok:
		_show_error(started.message)
		return
	_before_gesture = _capture_context()
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var offset: Vector2i = Vector2i(8, 8) * (_paste_serial + 1)
	var target: Vector2i = drawing_clipboard.source_position + offset
	var staged: DrawingResult = drawing_clipboard.paste(edit, target)
	if not staged.ok:
		edit.cancel()
		_before_gesture = null
		_show_error(staged.message)
		return
	var pasted_mask: DrawingSelection = drawing_clipboard.source_selection.translated(offset) \
		if drawing_clipboard.source_selection != null else DrawingSelection.new(
		Rect2i(target, Vector2i(drawing_clipboard.width, drawing_clipboard.height)), true)
	_paste_serial += 1
	_commit_clipboard_edit(edit, pasted_mask)


func _show_preferences() -> void:
	preferences_dialog.popup_centered(Vector2i(420, 110))


func _load_preferences() -> void:
	if not preferences_persistence_enabled:
		return
	var saved: Dictionary = WORKSPACE_PREFERENCES.read_file(preferences_settings_path)
	if not saved.is_empty():
		record_selection_history = saved["record_selection_history"]
		var brush: Dictionary = saved.get("brush", {})
		if not brush.is_empty():
			selected_brush_preset = brush["preset"]
			brush_width_value = float(brush["width"])
			brush_opacity_value = float(brush["opacity"])
			brush_hardness_overrides = brush["hardness"].duplicate(true)
			brush_density_overrides = brush.get("density", {}).duplicate(true)


func _toggle_selection_history() -> void:
	_selection_history_preference_changed(not record_selection_history)
	if selection_history_toggle != null:
		selection_history_toggle.set_pressed_no_signal(record_selection_history)


func _toggle_document_tabs() -> void:
	show_document_tabs = not show_document_tabs
	tabs_line.visible = show_document_tabs
	top_bar.set_menu_checked("Window", 2, show_document_tabs)


func _cycle_tab(direction: int) -> void:
	if tabs.is_empty():
		return
	_activate(wrapi(active_tab + direction, 0, tabs.size()))


func _toggle_dock() -> void:
	var minimized: bool = bool(dock_layout.container_info("right")["minimized"])
	if not minimized:
		# Temporary narrow-window clamps must not replace the last width
		# explicitly chosen by splitter drag or Window > Reset dock width.
		_expanded_scroll = inspector.scroll_vertical
	if dock_layout.set_minimized("right", not minimized):
		_render_dock()
		# Only the rail width changes on minimize. The flyout is an overlay
		# under canvas and must not participate in HSplitContainer sizing.
		dock_split.split_offset = maxi(0, int(dock_split.size.x) - (48 if not minimized else _expanded_dock_width))
		if minimized:
			call_deferred("_restore_expanded_scroll")
		_layout_dock_toggle()
		_schedule_layout_save()


func _on_dock_split_dragged(_offset: int) -> void:
	if not _layout_booted or dock_layout.container_info("right")["minimized"]:
		return
	# Drag is observed before some Godot layouts finish sizing. The deferred
	# save reads the realized inspector width after the splitter has settled.
	call_deferred("_capture_dragged_dock_width")


func _capture_dragged_dock_width() -> void:
	if dock_split == null or dock_layout.container_info("right")["minimized"]:
		return
	_expanded_dock_width = clampi(roundi(inspector.size.x), 160, 800)
	_schedule_layout_save()


func _reset_dock_width() -> void:
	if bool(dock_layout.container_info("right")["minimized"]):
		_toggle_dock()
	_expanded_dock_width = 270
	dock_split.split_offset = maxi(0, int(dock_split.size.x) - 270)
	_schedule_layout_save()


func _show_about_workspace() -> void:
	(get_node("WorkspaceAbout") as AcceptDialog).popup_centered()


func _capture_context() -> DrawingHistoryContext:
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	if current_document() == null:
		return context
	context.document_id = current_document().id
	if not current_layer().is_empty():
		context.selected_layer_ids.append(current_layer())
	context.selected_tree_id = selected_layer_node()
	context.editor_mode = active_tool
	context.selected_rect = canvas.selected
	context.selection_mask = canvas.selection_mask.detached_copy()
	return context


func _selection_history_preference_changed(enabled: bool) -> void:
	record_selection_history = enabled
	for tab: Dictionary in tabs:
		(tab["document"] as DrawingDocument).record_selection_history = enabled
	if selection_history_toggle != null and selection_history_toggle.button_pressed != enabled:
		selection_history_toggle.set_pressed_no_signal(enabled)
	_save_workspace_preferences()


func _gesture_started() -> void:
	_before_gesture = _capture_context()


func _selection_changed(_area: Rect2i) -> void:
	_record_selection_context(_last_selection_context)
	_update_status()


func _record_selection_context(before: DrawingHistoryContext) -> void:
	if active_tab < 0 or _restoring_context:
		return
	var after: DrawingHistoryContext = _capture_context()
	if before != null:
		current_document().record_selection_change(before, after)
	_last_selection_context = after


func _restore_context(context: DrawingHistoryContext) -> void:
	if context == null or context.document_id != current_document().id:
		return
	_restoring_context = true
	var row_id: String = context.selected_tree_id
	if row_id.is_empty() and not context.selected_layer_ids.is_empty():
		row_id = context.selected_layer_ids[0]
	if not current_document().has_node(row_id):
		row_id = _first_editable(current_document(), DrawingDocument.ROOT_ID)
	if not row_id.is_empty():
		_select_layer_node(row_id, false)
	else:
		tabs[active_tab]["selected_node"] = ""
		tabs[active_tab]["layer"] = ""
		canvas.layer_id = ""
	canvas.set_selection_mask(context.selection_mask if context.selection_mask != null else
		DrawingSelection.new(context.selected_rect, context.selected_rect.has_area()), false)
	if context.editor_mode in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]:
		_change_tool(context.editor_mode)
	_last_selection_context = _capture_context()
	_reveal_selected_layer()
	_restoring_context = false


func _canvas_changed(_result: DrawingResult) -> void:
	if _before_gesture != null:
		current_document().annotate_latest_gesture(_before_gesture, _capture_context())
	_before_gesture = null
	_last_selection_context = _capture_context()
	_after_edit()


func _after_edit() -> void:
	_refresh_layers()
	_update_status()
	canvas.queue_redraw()


func _update_status() -> void:
	if active_tab < 0:
		return
	var document: DrawingDocument = current_document()
	var session: DrawingObjectEditorSession = current_object()
	var dirty: bool = session.is_dirty() if session != null else (document.is_dirty() or
		bool(tabs[active_tab].get("frame_dirty", false)))
	tab_bar.set_tab_title(active_tab, String(tabs[active_tab]["title"]) + (" *" if dirty else ""))
	var origin: String = " | instance %s @ %s" % [session.origin_instance_id,
		session.origin_map_id] if session != null and not session.origin_instance_id.is_empty() else ""
	var source: String = "Object %s (%s) rev %d%s | " % [session.name,
		session.source_id if not session.source_id.is_empty() else "new", session.source_revision,
		origin] if session != null else ""
	var cursor: Vector2i = canvas.position_to_pixel(
		canvas.last_pointer_position if canvas.pointer_known else canvas.size * 0.5)
	var canvas_pixels: Vector2i = Vector2i(ceili(canvas.size.x / canvas.zoom),
		ceili(canvas.size.y / canvas.zoom))
	# Retain document identity and dirty indication while the tab strip is hidden.
	var tab_identity: String = String(tabs[active_tab]["title"]) + (" *" if dirty else "")
	var guide: String = " | image %d×%d @ %d,%d" % [canvas.image_bounds.size.x,
		canvas.image_bounds.size.y, canvas.image_bounds.position.x,
		canvas.image_bounds.position.y] if canvas.image_bounds.has_area() else ""
	var grid_info: String = " | grid %dpx @ %d,%d (%s, snap %s)" % [canvas.grid_spacing,
		canvas.grid_origin.x, canvas.grid_origin.y,
		"shown" if canvas.show_grid else "hidden", "on" if canvas.snap_to_grid else "off"]
	status.text = "%s | %s%s | cursor %d,%d | view %d×%d px | zoom %.0f%%%s%s | history %d/%d | %s" % [
		tab_identity, source, active_tool, cursor.x, cursor.y, canvas_pixels.x, canvas_pixels.y,
		canvas.zoom * 100.0, guide, grid_info, document.history_position(),
		document.history_length(), "Unsaved changes" if dirty else "Saved"]
	if canvas.has_floating_move():
		status.text += " | Floating Move: Enter drop / Esc cancel"
	status.tooltip_text = status.text
	_refresh_history()


func _set_snap_enabled(enabled: bool) -> void:
	canvas.snap_to_grid = enabled
	if active_tab >= 0:
		tabs[active_tab]["snap"] = enabled
	canvas.queue_redraw()
	_update_status()


func _toggle_grid() -> void:
	if active_tab < 0:
		return
	canvas.show_grid = not canvas.show_grid
	tabs[active_tab]["show_grid"] = canvas.show_grid
	top_bar.set_menu_checked("View", 3, canvas.show_grid)
	canvas.queue_redraw()
	_update_status()


func _toggle_pixel_grid() -> void:
	canvas.show_pixel_grid = not canvas.show_pixel_grid
	top_bar.set_menu_checked("View", 5, canvas.show_pixel_grid)
	canvas.queue_redraw()


func _ask_grid_settings() -> void:
	if active_tab < 0:
		return
	for index: int in range(3):
		grid_fields[index].value = [canvas.grid_spacing, canvas.grid_origin.x,
			canvas.grid_origin.y][index]
	_capture_authoring_dialog_target("grid")
	grid_dialog.popup_centered()


func _apply_grid_settings() -> void:
	if active_tab < 0:
		return
	canvas.grid_spacing = int(grid_fields[0].value)
	canvas.grid_origin = Vector2i(int(grid_fields[1].value), int(grid_fields[2].value))
	tabs[active_tab]["grid_spacing"] = canvas.grid_spacing
	tabs[active_tab]["grid_origin"] = canvas.grid_origin
	snap_toggle.text = "Snap (%d px)" % canvas.grid_spacing
	canvas.queue_redraw()
	_update_status()


func _ask_image_frame() -> void:
	if active_tab < 0 or current_object() != null:
		_show_error("Image frame is for standalone Drawing tabs; use Object frame for Objects")
		return
	var bounds: Rect2i = canvas.image_bounds
	var values: Array[int] = [bounds.position.x, bounds.position.y,
		bounds.size.x, bounds.size.y]
	for index: int in range(image_frame_fields.size()):
		image_frame_fields[index].value = values[index]
	_capture_authoring_dialog_target("image_frame")
	image_frame_dialog.popup_centered()


func _apply_image_frame() -> void:
	if active_tab < 0 or current_object() != null:
		return
	var frame: Rect2i = Rect2i(int(image_frame_fields[0].value),
		int(image_frame_fields[1].value), int(image_frame_fields[2].value),
		int(image_frame_fields[3].value))
	var checked: DrawingResult = IMAGE_FRAME.decode(IMAGE_FRAME.encode(frame))
	if not checked.ok:
		_show_error(checked.message)
		return
	if frame == canvas.image_bounds:
		return
	# Changing clip/authoring bounds while a stroke drains would cancel
	# already received paint and its queued successor through Canvas's setter.
	if not _can_persist_or_close("Change Image Frame"):
		return
	tabs[active_tab]["frame"] = frame
	tabs[active_tab]["frame_dirty"] = frame != tabs[active_tab].get("saved_frame", frame)
	canvas.image_bounds = frame
	canvas.queue_redraw()
	_update_status()


func _maybe_fit_image_frame() -> void:
	if active_tab >= 0 and bool(tabs[active_tab].get("fit_pending", false)):
		_fit_image_frame()


func _fit_image_frame() -> void:
	if not canvas.image_bounds.has_area() or canvas.size.x < 40 or canvas.size.y < 40:
		return
	var bounds: Rect2i = canvas.image_bounds
	canvas.camera = Vector2(bounds.position) + Vector2(bounds.size) * 0.5
	canvas.zoom = clampf(minf(canvas.size.x / float(bounds.size.x),
		canvas.size.y / float(bounds.size.y)) * 0.85, 0.25, 24.0)
	tabs[active_tab]["fit_pending"] = false
	canvas.queue_redraw()


func _undo() -> void:
	if active_tab < 0:
		return
	# History changes the document revision and would cancel unpublished Brush input.
	if not _can_persist_or_close("Undo"):
		return
	if canvas.has_floating_move():
		_cancel_floating_move()
		return
	var result: DrawingResult = current_document().undo()
	if result.ok:
		_restore_context(result.value as DrawingHistoryContext)
		_after_edit()
	else:
		_show_error(result.message)


func _redo() -> void:
	if active_tab < 0:
		return
	if not _can_persist_or_close("Redo"):
		return
	if canvas.has_floating_move():
		_cancel_floating_move()
		return
	var result: DrawingResult = current_document().redo()
	if result.ok:
		_restore_context(result.value as DrawingHistoryContext)
		_after_edit()
	else:
		_show_error(result.message)


func _zoom(factor: float) -> void:
	canvas.zoom = clampf(canvas.zoom * factor, 0.25, 24.0)
	canvas.queue_redraw()
	_update_status()


func _reset_view() -> void:
	if canvas.image_bounds.has_area():
		_fit_image_frame()
	else:
		canvas.zoom = 4.0
		canvas.camera = Vector2.ZERO
	canvas.queue_redraw()
	_update_status()


func _open_raster_file(path: String) -> void:
	if not _can_persist_or_close("Open"):
		return
	var opened: DrawingResult = DrawingRasterImport.load_file_image(path)
	if not opened.ok:
		_show_error(opened.message)
		return
	var image: Image = opened.value as Image
	var document: DrawingDocument = DrawingDocument.new()
	document.record_selection_history = record_selection_history
	var created: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Imported image")
	if not created.ok:
		_show_error(created.message)
		return
	var raster: String = String(created.value)
	var imported: DrawingResult = DrawingRasterImport.import_image(document, raster,
		image, 0, 0, document.revision)
	if not imported.ok and imported.code != "NO_CHANGE":
		_show_error("Image import failed: " + imported.message + ". No Drawing was created.")
		return
	var image_bounds: Rect2i = Rect2i(0, 0, image.get_width(), image.get_height())
	tabs.append({"document": document, "path": "", "title": "Imported: " + path.get_file(),
		"layer": raster, "selected_node": raster, "saved": -1, "frame": image_bounds,
		"saved_frame": image_bounds, "frame_dirty": false, "fit_pending": true})
	tab_bar.add_tab("Imported: " + path.get_file())
	_activate(tabs.size() - 1)


func _ask_open() -> void:
	if _can_persist_or_close("Open"):
		open_dialog.popup_centered()


## A delayed editing confirmation must remain tied to the exact document
## and Object session that opened it. Layer/Text dialogs additionally freeze
## their selected source node and revision. Consume authority on first signal
## (including rejected signals) so Cancel and duplicate confirms fail closed.
func _capture_authoring_dialog_target(kind: String) -> void:
	var target: Dictionary = _capture_save_target()
	if not target.is_empty():
		target["layer"] = current_layer()
		target["selected_node"] = selected_layer_node()
		target["revision"] = current_document().revision
	_authoring_dialog_targets[kind] = target


func _cancel_authoring_dialog(kind: String) -> void:
	_authoring_dialog_targets.erase(kind)


func _authoring_dialog_is_current(kind: String, require_layer: bool = false) -> bool:
	var target: Dictionary = _authoring_dialog_targets.get(kind, {})
	_authoring_dialog_targets.erase(kind)
	var valid: bool = _save_target_is_current(target)
	if valid and require_layer:
		valid = (current_layer() == String(target["layer"])
			and selected_layer_node() == String(target["selected_node"])
			and current_document().revision == int(target["revision"]))
	if not valid:
		_show_error("Authoring dialog belongs to another document, layer or tab; reopen it")
	return valid


func _confirm_layer_rename() -> void:
	if _authoring_dialog_is_current("layer_rename", true):
		_commit_layer_rename()


func _confirm_text() -> void:
	if _authoring_dialog_is_current("text", true):
		_commit_text_dialog()


func _confirm_object_rename() -> void:
	if _authoring_dialog_is_current("object_rename"):
		_rename_object()


func _confirm_object_frame() -> void:
	if _authoring_dialog_is_current("object_frame"):
		_change_object_frame()


func _confirm_grid() -> void:
	if _authoring_dialog_is_current("grid"):
		_apply_grid_settings()


func _confirm_image_frame() -> void:
	if _authoring_dialog_is_current("image_frame"):
		_apply_image_frame()


## A dialog may outlive its original tab or even its original index.
## Identity is checked after the signal, before any path or metadata mutation.
func _capture_save_target() -> Dictionary:
	if active_tab < 0 or active_tab >= tabs.size():
		return {}
	return {"tab": active_tab, "document": current_document(), "object": current_object()}


func _save_target_is_current(target: Dictionary) -> bool:
	return (not target.is_empty() and active_tab >= 0 and active_tab < tabs.size()
		and active_tab == int(target["tab"])
		and current_document() == target["document"]
		and current_object() == target["object"])


func _save_dialog_cancelled() -> void:
	_save_dialog_target.clear()
	_local_save_as = false
	_cancel_pending_close()


func _save_dialog_selected(path: String) -> void:
	var target: Dictionary = _save_dialog_target
	_save_dialog_target = {}
	if not _save_target_is_current(target):
		_local_save_as = false
		_cancel_pending_close()
		_show_error("Save As belongs to another document or tab; reopen the dialog")
		return
	_save_file(path)
	_local_save_as = false


func _variant_dialog_cancelled() -> void:
	_variant_dialog_target.clear()
	_cancel_pending_close()


func _variant_dialog_confirmed() -> void:
	var target: Dictionary = _variant_dialog_target
	_variant_dialog_target = {}
	if not _save_target_is_current(target):
		_cancel_pending_close()
		_show_error("Object Save As belongs to another document or tab; reopen the dialog")
		return
	_save_as_named_object()


func _show_save_dialog() -> void:
	_save_dialog_target = _capture_save_target()
	# Godot headless reports a 0x0 screen: centering the native FileDialog
	# spawns its window at a negative position and emits a runtime ERROR.
	# Preserve the real dialog and Save/Close routing in headless CI without
	# changing normal desktop placement.
	if DisplayServer.get_name() == "headless":
		save_dialog.show()
	else:
		save_dialog.popup_centered()


func _ask_save() -> void:
	if active_tab < 0:
		return
	if not _can_persist_or_close("Save As"):
		return
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	var session: DrawingObjectEditorSession = current_object()
	if session != null and not session.save_as_publisher.is_valid():
		_show_error("No Object Asset publisher is connected")
		return
	if session != null and not bool(tabs[active_tab].get("local_object", false)):
		variant_name.text = session.name + " copy"
		_variant_dialog_target = _capture_save_target()
		variant_dialog.popup_centered()
	else:
		_local_save_as = session != null
		_show_save_dialog()


func _save() -> void:
	if active_tab < 0:
		return
	if not _can_persist_or_close("Save"):
		return
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	var session: DrawingObjectEditorSession = current_object()
	if session != null:
		if not session.save_publisher.is_valid():
			_show_error("No Object Asset publisher is connected")
			return
		if session.source_id.is_empty() and tabs[active_tab]["path"].is_empty():
			_local_save_as = false
			_show_save_dialog()
		else:
			_publish_object(false)
		return
	var path: String = tabs[active_tab]["path"]
	if path.is_empty():
		_ask_save()
	else:
		_save_file(path)


func _publish_object(as_variant: bool) -> bool:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return false
	if not _can_persist_or_close("Save Object"):
		return false
	var result: DrawingResult = session.save_as() if as_variant else session.save()
	if not result.ok:
		if active_tab >= 0:
			tabs[active_tab].erase("_target_path")
		_cancel_pending_close()
		_show_error(result.message)
		return false
	_sync_object_tab()
	_close_if_saved()
	return true


func _save_file(path: String) -> void:
	if active_tab < 0:
		return
	if not _can_persist_or_close("Save"):
		return
	if canvas.has_floating_move() and not canvas.confirm_floating_move():
		return
	if not path.to_lower().ends_with(".drawing"):
		path += ".drawing"
	if current_object() != null:
		tabs[active_tab]["_target_path"] = path
		_publish_object(_local_save_as)
		_local_save_as = false
		return
	var result: DrawingResult = DrawingFileIO.save(current_document(), path,
		{"image_frame": IMAGE_FRAME.encode(canvas.image_bounds)})
	if result.ok:
		tabs[active_tab]["saved_frame"] = canvas.image_bounds
		tabs[active_tab]["frame_dirty"] = false
		tabs[active_tab]["path"] = path
		tabs[active_tab]["title"] = path.get_file()
		_update_status()
		_close_if_saved()
	else:
		_cancel_pending_close()
		_show_error(result.message)


func _open_file(path: String) -> void:
	if not _can_persist_or_close("Open"):
		return
	match path.get_extension().to_lower():
		"png", "webp", "jpg", "jpeg":
			_open_raster_file(path)
			return
		"drawing":
			pass
		_:
			_show_error("Unsupported file type. Open supports .drawing, PNG, WebP and JPEG.")
			return
	var opened: DrawingResult = DrawingFileIO.open_with_frame(path)
	if not opened.ok:
		_show_error(opened.message)
		return
	var content: Dictionary = opened.value
	var document: DrawingDocument = content["document"] as DrawingDocument
	document.record_selection_history = record_selection_history
	var raster: String = _first_editable(document, DrawingDocument.ROOT_ID)
	if raster.is_empty() and document.layer_count() == 0:
		var added: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1")
		raster = added.value
	tabs.append({"document": document, "path": path, "title": path.get_file(), "layer": raster,
		"selected_node": raster, "frame": content["image_frame"], "saved_frame": content["image_frame"],
		"frame_dirty": false, "fit_pending": true})
	tab_bar.add_tab(path.get_file())
	_activate(tabs.size() - 1)


func _first_editable(document: DrawingDocument, parent: String) -> String:
	for node_id: String in document.list_children(parent):
		var info: Dictionary = document.node_metadata(node_id)
		if info["kind"] in [DrawingLayerNode.RASTER, DrawingLayerNode.TEXT]:
			return node_id
		if info["kind"] == DrawingLayerNode.GROUP:
			var nested: String = _first_editable(document, node_id)
			if not nested.is_empty():
				return nested
	return ""


func _show_error(message: String) -> void:
	status.text = "Error: " + message
	push_warning("Drawing: " + message)


## Keyboard width adjustments share exactly the same SpinBox range and history-free state.
func _adjust_brush_size(delta: int) -> void:
	if active_tool not in ["Brush", "Eraser"]:
		return
	width_spin.value = clampf(width_spin.value + float(delta), width_spin.min_value,
		width_spin.max_value)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if not key.ctrl_pressed and not key.meta_pressed:
		if key.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT] and not key.alt_pressed:
			var focused: Control = get_viewport().gui_get_focus_owner()
			if not (focused is LineEdit or focused is TextEdit or focused is SpinBox):
				_adjust_brush_size(-1 if key.keycode == KEY_BRACKETLEFT else 1)
				get_viewport().set_input_as_handled()
				return
		if key.keycode == KEY_DELETE and canvas.has_focus():
			_delete_selection()
			get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_N: new_drawing()
		KEY_O: _ask_open()
		KEY_S:
			if key.shift_pressed:
				_ask_save()
			else:
				_save()
		KEY_Z:
			if key.shift_pressed:
				_redo()
			else:
				_undo()
		KEY_Y: _redo()
		KEY_C: _copy_selection()
		KEY_X: _cut_selection()
		KEY_V: _paste_selection()
		KEY_D: _deselect()
		KEY_TAB: _cycle_tab(-1 if key.shift_pressed else 1)
		KEY_W: _request_close_current()
		_: return
	get_viewport().set_input_as_handled()


## T-083: restore once the default T-063 groups and built-in panel Controls exist.
## No document, Object source, or layer data is included in this preference.
func _restore_workspace_layout() -> void:
	if layout_persistence_enabled:
		var stored: Dictionary = DrawingDockPersistence.read_file(layout_settings_path)
		if not stored.is_empty():
			var restored: Dictionary = DrawingDockPersistence.recover(stored, dock_layout, layout_panel_aliases)
			if not restored.is_empty() and dock_layout.restore(restored["layout"]):
				layout_recovery_status = "repaired" if restored["recovered"] else "loaded"
				_saved_layout_width = restored["dock_width"]
				_saved_layout_scroll = restored["dock_scroll"]
				_expanded_dock_width = _saved_layout_width
				_expanded_scroll = _saved_layout_scroll
				for metadata: Dictionary in restored["hosts"]:
					var host_id: String = metadata["id"]
					var host: DrawingFloatingHost = FLOATING_HOST_SCRIPT.new() as DrawingFloatingHost
					host.setup(host_id, dock_layout, dock_drag, dock_views, dock_stash, self)
					add_child(host)
					host.layout_changed.connect(_render_dock)
					host.hide_requested.connect(hide_floating_host)
					host.state_changed.connect(_schedule_layout_save)
					floating_hosts[host_id] = host
					host.set_host_rect(DrawingDockPersistence.restore_rect(metadata, size))
					if not metadata["visible"]:
						host.hide()
					if host_id.begins_with("float-") and host_id.substr(6).is_valid_int():
						_floating_serial = maxi(_floating_serial, int(host_id.substr(6)))
				_render_dock()
		elif FileAccess.file_exists(layout_settings_path):
			layout_recovery_status = "invalid"
	_layout_booted = true
	call_deferred("_apply_saved_dock_geometry")


func _apply_saved_dock_geometry() -> void:
	if dock_split == null or not is_inside_tree():
		return
	var minimized: bool = dock_layout.container_info("right")["minimized"]
	var usable: int = maxi(160, roundi(dock_split.size.x) - 180)
	var width: int = 48 if minimized else mini(_expanded_dock_width, usable)
	dock_split.split_offset = maxi(0, int(dock_split.size.x) - width)
	_layout_dock_toggle()
	if not minimized:
		inspector.scroll_vertical = _expanded_scroll


func _schedule_layout_save() -> void:
	if not _layout_booted or not layout_persistence_enabled or _layout_save_pending or dock_drag.is_dragging():
		return
	_layout_save_pending = true
	call_deferred("_flush_workspace_layout")


func _flush_workspace_layout() -> void:
	_layout_save_pending = false
	if not _layout_booted or not layout_persistence_enabled or dock_drag.is_dragging():
		return
	_save_workspace_layout()


func _save_workspace_layout() -> bool:
	if not layout_persistence_enabled or dock_layout == null:
		return false
	if not dock_layout.container_info("right")["minimized"]:
		# Capture geometry only on actual user drag (or explicit reset), not
		# during a viewport resize or an unrelated layout save.
		_expanded_scroll = inspector.scroll_vertical
	var state: Dictionary = DrawingDockPersistence.capture(dock_layout, floating_hosts,
		_expanded_dock_width, _expanded_scroll, size)
	return DrawingDockPersistence.save_file(layout_settings_path, state)


func reset_workspace_layout() -> void:
	# Return views to a safe parent before destroying the existing hosts.
	_cancel_cross_drop()
	for panel_view: Control in dock_views.values():
		if panel_view.get_parent() != dock_stash:
			panel_view.reparent(dock_stash)
	for host: DrawingFloatingHost in floating_hosts.values():
		host.queue_free()
	floating_hosts.clear()
	_floating_serial = 0
	dock_layout = DOCK_LAYOUT_SCRIPT.new() as DrawingDockLayout
	dock_layout.create_container("right")
	for panel_id: String in dock_views:
		dock_layout.register_panel(panel_id)
		dock_layout.attach_panel(panel_id, "right", panel_id)
	dock_drag = DOCK_DRAG_SCRIPT.new(dock_layout) as DrawingDockDrag
	_expanded_dock_width = 270
	_expanded_scroll = 0
	_render_dock()
	call_deferred("_apply_saved_dock_geometry")
	_schedule_layout_save()


## Dynamic peers, including a future Asset Browser, are registered by stable ID;
## no plugin panel is hardcoded into the persisted schema or initial dock.
func register_workspace_panel(panel_id: String, view: Control) -> bool:
	if view == null or panel_id.is_empty() or dock_views.has(panel_id):
		return false
	if not dock_layout.register_panel(panel_id):
		return false
	var group_id: String = panel_id
	var counter: int = 1
	while not dock_layout.group_info(group_id).is_empty():
		group_id = "%s-extra-%d" % [panel_id, counter]
		counter += 1
	if not dock_layout.attach_panel(panel_id, "right", group_id):
		return false
	dock_views[panel_id] = view
	dock_stash.add_child(view)
	_render_dock()
	return true


func _exit_tree() -> void:
	if _window_quit_guard_enabled:
		get_tree().auto_accept_quit = _old_auto_accept_quit
		_window_quit_guard_enabled = false
	if _layout_booted and layout_persistence_enabled:
		_save_workspace_layout()
