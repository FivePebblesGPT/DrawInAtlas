// T-068 opt-in Blend2D 0.21.2 brush/mask screen. No application linkage.
// SPDX-License-Identifier: MIT
#include <blend2d/blend2d.h>

#include <algorithm>
#include <chrono>
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
using Clock = std::chrono::steady_clock;
uint64_t elapsed_ns(Clock::time_point since) noexcept {
    return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - since).count());
}
bool overlaps(const void* a, size_t len_a, const void* b, size_t len_b) noexcept {
    const auto x = reinterpret_cast<uintptr_t>(a);
    const auto y = reinterpret_cast<uintptr_t>(b);
    if (len_a > std::numeric_limits<uintptr_t>::max() - x ||
        len_b > std::numeric_limits<uintptr_t>::max() - y) return true;
    return x < y + len_b && y < x + len_a;
}
uint8_t round8(double value) noexcept {
    return uint8_t(std::clamp(long(std::lround(value)), 0L, 255L));
}

// Keep DrawingEditSession's straight-RGBA8 source-over and half-away rounding;
// Blend2D is used for COVERAGE ONLY, never for canonical pixel storage.
void source_over(uint8_t* target, const uint8_t* paint) noexcept {
    const double sa = paint[3] / 255.0;
    if (sa <= 0.0) return; // Preserve hidden RGB of zero-alpha source-over.
    const double da = target[3] / 255.0;
    const double alpha = sa + da * (1.0 - sa);
    const double inv = da * (1.0 - sa);
    for (int c = 0; c < 3; ++c)
        target[c] = round8((paint[c] * sa + target[c] * inv) / alpha);
    target[3] = round8(alpha * 255.0);
}
} // namespace

/// Research-only ABI version: must be checked before binding the brush entrypoint.
T068_EXPORT int32_t t068_blend2d_brush_abi_version() noexcept { return 1; }

/// Draw one complete stroke into a temporary Blend2D A8 stencil, then apply
/// the *binary* selection and canonical RGBA8 compositor exactly once/pixel.
/// This is an isolated benchmark ABI, NOT a Drawing native module.
/// @param source Exact straight-RGBA8 (side²*4 bytes), never modified.
/// @param *_bytes Explicit byte capacities, including point pairs and outputs.
/// @param output Detached straight-RGBA8, only written upon success.
/// @param coverage Returned binary 0/255 postselection stencil, only on success.
/// @param selection Exactly side² bytes of 0/1 eligibility, not an AA mask.
/// @param points Flat pairs of local raster-space double x/y coordinates.
/// @param threshold A8 alpha threshold 1..255; Blend2D AA is thresholded.
/// @param draw_ns Synchronous stencil setup+render+end (not Godot/USB/GPU).
/// @param composite_ns Selection and canonical RGBA8 CPU pass (no publication).
/// @return Changed pixel count, or -1 invalid args, -2 Blend2D failure,
///         -3 nonbinary selection, -4 allocation failure. All negative returns
///         leave output buffers and timing counters intact.
T068_EXPORT int32_t t068_blend2d_brush(
    const uint8_t* source, uint64_t source_bytes, uint8_t* output,
    uint64_t output_bytes, uint8_t* coverage, uint64_t coverage_bytes,
    const uint8_t* selection, uint64_t selection_bytes,
    int32_t side, const double* points, uint64_t point_bytes,
    int32_t point_count, double width,
    uint32_t argb, int32_t erase, int32_t threshold, uint64_t* draw_ns,
    uint64_t* composite_ns) noexcept {
    if (side < 1 || side > 2048 || !source || !output || !coverage || !selection ||
        !points || !draw_ns || !composite_ns || source == output ||
        point_count < 1 || point_count > 128 || !std::isfinite(width) ||
        width <= 0 || width > 512 || erase < 0 || erase > 1 ||
        threshold < 1 || threshold > 255) return -1;
    const size_t count = size_t(side) * size_t(side);
    if (source_bytes != count * 4U || output_bytes != count * 4U ||
        selection_bytes != count || coverage_bytes != count ||
        point_bytes != uint64_t(point_count) * 2U * sizeof(double)) return -1;
    // Timing pointers are outputs too: they must not alias any input or output
    // buffer, nor each other. Otherwise a successful call can mutate "const"
    // source bytes or corrupt a delivered pixel buffer after validation.
    for (const auto* timing : {draw_ns, composite_ns}) {
        if (overlaps(timing, sizeof(uint64_t), source, count * 4U) ||
            overlaps(timing, sizeof(uint64_t), selection, count) ||
            overlaps(timing, sizeof(uint64_t), points, size_t(point_bytes)) ||
            overlaps(timing, sizeof(uint64_t), output, count * 4U) ||
            overlaps(timing, sizeof(uint64_t), coverage, count)) return -1;
    }
    if (overlaps(draw_ns, sizeof(uint64_t), composite_ns, sizeof(uint64_t))) return -1;
    if (overlaps(output, count * 4U, source, count * 4U) ||
        overlaps(output, count * 4U, selection, count) ||
        overlaps(output, count * 4U, points, point_bytes) ||
        overlaps(coverage, count, source, count * 4U) ||
        overlaps(coverage, count, selection, count) ||
        overlaps(coverage, count, points, point_bytes) ||
        overlaps(output, count * 4U, coverage, count)) return -1;
    for (int32_t i = 0; i < point_count * 2; ++i)
        if (!std::isfinite(points[i]) || points[i] < -2.0 * side ||
            points[i] > 3.0 * side) return -1;
    for (size_t i = 0; i < count; ++i)
        if (selection[i] != 0U && selection[i] != 1U) return -3;

    try {
    std::vector<uint8_t> stencil(count, 0);
    const auto draw_start = Clock::now();
    BLImage image;
    if (image.create_from_data(side, side, BL_FORMAT_A8, stencil.data(), side) != BL_SUCCESS)
        return -2;
    BLContext context;
    if (context.begin(image) != BL_SUCCESS) return -2;
    BLResult result = context.set_comp_op(BL_COMP_OP_SRC_COPY);
    if (result == BL_SUCCESS) {
        if (point_count == 1) {
            result = context.set_fill_style(BLRgba32(0xffffffffU));
            if (result == BL_SUCCESS)
                result = context.fill_circle(points[0], points[1], width * 0.5);
        } else {
            BLPath path;
            result = path.move_to(points[0], points[1]);
            for (int32_t i = 1; i < point_count && result == BL_SUCCESS; ++i)
                result = path.line_to(points[i * 2], points[i * 2 + 1]);
            if (result == BL_SUCCESS) result = context.set_stroke_style(BLRgba32(0xffffffffU));
            if (result == BL_SUCCESS) result = context.set_stroke_width(width);
            if (result == BL_SUCCESS) result = context.set_stroke_caps(BL_STROKE_CAP_ROUND);
            if (result == BL_SUCCESS) result = context.set_stroke_join(BL_STROKE_JOIN_ROUND);
            if (result == BL_SUCCESS) result = context.stroke_path(path);
        }
    }
    const BLResult end = context.end();
    if (result != BL_SUCCESS || end != BL_SUCCESS) return -2;
    const uint64_t draw_time = elapsed_ns(draw_start);

    const auto composite_start = Clock::now();
    std::vector<uint8_t> staged(source, source + count * 4U);
    std::vector<uint8_t> staged_coverage(count, 0);
    const uint8_t paint[4] = {uint8_t(argb >> 16U), uint8_t(argb >> 8U),
                              uint8_t(argb), uint8_t(argb >> 24U)};
    int32_t changed = 0;
    for (size_t i = 0; i < count; ++i) {
        if (selection[i] == 0U || stencil[i] < uint8_t(threshold)) continue;
        staged_coverage[i] = 255U;
        uint8_t* pixel = staged.data() + i * 4U;
        const uint8_t before[4] = {pixel[0], pixel[1], pixel[2], pixel[3]};
        if (erase == 1) {
            std::memset(pixel, 0, 4U);
        } else {
            source_over(pixel, paint);
        }
        if (std::memcmp(before, pixel, 4U) != 0) ++changed;
    }
    const uint64_t composite_time = elapsed_ns(composite_start);
    std::memcpy(output, staged.data(), count * 4U);
    std::memcpy(coverage, staged_coverage.data(), count);
    *draw_ns = draw_time;
    *composite_ns = composite_time;
    return changed;
    } catch (const std::bad_alloc&) {
        return -4;  // A large detached tile could not be allocated; outputs untouched.
    }
}
