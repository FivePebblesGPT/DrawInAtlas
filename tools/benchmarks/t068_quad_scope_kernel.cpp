// T-068 detached four-corner convex polygon eligibility for the temporary
// GDExtension benchmark. Derived from the tested Blend2D scope shim; no
// Blend2D dependency and no production linkage. SPDX-License-Identifier: MIT
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

// Nonfinite-input rejection and Godot float32 near-edge parity require strict
// floating-point semantics. GCC -Ofast can erase std::isfinite() checks and
// publish an output mask for NaN transforms. Fail closed at build time even
// when fast-math is inherited from a parent project toolchain.
#if defined(__FAST_MATH__)
#error "T-068 quad scope requires strict floating-point semantics (no -ffast-math/-Ofast)"
#endif

namespace {
bool overlaps(const void* a, size_t len_a, const void* b, size_t len_b) noexcept {
    const auto x = reinterpret_cast<uintptr_t>(a);
    const auto y = reinterpret_cast<uintptr_t>(b);
    if (len_a > std::numeric_limits<uintptr_t>::max() - x ||
        len_b > std::numeric_limits<uintptr_t>::max() - y) return true;
    return x < y + len_b && y < x + len_a;
}

// Match the pinned Godot 4.8b2 Vector2/Geometry2D float32 path, including
// its approximate edge hit. A strict double-precision ray test misses legal
// near-edge pixels. This is a detached compatibility kernel, not a generic
// exact-geometry predicate (and not an application backend).
struct Vec2f {
    float x, y;
    Vec2f operator+(Vec2f v) const noexcept { return {x + v.x, y + v.y}; }
    Vec2f operator-(Vec2f v) const noexcept { return {x - v.x, y - v.y}; }
    Vec2f operator*(float v) const noexcept { return {x * v, y * v}; }
    Vec2f operator/(float v) const noexcept { return {x / v, y / v}; }
};

bool approximate(float left, float right) noexcept {
    return left == right || std::abs(left - right) <
        std::max(1.e-5f, 1.e-5f * std::abs(left));
}

bool segment_intersection(Vec2f from, Vec2f to, Vec2f other_from,
                          Vec2f other_to, Vec2f& intersection) noexcept {
    const Vec2f line = to - from;
    Vec2f a = other_from - from;
    Vec2f b = other_to - from;
    const float length_squared = line.x * line.x + line.y * line.y;
    if (length_squared <= 0.f) return false;
    const Vec2f normalized = line / length_squared;
    a = {a.x * normalized.x + a.y * normalized.y,
         a.y * normalized.x - a.x * normalized.y};
    b = {b.x * normalized.x + b.y * normalized.y,
         b.y * normalized.x - b.x * normalized.y};
    if ((a.y < -1.e-5f && b.y < -1.e-5f) ||
        (a.y > 1.e-5f && b.y > 1.e-5f) || approximate(a.y, b.y)) return false;
    const float position = b.x + (a.x - b.x) * b.y / (b.y - a.y);
    if (position < 0.f || position > 1.f) return false;
    intersection = from + line * position;
    return true;
}

bool godot_point_in_polygon(float x, float y, const double* polygon,
                            int32_t vertices) noexcept {
    Vec2f far = {-1.e20f, -1.e20f};
    Vec2f near = {1.e20f, 1.e20f};
    for (int32_t i = 0; i < vertices; ++i) {
        const Vec2f vertex = {float(polygon[2 * i]), float(polygon[2 * i + 1])};
        far = {std::max(far.x, vertex.x), std::max(far.y, vertex.y)};
        near = {std::min(near.x, vertex.x), std::min(near.y, vertex.y)};
    }
    const Vec2f extent = far - near;
    far = far + Vec2f{extent.x * 1.221313f, extent.y * 1.512312f};
    const Vec2f point = {x, y};
    int intersections = 0;
    for (int32_t i = 0; i < vertices; ++i) {
        const int32_t next = (i + 1) % vertices;
        const Vec2f v1 = {float(polygon[2 * i]), float(polygon[2 * i + 1])};
        const Vec2f v2 = {float(polygon[2 * next]), float(polygon[2 * next + 1])};
        Vec2f hit{};
        if (segment_intersection(v1, v2, point, far, hit)) {
            ++intersections;
            if (approximate(hit.x, x) && approximate(hit.y, y)) return true;
        }
    }
    return (intersections & 1) != 0;
}
}

extern "C" int32_t t068_quad_scope_mask(
    uint8_t* output, uint64_t output_bytes, int32_t side,
    const double* coefficients, uint64_t coefficient_bytes,
    double density, const double* polygon, uint64_t polygon_bytes,
    int32_t vertices, int32_t enabled) noexcept {
    if (!output || side < 1 || side > 2048 || !coefficients ||
        output_bytes != uint64_t(side) * uint64_t(side) ||
        coefficient_bytes != 6 * sizeof(double) ||
        !std::isfinite(density) || density <= 0.0 || density > 1024.0 ||
        (enabled != 0 && enabled != 1) || vertices < 0 || vertices > 32 ||
        polygon_bytes != uint64_t(vertices) * 2 * sizeof(double) ||
        (vertices != 0 && !polygon)) return -1;
    const size_t count = size_t(side) * size_t(side);
    if (overlaps(output, count, coefficients, coefficient_bytes) ||
        (vertices != 0 && overlaps(output, count, polygon, polygon_bytes))) return -1;
    for (int i = 0; i < 6; ++i)
        if (!std::isfinite(coefficients[i]) || std::abs(coefficients[i]) > 1.e9) return -1;
    const double determinant = coefficients[0] * coefficients[3] - coefficients[1] * coefficients[2];
    if (!std::isfinite(determinant) || std::abs(determinant) < 1.e-8) return -1;
    if (enabled && vertices != 0) {
        if (vertices < 3) return -3;
        for (int i = 0; i < vertices * 2; ++i)
            if (!std::isfinite(polygon[i]) || std::abs(polygon[i]) > 1.e9) return -3;
        double orientation = 0.0;
        for (int i = 0; i < vertices; ++i) {
            const int next = (i + 1) % vertices;
            const double ax = polygon[2 * i], ay = polygon[2 * i + 1];
            const double dx = polygon[2 * next] - ax, dy = polygon[2 * next + 1] - ay;
            if (dx == 0.0 && dy == 0.0) return -3;
            for (int j = 0; j < vertices; ++j) {
                const double cross = dx * (polygon[2 * j + 1] - ay) -
                                     dy * (polygon[2 * j] - ax);
                if (!std::isfinite(cross)) return -3;
                if (cross == 0.0) continue;
                if (orientation == 0.0) orientation = cross > 0.0 ? 1.0 : -1.0;
                else if (cross * orientation < 0.0) return -3;
            }
        }
        if (orientation == 0.0) return -3;
    }
    try {
        std::vector<uint8_t> staged(count, 0);
        int32_t selected = 0;
        if (!enabled) {
            std::fill(staged.begin(), staged.end(), uint8_t(1));
            selected = int32_t(count);
        } else if (vertices != 0) {
            for (int32_t y = 0; y < side; ++y) {
                for (int32_t x = 0; x < side; ++x) {
                    bool allowed = true;
                    for (int cy = 0; cy < 2 && allowed; ++cy) {
                        for (int cx = 0; cx < 2; ++cx) {
                            const float lx = float((double(x) + cx) / density);
                            const float ly = float((double(y) + cy) / density);
                            const float board_x = float(coefficients[0]) * lx + float(coefficients[2]) * ly + float(coefficients[4]);
                            const float board_y = float(coefficients[1]) * lx + float(coefficients[3]) * ly + float(coefficients[5]);
                            if (!std::isfinite(board_x) || !std::isfinite(board_y) ||
                                !godot_point_in_polygon(board_x, board_y, polygon, vertices)) {
                                allowed = false;
                                break;
                            }
                        }
                    }
                    if (allowed) {
                        staged[size_t(y) * size_t(side) + size_t(x)] = 1;
                        ++selected;
                    }
                }
            }
        }
        std::memcpy(output, staged.data(), count);
        return selected;
    } catch (const std::bad_alloc&) {
        return -4;
    }
}
