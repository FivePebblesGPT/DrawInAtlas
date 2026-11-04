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

namespace {
bool overlaps(const void* a, size_t len_a, const void* b, size_t len_b) noexcept {
    const auto x = reinterpret_cast<uintptr_t>(a);
    const auto y = reinterpret_cast<uintptr_t>(b);
    if (len_a > std::numeric_limits<uintptr_t>::max() - x ||
        len_b > std::numeric_limits<uintptr_t>::max() - y) return true;
    return x < y + len_b && y < x + len_a;
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
            const auto inside = [polygon, vertices](double x, double y) noexcept -> bool {
                bool found = false;
                for (int i = 0, j = vertices - 1; i < vertices; j = i++) {
                    const double xi = polygon[2 * i], yi = polygon[2 * i + 1];
                    const double xj = polygon[2 * j], yj = polygon[2 * j + 1];
                    // Godot Geometry2D.is_point_in_polygon includes points on
                    // an edge, unlike a conventional strict ray crossing.
                    const double dx = xj - xi, dy = yj - yi;
                    const double cross = (x - xi) * dy - (y - yi) * dx;
                    if (cross == 0.0 &&
                        x >= std::min(xi, xj) && x <= std::max(xi, xj) &&
                        y >= std::min(yi, yj) && y <= std::max(yi, yj)) return true;
                    if ((yi > y) != (yj > y) &&
                        x < dx * (y - yi) / dy + xi) found = !found;
                }
                return found;
            };
            for (int32_t y = 0; y < side; ++y) {
                for (int32_t x = 0; x < side; ++x) {
                    bool allowed = true;
                    for (int cy = 0; cy < 2 && allowed; ++cy) {
                        for (int cx = 0; cx < 2; ++cx) {
                            const double lx = (double(x) + cx) / density;
                            const double ly = (double(y) + cy) / density;
                            const double board_x = coefficients[0] * lx + coefficients[2] * ly + coefficients[4];
                            const double board_y = coefficients[1] * lx + coefficients[3] * ly + coefficients[5];
                            if (!std::isfinite(board_x) || !std::isfinite(board_y) ||
                                !inside(board_x, board_y)) {
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
