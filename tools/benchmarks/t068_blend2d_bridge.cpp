// T-068 opt-in Blend2D CPU comparator; never linked into Drawing or Atlas.
// SPDX-License-Identifier: MIT
#include <blend2d/blend2d.h>

#include <chrono>
#include <cstdint>

#if defined(_WIN32)
#define T068_EXPORT extern "C" __declspec(dllexport)
#else
#define T068_EXPORT extern "C" __attribute__((visibility("default")))
#endif

/// Draw one hard-edged rectangle on caller-owned little-endian PRGB32 bytes.
/// The caller must convert from/to canonical straight RGBA8 explicitly.
/// @param pixels Writable pre-multiplied BGRA bytes, not canonical RGBA8.
/// @param bytes Actual caller-declared buffer length; memory ownership is not proven.
/// @param operation 0: source-over, 1: exact source-copy, 2: clear.
/// @param context_ns Synchronous context creation, render, and end time, in ns.
/// @return 0 for success, -1 invalid arguments, -2 Blend2D failure.
T068_EXPORT int32_t t068_blend2d_draw(uint8_t* pixels, uint64_t bytes,
                                      int32_t side, int32_t x, int32_t y,
                                      int32_t width, int32_t height,
                                      uint32_t argb, int32_t operation,
                                      uint64_t* context_ns) noexcept {
    if (!pixels || !context_ns || side < 1 || side > 512 ||
        bytes != uint64_t(side) * uint64_t(side) * 4U ||
        x < 0 || y < 0 || width <= 0 || height <= 0 ||
        width > side - x || height > side - y ||
        operation < 0 || operation > 2) return -1;

    BLImage image;
    if (image.create_from_data(side, side, BL_FORMAT_PRGB32,
                               pixels, intptr_t(side) * 4) != BL_SUCCESS) return -2;
    BLContext context;
    const auto start = std::chrono::steady_clock::now();
    if (context.begin(image) != BL_SUCCESS) return -2;
    const BLCompOp comp_op = operation == 0 ? BL_COMP_OP_SRC_OVER :
                             operation == 1 ? BL_COMP_OP_SRC_COPY : BL_COMP_OP_CLEAR;
    const BLResult setup = context.set_comp_op(comp_op);
    const BLResult style = context.set_fill_style(BLRgba32(argb));
    const BLResult fill = setup == BL_SUCCESS && style == BL_SUCCESS ?
                          context.fill_rect(BLRectI(x, y, width, height)) : BL_ERROR_INVALID_STATE;
    const BLResult done = context.end(); // Includes synchronous flush.
    *context_ns = uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now() - start).count());
    return (setup == BL_SUCCESS && style == BL_SUCCESS && fill == BL_SUCCESS &&
            done == BL_SUCCESS) ? 0 : -2;
}
