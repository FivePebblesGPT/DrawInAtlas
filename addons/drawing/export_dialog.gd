class_name DrawingExportDialog
extends ConfirmationDialog
## Explicit preview refresh avoids encoding a full image on every slider event.

var format_option: OptionButton
var lossless_option: CheckBox
var quality_option: SpinBox
var matte_option: ColorPickerButton
var dimensions: Label
var preview: TextureRect
var preview_area: TextureRect
var feedback: Label
var quality_row: HBoxContainer
var matte_row: HBoxContainer
var source: Image
var original_preview: ImageTexture
var render_warning: String = ""
var encoded: PackedByteArray = PackedByteArray()

func _ready() -> void:
	title = "Export image"
	dialog_hide_on_ok = false
	get_ok_button().text = "Choose file…"
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(320, 225)
	add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	dimensions = Label.new()
	content.add_child(dimensions)
	format_option = OptionButton.new()
	for label: String in ["PNG", "WebP", "JPEG"]:
		format_option.add_item(label)
	_row(content, "Format", format_option)
	lossless_option = CheckBox.new()
	lossless_option.text = "Lossless (preserve RGBA8)"
	lossless_option.button_pressed = true
	content.add_child(lossless_option)
	quality_option = SpinBox.new()
	quality_option.min_value = 0
	quality_option.max_value = 100
	quality_option.value = 90
	quality_option.suffix = "%"
	quality_row = _row(content, "Quality", quality_option)
	matte_option = ColorPickerButton.new()
	matte_option.edit_alpha = false
	matte_option.color = Color.WHITE
	matte_option.custom_minimum_size.x = 80
	matte_row = _row(content, "JPEG matte", matte_option)
	var background: TextureRect = TextureRect.new()
	preview_area = background
	var checker: Image = Image.create_empty(16, 16, false, Image.FORMAT_RGB8)
	checker.fill(Color(0.25, 0.25, 0.25))
	checker.fill_rect(Rect2i(0, 0, 8, 8), Color(0.35, 0.35, 0.35))
	checker.fill_rect(Rect2i(8, 8, 8, 8), Color(0.35, 0.35, 0.35))
	background.texture = ImageTexture.create_from_image(checker)
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.custom_minimum_size = Vector2(280, 128)
	background.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(background)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(preview)
	var refresh: Button = Button.new()
	refresh.text = "Update encoded preview"
	content.add_child(refresh)
	refresh.pressed.connect(refresh_preview)
	feedback = Label.new()
	feedback.clip_text = true
	content.add_child(feedback)
	format_option.item_selected.connect(func(_index: int) -> void: _options_changed())
	lossless_option.toggled.connect(func(_pressed: bool) -> void: _options_changed())
	quality_option.value_changed.connect(func(_value: float) -> void: _options_changed())
	matte_option.color_changed.connect(func(_color: Color) -> void: _options_changed())
	_options_changed()


func _row(parent: VBoxContainer, caption: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	parent.add_child(row)
	return row


func set_compact_preview(compact: bool) -> void:
	preview_area.custom_minimum_size.y = 76.0 if compact else 128.0


func selected_format() -> String:
	return ["png", "webp", "jpeg"][format_option.selected]


func prepare(image: Image, bounds: Rect2i, warning: String = "") -> void:
	source = image
	original_preview = _preview_texture(image)
	render_warning = warning
	dimensions.text = "%d × %d px · frame (%d, %d)" % [bounds.size.x, bounds.size.y, bounds.position.x, bounds.position.y]
	dimensions.tooltip_text = warning
	_options_changed()


func _options_changed() -> void:
	var format: String = selected_format()
	lossless_option.visible = format == "webp"
	quality_row.visible = format == "jpeg" or (format == "webp" and not lossless_option.button_pressed)
	matte_row.visible = format == "jpeg"
	encoded = PackedByteArray()
	preview.texture = original_preview
	var note: String = "Lossless with alpha." if format == "png" else (
		"Alpha is flattened onto the matte." if format == "jpeg" else "WebP preserves alpha.")
	feedback.tooltip_text = render_warning
	feedback.text = note + "\nOriginal composite. Update for encoded size." + _warning_suffix()


func encode_current() -> DrawingResult:
	if not encoded.is_empty():
		return DrawingResult.success(encoded)
	var result: DrawingResult = DrawingRasterExport.encode(source, selected_format(),
		lossless_option.button_pressed, quality_option.value / 100.0, matte_option.color)
	if result.ok:
		encoded = result.value as PackedByteArray
	else:
		feedback.text = "Encoding failed. Hover for details."
		feedback.tooltip_text = result.message
	return result


func refresh_preview() -> void:
	var result: DrawingResult = encode_current()
	if not result.ok:
		return
	var decoded: DrawingResult = DrawingRasterImport.decode_image_bytes(encoded, selected_format())
	if not decoded.ok:
		feedback.text = "Preview decode failed. Hover for details."
		feedback.tooltip_text = decoded.message
		return
	preview.texture = _preview_texture(decoded.value as Image)
	var size_label: String = "%d bytes" % encoded.size() if encoded.size() < 1024 else "%s (%d bytes)" % [String.humanize_size(encoded.size()), encoded.size()]
	feedback.text = "Encoded preview · " + size_label + _warning_suffix()
	feedback.tooltip_text = render_warning


func _warning_suffix() -> String:
	return "\nText fallback; hover for details." if not render_warning.is_empty() else ""


func _preview_texture(image: Image) -> ImageTexture:
	var scaled: Image = image.duplicate()
	var edge: int = maxi(scaled.get_width(), scaled.get_height())
	if edge > 512:
		var factor: float = 512.0 / float(edge)
		scaled.resize(maxi(1, roundi(scaled.get_width() * factor)), maxi(1, roundi(scaled.get_height() * factor)), Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(scaled)


func clear_snapshot() -> void:
	source = null
	original_preview = null
	render_warning = ""
	encoded = PackedByteArray()
	preview.texture = null
