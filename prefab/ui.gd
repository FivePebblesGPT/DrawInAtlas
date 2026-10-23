extends Control

@onready var _split: HSplitContainer = %WorkspaceSplit
@onready var _sidebar: Sidebar = %Sidebar

var _expanded_offset: int = 308


func _ready() -> void:
	_sidebar.panel_toggled.connect(_on_panel_toggled)
	_split.dragged.connect(_on_sidebar_resized)


func _on_panel_toggled(expanded: bool) -> void:
	_split.dragging_enabled = expanded
	_split.dragger_visibility = (
		SplitContainer.DRAGGER_HIDDEN if expanded
		else SplitContainer.DRAGGER_HIDDEN_COLLAPSED
	)
	_split.split_offsets = PackedInt32Array([_expanded_offset if expanded else 0])


func _on_sidebar_resized(offset: int) -> void:
	_expanded_offset = offset
