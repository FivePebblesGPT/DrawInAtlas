class_name DrawingFloatingHost
extends PanelContainer
## In-app tabbed group host. State/ownership lives exclusively in DrawingDockLayout.
## Geometry is transient until T-083 adds workspace persistence.

signal layout_changed
signal hide_requested(host_id: String)
signal state_changed

const MIN_FRAME: Vector2 = Vector2(236, 180)
const EDGE_MARGIN: float = 5.0

var host_id: String = ""
var layout: DrawingDockLayout
var drag: DrawingDockDrag
var views: Dictionary
var stash: Control
var coordinator: Control
var group_frames: Dictionary = {}
var tab_buttons: Dictionary = {}
var group_handles: Dictionary = {}
var tab_strips: Dictionary = {}
var _body: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _hint: ColorRect
var _gesture: String = ""
var _pointer_start: Vector2
var _frame_start: Rect2
var _candidate_kind: String = ""
var _candidate_id: String = ""
var _candidate_start: Vector2
var _suppress_release: bool = false


func setup(id: String, state: DrawingDockLayout, planner: DrawingDockDrag,
		panel_views: Dictionary, storage: Control, workspace: Control = null) -> void:
	host_id = id
	layout = state
	drag = planner
	views = panel_views
	stash = storage
	coordinator = workspace
	name = "FloatingHost_" + id
	tooltip_text = "Floating Drawing panels: " + id


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	var root_column: VBoxContainer = VBoxContainer.new()
	root_column.name = "FloatingColumn"
	add_child(root_column)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.name = "FloatingTitleBar"
	root_column.add_child(title_row)
	var grip: Button = Button.new()
	grip.name = "MoveHandle"
	grip.text = "⠿"
	grip.tooltip_text = "Move floating panel container; drag with left mouse button"
	grip.custom_minimum_size = Vector2(42, 42)
	grip.focus_mode = Control.FOCUS_ALL
	grip.gui_input.connect(_handle_press.bind("move"))
	title_row.add_child(grip)
	_title = Label.new()
	_title.name = "FloatingTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	title_row.add_child(_title)
	var hide_button: Button = Button.new()
	hide_button.name = "HideHost"
	hide_button.text = "×"
	hide_button.custom_minimum_size = Vector2(42, 42)
	hide_button.tooltip_text = "Hide floating panels; reopen from Window menu"
	hide_button.focus_mode = Control.FOCUS_ALL
	hide_button.pressed.connect(func() -> void: hide_requested.emit(host_id))
	title_row.add_child(hide_button)
	_scroll = ScrollContainer.new()
	_scroll.name = "FloatingScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	root_column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "FloatingGroups"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	var resize_row: HBoxContainer = HBoxContainer.new()
	resize_row.name = "ResizeBar"
	root_column.add_child(resize_row)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resize_row.add_child(spacer)
	var resize: Button = Button.new()
	resize.name = "ResizeHandle"
	resize.text = "◢"
	resize.tooltip_text = "Resize floating panel container"
	resize.custom_minimum_size = Vector2(44, 38)
	resize.focus_mode = Control.FOCUS_ALL
	resize.gui_input.connect(_handle_press.bind("resize"))
	resize_row.add_child(resize)
	_hint = ColorRect.new()
	_hint.name = "FloatingInsertionHint"
	_hint.color = Color(0.19, 0.78, 0.95, 0.9)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.top_level = true
	_hint.z_index = 100
	_hint.visible = false
	add_child(_hint)


## Reject non-finite geometry and retain a usable title/resize affordance in small windows.
func set_host_rect(requested: Rect2) -> void:
	var extent: Vector2 = Vector2(maxf(1.0, _client_extent().x), maxf(1.0, _client_extent().y))
	var margin: Vector2 = Vector2(minf(EDGE_MARGIN, (extent.x - 1.0) / 2.0),
		minf(EDGE_MARGIN, (extent.y - 1.0) / 2.0))
	var max_size: Vector2 = extent - margin * 2.0
	var minimum: Vector2 = Vector2(minf(MIN_FRAME.x, max_size.x), minf(MIN_FRAME.y, max_size.y))
	var desired_size: Vector2 = requested.size
	if not _finite_vector(desired_size):
		desired_size = size if _finite_vector(size) else minimum
	desired_size = desired_size.clamp(minimum, max_size)
	var desired_position: Vector2 = requested.position
	if not _finite_vector(desired_position):
		desired_position = position if _finite_vector(position) else Vector2.ZERO
	desired_position.x = clampf(desired_position.x, margin.x, maxf(margin.x, extent.x - desired_size.x - margin.x))
	desired_position.y = clampf(desired_position.y, margin.y, maxf(margin.y, extent.y - desired_size.y - margin.y))
	set_size(desired_size)
	position = desired_position


func clamp_to_client() -> void:
	set_host_rect(Rect2(position, size))


func _client_extent() -> Vector2:
	var parent_control: Control = get_parent() as Control
	return parent_control.size if parent_control != null else Vector2(1280, 800)


func _finite_vector(value: Vector2) -> bool:
	return not (is_nan(value.x) or is_nan(value.y) or is_inf(value.x) or is_inf(value.y))


func raise_host() -> void:
	if get_parent() != null and get_index() != get_parent().get_child_count() - 1:
		get_parent().move_child(self, get_parent().get_child_count() - 1)
		state_changed.emit()


func _frontmost_at(point: Vector2) -> bool:
	if not get_global_rect().has_point(point):
		return false
	for sibling: Node in get_parent().get_children():
		if sibling is DrawingFloatingHost and sibling != self and sibling.get_index() > get_index():
			if (sibling as DrawingFloatingHost).visible and (sibling as Control).get_global_rect().has_point(point):
				return false
	return true


func render() -> void:
	if layout == null or _body == null:
		return
	# No panel duplication: the workspace stashes all real Controls before rendering.
	for child: Node in _body.get_children():
		child.queue_free()
	group_frames.clear()
	tab_buttons.clear()
	group_handles.clear()
	tab_strips.clear()
	var state: Dictionary = layout.container_info(host_id)
	if state.is_empty():
		return
	_title.text = "Floating panels (%d groups)" % state["groups"].size()
	for group: Dictionary in state["groups"]:
		var group_id: String = group["id"]
		var members: Array[String] = []
		for panel_id: String in group["panels"]:
			if views.has(panel_id) and layout.rail_icons(host_id).any(func(entry: Dictionary) -> bool: return entry["panel"] == panel_id):
				members.append(panel_id)
		if members.is_empty():
			continue
		var frame: VBoxContainer = VBoxContainer.new()
		frame.name = "Group_" + group_id
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(frame)
		group_frames[group_id] = frame
		var heading: HBoxContainer = HBoxContainer.new()
		heading.name = "GroupHeader"
		frame.add_child(heading)
		var collapse: Button = Button.new()
		collapse.name = "Collapse_" + group_id
		collapse.text = "▸" if group["collapsed"] else "▾"
		collapse.tooltip_text = "Collapse/expand floating group " + group_id
		collapse.custom_minimum_size = Vector2(40, 40)
		collapse.focus_mode = Control.FOCUS_ALL
		collapse.pressed.connect(_toggle_collapse.bind(group_id))
		heading.add_child(collapse)
		var name_label: Label = Label.new()
		name_label.text = group_id.capitalize()
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(name_label)
		var handle: Button = Button.new()
		handle.name = "GroupDrag_" + group_id
		handle.text = "↕"
		handle.tooltip_text = "Drag floating group " + group_id + " to a dock or another host; Ctrl+Alt+Shift+D redocks"
		handle.custom_minimum_size = Vector2(38, 40)
		handle.focus_mode = Control.FOCUS_ALL
		handle.gui_input.connect(_tab_press.bind(DrawingDockDrag.GROUP, group_id))
		heading.add_child(handle)
		group_handles[group_id] = handle
		var arrange: MenuButton = MenuButton.new()
		arrange.name = "Arrange_" + group_id
		arrange.text = "⋮"
		arrange.tooltip_text = "Arrange floating tabs and groups"
		arrange.custom_minimum_size = Vector2(38, 40)
		arrange.focus_mode = Control.FOCUS_ALL
		heading.add_child(arrange)
		var menu: PopupMenu = arrange.get_popup()
		for action: String in ["Move active tab left", "Move active tab right", "Split active tab into new group", "Move group up", "Move group down", "Merge into previous group", "Merge into next group", "Redock active tab (last group)", "Redock whole group (last group)", "Send active tab to another floating host", "Send whole group to another floating host"]:
			menu.add_item(action)
		menu.id_pressed.connect(_arrange.bind(group_id))
		var tab_scroll: ScrollContainer = ScrollContainer.new()
		tab_scroll.name = "TabStripScroll_" + group_id
		tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tab_scroll.custom_minimum_size.y = 44
		frame.add_child(tab_scroll)
		tab_strips[group_id] = tab_scroll
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "TabStrip_" + group_id
		tab_scroll.add_child(row)
		for panel_id: String in members:
			var tab: Button = Button.new()
			tab.name = "Tab_" + panel_id
			tab.text = panel_id.capitalize()
			tab.tooltip_text = "Floating tab " + panel_id + "; drag between dock/hosts; Ctrl+Alt+D redocks"
			tab.custom_minimum_size.y = 40
			tab.focus_mode = Control.FOCUS_ALL
			tab.toggle_mode = true
			tab.button_pressed = group["active"] == panel_id
			tab.pressed.connect(_select_panel.bind(panel_id))
			tab.gui_input.connect(_tab_press.bind(DrawingDockDrag.PANEL, panel_id))
			row.add_child(tab)
			tab_buttons[panel_id] = tab
		if not group["collapsed"] and views.has(group["active"]):
			var panel_view: Control = views[group["active"]]
			panel_view.reparent(frame)
		frame.add_child(HSeparator.new())


func _select_panel(panel_id: String) -> void:
	if layout.select_panel(panel_id):
		layout_changed.emit()


func _toggle_collapse(group_id: String) -> void:
	var group: Dictionary = layout.group_info(group_id)
	if layout.set_group_collapsed(group_id, not bool(group["collapsed"])):
		layout_changed.emit()


func _arrange(action: int, group_id: String) -> void:
	var groups: Array = layout.container_info(host_id)["groups"]
	var group_index: int = -1
	for i: int in range(groups.size()):
		if groups[i]["id"] == group_id:
			group_index = i
	if group_index < 0:
		return
	var group: Dictionary = layout.group_info(group_id)
	var panel_id: String = group["active"]
	var panel_index: int = group["panels"].find(panel_id)
	var kind: String = DrawingDockDrag.PANEL
	var source: String = panel_id
	var target: Dictionary = {}
	match action:
		0:
			if panel_index > 0:
				target = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": panel_index - 1}
		1:
			if panel_index < group["panels"].size() - 1:
				target = {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": panel_index + 2}
		2:
			target = {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": group_index + 1}
		3, 4:
			kind = DrawingDockDrag.GROUP
			source = group_id
			var to: int = group_index - 1 if action == 3 else group_index + 2
			if to >= 0 and to <= groups.size():
				target = {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": to}
		5, 6:
			kind = DrawingDockDrag.GROUP
			source = group_id
			var other_index: int = group_index + (-1 if action == 5 else 1)
			if other_index >= 0 and other_index < groups.size():
				target = {"kind": DrawingDockDrag.MERGE_GROUP, "group": groups[other_index]["id"], "index": groups[other_index]["panels"].size()}
		7, 8:
			kind = DrawingDockDrag.PANEL if action == 7 else DrawingDockDrag.GROUP
			source = panel_id if action == 7 else group_id
			var right_groups: Array = layout.container_info("right")["groups"]
			target = {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": right_groups.size()}
		9, 10:
			if coordinator != null:
				for other_id: String in coordinator.floating_hosts:
					if other_id != host_id and (coordinator.floating_hosts[other_id] as DrawingFloatingHost).visible:
						kind = DrawingDockDrag.PANEL if action == 9 else DrawingDockDrag.GROUP
						source = panel_id if action == 9 else group_id
						target = {"kind": DrawingDockDrag.GROUP_SLOT, "container": other_id,
							"index": layout.container_info(other_id)["groups"].size()}
						break
	if not target.is_empty():
		_apply(kind, source, target)


func _apply(kind: String, source: String, target: Dictionary) -> bool:
	var started: bool = drag.begin_panel(source) if kind == DrawingDockDrag.PANEL else drag.begin_group(source)
	if not started or not drag.preview(target):
		drag.cancel()
		return false
	if not drag.commit():
		return false
	if coordinator != null:
		coordinator._reap_empty_hosts()
	layout_changed.emit()
	return true


func _handle_press(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_gesture = kind
		_pointer_start = event.global_position
		_frame_start = Rect2(position, size)
		raise_host()


func _tab_press(event: InputEvent, kind: String, source: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_candidate_kind = kind
		_candidate_id = source
		_candidate_start = event.global_position
		raise_host()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _gesture.is_empty() or not _candidate_id.is_empty() or (drag.is_dragging() and _owns_drag()):
			_suppress_release = true
			_clear_gesture()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.alt_pressed and not event.echo:
		if _keyboard(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _frontmost_at(event.global_position):
			raise_host()
	elif event is InputEventMouseMotion:
		if not _gesture.is_empty():
			var delta: Vector2 = event.global_position - _pointer_start
			if _gesture == "move":
				set_host_rect(Rect2(_frame_start.position + delta, _frame_start.size))
			else:
				set_host_rect(Rect2(_frame_start.position, _frame_start.size + delta))
			get_viewport().set_input_as_handled()
		elif not _candidate_id.is_empty():
			if not drag.is_dragging() and event.global_position.distance_to(_candidate_start) >= 7.0:
				if coordinator != null:
					coordinator.begin_cross_drag(host_id, _candidate_kind, _candidate_id)
				elif _candidate_kind == DrawingDockDrag.PANEL:
					drag.begin_panel(_candidate_id)
				else:
					drag.begin_group(_candidate_id)
			if drag.is_dragging() and _owns_drag():
				if coordinator != null:
					coordinator._preview_cross_drop(event.global_position)
				else:
					_preview(event.global_position)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _suppress_release:
			_suppress_release = false
			get_viewport().set_input_as_handled()
			return
		if not _gesture.is_empty():
			_gesture = ""
			state_changed.emit()
			get_viewport().set_input_as_handled()
		elif not _candidate_id.is_empty():
			if drag.is_dragging() and _owns_drag():
				if coordinator != null:
					coordinator._commit_cross_drop(event.global_position, host_id)
				else:
					_preview(event.global_position)
					var accepted: bool = drag.commit()
					if accepted:
						layout_changed.emit()
				_clear_gesture()
				get_viewport().set_input_as_handled()
			else:
				# A click is not a drag: allow Button.pressed to select its tab.
				_clear_gesture()


func _owns_drag() -> bool:
	if _candidate_id.is_empty():
		return false
	if _candidate_kind == DrawingDockDrag.PANEL:
		return layout.owner_of(_candidate_id) == host_id
	return layout.container_info(host_id)["groups"].any(func(g: Dictionary) -> bool: return g["id"] == _candidate_id)


func _clear_gesture() -> void:
	_gesture = ""
	_candidate_id = ""
	_candidate_kind = ""
	drag.cancel()
	if coordinator != null:
		coordinator._cancel_cross_drop()
	if _hint != null:
		_hint.visible = false


func _target_at(point: Vector2) -> Dictionary:
	if not get_global_rect().has_point(point):
		return {}
	var groups: Array = layout.container_info(host_id)["groups"]
	for i: int in range(groups.size()):
		var group_id: String = groups[i]["id"]
		var frame: Control = group_frames.get(group_id) as Control
		if frame == null or not frame.get_global_rect().has_point(point):
			continue
		var frame_rect: Rect2 = frame.get_global_rect()
		if point.y < frame_rect.position.y + 8.0:
			return {"target": {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": i},
				"rect": Rect2(frame_rect.position.x, frame_rect.position.y - 2.0, frame_rect.size.x, 4)}
		if point.y > frame_rect.end.y - 8.0:
			return {"target": {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": i + 1},
				"rect": Rect2(frame_rect.position.x, frame_rect.end.y - 2.0, frame_rect.size.x, 4)}
		var strip: ScrollContainer = tab_strips.get(group_id) as ScrollContainer
		if strip != null and strip.get_global_rect().has_point(point):
			var index: int = groups[i]["panels"].size()
			var x: float = strip.get_global_rect().end.x - 3.0
			for j: int in range(groups[i]["panels"].size()):
				var tab: Control = tab_buttons.get(groups[i]["panels"][j]) as Control
				if tab != null:
					var rect: Rect2 = tab.get_global_rect()
					if point.x < rect.get_center().x:
						index = j
						x = rect.position.x
						break
					x = rect.end.x
			x = clampf(x, strip.global_position.x + 2.0, strip.get_global_rect().end.x - 3.0)
			return {"target": {"kind": DrawingDockDrag.MERGE_GROUP if drag.source_kind() == DrawingDockDrag.GROUP else DrawingDockDrag.TAB_SLOT,
				"group": group_id, "index": index}, "rect": Rect2(x - 2.0, strip.global_position.y, 4.0, strip.size.y)}
		if point.y < frame_rect.position.y + 46.0:
			return {"target": {"kind": DrawingDockDrag.MERGE_GROUP if drag.source_kind() == DrawingDockDrag.GROUP else DrawingDockDrag.TAB_SLOT,
				"group": group_id, "index": groups[i]["panels"].size()},
				"rect": Rect2(frame_rect.position.x, frame_rect.position.y + 44.0, frame_rect.size.x, 4)}
	return {"target": {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": groups.size()},
		"rect": Rect2(_body.global_position.x, _body.get_global_rect().end.y, _body.size.x, 4)}


func _preview(point: Vector2) -> void:
	var hit: Dictionary = _target_at(point)
	if hit.is_empty() or not drag.preview(hit["target"]):
		_hint.visible = false
		return
	_hint.global_position = hit["rect"].position
	_hint.size = hit["rect"].size
	_hint.visible = true


func _keyboard(event: InputEventKey) -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	for id: String in tab_buttons:
		if tab_buttons[id] == focused:
			var group_id: String = layout.group_of(id)
			var members: Array = layout.group_info(group_id)["panels"]
			var index: int = members.find(id)
			if event.keycode == KEY_LEFT and index > 0:
				_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": index - 1})
				return true
			if event.keycode == KEY_RIGHT and index < members.size() - 1:
				_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": index + 2})
				return true
			if event.keycode == KEY_D and coordinator != null:
				_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.GROUP_SLOT,
					"container": "right", "index": layout.container_info("right")["groups"].size()})
				return true
			if event.keycode == KEY_S:
				var groups: Array = layout.container_info(host_id)["groups"]
				for j: int in range(groups.size()):
					if groups[j]["id"] == group_id:
						_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": j + 1})
						return true
	if event.shift_pressed and event.keycode == KEY_D and coordinator != null:
		for id: String in group_handles:
			if group_handles[id] == focused:
				_apply(DrawingDockDrag.GROUP, id, {"kind": DrawingDockDrag.GROUP_SLOT,
					"container": "right", "index": layout.container_info("right")["groups"].size()})
				return true
	if event.shift_pressed and (event.keycode == KEY_UP or event.keycode == KEY_DOWN):
		for id: String in group_handles:
			if group_handles[id] == focused:
				var groups: Array = layout.container_info(host_id)["groups"]
				for j: int in range(groups.size()):
					if groups[j]["id"] == id:
						var to: int = j - 1 if event.keycode == KEY_UP else j + 2
						if to >= 0 and to <= groups.size():
							_apply(DrawingDockDrag.GROUP, id, {"kind": DrawingDockDrag.GROUP_SLOT, "container": host_id, "index": to})
						return true
	return false
