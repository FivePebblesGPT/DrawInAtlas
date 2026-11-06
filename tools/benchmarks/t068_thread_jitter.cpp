// T-068: independent, experimental C++ kernel concurrency witness.
// SPDX-License-Identifier: MIT
// This is NOT an installed GDExtension, a frame-time test, or physical hardware approval.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

struct DrawDelta { uint32_t index, before, after; };
static_assert(sizeof(DrawDelta) == 12, "Unexpected kernel ABI layout");
extern "C" uint32_t draw_kernel_abi_version();
extern "C" int32_t draw_batch_deltas(const uint8_t*, int32_t, int32_t,
    const int32_t*, int32_t, uint32_t, int32_t, const uint8_t*, DrawDelta*, int32_t);
extern "C" int32_t draw_batch(const uint8_t*, uint8_t*, int32_t, int32_t,
    const int32_t*, int32_t, uint32_t, int32_t, const uint8_t*, DrawDelta*, int32_t);

struct Case {
    std::string name;
    int operation;
    uint32_t rgba;
    std::vector<int32_t> points;
    bool masked;
};

std::vector<Case> make_cases(int size) {
    std::vector<Case> result = {{"overlapping_source_over", 0, 0x88774422U, {}, false},
                                {"masked_erase", 1, 0U, {}, true},
                                {"exact_replace", 2, 0x00443322U, {}, false}};
    auto point = [](Case& item, int x, int y) {
        item.points.push_back(x); item.points.push_back(y);
    };
    const int mid = size / 2;
    for (int x = 12; x < size - 12; ++x) point(result[0], x, mid);
    for (int y = 12; y < size - 12; ++y) point(result[0], mid, y);
    const std::vector<int32_t> crossing = result[0].points;
    for (int i = int(crossing.size()) - 2; i >= 0; i -= 2)
        point(result[0], crossing[size_t(i)], crossing[size_t(i + 1)]);
    for (int y = 32; y < size - 32; ++y)
        for (int x = 32; x < size - 32; ++x) point(result[1], x, y);
    for (int y = 48; y < size - 48; ++y)
        for (int x = 48; x < size - 48; ++x) point(result[2], x, y);
    return result;
}

std::vector<uint8_t> make_source(int size) {
    std::vector<uint8_t> source(size_t(size) * size_t(size) * 4U);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            size_t pixel = (size_t(y) * size_t(size) + size_t(x)) * 4U;
            source[pixel] = uint8_t((x * 3 + y * 5) & 255);
            source[pixel + 1] = uint8_t((x * 13 + y) & 255);
            source[pixel + 2] = uint8_t((y * 7) & 255);
            source[pixel + 3] = uint8_t(((x + y) % 7) * 42);
        }
    }
    return source;
}

struct Buffers {
    std::vector<uint8_t> source, output, mask;
    std::vector<DrawDelta> deltas;
};

Buffers prepare(const std::vector<uint8_t>& source, const Case& test, int size) {
    Buffers buffer;
    buffer.source = source;
    buffer.output.resize(source.size());
    buffer.deltas.resize(test.points.size() / 2);
    if (test.masked) {
        buffer.mask.resize(size_t(size) * size_t(size));
        for (int y = 0; y < size; ++y)
            for (int x = 0; x < size; ++x)
                buffer.mask[size_t(y) * size_t(size) + size_t(x)] = uint8_t((x + y) % 3 != 0);
    }
    return buffer;
}

int run_kernel(Buffers& buffer, const Case& test, int size, bool sparse) {
    const auto count = int32_t(test.points.size() / 2);
    const uint8_t* mask = buffer.mask.empty() ? nullptr : buffer.mask.data();
    if (sparse) return draw_batch_deltas(buffer.source.data(), size, size,
        test.points.data(), count, test.rgba, test.operation, mask,
        buffer.deltas.data(), count);
    return draw_batch(buffer.source.data(), buffer.output.data(), size, size,
        test.points.data(), count, test.rgba, test.operation, mask,
        buffer.deltas.data(), count);
}

struct Worker {
    Buffers buffers;
    std::vector<double> milliseconds;
    int changed = -1;
};

// Nearest-rank order statistic; avoid interpolating synthetic p95 values.
double percentile(std::vector<double> values, int percent) {
    if (values.empty()) throw std::runtime_error("empty latency series");
    std::sort(values.begin(), values.end());
    return values[(values.size() * size_t(percent) + 99U) / 100U - 1U];
}

void measure(const std::vector<uint8_t>& source, const Case& test,
             int size, int worker_count, int trials, int warmups, bool sparse) {
    Buffers reference = prepare(source, test, size);
    const int expected = run_kernel(reference, test, size, sparse);
    if (expected < 0) throw std::runtime_error("reference native call failed");
    std::vector<Worker> workers(static_cast<size_t>(worker_count));
    for (Worker& worker : workers) {
        worker.buffers = prepare(source, test, size);
        worker.milliseconds.reserve(size_t(trials));
    }
    std::atomic<int> ready{0};
    std::atomic<bool> go{false};
    std::vector<std::thread> threads;
    threads.reserve(size_t(worker_count));
    for (int i = 0; i < worker_count; ++i) {
        threads.emplace_back([&, i] {
            Worker& worker = workers[size_t(i)];
            for (int n = 0; n < warmups; ++n)
                worker.changed = run_kernel(worker.buffers, test, size, sparse);
            ready.fetch_add(1, std::memory_order_release);
            while (!go.load(std::memory_order_acquire)) std::this_thread::yield();
            for (int n = 0; n < trials; ++n) {
                const auto begin = std::chrono::steady_clock::now();
                worker.changed = run_kernel(worker.buffers, test, size, sparse);
                const auto end = std::chrono::steady_clock::now();
                worker.milliseconds.push_back(
                    std::chrono::duration<double, std::milli>(end - begin).count());
            }
        });
    }
    while (ready.load(std::memory_order_acquire) != worker_count)
        std::this_thread::yield();
    go.store(true, std::memory_order_release);
    for (std::thread& thread : threads) thread.join();
    std::vector<double> combined;
    combined.reserve(size_t(trials) * size_t(worker_count));
    for (const Worker& worker : workers) {
        if (worker.changed != expected || worker.buffers.source != source)
            throw std::runtime_error("concurrent native source or result count mismatch");
        if (!std::equal(reference.deltas.begin(), reference.deltas.begin() + expected,
                        worker.buffers.deltas.begin(),
                        [](const DrawDelta& a, const DrawDelta& b) {
                            return a.index == b.index && a.before == b.before && a.after == b.after;
                        })) throw std::runtime_error("concurrent native pixel delta mismatch");
        if (!sparse && worker.buffers.output != reference.output)
            throw std::runtime_error("concurrent output pixels changed");
        combined.insert(combined.end(), worker.milliseconds.begin(), worker.milliseconds.end());
    }
    const double p50 = percentile(combined, 50);
    const double p95 = percentile(combined, 95);
    const double maximum = percentile(combined, 100);
    std::cout << test.name << '\t' << (sparse ? "sparse" : "full") << '\t'
              << worker_count << '\t' << trials << '\t' << test.points.size() / 2
              << '\t' << expected << '\t' << p50 << '\t' << p95 << '\t'
              << maximum << '\t' << combined.size() << "\n";
}

int main(int argc, char** argv) {
    try {
        if (argc < 4) throw std::runtime_error("usage: benchmark size trials workers...");
        const int size = std::stoi(argv[1]);
        const int trials = std::stoi(argv[2]);
        if (size < 128 || size > 1024 || size % 64 != 0 || trials < 3 || trials > 2000)
            throw std::runtime_error("invalid region or trial count");
        if (draw_kernel_abi_version() != 1) throw std::runtime_error("unsupported kernel ABI");
        const std::vector<uint8_t> source = make_source(size);
        std::cout << "case\tmode\tworkers\ttrials\tcandidates\tchanged\tmedian_ms\tp95_ms\tmax_ms\tchecked_calls\n";
        for (const Case& test : make_cases(size))
            for (bool sparse : {true, false})
                for (int i = 3; i < argc; ++i) {
                    const int workers = std::stoi(argv[i]);
                    if (workers < 1 || workers > 16)
                        throw std::runtime_error("invalid worker count");
                    measure(source, test, size, workers, trials, 3, sparse);
                }
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "T068_NATIVE_THREAD_JITTER_FAILED " << error.what() << "\n";
        return 2;
    }
}
