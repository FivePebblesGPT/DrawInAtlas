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

struct DrawDelta {
    uint32_t index;
    uint32_t before;
    uint32_t after;
};

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
// the caller until an independent parity test approves a native sweep algorithm.
// operation: 0=source-over, 1=clear to canonical zero, 2=exact RGBA8 replace.
// Optional mask is one byte per view pixel. Repeated coordinates blend once.
// On any negative return, source, output and deltas are left untouched.
// Deltas contain only changed pixel indices and canonical before/after bytes.
DRAW_EXPORT int32_t draw_batch(const uint8_t* source, uint8_t* output,
                               int32_t width, int32_t height,
                               const int32_t* points, int32_t count,
                               uint32_t rgba, int32_t operation,
                               const uint8_t* mask, DrawDelta* deltas,
                               int32_t delta_capacity) {
    if (source == nullptr || output == nullptr || source == output ||
        width <= 0 || height <= 0 || width > 2048 || height > 2048 ||
        count < 0 || count > 1048576 || delta_capacity < 0 ||
        (count != 0 && points == nullptr) || (delta_capacity > 0 && deltas == nullptr) ||
        operation < 0 || operation > 2) return -1;
    const size_t pixels = size_t(width) * size_t(height);
    for (int32_t index = 0; index < count; ++index) {
        if (points[index * 2] < 0 || points[index * 2] >= width ||
            points[index * 2 + 1] < 0 || points[index * 2 + 1] >= height)
            return -2;
    }
    std::vector<uint8_t> scratch(source, source + pixels * 4);
    std::vector<uint8_t> visited(pixels, 0);
    std::vector<DrawDelta> pending;
    pending.reserve(size_t(std::min(count, delta_capacity)));
    for (int32_t index = 0; index < count; ++index) {
        const size_t pixel = size_t(points[index * 2 + 1]) * size_t(width) +
                             size_t(points[index * 2]);
        if (visited[pixel] != 0 || (mask != nullptr && mask[pixel] == 0)) continue;
        visited[pixel] = 1;
        const uint32_t before = read_rgba(source + pixel * 4);
        const uint32_t after = operation == 1 ? 0U :
            operation == 2 ? rgba : draw_source_over(rgba, before);
        if (before == after) continue;
        if (pending.size() >= size_t(delta_capacity)) return -3;
        write_rgba(scratch.data() + pixel * 4, after);
        pending.push_back({uint32_t(pixel), before, after});
    }
    std::memcpy(output, scratch.data(), pixels * 4);
    if (!pending.empty()) std::memcpy(deltas, pending.data(), pending.size() * sizeof(DrawDelta));
    return int32_t(pending.size());
}
