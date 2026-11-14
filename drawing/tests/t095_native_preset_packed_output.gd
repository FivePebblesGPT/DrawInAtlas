extends SceneTree
## T-095: exact ordered Hokusai delta bytes across a bulk export and a
## rejected GDScript batch. Golden hashes were captured from the pre-change
## per-element PackedInt32Array writer (5174fb0), never from the new writer.

const PRESET_FILES: Dictionary = {
    "hard": "hard_round", "soft": "soft", "ink": "ink", "airbrush": "airbrush"
}
const EXPECTED: Dictionary = {
    "hard": "90190a1390e89e0615c077bddb27b59cec99613c6de30b17514381f30495227a",
    "soft": "86ab6b6c7e901be85f6740166770e3310a0c76edca465df785d640b0b2e66a7d",
    "ink": "abe74096f2f4807d94491f5e054b0066e7831d64d4ef41ff4ba92f95dea6cb82",
    "airbrush": "081a34720cbb7a1b6a7fdde4ac1bedb9fbf31f380885b07c80bc540bf38cc174"
}
const TINT: int = 0x9c53a071
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("T095_NATIVE_PRESET_PACKED_FAILED: " + label)

func points_for(index: int, length: int, y_scale: float = 1.0) -> PackedVector2Array:
    var values: PackedVector2Array = PackedVector2Array()
    for j: int in range(length):
        var t: float = float(j) / float(length - 1)
        values.append(Vector2(-91.5 + float(index) * 7.0 + 171.0 * t,
            (31.5 * sin(t * TAU * (3.0 + float(index))) + float(index) * 4.0) * y_scale))
    return values

func make_native(settings: String) -> Object:
    var native: Object = ClassDB.instantiate("DrawingNativeBrush")
    check(bool(native.call("configure_preset", settings, 60.0, TINT)),
        "configure real Hokusai brush")
    return native

func add_digest(digest: HashingContext, pixels: PackedInt32Array) -> void:
    var length: PackedByteArray = PackedByteArray()
    length.resize(4)
    length.encode_u32(0, pixels.size())
    digest.update(length)
    digest.update(pixels.to_byte_array())

func run_preset(name: String, file_stem: String) -> void:
    var settings: String = FileAccess.get_file_as_string(
        "res://addons/drawing/brushes/%s.myb" % file_stem)
    check(not settings.is_empty(), name + " bundled .myb exists")
    var subject: Object = make_native(settings)
    var reference: Object = make_native(settings)
    var digest: HashingContext = HashingContext.new()
    check(digest.start(HashingContext.HASH_SHA256) == OK, name + " digest starts")
    var total_pixels: int = 0
    var paths: Array[PackedVector2Array] = [
        points_for(0, 56), points_for(1, 48, -1.0), points_for(2, 32)
    ]
    for batch: int in range(paths.size()):
        var pressure: float = 0.8 if batch == 1 else 1.0
        check(bool(subject.call("begin_preset_batch")), name + " begin transaction " + str(batch))
        var actual: PackedInt32Array = subject.call("preset_segments", paths[batch], pressure)
        check(actual.size() % 3 == 0, name + " complete signed RGBA triples")
        if batch == 1:
            # Discard native pigment, RNG/cursor and quantized export after the
            # (simulated) late failure of the downstream GDScript source read.
            subject.call("rollback_preset_batch")
            check(bool(subject.call("begin_preset_batch")), name + " retry transaction")
            var repeated: PackedInt32Array = subject.call("preset_segments", paths[batch], pressure)
            check(actual == repeated, name + " rollback reproduces ordered delta bytes")
            actual = repeated
        subject.call("commit_preset_batch")
        var expected: PackedInt32Array = reference.call("preset_segments", paths[batch], pressure)
        check(actual == expected, name + " uninterrupted pigment stream matches")
        total_pixels += actual.size() / 3
        add_digest(digest, actual)
    var checksum: String = digest.finish().hex_encode()
    print("T095_NATIVE_PRESET_PACKED_SAMPLE preset=%s pixels=%d sha256=%s" % [name, total_pixels, checksum])
    if EXPECTED.has(name):
        check(checksum == EXPECTED[name], name + " unchanged pre-optimization delta digest")
    else:
        check(false, name + " missing baseline digest")
    check(total_pixels > 1000, name + " substantial native pixel output")

func run() -> void:
    check(ClassDB.class_exists("DrawingNativeBrush"), "actual extension registered")
    if ClassDB.class_exists("DrawingNativeBrush"):
        for name: String in ["hard", "soft", "ink", "airbrush"]:
            run_preset(name, String(PRESET_FILES[name]))
    print("T095_NATIVE_PRESET_PACKED_RESULT checks=%d failures=%d" % [checks, failures])
    if failures == 0:
        print("T095_NATIVE_PRESET_PACKED_PASSED")
    quit(1 if failures else 0)

func _initialize() -> void:
    call_deferred("run")
