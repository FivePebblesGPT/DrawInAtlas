class_name DrawingFloatingHost
extends PanelContainer
## In-app tabbed group host. State/ownership lives exclusively in DrawingDockLayout.
## One group per floating host; geometry is stored in workspace preferences.

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
var _header: HBoxContainer
var _resize_sides: Vector4i = Vector4i.ZERO # left, top, right, bottom
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
	_header = HBoxContainer.new()
	_header.name = "FloatingTitleBar"
	root_column.add_child(_header)
	var grip: Button = Button.new()
	grip.name = "MoveHandle"
	grip.text = "⠿"
	grip.tooltip_text = "Drag to move; release over the right dock to redock the group (Shift: transfer group)"
	grip.custom_minimum_size = Vector2(34, 34)
	grip.focus_mode = Control.FOCUS_ALL
	grip.gui_input.connect(_handle_press.bind("move"))
	_header.add_child(grip)
	var hide_button: Button = Button.new()
	hide_button.name = "HideHost"
	hide_button.text = "×"
	hide_button.custom_minimum_size = Vector2(34, 34)
	hide_button.tooltip_text = "Hide this floating group; reopen from Window menu"
	hide_button.focus_mode = Control.FOCUS_ALL
	hide_button.pressed.connect(func() -> void: hide_requested.emit(host_id))
	_header.add_child(hide_button)
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
	_hint = ColorRect.new()
	_hint.name = "FloatingInsertionHint"
	_hint.color = Color(0.19, 0.78, 0.95, 0.9)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.top_level = true
	_hint.z_index = 100
	_hint.visible = false
	add_child(_hint)
	resized.connect(queue_redraw)


func _draw() -> void:
	# Textarea-like hint, without an extra full-height resize toolbar.
	var tone: Color = Color(0.63, 0.69, 0.75, 0.7)
	for offset: float in [5.0, 10.0, 15.0]:
		draw_line(Vector2(size.x - offset, size.y - 3.0),
			Vector2(size.x - 3.0, size.y - offset), tone, 1.0)


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
	# A dock refresh can be requested several times before the next frame.
	# queue_free() alone leaves old tab strips and group chrome in layout until
	# the frame ends. Detach immediately, then delete; never free panel views.
	for view: Control in views.values():
		if _body.is_ancestor_of(view) and stash != null:
			view.reparent(stash)
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for child: Node in _header.get_children():
		if child.name.begins_with("TabStripScroll_"):
			_header.remove_child(child)
			child.queue_free()
	group_frames.clear()
	tab_buttons.clear()
	group_handles.clear()
	tab_strips.clear()
	var state: Dictionary = layout.container_info(host_id)
	if state.is_empty() or (state["groups"] as Array).size() != 1:
		return
	var group: Dictionary = state["groups"][0]
	var group_id: String = group["id"]
	var members: Array[String] = []
	for panel_id: String in group["panels"]:
		if views.has(panel_id) and layout.rail_icons(host_id).any(func(entry: Dictionary) -> bool: return entry["panel"] == panel_id):
			members.append(panel_id)
	if members.is_empty():
		return
	# Grip, *one* tab strip and close occupy the same compact header.
	var tab_scroll: ScrollContainer = ScrollContainer.new()
	tab_scroll.name = "TabStripScroll_" + group_id
	tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size.y = 34
	_header.add_child(tab_scroll)
	_header.move_child(tab_scroll, 1)
	tab_strips[group_id] = tab_scroll
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "TabStrip_" + group_id
	tab_scroll.add_child(row)
	for panel_id: String in members:
		var tab: Button = Button.new()
		tab.name = "Tab_" + panel_id
		tab.text = panel_id.capitalize()
		tab.tooltip_text = "Floating tab " + panel_id + "; drag to redock or reorder"
		tab.custom_minimum_size.y = 32
		tab.focus_mode = Control.FOCUS_ALL
		tab.toggle_mode = true
		tab.button_pressed = group["active"] == panel_id
		tab.pressed.connect(_select_panel.bind(panel_id))
		row.add_child(tab)
		tab_buttons[panel_id] = tab
	# The existing move handle doubles as the keyboard-accessible group handle.
	group_handles[group_id] = _header.get_node("MoveHandle") as Button
	var frame: VBoxContainer = VBoxContainer.new()
	frame.name = "Group_" + group_id
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(frame)
	group_frames[group_id] = frame
	if views.has(group["active"]):
		var panel_view: Control = views[group["active"]]
		panel_view.reparent(frame)


func _select_panel(panel_id: String) -> void:
	if layout.select_panel(panel_id):
		layout_changed.emit()


func _toggle_collapse(group_id: String) -> void:
	var group: Dictionary = layout.group_info(group_id)
	if layout.set_group_collapsed(group_id, not bool(group["collapsed"])):
		layout_changed.emit()


## Accessible commands are scoped to one host/group. Splitting a floating tab
## creates a *new host*, never a nested second group in this container.
func _arrange(action: int, group_id: String) -> void:
	var group: Dictionary = layout.group_info(group_id)
	if group.is_empty():
		return
	var panel_id: String = group["active"]
	var panel_index: int = group["panels"].find(panel_id)
	match action:
		0:
			if panel_index > 0:
				_apply(DrawingDockDrag.PANEL, panel_id,
					{"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": panel_index - 1})
		1:
			if panel_index < group["panels"].size() - 1:
				_apply(DrawingDockDrag.PANEL, panel_id,
					{"kind": DrawingDockDrag.TAB_SLOT, "group": group_id, "index": panel_index + 2})
		2:
			if coordinator != null and group["panels"].size() > 1:
				coordinator._float_source(DrawingDockDrag.PANEL, panel_id)
		3, 4:
			var kind: String = DrawingDockDrag.PANEL if action == 3 else DrawingDockDrag.GROUP
			var source: String = panel_id if action == 3 else group_id
			_apply(kind, source, {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right",
				"index": layout.container_info("right")["groups"].size()})
		5, 6:
			if coordinator != null:
				for other_id: String in coordinator.floating_hosts:
					if other_id == host_id or not (coordinator.floating_hosts[other_id] as DrawingFloatingHost).visible:
						continue
					var other_group: Dictionary = layout.container_info(other_id)["groups"][0]
					var kind: String = DrawingDockDrag.PANEL if action == 5 else DrawingDockDrag.GROUP
					var source: String = panel_id if action == 5 else group_id
					_apply(kind, source, {"kind": DrawingDockDrag.TAB_SLOT if action == 5 else DrawingDockDrag.MERGE_GROUP,
						"group": other_group["id"], "index": other_group["panels"].size()})
					return


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
		if kind == "move" and (event as InputEventMouseButton).shift_pressed and not group_handles.is_empty():
			var group_id: String = group_handles.keys()[0]
			_tab_press(event, DrawingDockDrag.GROUP, group_id)
			return
		_gesture = kind
		_resize_sides = Vector4i.ZERO
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
			# A prior target host may have seen a press without the matching
			# release during a cross-host transfer. Never replay that stale tab.
			_candidate_id = ""
			_candidate_kind = ""
			for panel_id: String in tab_buttons:
				var tab: Control = tab_buttons[panel_id] as Control
				if tab.get_global_rect().has_point(event.global_position):
					_candidate_kind = DrawingDockDrag.PANEL
					_candidate_id = panel_id
					_candidate_start = event.global_position
					# Godot 4.8 beta's forwarded GUI events may hit the
					# wrong button in a scrolled strip. Route viewport hits
					# by the actual visible tab rectangles instead.
					get_viewport().set_input_as_handled()
					break
			var sides: Vector4i = _hit_resize_edges(event.global_position)
			if sides != Vector4i.ZERO:
				_gesture = "resize"
				_resize_sides = sides
				_pointer_start = event.global_position
				_frame_start = Rect2(position, size)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if not _gesture.is_empty():
			var delta: Vector2 = event.global_position - _pointer_start
			if _gesture == "move":
				# Normal grip dragging moves the host over the canvas, but a
				# valid dock target offers a whole-group redock on release.
				# Hit-test the underlying dock even when this tall host overlaps it.
				var redock: bool = coordinator != null and not group_handles.is_empty() and \
					coordinator._preview_grip_redock(host_id, String(group_handles.keys()[0]), event.global_position)
				if not redock:
					set_host_rect(Rect2(_frame_start.position + delta, _frame_start.size))
			else:
				_resize_from_pointer(delta)
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
			var was_move: bool = _gesture == "move"
			_gesture = ""
			if was_move and coordinator != null and coordinator._commit_grip_redock(host_id, event.global_position):
				get_viewport().set_input_as_handled()
				return
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
				# A click selects the hit-tested tab; keyboard Button.pressed
				# remains connected for accessibility.
				var clicked_id: String = _candidate_id
				_clear_gesture()
				if layout.select_panel(clicked_id):
					layout_changed.emit()
				get_viewport().set_input_as_handled()


func _hit_resize_edges(point: Vector2) -> Vector4i:
	var frame: Rect2 = get_global_rect()
	if not frame.has_point(point):
		return Vector4i.ZERO
	var local: Vector2 = point - frame.position
	var border: float = 8.0
	return Vector4i(int(local.x < border), int(local.y < border),
		int(local.x >= frame.size.x - border), int(local.y >= frame.size.y - border))


func _resize_from_pointer(delta: Vector2) -> void:
	# The ungrabbed edge must remain stationary when the pointer crosses a
	# client boundary. Feeding an oversized rectangle to set_host_rect() would
	# instead shift the *whole* host to fit, moving the opposite edge.
	var extent: Vector2 = _client_extent().max(Vector2.ONE)
	var margin: Vector2 = Vector2(minf(EDGE_MARGIN, (extent.x - 1.0) / 2.0),
		minf(EDGE_MARGIN, (extent.y - 1.0) / 2.0))
	var minimum: Vector2 = MIN_FRAME.min(extent - 2.0 * margin)
	var rect: Rect2 = _frame_start
	if _resize_sides.x == 1:
		var left: float = clampf(_frame_start.position.x + delta.x,
			margin.x, _frame_start.end.x - minimum.x)
		rect.position.x = left
		rect.size.x = _frame_start.end.x - left
	elif _resize_sides.z == 1:
		rect.size.x = clampf(_frame_start.end.x + delta.x,
			_frame_start.position.x + minimum.x, extent.x - margin.x) - _frame_start.position.x
	if _resize_sides.y == 1:
		var top: float = clampf(_frame_start.position.y + delta.y,
			margin.y, _frame_start.end.y - minimum.y)
		rect.position.y = top
		rect.size.y = _frame_start.end.y - top
	elif _resize_sides.w == 1:
		rect.size.y = clampf(_frame_start.end.y + delta.y,
			_frame_start.position.y + minimum.y, extent.y - margin.y) - _frame_start.position.y
	set_host_rect(rect)


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
	if groups.size() != 1:
		return {}
	var group_id: String = groups[0]["id"]
	var strip: ScrollContainer = tab_strips.get(group_id) as ScrollContainer
	if strip == null:
		return {}
	var index: int = groups[0]["panels"].size()
	var x: float = strip.get_global_rect().end.x - 3.0
	for j: int in range(groups[0]["panels"].size()):
		var tab: Control = tab_buttons.get(groups[0]["panels"][j]) as Control
		if tab != null:
			var tab_rect: Rect2 = tab.get_global_rect()
			if point.x < tab_rect.get_center().x:
				index = j
				x = tab_rect.position.x
				break
			x = tab_rect.end.x
	x = clampf(x, strip.global_position.x + 2.0, strip.get_global_rect().end.x - 3.0)
	return {"target": {"kind": DrawingDockDrag.MERGE_GROUP if drag.source_kind() == DrawingDockDrag.GROUP else DrawingDockDrag.TAB_SLOT,
		"group": group_id, "index": index},
		"rect": Rect2(x - 2.0, strip.global_position.y, 4.0, strip.size.y)}


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
		if tab_buttons[id] != focused:
			continue
		var group_id: String = layout.group_of(id)
		var members: Array = layout.group_info(group_id)["panels"]
		var index: int = members.find(id)
		if event.keycode == KEY_LEFT and index > 0:
			_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.TAB_SLOT,
				"group": group_id, "index": index - 1})
			return true
		if event.keycode == KEY_RIGHT and index < members.size() - 1:
			_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.TAB_SLOT,
				"group": group_id, "index": index + 2})
			return true
		if event.keycode == KEY_D:
			_apply(DrawingDockDrag.PANEL, id, {"kind": DrawingDockDrag.GROUP_SLOT,
				"container": "right", "index": layout.container_info("right")["groups"].size()})
			return true
		if event.keycode == KEY_S and coordinator != null and members.size() > 1:
			coordinator._float_source(DrawingDockDrag.PANEL, id)
			return true
	if event.shift_pressed and event.keycode == KEY_D and coordinator != null:
		for group_id: String in group_handles:
			if group_handles[group_id] == focused:
				_apply(DrawingDockDrag.GROUP, group_id, {"kind": DrawingDockDrag.GROUP_SLOT,
					"container": "right", "index": layout.container_info("right")["groups"].size()})
				return true
	return false
