// T-068: isolated scalar hard-brush coverage comparator, NOT a runtime backend.
// SPDX-License-Identifier: MIT
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

// The hard brush validates NaN/Inf widths and pointer samples before writing.
// Fast-math can remove these checks (GCC -Ofast accepts NaN and overwrites
// the output), violating the detached ABI's failure-atomicity contract.
#if defined(__FAST_MATH__)
#error "T-068 scalar brush requires strict floating-point semantics (no -ffast-math/-Ofast)"
#endif

#if defined(_WIN32)
#define T068_EXPORT extern "C" __declspec(dllexport)
#else
#define T068_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
struct Point {
    float x;
    float y;
};

bool overlap(const void* a, uint64_t a_bytes, const void* b, uint64_t b_bytes) noexcept {
    const uintptr_t x = reinterpret_cast<uintptr_t>(a);
    const uintptr_t y = reinterpret_cast<uintptr_t>(b);
    if (a_bytes > std::numeric_limits<uintptr_t>::max() - x ||
        b_bytes > std::numeric_limits<uintptr_t>::max() - y) return true;
    return x < y + uintptr_t(b_bytes) && y < x + uintptr_t(a_bytes);
}

// Godot's hard brush tests the distance from a transformed pixel center to
// each segment, not whether a third-party antialiased stencil passes a cutoff.
bool touched(Point center, const std::vector<Point>& path, float radius) noexcept {
    for (size_t i = 0; i < path.size(); ++i) {
        const Point a = path[i == 0 ? 0 : i - 1];
        const Point b = path[i];
        const float dx = b.x - a.x, dy = b.y - a.y;
        const float squared = dx * dx + dy * dy;
        const float t = squared > 0.0f
            ? std::clamp(((center.x - a.x) * dx + (center.y - a.y) * dy) / squared, 0.0f, 1.0f)
            : 0.0f;
        const float ex = center.x - (a.x + t * dx);
        const float ey = center.y - (a.y + t * dy);
        if (std::sqrt(ex * ex + ey * ey) <= radius) return true;
    }
    return false;
}

uint8_t round_channel(double value) noexcept {
    return uint8_t(std::clamp(std::lround(value), 0L, 255L));
}

// DrawingEditSession's straight-RGBA8 source-over, never a premultiplied
// transfer. An alpha-zero paint must not destroy transparent hidden RGB.
void composite(uint8_t* destination, const uint8_t* paint, bool erase) noexcept {
    if (erase) {
        std::memset(destination, 0, 4);
        return;
    }
    const double sa = double(paint[3]) / 255.0;
    if (sa <= 0.0) return;
    const double da = double(destination[3]) / 255.0;
    const double inv = da * (1.0 - sa);
    const double alpha = sa + inv;
    for (int c = 0; c < 3; ++c)
        destination[c] = round_channel((paint[c] * sa + destination[c] * inv) / alpha);
    destination[3] = round_channel(alpha * 255.0);
}
} // namespace

/// Research-only, scalar, local-pixel hard brush ABI. Return the complete 0/255
/// once-per-gesture coverage after a binary selection (0/1). Pointer samples
/// are already mapped to raster-local coordinates. Output remains untouched on
/// failure; no Godot, Blend2D, texture or publication timing is included.
/// @return Covered pixels, -1 malformed sizes/aliases/nonfinite input,
///         -3 invalid mask, -4 allocation failure.
T068_EXPORT int32_t t068_scalar_hard_brush(
    uint8_t* output, uint64_t output_bytes,
    const uint8_t* selection, uint64_t selection_bytes,
    int32_t side, const double* points, uint64_t point_bytes,
    int32_t point_count, double width) noexcept {
    if (!output || !selection || !points || side < 1 || side > 2048 ||
        point_count < 1 || point_count > 128 || !std::isfinite(width) ||
        width <= 0.0 || width > 512.0) return -1;
    const uint64_t count = uint64_t(side) * uint64_t(side);
    if (output_bytes != count || selection_bytes != count ||
        point_bytes != uint64_t(point_count) * 2U * sizeof(double) ||
        overlap(output, count, selection, count) ||
        overlap(output, count, points, point_bytes)) return -1;
    for (uint64_t i = 0; i < count; ++i)
        if (selection[i] != 0 && selection[i] != 1) return -3;
    for (int32_t i = 0; i < point_count * 2; ++i)
        if (!std::isfinite(points[i]) || points[i] < -2.0 * side ||
            points[i] > 3.0 * side) return -1;
    try {
        std::vector<Point> path;
        path.reserve(size_t(point_count));
        for (int i = 0; i < point_count; ++i)
            path.push_back({float(points[2 * i]), float(points[2 * i + 1])});
        std::vector<uint8_t> staged(size_t(count), 0);
        int32_t covered = 0;
        for (int32_t y = 0; y < side; ++y) {
            for (int32_t x = 0; x < side; ++x) {
                const size_t index = size_t(y) * size_t(side) + size_t(x);
                if (!selection[index] || !touched({float(x) + 0.5f, float(y) + 0.5f}, path, float(width * 0.5)))
                    continue;
                staged[index] = 255;
                ++covered;
            }
        }
        std::memcpy(output, staged.data(), size_t(count));
        return covered;
    } catch (const std::bad_alloc&) {
        return -4;
    }
}


/// Research-only complete hard-brush raster+composite ABI. On success output
/// contains detached canonical straight-RGBA8 and coverage has 0/255 bytes.
/// Source/selection/paint/points are read-only. No output changes on failure,
/// including a malformed selection or any aliased output/input range.
/// This does NOT commit a DrawingDocument transaction or upload a texture.
/// @return Covered pixels; -1 malformed buffer/alias/operation, -3 bad mask,
///         -4 allocation failure. Outputs remain unchanged for all errors.
T068_EXPORT int32_t t068_scalar_hard_brush_rgba8(
    uint8_t* output, uint64_t output_bytes,
    uint8_t* coverage, uint64_t coverage_bytes,
    const uint8_t* source, uint64_t source_bytes,
    const uint8_t* selection, uint64_t selection_bytes,
    int32_t side, const double* points, uint64_t point_bytes,
    int32_t point_count, double width,
    const uint8_t* paint, uint64_t paint_bytes, int32_t erase) noexcept {
    if (!output || !coverage || !source || !selection || !points || !paint ||
        side < 1 || side > 2048 || (erase != 0 && erase != 1)) return -1;
    const uint64_t count = uint64_t(side) * uint64_t(side);
    const uint64_t rgba_bytes = count * 4U;
    if (output_bytes != rgba_bytes || source_bytes != rgba_bytes ||
        coverage_bytes != count || selection_bytes != count || paint_bytes != 4 ||
        overlap(output, rgba_bytes, coverage, count) ||
        overlap(output, rgba_bytes, source, rgba_bytes) ||
        overlap(output, rgba_bytes, selection, count) ||
        overlap(output, rgba_bytes, points, point_bytes) ||
        overlap(output, rgba_bytes, paint, 4) ||
        overlap(coverage, count, source, rgba_bytes) ||
        overlap(coverage, count, selection, count) ||
        overlap(coverage, count, points, point_bytes) ||
        overlap(coverage, count, paint, 4)) return -1;
    try {
        std::vector<uint8_t> staged_coverage(size_t(count), 0);
        const int32_t covered = t068_scalar_hard_brush(
            staged_coverage.data(), count, selection, selection_bytes,
            side, points, point_bytes, point_count, width);
        if (covered < 0) return covered;
        std::vector<uint8_t> staged_rgba(source, source + rgba_bytes);
        for (uint64_t i = 0; i < count; ++i)
            if (staged_coverage[size_t(i)] != 0)
                composite(staged_rgba.data() + size_t(i * 4), paint, erase != 0);
        std::memcpy(output, staged_rgba.data(), size_t(rgba_bytes));
        std::memcpy(coverage, staged_coverage.data(), size_t(count));
        return covered;
    } catch (const std::bad_alloc&) {
        return -4;
    }
}

/// Research-only sparse hard-brush RGBA8 edit wire format, shared with the
/// isolated Godot bridge: LE32 changed-count, then sorted 12-byte records
/// {LE32 pixel index, 4-byte before RGBA, 4-byte after RGBA}. Only actual
/// pixel changes are emitted; coverage-only alpha-zero gestures return a
/// four-byte zero count. No document revision or publication is performed.
/// All input is validated and records are staged before the caller's payload
/// is modified. Capacity shortage (-5), like other errors, is failure atomic.
/// @return Number of *changed* pixels, -1 malformed lengths/aliases/points,
///         -3 invalid selection, -4 allocation failure, -5 short payload.
T068_EXPORT int32_t t068_scalar_hard_brush_deltas(
    uint8_t* payload, uint64_t capacity,
    const uint8_t* source, uint64_t source_bytes,
    const uint8_t* selection, uint64_t selection_bytes,
    int32_t side, const double* points, uint64_t point_bytes,
    int32_t point_count, double width,
    const uint8_t* paint, uint64_t paint_bytes, int32_t erase) noexcept {
    if (!payload || !source || !selection || !points || !paint ||
        side < 1 || side > 2048 || point_count < 1 || point_count > 128 ||
        !std::isfinite(width) || width <= 0.0 || width > 512.0 ||
        (erase != 0 && erase != 1)) return -1;
    const uint64_t count = uint64_t(side) * uint64_t(side);
    const uint64_t rgba_bytes = count * 4U;
    if (capacity < 4 || capacity > 4 + count * 12U ||
        source_bytes != rgba_bytes || selection_bytes != count ||
        point_bytes != uint64_t(point_count) * 2U * sizeof(double) ||
        paint_bytes != 4 ||
        overlap(payload, capacity, source, rgba_bytes) ||
        overlap(payload, capacity, selection, count) ||
        overlap(payload, capacity, points, point_bytes) ||
        overlap(payload, capacity, paint, 4)) return -1;
    for (uint64_t i = 0; i < count; ++i)
        if (selection[i] > 1) return -3;
    for (int32_t i = 0; i < point_count * 2; ++i)
        if (!std::isfinite(points[i]) || points[i] < -2.0 * side ||
            points[i] > 3.0 * side) return -1;
    try {
        std::vector<Point> path;
        path.reserve(size_t(point_count));
        for (int32_t i = 0; i < point_count; ++i)
            path.push_back({float(points[2 * i]), float(points[2 * i + 1])});
        // A sparse record is twelve bytes. The source buffer remains
        // immutable and no full-tile output or coverage buffer is allocated.
        struct Record { uint32_t index; uint8_t before[4]; uint8_t after[4]; };
        std::vector<Record> changed;
        const float radius = float(width * 0.5);
        if (erase != 0 || paint[3] != 0) {
            for (int32_t y = 0; y < side; ++y) {
                for (int32_t x = 0; x < side; ++x) {
                    const size_t index = size_t(y) * size_t(side) + size_t(x);
                    if (!selection[index] ||
                        !touched({float(x) + 0.5f, float(y) + 0.5f}, path, radius)) continue;
                    Record record{};
                    record.index = uint32_t(index);
                    std::memcpy(record.before, source + index * 4, 4);
                    std::memcpy(record.after, record.before, 4);
                    composite(record.after, paint, erase != 0);
                    if (std::memcmp(record.before, record.after, 4) != 0)
                        changed.push_back(record);
                }
            }
        }
        const uint64_t needed = 4U + uint64_t(changed.size()) * 12U;
        if (needed > capacity) return -5;
        auto write32 = [payload](size_t offset, uint32_t value) noexcept {
            for (unsigned i = 0; i < 4; ++i)
                payload[offset + i] = uint8_t(value >> (i * 8U));
        };
        write32(0, uint32_t(changed.size()));
        for (size_t i = 0; i < changed.size(); ++i) {
            const size_t offset = 4 + i * 12;
            write32(offset, changed[i].index);
            std::memcpy(payload + offset + 4, changed[i].before, 4);
            std::memcpy(payload + offset + 8, changed[i].after, 4);
        }
        return int32_t(changed.size());
    } catch (const std::bad_alloc&) {
        return -4;
    }
}
