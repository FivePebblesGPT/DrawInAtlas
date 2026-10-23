extends Control

@onready var _split: HSplitContainer = %WorkspaceSplit
@onready var _sidebar: Sidebar = %Sidebar

var _expanded_offset: int = 308


func _ready() -> void:
	_expanded_offset = _split.split_offsets[0]
	_sidebar.panel_toggled.connect(_on_panel_toggled)
	_split.dragged.connect(_on_sidebar_resized)
	$MenuBar/File.get_popup().id_pressed.connect(_on_file_menu)


func _on_panel_toggled(expanded: bool) -> void:
	_split.dragging_enabled = expanded
	_split.dragger_visibility = (
		SplitContainer.DRAGGER_HIDDEN if expanded
		else SplitContainer.DRAGGER_HIDDEN_COLLAPSED
	)
	_split.split_offsets = PackedInt32Array([_expanded_offset if expanded else 0])


func _on_sidebar_resized(offset: int) -> void:
	_expanded_offset = offset


func _on_file_menu(id: int) -> void:
	var editor: AtlasEditor = _split.get_node("Workspace")
	match id:
		0:
			editor._on_sample()
		1:
			editor._on_save()
		2:
			editor._on_load()
