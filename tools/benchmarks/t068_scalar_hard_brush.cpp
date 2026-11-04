// T-068: isolated scalar hard-brush coverage comparator, NOT a runtime backend.
// SPDX-License-Identifier: MIT
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

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
