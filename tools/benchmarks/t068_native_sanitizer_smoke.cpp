// T-068 detached native ABI ASan/UBSan regression. Not linked by either app.
// SPDX-License-Identifier: MIT
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <vector>

extern "C" int32_t t068_quad_scope_mask(uint8_t*, uint64_t, int32_t,
    const double*, uint64_t, double, const double*, uint64_t, int32_t, int32_t) noexcept;
extern "C" int32_t t068_scalar_hard_brush(uint8_t*, uint64_t, const uint8_t*,
    uint64_t, int32_t, const double*, uint64_t, int32_t, double) noexcept;
extern "C" int32_t t068_scalar_hard_brush_rgba8(uint8_t*, uint64_t, uint8_t*,
    uint64_t, const uint8_t*, uint64_t, const uint8_t*, uint64_t,
    int32_t, const double*, uint64_t, int32_t, double,
    const uint8_t*, uint64_t, int32_t) noexcept;
extern "C" int32_t t068_scalar_hard_brush_deltas(uint8_t*, uint64_t,
    const uint8_t*, uint64_t, const uint8_t*, uint64_t, int32_t,
    const double*, uint64_t, int32_t, double,
    const uint8_t*, uint64_t, int32_t) noexcept;

namespace {
uint32_t state = 0x6804826u;
int checks = 0;
int rejected = 0;
int cases = 0;
int changed_total = 0;
int covered_total = 0;
uint64_t signature = 14695981039346656037ULL;

uint32_t random32() noexcept {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

void digest(const uint8_t* bytes, size_t size) noexcept {
    for (size_t i = 0; i < size; ++i) {
        signature ^= bytes[i];
        signature *= 1099511628211ULL;
    }
}

bool require(bool condition, const char* label) noexcept {
    ++checks;
    if (!condition) std::fprintf(stderr, "T068_SANITIZER_FAILURE: %s\n", label);
    return condition;
}

uint32_t read32(const uint8_t* p) noexcept {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) |
           (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

bool do_case(int trial) {
    const int side = trial == 0 ? 8 : 1 + int(random32() % 23);
    const size_t pixels = size_t(side) * size_t(side);
    std::vector<uint8_t> mask(pixels + 2, 0xA5);
    // The integer offsets avoid a manufactured all-edge numerical tie; the
    // dedicated Godot-authored corpora cover float32 edge compatibility.
    const double left = 0.25 + double(random32() % 6);
    const double top = 0.25 + double(random32() % 6);
    const double right = left + 3.5 + double(random32() % 11);
    const double bottom = top + 3.5 + double(random32() % 11);
    const std::array<double, 8> polygon = {
        left, top, right, top, right, bottom, left, bottom
    };
    const std::array<double, 6> transform = {1., 0., 0., 1., 0., 0.};
    const int32_t selected = t068_quad_scope_mask(mask.data() + 1, pixels, side,
        transform.data(), sizeof(transform), 1.0, polygon.data(), sizeof(polygon), 4, 1);
    if (!require(selected >= 0, "valid quad result") ||
        !require(mask.front() == 0xA5 && mask.back() == 0xA5, "quad redzones") ||
        !require(std::count(mask.begin() + 1, mask.end() - 1, uint8_t(1)) == selected,
                 "quad count")) return false;
    for (int y = 0; y < side; ++y) for (int x = 0; x < side; ++x) {
        // Corners must all be inside this axis-aligned rectangle. The native
        // result is independently verified away from approximate boundaries.
        const uint8_t expected = (double(x) >= left && double(x + 1) <= right &&
                                  double(y) >= top && double(y + 1) <= bottom) ? 1 : 0;
        if (!require(mask[1 + size_t(y) * side + x] == expected, "quad geometry")) return false;
    }
    digest(mask.data() + 1, pixels);
    std::vector<uint8_t> selection(mask.begin() + 1, mask.end() - 1);
    std::vector<uint8_t> source(pixels * 4);
    for (uint8_t& component : source) component = uint8_t(random32() & 255U);
    const std::array<double, 4> points = {
        double(random32() % uint32_t(side)), double(random32() % uint32_t(side)),
        double(random32() % uint32_t(side)), double(random32() % uint32_t(side))
    };
    const double width = 1. + double(random32() % 8);
    const std::array<uint8_t, 4> paint = {uint8_t(random32()), uint8_t(random32()),
                                          uint8_t(random32()), uint8_t(random32())};
    const int erase = trial % 5 == 0 ? 1 : 0;
    std::vector<uint8_t> coverage(pixels + 2, 0xA5);
    std::vector<uint8_t> rgba(pixels * 4 + 2, 0xA5);
    const int32_t covered = t068_scalar_hard_brush_rgba8(
        rgba.data() + 1, source.size(), coverage.data() + 1, pixels,
        source.data(), source.size(), selection.data(), selection.size(),
        side, points.data(), sizeof(points), 2, width, paint.data(), paint.size(), erase);
    if (!require(covered >= 0, "valid full RGBA result") ||
        !require(rgba.front() == 0xA5 && rgba.back() == 0xA5 &&
                 coverage.front() == 0xA5 && coverage.back() == 0xA5, "RGBA redzones") ||
        !require(std::count(coverage.begin() + 1, coverage.end() - 1, uint8_t(255)) == covered,
                 "coverage count")) return false;
    std::vector<uint8_t> plain_coverage(pixels, 0xA5);
    const int32_t raw_covered = t068_scalar_hard_brush(
        plain_coverage.data(), pixels, selection.data(), pixels,
        side, points.data(), sizeof(points), 2, width);
    if (!require(raw_covered == covered &&
        std::equal(coverage.begin() + 1, coverage.end() - 1, plain_coverage.begin()),
        "coverage/full consistency")) return false;
    const size_t capacity = 4 + pixels * 12;
    std::vector<uint8_t> sparse(capacity + 2, 0xA5);
    const int32_t changed = t068_scalar_hard_brush_deltas(
        sparse.data() + 1, capacity, source.data(), source.size(),
        selection.data(), pixels, side, points.data(), sizeof(points), 2,
        width, paint.data(), paint.size(), erase);
    if (!require(changed >= 0, "valid sparse result") ||
        !require(sparse.front() == 0xA5 && sparse.back() == 0xA5, "sparse redzones") ||
        !require(read32(sparse.data() + 1) == uint32_t(changed), "sparse count")) return false;
    std::vector<uint8_t> rebuilt(source);
    uint32_t previous = 0;
    for (int i = 0; i < changed; ++i) {
        const uint8_t* record = sparse.data() + 1 + 4 + size_t(i) * 12;
        const uint32_t index = read32(record);
        if (!require(index < pixels && (i == 0 || index > previous), "ordered sparse index") ||
            !require(std::memcmp(record + 4, source.data() + index * 4, 4) == 0,
                     "sparse original")) return false;
        std::memcpy(rebuilt.data() + index * 4, record + 8, 4);
        previous = index;
    }
    if (!require(std::equal(rebuilt.begin(), rebuilt.end(), rgba.begin() + 1),
                 "full/delta reconstruction")) return false;
    digest(rebuilt.data(), rebuilt.size());
    digest(coverage.data() + 1, pixels);
    covered_total += covered;
    changed_total += changed;
    ++cases;
    return true;
}

bool invalid_cases() {
    constexpr int side = 8;
    constexpr uint64_t pixels = 64;
    std::array<uint8_t, pixels> output{};
    output.fill(0xA5);
    std::array<uint8_t, pixels> selection{};
    selection.fill(1);
    const std::array<double, 6> transform = {1., 0., 0., 1., 0., 0.};
    const std::array<double, 8> polygon = {2.25, 2.25, 6.25, 2.25, 6.25, 6.25, 2.25, 6.25};
    const std::array<double, 4> points = {2., 2., 5., 5.};
    const std::array<uint8_t, 4> paint = {255, 0, 80, 125};
    std::vector<uint8_t> rgba(pixels * 4, 0xA5);
    std::array<uint8_t, pixels> coverage{};
    coverage.fill(0xA5);
    std::vector<uint8_t> sparse(4 + pixels * 12, 0xA5);
    std::vector<uint8_t> source(pixels * 4, 0x19);
    const auto is_atomic = [](int code, const uint8_t* ptr, size_t len) {
        ++checks;
        if (code >= 0 || !std::all_of(ptr, ptr + len, [](uint8_t p) { return p == 0xA5; })) {
            std::fputs("T068_SANITIZER_FAILURE: non-atomic rejected call\n", stderr);
            return false;
        }
        ++rejected;
        return true;
    };
    std::array<double, 6> bad_transform = transform;
    bad_transform[0] = std::numeric_limits<double>::quiet_NaN();
    if (!is_atomic(t068_quad_scope_mask(output.data(), pixels, side,
        bad_transform.data(), sizeof(bad_transform), 1, polygon.data(), sizeof(polygon), 4, 1),
        output.data(), pixels)) return false;
    if (!is_atomic(t068_quad_scope_mask(output.data(), pixels - 1, side,
        transform.data(), sizeof(transform), 1, polygon.data(), sizeof(polygon), 4, 1),
        output.data(), pixels)) return false;
    if (!is_atomic(t068_quad_scope_mask(output.data(), pixels, side,
        transform.data(), sizeof(transform), 1, polygon.data(), sizeof(polygon) - 8, 4, 1),
        output.data(), pixels)) return false;
    if (!is_atomic(t068_quad_scope_mask(output.data(), pixels, side,
        transform.data(), sizeof(transform), 1, polygon.data(), sizeof(polygon), 2, 1),
        output.data(), pixels)) return false;
    if (!is_atomic(t068_quad_scope_mask(output.data(), pixels, side,
        reinterpret_cast<const double*>(output.data()), 48, 1,
        polygon.data(), sizeof(polygon), 4, 1), output.data(), pixels)) return false;
    if (!is_atomic(t068_quad_scope_mask(output.data(), pixels, side,
        transform.data(), sizeof(transform), std::numeric_limits<double>::infinity(),
        polygon.data(), sizeof(polygon), 4, 1), output.data(), pixels)) return false;
    if (!is_atomic(t068_scalar_hard_brush(output.data(), pixels, selection.data(), pixels,
        side, points.data(), sizeof(points), 2, std::numeric_limits<double>::quiet_NaN()),
        output.data(), pixels)) return false;
    if (!is_atomic(t068_scalar_hard_brush(output.data(), pixels - 1, selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2), output.data(), pixels)) return false;
    if (!is_atomic(t068_scalar_hard_brush(output.data(), pixels, selection.data(), pixels,
        side, points.data(), sizeof(points) - 8, 2, 2), output.data(), pixels)) return false;
    std::array<uint8_t, pixels> bad_selection = selection;
    bad_selection[3] = 2;
    if (!is_atomic(t068_scalar_hard_brush(output.data(), pixels, bad_selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2), output.data(), pixels)) return false;
    if (!is_atomic(t068_scalar_hard_brush(output.data(), pixels, output.data(), pixels,
        side, points.data(), sizeof(points), 2, 2), output.data(), pixels)) return false;
    if (!is_atomic(t068_scalar_hard_brush_rgba8(rgba.data(), rgba.size(),
        coverage.data(), pixels, source.data(), source.size(), selection.data(), pixels,
        side, points.data(), sizeof(points), 2, std::numeric_limits<double>::infinity(),
        paint.data(), 4, 0), rgba.data(), rgba.size()) ||
        !require(std::all_of(coverage.begin(), coverage.end(), [](uint8_t v) { return v == 0xA5; }),
                 "rejected coverage atomicity")) return false;
    if (!is_atomic(t068_scalar_hard_brush_rgba8(rgba.data(), rgba.size(),
        coverage.data(), pixels, source.data(), source.size(), selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2, paint.data(), 3, 0),
        rgba.data(), rgba.size())) return false;
    if (!is_atomic(t068_scalar_hard_brush_rgba8(rgba.data(), rgba.size(),
        rgba.data(), pixels, source.data(), source.size(), selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2, paint.data(), 4, 0),
        rgba.data(), rgba.size())) return false;
    if (!is_atomic(t068_scalar_hard_brush_deltas(sparse.data(), sparse.size(),
        source.data(), source.size(), selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2, paint.data(), 4, 2),
        sparse.data(), sparse.size())) return false;
    if (!is_atomic(t068_scalar_hard_brush_deltas(sparse.data(), 4,
        source.data(), source.size(), selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2, paint.data(), 4, 0),
        sparse.data(), sparse.size())) return false;
    if (!is_atomic(t068_scalar_hard_brush_deltas(sparse.data(), sparse.size(),
        source.data(), source.size(), selection.data(), pixels,
        side, points.data(), sizeof(points), 2, 2, paint.data(), 3, 0),
        sparse.data(), sparse.size())) return false;
    return true;
}
}  // namespace

int main() {
    if (!invalid_cases()) return 1;
    for (int i = 0; i < 256; ++i)
        if (!do_case(i)) return 1;
    std::printf("T068_SANITIZER_OK cases=%d checks=%d rejected=%d covered=%d changed=%d digest=%016llx\n",
        cases, checks, rejected, covered_total, changed_total,
        static_cast<unsigned long long>(signature));
    return 0;
}
