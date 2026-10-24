class_name AtlasRasterImporter
extends Node

signal image_ready(image: Image)
signal failed(message: String)

const MAX_ENCODED_BYTES: int = 32 * 1024 * 1024
const MAX_DIMENSION: int = 4096

# No JavaScriptBridge/JavaScriptObject type references: native builds lack them.
const WEB_PICKER_SCRIPT: String = """
(() => {
    const key = %s;
    const picker = { dispose() {} };
    picker.open = (callback, limit) => {
        let input = null;
        let reader = null;
        let timer = null;
        let finished = false;
        let reading = false;
        let blurred = false;
        const cleanup = () => {
            if (timer !== null) window.clearTimeout(timer);
            window.removeEventListener('blur', onBlur);
            window.removeEventListener('focus', onFocus);
            if (input) {
                input.onchange = null;
                input.oncancel = null;
                input.remove();
                input = null;
            }
            if (reader) {
                reader.onload = null;
                reader.onerror = null;
                reader.onabort = null;
                if (reader.readyState === 1) reader.abort();
                reader = null;
            }
            picker.dispose = () => {};
        };
        const finish = (status, value = null) => {
            if (finished) return;
            finished = true;
            cleanup();
            callback(status, value);
        };
        const onBlur = () => { blurred = true; };
        const onFocus = () => {
            if (!blurred || reading || finished) return;
            // Legacy fallback only; Chromium's cancel event avoids this race.
            timer = window.setTimeout(() => {
                if (!finished && !reading && input && !input.files.length)
                    finish('cancel');
            }, 500);
        };
        picker.dispose = () => {
            finished = true;
            cleanup();
        };
        try {
            if (navigator.userActivation && !navigator.userActivation.isActive)
                throw new Error('Start image import from a button click or key press.');
            input = document.createElement('input');
            input.type = 'file';
            input.accept = 'image/png,image/jpeg,image/webp';
            input.style.display = 'none';
            input.oncancel = () => finish('cancel');
            input.onchange = () => {
                const file = input.files[0];
                if (!file) { finish('cancel'); return; }
                if (file.size === 0) { finish('error', 'The selected image is empty.'); return; }
                if (file.size > limit) {
                    finish('error', 'The selected image exceeds the 32 MiB file limit.');
                    return;
                }
                reading = true;
                try {
                    reader = new FileReader();
                    reader.onerror = () => finish('error', 'Could not read the selected image.');
                    reader.onabort = () => finish('cancel');
                    reader.onload = () => {
                        const bytes = reader.result;
                        if (!(bytes instanceof ArrayBuffer) || bytes.byteLength !== file.size) {
                            finish('error', 'The selected image could not be read completely.');
                            return;
                        }
                        finish('bytes', bytes);
                    };
                    reader.readAsArrayBuffer(file);
                } catch (error) {
                    finish('error', 'Could not read the selected image: ' + error.message);
                }
            };
            if (!('oncancel' in HTMLInputElement.prototype)) {
                window.addEventListener('blur', onBlur);
                window.addEventListener('focus', onFocus);
            }
            document.body.appendChild(input);
            input.click();
        } catch (error) {
            finish('error', 'Could not open the image picker: ' + error.message);
        }
    };
    window[key] = picker;
    return 'ready';
})()
"""

var _in_flight: bool = false
var _dialog: FileDialog
var _bridge: Object
var _web_callback: Object
var _web_picker: Variant
var _web_key: String = ""


## Call directly from a user input handler so browsers allow opening the picker.
func request_import() -> void:
    if _in_flight:
        return
    if not is_inside_tree():
        _fail("Image importer must be added to the scene tree before importing.")
        return
    _in_flight = true
    if OS.has_feature("web"):
        _request_web_import()
    else:
        _request_native_import()


func _exit_tree() -> void:
    _clear_web_picker()
    _web_callback = null
    _bridge = null
    _in_flight = false
    if is_instance_valid(_dialog):
        _dialog.hide()


func _request_native_import() -> void:
    if not is_instance_valid(_dialog):
        _dialog = FileDialog.new()
        _dialog.access = FileDialog.ACCESS_FILESYSTEM
        _dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        _dialog.use_native_dialog = true
        _dialog.filters = PackedStringArray([
            "*.png,*.jpg,*.jpeg,*.webp;PNG, JPEG, or WebP images",
            "*.png;PNG images;image/png",
            "*.jpg,*.jpeg;JPEG images;image/jpeg",
            "*.webp;WebP images;image/webp",
        ])
        _dialog.file_selected.connect(_on_file_selected)
        _dialog.canceled.connect(_on_canceled)
        add_child(_dialog)
    _dialog.popup_file_dialog()


func _on_canceled() -> void:
    _in_flight = false


func _on_file_selected(path: String) -> void:
    if not _in_flight:
        return
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        _fail("Could not open the selected image: %s." % error_string(FileAccess.get_open_error()))
        return
    var length: int = file.get_length()
    if length <= 0 or length > MAX_ENCODED_BYTES:
        file.close()
        _fail("Choose a nonempty image file of at most 32 MiB.")
        return
    var bytes: PackedByteArray = file.get_buffer(length)
    file.close()
    if bytes.size() != length:
        _fail("The selected image could not be read completely.")
        return
    _decode_image(bytes)


func _request_web_import() -> void:
    if not Engine.has_singleton("JavaScriptBridge"):
        _fail("This Web build does not provide JavaScriptBridge for image import.")
        return
    _bridge = Engine.get_singleton("JavaScriptBridge")
    if _web_callback == null:
        _web_callback = _bridge.call("create_callback", _on_web_result)
    _web_key = "__atlasRasterImporter_%s" % get_instance_id()
    var installed: Variant = _bridge.call("eval", WEB_PICKER_SCRIPT % JSON.stringify(_web_key))
    # This beta may map JavaScript booleans to integers; use a typed string handshake.
    if not installed is String or installed != "ready":
        _fail("Could not initialize the browser image picker.")
        return
    _web_picker = _bridge.call("get_interface", _web_key)
    if _web_picker == null or _web_callback == null:
        _fail("Could not connect the browser image picker.")
        return
    _web_picker.open(_web_callback, MAX_ENCODED_BYTES)


func _on_web_result(arguments: Array) -> void:
    if not _in_flight:
        return
    _clear_web_picker()
    if arguments.is_empty() or not arguments[0] is String:
        _fail("The browser returned an invalid image import response.")
        return
    match arguments[0]:
        "cancel":
            _on_canceled()
        "error":
            var message: String = "Could not read the selected image."
            if arguments.size() > 1 and arguments[1] is String:
                message = arguments[1]
            _fail(message)
        "bytes":
            if arguments.size() < 2 or not arguments[1] is Object:
                _fail("The browser did not return image bytes.")
                return
            if not _bridge.call("is_js_buffer", arguments[1]):
                _fail("The browser did not return a valid image buffer.")
                return
            var bytes: PackedByteArray = _bridge.call("js_buffer_to_packed_byte_array", arguments[1])
            _decode_image(bytes)
        _:
            _fail("The browser returned an unknown image import response.")


func _clear_web_picker() -> void:
    if _web_picker != null:
        _web_picker.dispose()
        _web_picker = null
    if _bridge != null and not _web_key.is_empty():
        _bridge.call("eval", "delete window[%s]" % JSON.stringify(_web_key))
    _web_key = ""


func _fail(message: String) -> void:
    _clear_web_picker()
    _in_flight = false
    failed.emit(message)


func _decode_image(bytes: PackedByteArray) -> void:
    if bytes.is_empty() or bytes.size() > MAX_ENCODED_BYTES:
        _fail("Choose a nonempty image file of at most 32 MiB.")
        return
    var format: String = ""
    var dimensions: Vector2i = Vector2i.ZERO
    if bytes.size() >= 24 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
        format = "PNG"
        if _read_big_endian(bytes, 8, 4) == 13 and bytes.slice(12, 16).get_string_from_ascii() == "IHDR":
            dimensions = Vector2i(_read_big_endian(bytes, 16, 4), _read_big_endian(bytes, 20, 4))
    elif bytes.size() >= 4 and bytes[0] == 0xff and bytes[1] == 0xd8:
        format = "JPEG"
        dimensions = _jpeg_dimensions(bytes)
    elif bytes.size() >= 25 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
        format = "WebP"
        dimensions = _webp_dimensions(bytes)
    else:
        _fail("Unsupported image format. Choose a PNG, JPEG, or WebP image.")
        return
    if dimensions.x <= 0 or dimensions.y <= 0:
        _fail("The %s image has an invalid or unsupported header." % format)
        return
    if dimensions.x > MAX_DIMENSION or dimensions.y > MAX_DIMENSION:
        _fail("Image dimensions must be at most 4096 × 4096 pixels (selected: %s × %s)." % [dimensions.x, dimensions.y])
        return
    var image: Image = Image.new()
    var result: Error = ERR_FILE_UNRECOGNIZED
    match format:
        "PNG":
            result = image.load_png_from_buffer(bytes)
        "JPEG":
            result = image.load_jpg_from_buffer(bytes)
        "WebP":
            result = image.load_webp_from_buffer(bytes)
    if result != OK or image.is_empty():
        _fail("Could not decode the %s image. The file may be damaged or unsupported." % format)
        return
    if image.get_size() != dimensions:
        _fail("The decoded image dimensions do not match its header.")
        return
    _in_flight = false
    image_ready.emit(image)


# Inspect dimensions before invoking a decoder, bounding decoded pixel memory too.
func _jpeg_dimensions(bytes: PackedByteArray) -> Vector2i:
    var offset: int = 2
    while offset < bytes.size():
        if bytes[offset] != 0xff:
            return Vector2i.ZERO
        while offset < bytes.size() and bytes[offset] == 0xff:
            offset += 1
        if offset >= bytes.size():
            return Vector2i.ZERO
        var marker: int = bytes[offset]
        offset += 1
        if marker == 0xda or marker == 0xd9:
            return Vector2i.ZERO
        if marker == 0x01 or (marker >= 0xd0 and marker <= 0xd7):
            continue
        if offset + 2 > bytes.size():
            return Vector2i.ZERO
        var length: int = _read_big_endian(bytes, offset, 2)
        if length < 2 or offset + length > bytes.size():
            return Vector2i.ZERO
        if marker >= 0xc0 and marker <= 0xcf and marker not in [0xc4, 0xc8, 0xcc]:
            if length < 8:
                return Vector2i.ZERO
            return Vector2i(_read_big_endian(bytes, offset + 5, 2), _read_big_endian(bytes, offset + 3, 2))
        offset += length
    return Vector2i.ZERO


func _webp_dimensions(bytes: PackedByteArray) -> Vector2i:
    var chunk: String = bytes.slice(12, 16).get_string_from_ascii()
    var length: int = bytes.decode_u32(16)
    if length > bytes.size() - 20:
        return Vector2i.ZERO
    match chunk:
        "VP8X":
            if length != 10:
                return Vector2i.ZERO
            return Vector2i(1 + _read_little_endian_24(bytes, 24), 1 + _read_little_endian_24(bytes, 27))
        "VP8 ":
            if length < 10 or bytes.slice(23, 26) != PackedByteArray([0x9d, 0x01, 0x2a]):
                return Vector2i.ZERO
            return Vector2i(bytes.decode_u16(26) & 0x3fff, bytes.decode_u16(28) & 0x3fff)
        "VP8L":
            if length < 5 or bytes[20] != 0x2f:
                return Vector2i.ZERO
            var bits: int = bytes.decode_u32(21)
            return Vector2i(1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff))
    return Vector2i.ZERO


func _read_big_endian(bytes: PackedByteArray, offset: int, count: int) -> int:
    var value: int = 0
    for index: int in range(offset, offset + count):
        value = (value << 8) | bytes[index]
    return value


func _read_little_endian_24(bytes: PackedByteArray, offset: int) -> int:
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16)
