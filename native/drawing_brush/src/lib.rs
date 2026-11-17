//! Versioned Hokusai preset stroke transactions and native tile editing.
//! The T-148 tile store is implemented independently; production Canvas still
//! uses its transitional GDScript source adapter pending the T-149 cutover.
mod native_tiles;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use godot::classes::IRefCounted;
use godot::prelude::*;
use hokusai::mapping::SettingValue;
use hokusai::{Brush, BrushSetting, BrushState, TILE_SIZE, TiledSurface};

type TileSnapshot = Option<Box<hokusai::tile::TilePixels>>;

/// Hokusai-compatible sparse tile surface with per-batch dirty tracking.
/// Unlike the stock MemSurface, the owned tile map can remove a newly created
/// tile on rollback. Repeated rejected source reads must not retain blank
/// native tiles and silently grow a long-lived brush stroke's memory.
#[derive(Default)]
struct TrackedSurface {
    tiles: HashMap<(i32, i32), Box<hokusai::tile::TilePixels>>,
    changed: HashSet<(i32, i32)>,
    atomic_dirty: HashSet<(i32, i32)>,
    in_atomic: bool,
    /// Copy-on-first-write source tiles for the unacknowledged GDScript batch.
    /// None means the tile did not exist before the native call.
    before_batch: Option<HashMap<(i32, i32), TileSnapshot>>,
}

impl TrackedSurface {
    fn begin_batch(&mut self) {
        self.before_batch = Some(HashMap::new());
    }

    fn commit_batch(&mut self) {
        self.before_batch = None;
    }

    fn rollback_batch(&mut self) {
        if let Some(before) = self.before_batch.take() {
            for (position, previous) in before {
                if let Some(previous) = previous {
                    self.tiles.insert(position, previous);
                } else {
                    self.tiles.remove(&position);
                }
            }
        }
        self.changed.clear();
        self.atomic_dirty.clear();
        self.in_atomic = false;
    }

    fn tile(&self, x: i32, y: i32) -> Option<&hokusai::tile::TilePixels> {
        self.tiles.get(&(x, y)).map(Box::as_ref)
    }
}

impl TiledSurface for TrackedSurface {
    fn tile_request_start(&mut self, x: i32, y: i32) -> &mut hokusai::tile::TilePixels {
        let key = (x, y);
        if self
            .before_batch
            .as_ref()
            .is_some_and(|before| !before.contains_key(&key))
        {
            let previous = self.tiles.get(&key).cloned();
            self.before_batch
                .as_mut()
                .expect("active preset transaction")
                .insert(key, previous);
        }
        self.changed.insert(key);
        if self.in_atomic {
            self.atomic_dirty.insert(key);
        }
        self.tiles
            .entry(key)
            .or_insert_with(|| Box::new([[[0; 4]; TILE_SIZE]; TILE_SIZE]))
            .as_mut()
    }

    fn tile_request_end(&mut self, _x: i32, _y: i32) {}

    fn tile_lookup(&self, x: i32, y: i32) -> Option<&hokusai::tile::TilePixels> {
        self.tile(x, y)
    }

    fn begin_atomic(&mut self) {
        self.in_atomic = true;
        self.atomic_dirty.clear();
    }

    fn end_atomic(&mut self) -> Vec<(i32, i32)> {
        self.in_atomic = false;
        self.atomic_dirty.drain().collect()
    }
}

/// Quantized output plus the last observed native fixed-point pixels. Most
/// Hokusai dabs touch only a small part of an already painted 64px tile.
/// Comparing the cheap fixed-point values before sRGB conversion avoids
/// converting all 4096 pixels again at every native batch boundary.
#[derive(Clone)]
struct ExportedTile {
    raw: Vec<[u16; 4]>,
    rgba: Vec<u32>,
}

impl Default for ExportedTile {
    fn default() -> Self {
        Self {
            raw: vec![[0; 4]; TILE_SIZE * TILE_SIZE],
            rgba: vec![0; TILE_SIZE * TILE_SIZE],
        }
    }
}

fn quantize_pixel(pixel: &[u16; 4]) -> u32 {
    let alpha = hokusai::fix15::to_f32(pixel[3]).clamp(0.0, 1.0);
    let mut rgba = 0_u32;
    for (index, &channel) in pixel.iter().take(3).enumerate() {
        let linear = if alpha > 0.0 {
            hokusai::fix15::to_f32(channel) / alpha
        } else {
            0.0
        };
        let value = (hokusai::color::linear_to_srgb(linear).clamp(0.0, 1.0) * 255.0).round() as u32;
        rgba |= value << (8 * index);
    }
    rgba | (((alpha * 255.0).round() as u32) << 24)
}

/// Only changed quantized bytes are exported, even when the native fixed-point
/// value changed within the same 8-bit bucket. Never use raw equality to
/// decide whether a pixel must be re-composited in DrawingDocument.
fn scan_changed_pixels(
    tile: &hokusai::tile::TilePixels,
    published: &mut ExportedTile,
    mut emit: impl FnMut(usize, u32),
) {
    for (row, tile_row) in tile.iter().enumerate() {
        for (column, pixel) in tile_row.iter().enumerate() {
            let index = row * TILE_SIZE + column;
            if published.raw[index] == *pixel {
                continue;
            }
            published.raw[index] = *pixel;
            let rgba = quantize_pixel(pixel);
            if rgba != published.rgba[index] {
                published.rgba[index] = rgba;
                emit(index, rgba);
            }
        }
    }
}

struct PresetBatch {
    state: BrushState,
    /// Only quantized caches for touched tiles are journaled, never the
    /// entire accumulated pigment surface or preview for a long gesture.
    published: HashMap<(i32, i32), Option<ExportedTile>>,
}

struct PresetStroke {
    brush: Brush,
    state: BrushState,
    surface: TrackedSurface,
    /// Last exported raw fixed-point and straight-alpha RGBA8 pixels. A
    /// quantized repeat must not re-enter GDScript staging or invalidate a
    /// detached preview, even when the underlying native surface changed.
    published: HashMap<(i32, i32), ExportedTile>,
}

/// The ABI is v1; handle and source revision must accompany every operation.
/// One DrawingNativeBrush owns at most one live stroke; transaction handles are
/// globally monotonic to reject stale calls even across distinct instances.
const STROKE_ABI_VERSION: i32 = 1;
const MAX_BATCH_SAMPLES: usize = 4096;
const MAX_EXPORTED_INTS: usize = 3 * 1_048_576;
static NEXT_STROKE_HANDLE: AtomicU64 = AtomicU64::new(1);

struct BrushSample {
    point: Vector2,
    pressure: f32,
    delta_seconds: f32,
}

fn parse_samples(values: &[f32]) -> Result<Vec<BrushSample>, &'static str> {
    if values.is_empty() || !values.len().is_multiple_of(4) || values.len() > MAX_BATCH_SAMPLES * 4
    {
        return Err("Expected 1..4096 packed [x,y,pressure,delta_seconds] samples");
    }
    let mut samples = Vec::with_capacity(values.len() / 4);
    for data in values.as_chunks::<4>().0 {
        if !data[0].is_finite()
            || !data[1].is_finite()
            || data[0].abs() >= 1_000_000_000.0
            || data[1].abs() >= 1_000_000_000.0
            || !data[2].is_finite()
            || !(0.0..=1.0).contains(&data[2])
            || !data[3].is_finite()
            || !(0.0..=1.0).contains(&data[3])
            || data[3] == 0.0
        {
            return Err("Invalid signed sample coordinate, pressure, or delta seconds");
        }
        samples.push(BrushSample {
            point: Vector2::new(data[0], data[1]),
            pressure: data[2],
            delta_seconds: data[3],
        });
    }
    Ok(samples)
}

struct NativeStroke {
    handle: i64,
    layer: String,
    source_revision: i64,
    rgba: i64,
    clip: Rect2i,
    preset: PresetStroke,
    pending: Option<PresetBatch>,
    preview: Vec<i32>,
    ffi_calls: i64,
    batches: i64,
    input_floats: i64,
    emitted_ints: i64,
    // Opt-in T-188 profiling: raster, delta scan, tile store apply, ack, tile discovery.
    phase_us: [u64; 5],
}

impl NativeStroke {
    fn acknowledge(&mut self, accepted: bool) -> bool {
        let Some(snapshot) = self.pending.take() else {
            return false;
        };
        if accepted {
            self.preset.surface.commit_batch();
            self.batches += 1;
        } else {
            self.preset.surface.rollback_batch();
            self.preset.state = snapshot.state;
            for (key, previous) in snapshot.published {
                if let Some(previous) = previous {
                    self.preset.published.insert(key, previous);
                } else {
                    self.preset.published.remove(&key);
                }
            }
        }
        self.preview.clear();
        true
    }

    fn append(&mut self, samples: &[BrushSample]) -> Result<(), &'static str> {
        if self.pending.is_some() {
            return Err("Previous native sample batch needs acknowledgement");
        }
        self.pending = Some(PresetBatch {
            state: self.preset.state.clone(),
            published: HashMap::new(),
        });
        self.preset.surface.begin_batch();
        let raster_start = Instant::now();
        for sample in samples {
            self.preset.brush.stroke_to(
                &mut self.preset.state,
                &mut self.preset.surface,
                sample.point.x,
                sample.point.y,
                sample.pressure,
                0.0,
                0.0,
                sample.delta_seconds as f64,
            );
        }
        self.phase_us[0] += raster_start.elapsed().as_micros() as u64;
        let scan_start = Instant::now();
        let mut output = Vec::new();
        let mut dirty: Vec<_> = self.preset.surface.changed.drain().collect();
        dirty.sort_unstable();
        for (tx, ty) in dirty {
            let Some(tile) = self.preset.surface.tile(tx, ty) else {
                continue;
            };
            if let Some(snapshot) = self.pending.as_mut() {
                snapshot
                    .published
                    .entry((tx, ty))
                    .or_insert_with(|| self.preset.published.get(&(tx, ty)).cloned());
            }
            let exported = self.preset.published.entry((tx, ty)).or_default();
            scan_changed_pixels(tile, exported, |index, rgba| {
                output.extend_from_slice(&[
                    tx * TILE_SIZE as i32 + (index % TILE_SIZE) as i32,
                    ty * TILE_SIZE as i32 + (index / TILE_SIZE) as i32,
                    rgba as i32,
                ]);
            });
        }
        if output.len() > MAX_EXPORTED_INTS {
            self.acknowledge(false);
            return Err("Native sample delta exceeds batch output limit");
        }
        self.phase_us[1] += scan_start.elapsed().as_micros() as u64;
        self.input_floats += (samples.len() * 4) as i64;
        self.emitted_ints += output.len() as i64;
        self.preview = output;
        Ok(())
    }
}

fn error_result(message: &str) -> Dictionary<Variant, Variant> {
    let mut result = Dictionary::new();
    result.set("ok", false);
    result.set("error", message);
    result
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct DrawingNativeBrush {
    base: Base<RefCounted>,
    stroke: Option<NativeStroke>,
}

#[godot_api]
impl IRefCounted for DrawingNativeBrush {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, stroke: None }
    }
}

#[godot_api]
impl DrawingNativeBrush {
    /// Versioned API: one instance owns one stroke, whose opaque handle and
    /// Godot-owned source revision authorize all following calls.
    #[func]
    fn stroke_abi_version(&self) -> i32 {
        STROKE_ABI_VERSION
    }

    /// Frozen at pointer-down: layer, MyPaint preset, width, color,
    /// edit revision and signed relative clip. Transform/selection are frozen
    /// and enforced by the DrawingEditSession adapter until T-148.
    // The frozen source options are intentionally explicit at this ABI boundary.
    #[allow(clippy::too_many_arguments)]
    #[func]
    fn begin_stroke(
        &mut self,
        layer: GString,
        preset_text: GString,
        width: f32,
        rgba: i64,
        source_revision: i64,
        clip: Rect2i,
    ) -> Dictionary<Variant, Variant> {
        if self.stroke.is_some() {
            return error_result("Native brush already has a live stroke");
        }
        if layer.is_empty()
            || !width.is_finite()
            || !(0.0..=4096.0).contains(&width)
            || width == 0.0
            || !(0..=0xffffffff).contains(&rgba)
            || source_revision < 0
            || clip.size.x < 0
            || clip.size.y < 0
            || (clip.position.x as i64 + clip.size.x as i64) > i32::MAX as i64
            || (clip.position.y as i64 + clip.size.y as i64) > i32::MAX as i64
        {
            return error_result("Invalid stroke layer, color, width, revision, or clip");
        }
        let Ok(mut brush) = hokusai::myb::from_str(&preset_text.to_string()) else {
            return error_result("Invalid Hokusai .myb preset");
        };
        let r = (rgba & 255) as f32 / 255.0;
        let g = ((rgba >> 8) & 255) as f32 / 255.0;
        let b = ((rgba >> 16) & 255) as f32 / 255.0;
        let hsv = hokusai::color::rgb_to_hsv(r, g, b);
        brush.set(BrushSetting::ColorH, SettingValue::constant(hsv.h));
        brush.set(BrushSetting::ColorS, SettingValue::constant(hsv.s));
        brush.set(BrushSetting::ColorV, SettingValue::constant(hsv.v));
        brush.set(
            BrushSetting::Radius,
            SettingValue::constant((width / 2.0).ln()),
        );
        let preset = PresetStroke {
            brush,
            state: BrushState::new(1000),
            surface: TrackedSurface::default(),
            published: HashMap::new(),
        };
        let handle = NEXT_STROKE_HANDLE.fetch_add(1, Ordering::Relaxed) as i64;
        self.stroke = Some(NativeStroke {
            handle,
            layer: layer.to_string(),
            source_revision,
            rgba,
            clip,
            preset,
            pending: None,
            preview: Vec::new(),
            ffi_calls: 1,
            batches: 0,
            input_floats: 0,
            emitted_ints: 0,
            phase_us: [0; 5],
        });
        let mut result = Dictionary::new();
        result.set("ok", true);
        result.set("handle", handle);
        result.set("abi_version", STROKE_ABI_VERSION);
        result
    }

    /// One input FFI call for up to 4096 interleaved f32 samples. Native
    /// changes are pending until GDScript source staging acknowledges them.
    #[func]
    fn append_samples(
        &mut self,
        handle: i64,
        source_revision: i64,
        packed_samples: PackedFloat32Array,
    ) -> Dictionary<Variant, Variant> {
        let Some(stroke) = self.stroke.as_mut() else {
            return error_result("No active stroke");
        };
        if stroke.handle != handle || stroke.source_revision != source_revision {
            return error_result("Invalid stroke handle or stale source revision");
        }
        stroke.ffi_calls += 1;
        let samples = match parse_samples(packed_samples.as_slice()) {
            Ok(samples) => samples,
            Err(message) => return error_result(message),
        };
        match stroke.append(&samples) {
            Ok(()) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("samples", samples.len() as i64);
                result
            }
            Err(message) => error_result(message),
        }
    }

    /// Changes are valid only during a pending batch. v1's transitional
    /// format is signed relative [x,y,rgba8] for every preset.
    /// Native tile RGBA8 buffers replace this pixel stream under T-148.
    #[func]
    fn preview_changes(
        &mut self,
        handle: i64,
        source_revision: i64,
    ) -> Dictionary<Variant, Variant> {
        let Some(stroke) = self.stroke.as_mut() else {
            return error_result("No active stroke");
        };
        if stroke.handle != handle
            || stroke.source_revision != source_revision
            || stroke.pending.is_none()
        {
            return error_result("Invalid handle, revision, or no pending sample batch");
        }
        stroke.ffi_calls += 1;
        let mut result = Dictionary::new();
        result.set("ok", true);
        result.set("format", "xy_rgba");
        result.set("changes", &PackedInt32Array::from(stroke.preview.clone()));
        result
    }

    /// Rejecting a source read restores the *same* Hokusai batch.
    /// Accepted batches accumulate until the single whole-stroke commit.
    #[func]
    fn acknowledge_batch(&mut self, handle: i64, source_revision: i64, accepted: bool) -> bool {
        let Some(stroke) = self.stroke.as_mut() else {
            return false;
        };
        if stroke.handle != handle || stroke.source_revision != source_revision {
            return false;
        }
        stroke.ffi_calls += 1;
        stroke.acknowledge(accepted)
    }

    /// Obtain signed storage-tile IDs needed by a pending batch. A Godot
    /// consumer can authorize and bulk-import *only* these source tiles before
    /// calling apply_tile_batch; no per-pixel coordinates leave Rust.
    #[allow(clippy::too_many_arguments)] // Source stamp, tile geometry, world transform.
    #[func]
    fn required_tiles(
        &mut self,
        handle: i64,
        revision: i64,
        stride: i64,
        anchor_x: i64,
        anchor_y: i64,
    ) -> Dictionary<Variant, Variant> {
        let Some(stroke) = self.stroke.as_mut().filter(|stroke| {
            stroke.handle == handle
                && stroke.source_revision == revision
                && stroke.pending.is_some()
        }) else {
            return error_result("Missing pending native brush batch or stale revision");
        };
        if !(16..=2048).contains(&stride) {
            return error_result("Invalid native storage tile stride");
        }
        stroke.ffi_calls += 1;
        let discovery_start = Instant::now();
        let step = 3;
        let mut coords = HashSet::new();
        let mut last_coords: Option<(i64, i64)> = None;
        let per_pixel = std::env::var_os("DRAWING_T188_PIXEL_GROUP_COUNTERFACTUAL").is_some();
        for delta in stroke.preview.chunks_exact(step) {
            if stroke.clip.size.x > 0
                && stroke.clip.size.y > 0
                && !stroke
                    .clip
                    .contains_point(Vector2i::new(delta[0], delta[1]))
            {
                continue;
            }
            let Some((x, y)) = anchor_x
                .checked_add(i64::from(delta[0]))
                .zip(anchor_y.checked_add(i64::from(delta[1])))
            else {
                return error_result("Signed native tile coordinate overflow");
            };
            if x.unsigned_abs() > (1_u64 << 60) || y.unsigned_abs() > (1_u64 << 60) {
                return error_result("Signed native tile coordinate outside safe bounds");
            }
            let tile = (x.div_euclid(stride), y.div_euclid(stride));
            if per_pixel || last_coords != Some(tile) {
                coords.insert(tile);
                last_coords = Some(tile);
            }
            if coords.len() > 128 {
                return error_result("Native sample batch exceeds touched-tile budget");
            }
        }
        let mut sorted: Vec<_> = coords.into_iter().collect();
        sorted.sort_by_key(|&(x, y)| (y, x));
        let mut tiles = Array::<Dictionary<Variant, Variant>>::new();
        for (x, y) in sorted {
            let mut tile = Dictionary::new();
            tile.set("tile_x", x);
            tile.set("tile_y", y);
            tiles.push(&tile);
        }
        let mut result = Dictionary::new();
        result.set("ok", true);
        result.set("tiles", &tiles);
        stroke.phase_us[4] += discovery_start.elapsed().as_micros() as u64;
        result
    }

    /// Atomically stage AND acknowledge a pending raster batch. The source
    /// buffer, MyPaint raster state and tile draft must never diverge:
    /// on failure both roll back, so the caller may reappend the same samples
    /// after authorizing the missing source tile or mask. No per-pixel values
    /// cross the Godot boundary.
    #[allow(clippy::too_many_arguments)] // Explicit Godot edit token and anchor.
    #[func]
    fn apply_tile_batch(
        &mut self,
        mut store: Gd<native_tiles::DrawingNativeTiles>,
        handle: i64,
        revision: i64,
        transaction: i64,
        anchor_x: i64,
        anchor_y: i64,
        erase: bool,
    ) -> Dictionary<Variant, Variant> {
        let Some(stroke) = self
            .stroke
            .as_mut()
            .filter(|s| s.handle == handle && s.source_revision == revision && s.pending.is_some())
        else {
            return error_result("Missing pending native brush batch or stale revision");
        };
        stroke.ffi_calls += 1;
        let mut tile_store = store.bind_mut();
        tile_store.store.ffi_calls += 1;
        if !tile_store
            .store
            .transaction_matches(transaction, revision, &stroke.layer)
        {
            stroke.acknowledge(false);
            return error_result("Brush layer/revision differs from native tile transaction");
        }
        let stage_start = Instant::now();
        let outcome = tile_store.store.stage(
            transaction,
            revision as u64,
            anchor_x,
            anchor_y,
            &stroke.preview,
            true,
            stroke.rgba as u32,
            erase,
            stroke.clip,
        );
        // A rejected source/mask read must rewind the brush's coverage,
        // pigment RNG and cursor before another batch may be appended.
        // TileStore::stage has already rolled back all tile writes on Err.
        stroke.phase_us[2] += stage_start.elapsed().as_micros() as u64;
        let ack_start = Instant::now();
        stroke.acknowledge(outcome.is_ok());
        stroke.phase_us[3] += ack_start.elapsed().as_micros() as u64;
        match outcome {
            Ok(changed) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("dirty_tiles", changed as i64);
                result
            }
            Err(message) => error_result(message),
        }
    }

    /// Atomically publish an entire accepted brush gesture into canonical
    /// raster tiles and their one reversible native history entry. The brush
    /// handle is consumed only *after* publication succeeds. An unauthorized
    /// layer, changed revision, or exhausted memory budget leaves the handle
    /// and tile draft intact and retryable.
    #[func]
    fn commit_tiles(
        &mut self,
        mut store: Gd<native_tiles::DrawingNativeTiles>,
        handle: i64,
        revision: i64,
        transaction: i64,
    ) -> Dictionary<Variant, Variant> {
        let Some(stroke) = self.stroke.as_ref().filter(|stroke| {
            stroke.handle == handle
                && stroke.source_revision == revision
                && stroke.pending.is_none()
        }) else {
            return error_result("Invalid brush handle, revision or unacknowledged batch");
        };
        let mut tile_store = store.bind_mut();
        tile_store.store.ffi_calls += 1;
        if !tile_store
            .store
            .transaction_matches(transaction, revision, &stroke.layer)
        {
            return error_result("Brush layer/revision differs from native tile transaction");
        }
        if tile_store.store.finish_noop(transaction, revision as u64) {
            self.stroke = None;
            let mut result = Dictionary::new();
            result.set("ok", true);
            result.set("dirty_tiles", 0);
            result.set("no_change", true);
            result.set("revision", revision);
            return result;
        }
        match tile_store.store.commit(transaction, revision as u64) {
            Ok(changed) => {
                self.stroke = None;
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("dirty_tiles", changed as i64);
                result.set("history_token", transaction);
                result.set("revision", revision + 1);
                result
            }
            Err(message) => error_result(message),
        }
    }

    /// Stable metrics report boundary call count and packed payload volumes;
    /// no per-pixel Godot call is performed on the native side.
    #[func]
    fn stroke_stats(&mut self, handle: i64, source_revision: i64) -> Dictionary<Variant, Variant> {
        let Some(stroke) = self.stroke.as_mut() else {
            return error_result("No active stroke");
        };
        if stroke.handle != handle || stroke.source_revision != source_revision {
            return error_result("Invalid stroke handle or stale revision");
        }
        stroke.ffi_calls += 1;
        let mut result = Dictionary::new();
        result.set("ok", true);
        result.set("layer", stroke.layer.as_str());
        result.set("rgba", stroke.rgba);
        result.set("format", "xy_rgba");
        result.set("ffi_calls", stroke.ffi_calls);
        result.set("batches", stroke.batches);
        result.set("input_floats", stroke.input_floats);
        result.set("exported_ints", stroke.emitted_ints);
        if std::env::var_os("DRAWING_T185_PROFILE").is_some() {
            for (label, us) in ["raster", "delta_scan", "tile_stage", "ack", "discovery"]
                .into_iter()
                .zip(stroke.phase_us)
            {
                result.set(format!("t188_{label}_us"), us as i64);
            }
        }
        result
    }

    #[func]
    fn commit_stroke(&mut self, handle: i64, source_revision: i64) -> bool {
        if !self.stroke.as_ref().is_some_and(|stroke| {
            stroke.handle == handle
                && stroke.source_revision == source_revision
                && stroke.pending.is_none()
        }) {
            return false;
        }
        self.stroke = None;
        true
    }

    #[func]
    fn abort_stroke(&mut self, handle: i64) -> bool {
        if !self
            .stroke
            .as_ref()
            .is_some_and(|stroke| stroke.handle == handle)
        {
            return false;
        }
        if let Some(stroke) = self.stroke.as_mut() {
            stroke.acknowledge(false);
        }
        self.stroke = None;
        true
    }
}

struct DrawingBrushExtension;

// No Godot scene APIs are used by this Rust class outside the engine main thread.
#[gdextension]
unsafe impl ExtensionLibrary for DrawingBrushExtension {}

#[cfg(test)]
mod tests {
    use super::*;

    /// Exact native-f32 reference: never use hard_row_bounds to generate its
    /// expected pixels. Checks order, fractional edges and large coordinates.
    #[test]
    fn pigment_tile_batch_rolls_back_existing_and_new_surface_tiles() {
        let mut surface = TrackedSurface::default();
        surface.tile_request_start(-1, 2)[3][4] = [21, 43, 65, 32768];
        surface.tile_request_end(-1, 2);
        surface.changed.clear();

        surface.begin_batch();
        surface.tile_request_start(-1, 2)[3][4] = [10, 20, 30, 40];
        surface.tile_request_end(-1, 2);
        surface.tile_request_start(3, -2)[0][0] = [900, 800, 700, 600];
        surface.tile_request_end(3, -2);
        assert_eq!(surface.changed.len(), 2);
        surface.rollback_batch();
        assert_eq!(surface.tile(-1, 2).unwrap()[3][4], [21, 43, 65, 32768]);
        assert!(surface.tile(3, -2).is_none());
        assert!(surface.changed.is_empty());
        assert_eq!(surface.tiles.len(), 1);

        surface.begin_batch();
        surface.tile_request_start(3, -2)[0][0] = [11, 12, 13, 14];
        surface.tile_request_end(3, -2);
        surface.commit_batch();
        assert_eq!(surface.tile(3, -2).unwrap()[0][0], [11, 12, 13, 14]);
        assert!(surface.before_batch.is_none());
    }

    #[test]
    fn cached_native_scan_matches_full_quantized_export() {
        let mut raw = [[[0_u16; 4]; TILE_SIZE]; TILE_SIZE];
        let mut cache = ExportedTile::default();
        let mut reference = vec![0_u32; TILE_SIZE * TILE_SIZE];
        for frame in 0..32_usize {
            // Model clustered dabs, including changes at both signed tile
            // edges, an erase to all zeros, and a reappearance after erase.
            for index in 0..397_usize {
                let column = (index * 137 + frame * 19) % TILE_SIZE;
                let row = (index * 37 + frame * 13) % TILE_SIZE;
                let alpha = if (index + frame) % 19 == 0 {
                    0
                } else {
                    (index * 89 + frame * 271) % 32769
                };
                raw[row][column] = if frame % 9 == 8 {
                    [0; 4]
                } else {
                    [
                        ((index * 119 + frame * 11) % 32769) as u16,
                        ((index * 81 + frame * 17) % 32769) as u16,
                        ((index * 41 + frame * 29) % 32769) as u16,
                        alpha as u16,
                    ]
                };
            }
            let mut expected = Vec::new();
            for (row, pixels) in raw.iter().enumerate() {
                for (column, pixel) in pixels.iter().enumerate() {
                    let index = row * TILE_SIZE + column;
                    let rgba = quantize_pixel(pixel);
                    if rgba != reference[index] {
                        reference[index] = rgba;
                        expected.push((index, rgba));
                    }
                }
            }
            let mut actual = Vec::new();
            scan_changed_pixels(&raw, &mut cache, |index, rgba| {
                actual.push((index, rgba));
            });
            assert_eq!(
                actual, expected,
                "frame {frame} must export exact RGBA8 deltas"
            );
            assert_eq!(cache.rgba, reference);
            let mut unchanged = Vec::new();
            scan_changed_pixels(&raw, &mut cache, |index, rgba| {
                unchanged.push((index, rgba));
            });
            assert!(
                unchanged.is_empty(),
                "unchanged native tile re-exported pixels"
            );
        }
    }

    #[test]
    fn native_changes_with_identical_rgba_do_not_reenter_script() {
        let mut raw = [[[0_u16; 4]; TILE_SIZE]; TILE_SIZE];
        let mut cache = ExportedTile::default();
        raw[0][0] = [200, 99, 71, 0]; // Hidden native RGB remains transparent.
        let mut emitted = Vec::new();
        scan_changed_pixels(&raw, &mut cache, |index, rgba| emitted.push((index, rgba)));
        assert!(emitted.is_empty());
        assert_eq!(cache.raw[0], raw[0][0]);

        raw[0][0] = [5000, 4000, 3000, 20000];
        scan_changed_pixels(&raw, &mut cache, |index, rgba| emitted.push((index, rgba)));
        assert_eq!(emitted.len(), 1);
        assert_eq!(emitted[0], (0, quantize_pixel(&raw[0][0])));
        emitted.clear();
        raw[0][0] = [7000, 123, 456, 0]; // Exact erase must emit alpha zero.
        scan_changed_pixels(&raw, &mut cache, |index, rgba| emitted.push((index, rgba)));
        assert_eq!(emitted, vec![(0, 0)]);
        emitted.clear();
        raw[0][0] = [71, 55, 92, 0]; // Hidden RGB changes remain silent.
        scan_changed_pixels(&raw, &mut cache, |index, rgba| emitted.push((index, rgba)));
        assert!(emitted.is_empty());

        // A native fix15 adjustment can stay inside one RGBA8 quantization
        // bucket; it must update the raw cache without emitting an edit.
        let same_bucket = (1_u16..=1000).find(|&value| {
            quantize_pixel(&[value, 0, 0, 32768]) == quantize_pixel(&[value + 1, 0, 0, 32768])
        });
        let value = same_bucket.expect("sRGB quantization has repeated buckets");
        raw[0][0] = [value, 0, 0, 32768];
        scan_changed_pixels(&raw, &mut cache, |index, rgba| emitted.push((index, rgba)));
        emitted.clear();
        raw[0][0][0] += 1;
        scan_changed_pixels(&raw, &mut cache, |index, rgba| emitted.push((index, rgba)));
        assert!(emitted.is_empty());
        assert_eq!(cache.raw[0], raw[0][0]);
    }
    fn sample(x: f32, y: f32, pressure: f32) -> BrushSample {
        BrushSample {
            point: Vector2::new(x, y),
            pressure,
            delta_seconds: 0.01,
        }
    }

    fn preset_stroke(width: f32, clip: Rect2i) -> NativeStroke {
        let mut brush = hokusai::myb::from_str(include_str!(
            "../../../addons/drawing/brushes/hard_round.myb"
        ))
        .expect("bundled preset must parse");
        brush.set(
            BrushSetting::Radius,
            SettingValue::constant((width / 2.0).ln()),
        );
        NativeStroke {
            handle: 1,
            layer: "test-layer".into(),
            source_revision: 7,
            rgba: 0xff123456,
            clip,
            preset: PresetStroke {
                brush,
                state: BrushState::new(1000),
                surface: TrackedSurface::default(),
                published: HashMap::new(),
            },
            pending: None,
            preview: Vec::new(),
            ffi_calls: 1,
            batches: 0,
            input_floats: 0,
            emitted_ints: 0,
            phase_us: [0; 5],
        }
    }

    #[test]
    fn preset_samples_validate_entire_batch_before_state_mutation() {
        assert!(parse_samples(&[]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 3.0]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 1.01, 0.01]).is_err());
        assert!(parse_samples(&[1.0, 2.0, f32::NAN, 0.01]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 0.8, 0.0]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 1.0, f32::INFINITY]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 1.0, 0.01, f32::NAN, 0.0, 1.0, 0.01]).is_err());
        assert!(parse_samples(&vec![0.0; (MAX_BATCH_SAMPLES + 1) * 4]).is_err());
        assert_eq!(parse_samples(&[-10.0, 2.0, 0.5, 0.01]).unwrap().len(), 1);
        let mut stroke = preset_stroke(12.0, Rect2i::new(Vector2i::ZERO, Vector2i::ZERO));
        stroke.append(&[sample(-9.0, 3.0, 1.0)]).unwrap();
        assert!(stroke.acknowledge(true));
        let count = stroke.batches;
        let last = stroke.preset.surface.tiles.len();
        assert!(parse_samples(&[0.0, 1.0, 1.0, 0.01, f32::NAN, 2.0, 1.0, 0.01]).is_err());
        assert!(stroke.pending.is_none());
        assert_eq!(stroke.batches, count);
        assert_eq!(stroke.preset.surface.tiles.len(), last);
    }

    #[test]
    fn hokusai_hard_round_rollback_and_signed_alpha() {
        let mut stroke = preset_stroke(
            24.0,
            Rect2i::new(Vector2i::new(-16, -16), Vector2i::new(32, 32)),
        );
        let path = [sample(-2.5, 3.5, 0.7), sample(3.5, -5.5, 1.0)];
        stroke.append(&path).unwrap();
        let expected = stroke.preview.clone();
        assert!(!expected.is_empty());
        assert_eq!(expected.len() % 3, 0);
        assert!(
            expected
                .as_chunks::<3>()
                .0
                .iter()
                .any(|triple| triple[0] < 0 || triple[1] < 0)
        );
        assert!(
            expected
                .as_chunks::<3>()
                .0
                .iter()
                .any(|triple| (triple[2] as u32 >> 24) > 0)
        );
        assert!(stroke.append(&path).is_err());
        assert!(stroke.acknowledge(false));
        stroke.append(&path).unwrap();
        assert_eq!(
            stroke.preview, expected,
            "rejected Hokusai batch replays byte-exact"
        );
        assert!(stroke.acknowledge(true));
        stroke.append(&[sample(5.0, 10.0, 0.1)]).unwrap();
        assert!(stroke.acknowledge(true));
        assert_eq!(stroke.batches, 2);
        assert_eq!(stroke.input_floats, 20);
    }

    #[test]
    fn all_bundled_presets_parse() {
        for text in [
            include_str!("../../../addons/drawing/brushes/hard_round.myb"),
            include_str!("../../../addons/drawing/brushes/soft.myb"),
            include_str!("../../../addons/drawing/brushes/ink.myb"),
            include_str!("../../../addons/drawing/brushes/airbrush.myb"),
        ] {
            assert!(hokusai::myb::from_str(text).is_ok());
        }
    }
}
