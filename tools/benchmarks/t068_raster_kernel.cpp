// T-068 isolated native CPU prototype; NOT a Godot GDExtension or installed backend.
// SPDX-License-Identifier: MIT
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

#if defined(_WIN32)
#define DRAW_EXPORT extern "C" __declspec(dllexport)
#else
#define DRAW_EXPORT extern "C" __attribute__((visibility("default")))
#endif

/// One changed straight-RGBA8 pixel in an operation-local, bounded region.
/// Layout is 3 little-endian uint32 values; ABI version 1 below.
struct DrawDelta {
    uint32_t index;
    uint32_t before;
    uint32_t after;
};

static_assert(sizeof(DrawDelta) == 12, "ABI requires 12-byte deltas");

/// Return the ABI version of the isolated native benchmark (NOT a GDExtension).
DRAW_EXPORT uint32_t draw_kernel_abi_version() { return 1; }

namespace {
uint32_t read_rgba(const uint8_t* data) {
    return uint32_t(data[0]) | (uint32_t(data[1]) << 8U) |
           (uint32_t(data[2]) << 16U) | (uint32_t(data[3]) << 24U);
}

void write_rgba(uint8_t* data, uint32_t rgba) {
    for (unsigned channel = 0; channel < 4; ++channel)
        data[channel] = uint8_t((rgba >> (channel * 8U)) & 255U);
}

int clamped_round(double value) {
    return std::clamp(int(std::lround(value)), 0, 255);
}
}

// Identical straight-RGBA8, 8-bit rounding semantics to DrawingEditSession._blend.
// A fully transparent *source* must retain the destination's hidden RGB bytes.
DRAW_EXPORT uint32_t draw_source_over(uint32_t source, uint32_t destination) {
    const double sa = double((source >> 24U) & 255U) / 255.0;
    if (sa <= 0.0) return destination;
    const double da = double((destination >> 24U) & 255U) / 255.0;
    const double alpha = sa + da * (1.0 - sa);
    uint32_t result = uint32_t(clamped_round(alpha * 255.0)) << 24U;
    for (unsigned channel = 0; channel < 3; ++channel) {
        const unsigned shift = channel * 8U;
        const double sc = double((source >> shift) & 255U);
        const double dc = double((destination >> shift) & 255U);
        result |= uint32_t(clamped_round((sc * sa + dc * da * (1.0 - sa)) / alpha)) << shift;
    }
    return result;
}

// Precovered view-relative coordinates, two ints each; sweep geometry stays with
// the caller until independent path parity tests approve a native sweep.
// operation: 0=source-over, 1=clear canonical zero, 2=exact RGBA8 replace.
// Optional mask is one byte per view pixel. Duplicate pixels blend once.
// All public functions are failure atomic: output and deltas remain untouched
// for every negative return. The source is never modified.
namespace {
int32_t collect_deltas(const uint8_t* source, int32_t width, int32_t height,
                       const int32_t* points, int32_t count, uint32_t rgba,
                       int32_t operation, const uint8_t* mask,
                       int32_t delta_capacity, std::vector<DrawDelta>& pending) {
    if (source == nullptr || width <= 0 || height <= 0 || width > 2048 ||
        height > 2048 || count < 0 || count > 1048576 || delta_capacity < 0 ||
        (count != 0 && points == nullptr) || operation < 0 || operation > 2)
        return -1;
    const size_t pixels = size_t(width) * size_t(height);
    for (int32_t index = 0; index < count; ++index) {
        if (points[index * 2] < 0 || points[index * 2] >= width ||
            points[index * 2 + 1] < 0 || points[index * 2 + 1] >= height)
            return -2;
    }
    // One visited bit per source pixel rather than a full byte or a dictionary.
    // This is temporary scratch, independent of unchanged RGBA8 source bytes.
    std::vector<uint64_t> visited((pixels + 63U) / 64U, 0U);
    pending.reserve(size_t(std::min(count, delta_capacity)));
    for (int32_t index = 0; index < count; ++index) {
        const size_t pixel = size_t(points[index * 2 + 1]) * size_t(width) +
                             size_t(points[index * 2]);
        if (mask != nullptr && mask[pixel] == 0) continue;
        const size_t word = pixel >> 6U;
        const uint64_t bit = uint64_t(1) << (pixel & 63U);
        if ((visited[word] & bit) != 0U) continue;
        visited[word] |= bit;
        const uint32_t before = read_rgba(source + pixel * 4);
        const uint32_t after = operation == 1 ? 0U :
            operation == 2 ? rgba : draw_source_over(rgba, before);
        if (before == after) continue;
        if (pending.size() >= size_t(delta_capacity)) return -3;
        pending.push_back({uint32_t(pixel), before, after});
    }
    return int32_t(pending.size());
}
} // namespace

/// Compute a batch of detached changed pixels without copying the edit region.
/// @param source Immutable, exact straight-RGBA8 region (width * height * 4 bytes).
/// @param points Flat x/y int32 pixel coordinates, with `count` pairs.
/// @param mask Optional byte-per-pixel eligibility mask, 0 means excluded.
/// @param deltas Caller-owned capacity-limited output; untouched on error.
/// @return Number of deltas, or -1 invalid arguments, -2 bad coordinate,
///         -3 insufficient capacity. The caller must check source revision and
///         apply the deltas to detached data before atomic publication.
/// @note This is an isolated C ABI prototype, not an integrated GDExtension.
DRAW_EXPORT int32_t draw_batch_deltas(const uint8_t* source,
                                      int32_t width, int32_t height,
                                      const int32_t* points, int32_t count,
                                      uint32_t rgba, int32_t operation,
                                      const uint8_t* mask, DrawDelta* deltas,
                                      int32_t delta_capacity) {
    if (delta_capacity > 0 && deltas == nullptr) return -1;
    std::vector<DrawDelta> pending;
    const int32_t outcome = collect_deltas(source, width, height, points, count,
                                            rgba, operation, mask, delta_capacity,
                                            pending);
    if (outcome < 0) return outcome;
    if (outcome > 0) std::memcpy(deltas, pending.data(), pending.size() * sizeof(DrawDelta));
    return outcome;
}

/// Compatibility benchmark API, returning a full detached output region.
/// @param output Caller-owned RGBA8 buffer; never touched on negative returns.
/// @param deltas Caller-owned array of individual before/after changes.
/// @return Number of edited pixels or the same error codes as draw_batch_deltas.
/// @note Validation precedes the single complete-region copy; on error neither
///       the output nor the delta buffer is modified.
DRAW_EXPORT int32_t draw_batch(const uint8_t* source, uint8_t* output,
                               int32_t width, int32_t height,
                               const int32_t* points, int32_t count,
                               uint32_t rgba, int32_t operation,
                               const uint8_t* mask, DrawDelta* deltas,
                               int32_t delta_capacity) {
    if (output == nullptr || source == output ||
        (delta_capacity > 0 && deltas == nullptr)) return -1;
    std::vector<DrawDelta> pending;
    const int32_t outcome = collect_deltas(source, width, height, points, count,
                                            rgba, operation, mask, delta_capacity,
                                            pending);
    if (outcome < 0) return outcome;
    const size_t pixel_count = size_t(width) * size_t(height);
    std::memcpy(output, source, pixel_count * 4);
    for (const DrawDelta& delta : pending)
        write_rgba(output + size_t(delta.index) * 4, delta.after);
    if (outcome > 0) std::memcpy(deltas, pending.data(), pending.size() * sizeof(DrawDelta));
    return outcome;
}

// The opt-in length-checked boundary does not change the original ABI 1
// entrypoints, which are used by existing benchmarking clients.
// It can reject short caller-declared buffers before touching any memory, but
// it cannot prove that a C pointer genuinely owns its declared number of bytes.
DRAW_EXPORT uint32_t draw_kernel_checked_api_version() { return 1; }

namespace {
/// Check two caller-declared ranges without performing undefined pointer arithmetic.
/// Reject address overflow rather than accepting a potentially wrapped range.
bool valid_range(const void* pointer, uint64_t bytes) {
    if (bytes == 0) return true;
    if (pointer == nullptr) return false;
    return bytes <= uint64_t(UINTPTR_MAX - reinterpret_cast<uintptr_t>(pointer));
}

bool intersects(const void* left, uint64_t left_bytes,
                const void* right, uint64_t right_bytes) {
    if (left_bytes == 0 || right_bytes == 0) return false;
    const uintptr_t a = reinterpret_cast<uintptr_t>(left);
    const uintptr_t b = reinterpret_cast<uintptr_t>(right);
    return a < b + right_bytes && b < a + left_bytes;
}

struct CheckedRegion {
    uint64_t source_bytes;
    uint64_t point_bytes;
    uint64_t mask_bytes;
    uint64_t delta_bytes;
};

/// -1 invalid operation/shape, -5 missing/short buffers, -6 unsafe aliasing.
int32_t check_buffers(const uint8_t* source, uint64_t source_capacity,
                      int32_t width, int32_t height,
                      const int32_t* points, uint64_t points_capacity, int32_t count,
                      int32_t operation, const uint8_t* mask, uint64_t mask_capacity,
                      const DrawDelta* deltas, uint64_t delta_capacity_bytes,
                      int32_t delta_capacity, CheckedRegion& size) {
    if (width <= 0 || height <= 0 || width > 2048 || height > 2048 ||
        count < 0 || count > 1048576 || delta_capacity < 0 ||
        operation < 0 || operation > 2) return -1;
    const uint64_t pixels = uint64_t(width) * uint64_t(height);
    size = {pixels * 4U, uint64_t(count) * 2U * sizeof(int32_t),
            mask == nullptr ? 0U : pixels,
            uint64_t(delta_capacity) * sizeof(DrawDelta)};
    if (source == nullptr || source_capacity < size.source_bytes ||
        (points == nullptr && (count != 0 || points_capacity != 0)) ||
        points_capacity < size.point_bytes ||
        (mask == nullptr && mask_capacity != 0) || mask_capacity < size.mask_bytes ||
        (deltas == nullptr && (delta_capacity != 0 || delta_capacity_bytes != 0)) ||
        delta_capacity_bytes < size.delta_bytes ||
        !valid_range(source, size.source_bytes) ||
        !valid_range(points, size.point_bytes) ||
        !valid_range(mask, size.mask_bytes) ||
        !valid_range(deltas, size.delta_bytes)) return -5;
    if (intersects(deltas, size.delta_bytes, source, size.source_bytes) ||
        intersects(deltas, size.delta_bytes, points, size.point_bytes) ||
        intersects(deltas, size.delta_bytes, mask, size.mask_bytes)) return -6;
    return 0;
}
} // namespace

/// Bounded-buffer counterpart of draw_batch_deltas().
/// @param source_bytes Accessible bytes at source (at least width*height*4).
/// @param point_bytes Accessible bytes at points (at least count*2*sizeof(int32_t)).
/// @param mask_bytes Accessible mask bytes; must be zero for a null mask.
/// @param delta_bytes Accessible bytes at deltas (at least capacity*sizeof(DrawDelta)).
/// @return >=0 changed pixels; -1 invalid shape, -2 bad coordinate,
///         -3 delta capacity, -4 internal C++ exception, -5 short/invalid buffer,
///         -6 alias with caller-owned output. No output is changed on errors.
/// @warning Declared capacities must reflect real allocations; an arbitrary
///          foreign C pointer cannot be independently memory-probed.
DRAW_EXPORT int32_t draw_batch_deltas_checked(
        const uint8_t* source, uint64_t source_bytes,
        int32_t width, int32_t height,
        const int32_t* points, uint64_t point_bytes, int32_t count,
        uint32_t rgba, int32_t operation,
        const uint8_t* mask, uint64_t mask_bytes,
        DrawDelta* deltas, uint64_t delta_bytes, int32_t delta_capacity) {
    CheckedRegion size{};
    const int32_t check = check_buffers(source, source_bytes, width, height,
        points, point_bytes, count, operation, mask, mask_bytes,
        deltas, delta_bytes, delta_capacity, size);
    if (check != 0) return check;
    try {
        return draw_batch_deltas(source, width, height, points, count,
                                 rgba, operation, mask, deltas, delta_capacity);
    } catch (...) {
        return -4;
    }
}

/// Bounded-buffer counterpart of draw_batch(). The output region must be
/// disjoint from all inputs and deltas, including partial overlaps.
DRAW_EXPORT int32_t draw_batch_checked(
        const uint8_t* source, uint64_t source_bytes,
        uint8_t* output, uint64_t output_bytes,
        int32_t width, int32_t height,
        const int32_t* points, uint64_t point_bytes, int32_t count,
        uint32_t rgba, int32_t operation,
        const uint8_t* mask, uint64_t mask_bytes,
        DrawDelta* deltas, uint64_t delta_bytes, int32_t delta_capacity) {
    CheckedRegion size{};
    const int32_t check = check_buffers(source, source_bytes, width, height,
        points, point_bytes, count, operation, mask, mask_bytes,
        deltas, delta_bytes, delta_capacity, size);
    if (check != 0) return check;
    if (output == nullptr || output_bytes < size.source_bytes ||
        !valid_range(output, size.source_bytes)) return -5;
    if (intersects(output, size.source_bytes, source, size.source_bytes) ||
        intersects(output, size.source_bytes, points, size.point_bytes) ||
        intersects(output, size.source_bytes, mask, size.mask_bytes) ||
        intersects(output, size.source_bytes, deltas, size.delta_bytes)) return -6;
    try {
        return draw_batch(source, output, width, height, points, count,
                          rgba, operation, mask, deltas, delta_capacity);
    } catch (...) {
        return -4;
    }
}
