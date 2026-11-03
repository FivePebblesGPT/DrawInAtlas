// T-068 opt-in Godot 4.8 beta 2 benchmark bridge. Never loaded by the app.
// SPDX-License-Identifier: MIT
#include "gdextension_interface.h"
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

struct DrawDelta {
    uint32_t index, before, after;
};
extern "C" int32_t draw_batch_checked(const uint8_t*, uint64_t,
    uint8_t*, uint64_t, int32_t, int32_t, const int32_t*, uint64_t,
    int32_t, uint32_t, int32_t, const uint8_t*, uint64_t,
    DrawDelta*, uint64_t, int32_t);

namespace {
GDExtensionClassLibraryPtr library = nullptr;
GDExtensionInterfaceStringNameNewWithLatin1Chars make_name = nullptr;
GDExtensionInterfaceVariantGetPtrDestructor get_destructor = nullptr;
GDExtensionInterfaceVariantGetPtrConstructor get_constructor = nullptr;
GDExtensionInterfaceVariantGetPtrBuiltinMethod get_builtin = nullptr;
GDExtensionInterfacePackedByteArrayOperatorIndexConst byte_at = nullptr;
GDExtensionInterfacePackedByteArrayOperatorIndex byte_at_mutable = nullptr;
GDExtensionInterfacePackedInt32ArrayOperatorIndexConst int_at = nullptr;
GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class = nullptr;
GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method = nullptr;
GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class = nullptr;
GDExtensionInterfaceClassdbConstructObject3 construct_object = nullptr;
GDExtensionInterfaceObjectSetInstance set_instance = nullptr;
GDExtensionInterfaceGetVariantFromTypeConstructor from_type = nullptr;
GDExtensionInterfaceGetVariantToTypeConstructor to_type = nullptr;
GDExtensionInterfaceVariantGetType variant_type = nullptr;
GDExtensionInterfaceVariantNewNil new_nil = nullptr;

GDExtensionPtrBuiltInMethod byte_size = nullptr, int_size = nullptr, byte_resize = nullptr;
GDExtensionPtrConstructor byte_constructor = nullptr;
GDExtensionPtrDestructor byte_destructor = nullptr, int_destructor = nullptr;
GDExtensionVariantFromTypeConstructorFunc variant_from_bytes = nullptr;
GDExtensionTypeFromVariantConstructorFunc bytes_from_variant = nullptr, ints_from_variant = nullptr, integer_from_variant = nullptr;

alignas(16) unsigned char class_name[64]{};
alignas(16) unsigned char object_name[64]{};
struct NativeInstance {};

struct Name {
    alignas(16) unsigned char bytes[64]{};
    explicit Name(const char* text) { make_name(bytes, text, 1); }
    ~Name() = default; // static string literals are interned for process lifetime
    void* data() { return bytes; }
};

int64_t packed_size(const void* value, GDExtensionPtrBuiltInMethod method) {
    int64_t size = -1;
    method(const_cast<void*>(value), nullptr, &size, 0);
    return size;
}

// Both ptrcall and generic Variant-call paths use this function. The returned
// PackedByteArray is initialized even on error; an empty array means failure.
void process(const void* source, const void* points, const void* mask,
             int64_t width, int64_t height, int64_t rgba, int64_t operation,
             void* result) {
    byte_constructor(result, nullptr);
    try {
    if (width <= 0 || height <= 0 || width > 2048 || height > 2048 ||
        operation < 0 || operation > 2 || rgba < 0 ||
        uint64_t(rgba) > uint64_t(UINT32_MAX)) return;
    const int64_t pixels = width * height;
    const int64_t source_len = packed_size(source, byte_size);
    const int64_t point_len = packed_size(points, int_size);
    const int64_t mask_len = packed_size(mask, byte_size);
    if (source_len != pixels * 4 || point_len < 0 || point_len % 2 != 0 ||
        point_len / 2 > 1048576 || (mask_len != 0 && mask_len != pixels)) return;
    const auto* input = byte_at(source, 0);
    const auto* coords = point_len != 0 ? int_at(points, 0) : nullptr;
    const auto* eligibility = mask_len != 0 ? byte_at(mask, 0) : nullptr;
    const int32_t count = int32_t(point_len / 2);
    // Allocate detached native output and deltas. Nothing mutates Godot's input.
    std::vector<uint8_t> output(static_cast<size_t>(source_len), 0U);
    std::vector<DrawDelta> deltas(size_t(std::min<int64_t>(count, pixels)));
    const int32_t changed = draw_batch_checked(input, uint64_t(source_len),
        output.data(), uint64_t(source_len), int32_t(width), int32_t(height),
        coords, uint64_t(point_len * sizeof(int32_t)), count, uint32_t(rgba),
        int32_t(operation), eligibility, uint64_t(mask_len),
        deltas.empty() ? nullptr : deltas.data(),
        uint64_t(deltas.size() * sizeof(DrawDelta)), int32_t(deltas.size()));
    if (changed < 0) return;
    const int64_t bytes = source_len;
    const void* args[] = {&bytes};
    int64_t resize_result = -1;
    byte_resize(result, args, &resize_result, 1);
    if (resize_result != 0) return;
    std::memcpy(byte_at_mutable(result, 0), output.data(), size_t(source_len));
    } catch (...) {
        // No C++ exception may cross Godot's C callback boundary.
        const int64_t zero = 0;
        const void* args[] = {&zero};
        int64_t ignored = -1;
        byte_resize(result, args, &ignored, 1);
    }
}

void ptrcall(void*, GDExtensionClassInstancePtr,
             const GDExtensionConstTypePtr* args, GDExtensionTypePtr result) {
    process(args[0], args[1], args[2],
        *static_cast<const int64_t*>(args[3]), *static_cast<const int64_t*>(args[4]),
        *static_cast<const int64_t*>(args[5]), *static_cast<const int64_t*>(args[6]), result);
}

void call(void*, GDExtensionClassInstancePtr,
          const GDExtensionConstVariantPtr* args, GDExtensionInt argc,
          GDExtensionVariantPtr result, GDExtensionCallError* error) {
    error->error = GDEXTENSION_CALL_OK;
    if (argc != 7) {
        error->error = argc < 7 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS :
                                   GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = 7;
        new_nil(result);
        return;
    }
    const GDExtensionVariantType expected[] = {
        GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT,
        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT};
    for (int i = 0; i < 7; ++i) {
        if (variant_type(args[i]) != expected[i]) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            error->argument = i;
            error->expected = expected[i];
            new_nil(result);
            return;
        }
    }
    alignas(16) unsigned char src[64]{}, coords[64]{}, mask[64]{}, output[64]{};
    bytes_from_variant(src, const_cast<void*>(args[0]));
    ints_from_variant(coords, const_cast<void*>(args[1]));
    bytes_from_variant(mask, const_cast<void*>(args[2]));
    int64_t integers[4]{};
    for (int i = 0; i < 4; ++i)
        integer_from_variant(&integers[i], const_cast<void*>(args[i + 3]));
    process(src, coords, mask, integers[0], integers[1], integers[2], integers[3], output);
    variant_from_bytes(result, output);
    byte_destructor(output);
    byte_destructor(mask);
    int_destructor(coords);
    byte_destructor(src);
}

GDExtensionObjectPtr create_instance(void*, GDExtensionBool) {
    GDExtensionObjectPtr object = construct_object(object_name);
    if (!object) return nullptr;
    set_instance(object, class_name, new NativeInstance{});
    return object;
}
void free_instance(void*, GDExtensionClassInstancePtr instance) {
    delete static_cast<NativeInstance*>(instance);
}

void initialize(void*, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    make_name(class_name, "T068RasterBench", 1);
    make_name(object_name, "Object", 1);
    Name method_name("apply_checked");
    Name size_name("size"), resize_name("resize");
    byte_size = get_builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, size_name.data(), 3173160232);
    int_size = get_builtin(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, size_name.data(), 3173160232);
    byte_resize = get_builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, resize_name.data(), 848867239);
    byte_constructor = get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    byte_destructor = get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    int_destructor = get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    variant_from_bytes = from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    bytes_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    ints_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    integer_from_variant = to_type(GDEXTENSION_VARIANT_TYPE_INT);
    GDExtensionClassCreationInfo6 klass{};
    klass.is_exposed = 1;
    klass.create_instance_func = create_instance;
    klass.free_instance_func = free_instance;
    register_class(library, class_name, object_name, &klass);

    const char* arg_names[] = {"source", "points", "mask", "width", "height", "rgba", "operation"};
    const GDExtensionVariantType types[] = {
        GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT,
        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT};
    std::vector<Name> names;
    names.reserve(7);
    for (const auto* name : arg_names) names.emplace_back(name);
    GDExtensionPropertyInfo args[7]{};
    for (int i = 0; i < 7; ++i) {
        args[i].type = types[i];
        args[i].name = names[size_t(i)].data();
        args[i].usage = 6; // PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE
    }
    Name return_name("");
    alignas(16) unsigned char empty_string[64]{};
    get_constructor(GDEXTENSION_VARIANT_TYPE_STRING, 0)(empty_string, nullptr);
    for (auto& arg : args) {
        arg.class_name = return_name.data();
        arg.hint_string = empty_string;
    }
    GDExtensionPropertyInfo ret{};
    ret.type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
    ret.name = return_name.data();
    ret.class_name = return_name.data();
    ret.hint_string = empty_string;
    ret.usage = 6;
    GDExtensionClassMethodInfo method{};
    method.name = method_name.data();
    method.call_func = call;
    method.ptrcall_func = ptrcall;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    method.has_return_value = 1;
    method.return_value_info = &ret;
    method.argument_count = 7;
    method.arguments_info = args;
    GDExtensionClassMethodArgumentMetadata metadata[7]{};
    method.arguments_metadata = metadata;
    register_method(library, class_name, &method);
    if (auto destroy = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING))
        destroy(empty_string);
}

void uninitialize(void*, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    unregister_class(library, class_name);
    // Static StringNames must not be destroyed.
}

template <typename T> bool load(GDExtensionInterfaceGetProcAddress get,
                                 T& output, const char* name) {
    output = reinterpret_cast<T>(get(name));
    return output != nullptr;
}
} // namespace

extern "C" GDExtensionBool t068_raster_bridge_init(
    GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr lib,
    GDExtensionInitialization* initialization) {
    library = lib;
    return load(get, make_name, "string_name_new_with_latin1_chars") &&
        load(get, get_destructor, "variant_get_ptr_destructor") &&
        load(get, get_constructor, "variant_get_ptr_constructor") &&
        load(get, get_builtin, "variant_get_ptr_builtin_method") &&
        load(get, byte_at, "packed_byte_array_operator_index_const") &&
        load(get, byte_at_mutable, "packed_byte_array_operator_index") &&
        load(get, int_at, "packed_int32_array_operator_index_const") &&
        load(get, register_class, "classdb_register_extension_class6") &&
        load(get, register_method, "classdb_register_extension_class_method") &&
        load(get, unregister_class, "classdb_unregister_extension_class") &&
        load(get, construct_object, "classdb_construct_object3") &&
        load(get, set_instance, "object_set_instance") &&
        load(get, from_type, "get_variant_from_type_constructor") &&
        load(get, to_type, "get_variant_to_type_constructor") &&
        load(get, variant_type, "variant_get_type") &&
        load(get, new_nil, "variant_new_nil") &&
        (initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE,
         initialization->initialize = initialize,
         initialization->deinitialize = uninitialize, true);
}
