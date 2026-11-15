//! Versioned NativeHard/Hokusai stroke transactions and native tile editing.
//! The T-148 tile store is implemented independently; production Canvas still
//! uses its transitional GDScript source adapter pending the T-149 cutover.
mod native_tiles;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};

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

/// A prevalidated segment whose candidate count fits the bounded batch.
/// Validation must finish before mutating the per-stroke coverage or cursor:
/// otherwise a bad *later* point can silently consume earlier brush pixels.
struct HardWindow {
    begin: Vector2,
    end: Vector2,
    left: i32,
    right: i32,
    top: i32,
    bottom: i32,
}

const MAX_HARD_CANDIDATES: i64 = 1_048_576;

fn validate_hard_windows(
    points: &[Vector2],
    width: f32,
    clip: Rect2i,
    previous: Option<Vector2>,
) -> Result<Vec<HardWindow>, &'static str> {
    if !width.is_finite() || width <= 0.0 || points.is_empty() {
        return Err("Invalid hard-brush width or path");
    }
    let radius = width * 0.5;
    let mut windows = Vec::with_capacity(points.len());
    let mut last = previous;
    let mut candidates = 0_i64;
    for &end in points {
        if !end.x.is_finite()
            || !end.y.is_finite()
            || end.x.abs() >= 1_000_000_000.0
            || end.y.abs() >= 1_000_000_000.0
        {
            return Err("Brush position exceeds safe coordinates");
        }
        let begin = last.unwrap_or(end);
        let mut left = (begin.x.min(end.x) - radius - 0.5).floor() as i32;
        let mut right = (begin.x.max(end.x) + radius + 0.5).ceil() as i32;
        let mut top = (begin.y.min(end.y) - radius - 0.5).floor() as i32;
        let mut bottom = (begin.y.max(end.y) + radius + 0.5).ceil() as i32;
        if clip.size.x > 0 && clip.size.y > 0 {
            left = left.max(clip.position.x);
            right = right.min(clip.position.x.saturating_add(clip.size.x));
            top = top.max(clip.position.y);
            bottom = bottom.min(clip.position.y.saturating_add(clip.size.y));
        }
        let columns = i64::from(right) - i64::from(left);
        let rows = i64::from(bottom) - i64::from(top);
        if columns > 0 && rows > 0 {
            let area = columns
                .checked_mul(rows)
                .ok_or("Native brush candidate budget overflow")?;
            candidates = candidates
                .checked_add(area)
                .ok_or("Native brush candidate budget overflow")?;
            if candidates > MAX_HARD_CANDIDATES {
                return Err("Native brush batch exceeds candidate budget");
            }
        }
        windows.push(HardWindow {
            begin,
            end,
            left,
            right,
            top,
            bottom,
        });
        last = Some(end);
    }
    Ok(windows)
}

/// Conservative X interval for a single oblique NativeHard candidate row.
/// The final f32 distance predicate is intentionally unchanged: this only
/// avoids testing pixels farther than the swept disc can possibly reach.
/// Use f64 for the bound, with extra error margin for f32 vector rounding.
/// Very large coordinates and near-horizontal slopes retain the reference
/// full-rectangle scan to avoid any change in edge-pixel semantics.
fn hard_row_bounds(window: &HardWindow, y: i32, radius: f32) -> (i32, i32) {
    let dy = window.end.y - window.begin.y;
    if !radius.is_finite()
        || dy.abs() < 0.001
        || !dy.is_finite()
        || [window.begin.x, window.begin.y, window.end.x, window.end.y]
            .iter()
            .any(|coordinate| coordinate.abs() >= 1_000_000.0)
    {
        return (window.left, window.right);
    }
    let broad = f64::from(radius) + 4.0;
    let center_y = f64::from(y) + 0.5;
    let begin_y = f64::from(window.begin.y);
    let slope_y = f64::from(dy);
    let a = (center_y - broad - begin_y) / slope_y;
    let b = (center_y + broad - begin_y) / slope_y;
    let lower = a.min(b).max(0.0);
    let upper = a.max(b).min(1.0);
    if lower > upper {
        return (window.left, window.left);
    }
    let begin_x = f64::from(window.begin.x);
    let slope_x = f64::from(window.end.x) - begin_x;
    let x_a = begin_x + slope_x * lower;
    let x_b = begin_x + slope_x * upper;
    let left = (x_a.min(x_b) - broad - 1.0).floor() as i32;
    let right = (x_a.max(x_b) + broad + 1.0).ceil() as i32;
    (left.max(window.left), right.min(window.right))
}

/// Only newly accepted coverage is journaled per GDScript sample batch; do
/// not copy the entire long-running coverage set on every input event.
struct HardBatch {
    last_hard: Option<Vector2>,
    inserted: Vec<(i32, i32)>,
}

impl HardBatch {
    fn rollback(self, covered: &mut HashSet<(i32, i32)>, last_hard: &mut Option<Vector2>) {
        for pixel in self.inserted {
            covered.remove(&pixel);
        }
        *last_hard = self.last_hard;
    }
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

/// Validate the *entire* hard batch before accepting any covered pixel. A
/// zero-pressure sample lifts the tip so its next mark cannot bridge a gap.
fn hard_windows_for_samples(
    samples: &[BrushSample],
    width: f32,
    clip: Rect2i,
    previous: Option<Vector2>,
) -> Result<Vec<Option<(HardWindow, f32)>>, &'static str> {
    let mut output = Vec::with_capacity(samples.len());
    let mut last = previous;
    let mut candidates = 0_i64;
    for sample in samples {
        if sample.pressure == 0.0 {
            last = None;
            output.push(None);
            continue;
        }
        let radius_width = width * sample.pressure;
        let mut windows = validate_hard_windows(&[sample.point], radius_width, clip, last)?;
        let window = windows.pop().expect("single point validated");
        let rows = i64::from(window.bottom) - i64::from(window.top);
        let columns = i64::from(window.right) - i64::from(window.left);
        if rows > 0 && columns > 0 {
            candidates = candidates
                .checked_add(rows.checked_mul(columns).ok_or("Hard candidate overflow")?)
                .ok_or("Hard candidate overflow")?;
            if candidates > MAX_HARD_CANDIDATES {
                return Err("Hard batch exceeds candidate budget");
            }
        }
        output.push(Some((window, radius_width)));
        last = Some(sample.point);
    }
    Ok(output)
}

enum StrokeStrategy {
    Hard {
        last: Option<Vector2>,
        covered: HashSet<(i32, i32)>,
    },
    Preset(Box<PresetStroke>),
}

/// Single native batch lifetime for *both* brush strategies. GDScript must
/// acknowledge only after source tile authorization and staging have passed.
enum BatchRollback {
    Hard(HardBatch),
    Preset(Box<PresetBatch>),
}

struct NativeStroke {
    handle: i64,
    layer: String,
    source_revision: i64,
    width: f32,
    rgba: i64,
    clip: Rect2i,
    strategy: StrokeStrategy,
    pending: Option<BatchRollback>,
    preview: Vec<i32>,
    ffi_calls: i64,
    batches: i64,
    input_floats: i64,
    emitted_ints: i64,
}

impl NativeStroke {
    fn format(&self) -> &'static str {
        match self.strategy {
            StrokeStrategy::Hard { .. } => "xy",
            StrokeStrategy::Preset(_) => "xy_rgba",
        }
    }

    fn acknowledge(&mut self, accepted: bool) -> bool {
        let Some(batch) = self.pending.take() else {
            return false;
        };
        match (batch, &mut self.strategy) {
            (BatchRollback::Hard(snapshot), StrokeStrategy::Hard { last, covered }) => {
                if !accepted {
                    snapshot.rollback(covered, last);
                }
            }
            (BatchRollback::Preset(snapshot), StrokeStrategy::Preset(preset)) => {
                if accepted {
                    preset.surface.commit_batch();
                } else {
                    preset.surface.rollback_batch();
                    preset.state = snapshot.state;
                    for (key, previous) in snapshot.published {
                        if let Some(previous) = previous {
                            preset.published.insert(key, previous);
                        } else {
                            preset.published.remove(&key);
                        }
                    }
                }
            }
            _ => unreachable!("strategy and rollback snapshot must match"),
        }
        self.preview.clear();
        if accepted {
            self.batches += 1;
        }
        true
    }

    fn append(&mut self, samples: &[BrushSample]) -> Result<(), &'static str> {
        if self.pending.is_some() {
            return Err("Previous native sample batch needs acknowledgement");
        }
        let mut output = Vec::new();
        match &mut self.strategy {
            StrokeStrategy::Hard { last, covered } => {
                let windows = hard_windows_for_samples(samples, self.width, self.clip, *last)?;
                let snapshot = HardBatch {
                    last_hard: *last,
                    inserted: Vec::new(),
                };
                self.pending = Some(BatchRollback::Hard(snapshot));
                for window in windows {
                    let Some((window, point_width)) = window else {
                        *last = None;
                        continue;
                    };
                    let delta = window.end - window.begin;
                    let squared = delta.length_squared();
                    let radius_squared = (point_width * 0.5).powi(2);
                    for y in window.top..window.bottom {
                        let (row_left, row_right) = hard_row_bounds(&window, y, point_width * 0.5);
                        for x in row_left..row_right {
                            if covered.contains(&(x, y)) {
                                continue;
                            }
                            let center = Vector2::new(x as f32 + 0.5, y as f32 + 0.5);
                            let fraction = if squared > 0.0 {
                                ((center - window.begin).dot(delta) / squared).clamp(0.0, 1.0)
                            } else {
                                0.0
                            };
                            if (center - (window.begin + delta * fraction)).length_squared()
                                <= radius_squared
                            {
                                covered.insert((x, y));
                                if let Some(BatchRollback::Hard(batch)) = self.pending.as_mut() {
                                    batch.inserted.push((x, y));
                                }
                                output.extend_from_slice(&[x, y]);
                            }
                        }
                    }
                    *last = Some(window.end);
                }
            }
            StrokeStrategy::Preset(preset) => {
                self.pending = Some(BatchRollback::Preset(Box::new(PresetBatch {
                    state: preset.state.clone(),
                    published: HashMap::new(),
                })));
                preset.surface.begin_batch();
                for sample in samples {
                    preset.brush.stroke_to(
                        &mut preset.state,
                        &mut preset.surface,
                        sample.point.x,
                        sample.point.y,
                        sample.pressure,
                        0.0,
                        0.0,
                        sample.delta_seconds as f64,
                    );
                }
                let mut dirty: Vec<_> = preset.surface.changed.drain().collect();
                dirty.sort_unstable();
                for (tx, ty) in dirty {
                    let Some(tile) = preset.surface.tile(tx, ty) else {
                        continue;
                    };
                    if let Some(BatchRollback::Preset(batch)) = self.pending.as_mut() {
                        batch
                            .published
                            .entry((tx, ty))
                            .or_insert_with(|| preset.published.get(&(tx, ty)).cloned());
                    }
                    let exported = preset.published.entry((tx, ty)).or_default();
                    scan_changed_pixels(tile, exported, |index, rgba| {
                        output.extend_from_slice(&[
                            tx * TILE_SIZE as i32 + (index % TILE_SIZE) as i32,
                            ty * TILE_SIZE as i32 + (index / TILE_SIZE) as i32,
                            rgba as i32,
                        ]);
                    });
                }
            }
        }
        if output.len() > MAX_EXPORTED_INTS {
            self.acknowledge(false);
            return Err("Native sample delta exceeds batch output limit");
        }
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

    /// Frozen at pointer-down: layer, raster brush strategy, width, color,
    /// edit revision and signed relative clip. Transform/selection are frozen
    /// and enforced by the DrawingEditSession adapter until T-148.
    // The frozen source options are intentionally explicit at this ABI boundary.
    #[allow(clippy::too_many_arguments)]
    #[func]
    fn begin_stroke(
        &mut self,
        layer: GString,
        mode: GString,
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
        let strategy = match mode.to_string().as_str() {
            "NativeHard" => StrokeStrategy::Hard {
                last: None,
                covered: HashSet::new(),
            },
            "Hokusai" => {
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
                StrokeStrategy::Preset(Box::new(PresetStroke {
                    brush,
                    state: BrushState::new(1000),
                    surface: TrackedSurface::default(),
                    published: HashMap::new(),
                }))
            }
            _ => return error_result("Unknown native stroke strategy"),
        };
        let handle = NEXT_STROKE_HANDLE.fetch_add(1, Ordering::Relaxed) as i64;
        self.stroke = Some(NativeStroke {
            handle,
            layer: layer.to_string(),
            source_revision,
            width,
            rgba,
            clip,
            strategy,
            pending: None,
            preview: Vec::new(),
            ffi_calls: 1,
            batches: 0,
            input_floats: 0,
            emitted_ints: 0,
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
    /// format is signed relative [x,y] for hard and [x,y,rgba8] for preset.
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
        result.set("format", stroke.format());
        result.set("changes", &PackedInt32Array::from(stroke.preview.clone()));
        result
    }

    /// Rejecting a source read restores the *same* batch in either strategy.
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
        let step = if stroke.format() == "xy_rgba" { 3 } else { 2 };
        let mut coords = HashSet::new();
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
            coords.insert((x.div_euclid(stride), y.div_euclid(stride)));
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
        result
    }

    /// Atomically stage AND acknowledge a pending raster batch. The source
    /// buffer, hard coverage/pigment state and tile draft must never diverge:
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
        let outcome = tile_store.store.stage(
            transaction,
            revision as u64,
            anchor_x,
            anchor_y,
            &stroke.preview,
            stroke.format() == "xy_rgba",
            stroke.rgba as u32,
            erase,
            stroke.clip,
        );
        // A rejected source/mask read must rewind the brush's coverage,
        // pigment RNG and cursor before another batch may be appended.
        // TileStore::stage has already rolled back all tile writes on Err.
        stroke.acknowledge(outcome.is_ok());
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
        result.set("mode", stroke.format());
        result.set("ffi_calls", stroke.ffi_calls);
        result.set("batches", stroke.batches);
        result.set("input_floats", stroke.input_floats);
        result.set("exported_ints", stroke.emitted_ints);
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
    fn hard_scanlines_equal_original_rectangles() {
        let samples: &[(Vector2, Vector2, f32, Option<Rect2i>)] = &[
            (
                Vector2::new(-92.25, -86.5),
                Vector2::new(94.75, 87.625),
                60.0,
                None,
            ),
            (
                Vector2::new(91.875, -84.5),
                Vector2::new(-91.625, 83.125),
                60.0,
                None,
            ),
            (
                Vector2::new(-92.25, 1.125),
                Vector2::new(94.75, 3.375),
                60.0,
                None,
            ),
            (
                Vector2::new(-92.25, 1.125),
                Vector2::new(94.75, 1.12505),
                60.0,
                None,
            ),
            (
                Vector2::new(-94.5, 3.5),
                Vector2::new(91.5, 3.5),
                60.0,
                None,
            ),
            (
                Vector2::new(3.5, -91.5),
                Vector2::new(3.5, 94.5),
                60.0,
                None,
            ),
            (Vector2::new(-7.5, 5.5), Vector2::new(-7.5, 5.5), 60.0, None),
            (
                Vector2::new(-68.125, -75.375),
                Vector2::new(74.875, 69.625),
                1.25,
                None,
            ),
            (
                Vector2::new(71.5, -71.5),
                Vector2::new(-76.5, 74.5),
                0.75,
                None,
            ),
            (
                Vector2::new(-88.5, -73.5),
                Vector2::new(91.5, 78.5),
                60.0,
                Some(Rect2i::new(Vector2i::new(-43, -37), Vector2i::new(84, 69))),
            ),
            (
                Vector2::new(10_000_012.0, -10_000_042.0),
                Vector2::new(10_000_068.0, -10_000_001.0),
                7.0,
                Some(Rect2i::new(
                    Vector2i::new(10_000_008, -10_000_048),
                    Vector2i::new(75, 63),
                )),
            ),
        ];
        let mut cases = samples.to_vec();
        // Deterministic additional slopes/centers exercise f32 edge rounding
        // without pulling in an RNG dependency or altering the native path.
        let mut seed = 0x9e37_79b9_u32;
        for sample in 0..96 {
            let mut draw = || {
                seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                (seed % 200_001) as f32 / 1000.0 - 100.0
            };
            let begin = Vector2::new(draw(), draw());
            let end = Vector2::new(draw(), draw());
            let width = [0.75, 1.25, 7.0, 16.5, 31.3, 60.0][sample % 6];
            cases.push((begin, end, width, None));
        }
        for &(begin, end, width, clip) in &cases {
            let window = validate_hard_windows(
                &[end],
                width,
                clip.unwrap_or(Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)),
                Some(begin),
            )
            .unwrap()
            .pop()
            .unwrap();
            let radius_squared = (width * 0.5) * (width * 0.5);
            let delta = end - begin;
            let squared = delta.length_squared();
            let accepted = |x: i32, y: i32| {
                let center = Vector2::new(x as f32 + 0.5, y as f32 + 0.5);
                let fraction = if squared > 0.0 {
                    ((center - begin).dot(delta) / squared).clamp(0.0, 1.0)
                } else {
                    0.0
                };
                (center - (begin + delta * fraction)).length_squared() <= radius_squared
            };
            let reference: Vec<_> = (window.top..window.bottom)
                .flat_map(|y| (window.left..window.right).map(move |x| (x, y)))
                .filter(|&(x, y)| accepted(x, y))
                .collect();
            let optimized: Vec<_> = (window.top..window.bottom)
                .flat_map(|y| {
                    let (left, right) = hard_row_bounds(&window, y, width * 0.5);
                    (left..right).map(move |x| (x, y))
                })
                .filter(|&(x, y)| accepted(x, y))
                .collect();
            assert_eq!(
                optimized, reference,
                "width={width} begin={begin:?} end={end:?}"
            );
        }
    }

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
    fn native_hard_preflight_rejects_late_batch_errors() {
        let clip = Rect2i::new(Vector2i::ZERO, Vector2i::ZERO);
        let first = Vector2::new(-1.5, -2.5);
        let good = [first, Vector2::new(7.5, 3.5)];
        let windows = validate_hard_windows(&good, 12.0, clip, None).unwrap();
        assert_eq!(windows.len(), good.len());
        assert_eq!(windows[1].begin, first);
        assert!(
            validate_hard_windows(&[first, Vector2::new(f32::NAN, 1.0)], 12.0, clip, None).is_err()
        );
        assert!(
            validate_hard_windows(&[first, Vector2::new(1_000_000.0, 1.0)], 12.0, clip, None)
                .is_err()
        );
        assert!(validate_hard_windows(&[first], f32::MAX, clip, None).is_err());
        // A small clip can safely bound a distant sweep. Validation must
        // agree with the renderer's original clip-window behavior.
        let clipped = Rect2i::new(Vector2i::new(-10, -10), Vector2i::new(20, 20));
        assert!(
            validate_hard_windows(
                &[first, Vector2::new(1_000_000.0, 1.0)],
                12.0,
                clipped,
                None
            )
            .is_ok()
        );
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
    fn hard_batch_rollback_keeps_previous_coverage_and_cursor() {
        let mut covered = HashSet::from([(-9, 3), (2, 2)]);
        let mut last_hard = Some(Vector2::new(-8.5, 3.5));
        let saved = last_hard;
        let mut batch = HardBatch {
            last_hard: saved,
            inserted: Vec::new(),
        };
        for point in [(-9, 3), (3, 2), (-11, -1), (3, 2)] {
            if covered.insert(point) {
                batch.inserted.push(point);
            }
        }
        last_hard = Some(Vector2::new(22.5, -12.5));
        batch.rollback(&mut covered, &mut last_hard);
        assert_eq!(covered, HashSet::from([(-9, 3), (2, 2)]));
        assert_eq!(last_hard, saved);
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

    fn hard_stroke(width: f32, clip: Rect2i) -> NativeStroke {
        NativeStroke {
            handle: 1,
            layer: "test-layer".to_string(),
            source_revision: 7,
            width,
            rgba: 0xff123456,
            clip,
            strategy: StrokeStrategy::Hard {
                last: None,
                covered: HashSet::new(),
            },
            pending: None,
            preview: Vec::new(),
            ffi_calls: 1,
            batches: 0,
            input_floats: 0,
            emitted_ints: 0,
        }
    }

    #[test]
    fn stroke_samples_validate_entire_batch_before_state_mutation() {
        assert!(parse_samples(&[]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 3.0]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 1.01, 0.01]).is_err());
        assert!(parse_samples(&[1.0, 2.0, f32::NAN, 0.01]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 0.8, 0.0]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 1.0, f32::INFINITY]).is_err());
        assert!(parse_samples(&[1.0, 2.0, 1.0, 0.01, f32::NAN, 0.0, 1.0, 0.01]).is_err());
        assert!(parse_samples(&vec![0.0; (MAX_BATCH_SAMPLES + 1) * 4]).is_err());
        assert_eq!(parse_samples(&[-10.0, 2.0, 0.5, 0.01]).unwrap().len(), 1);
        let mut stroke = hard_stroke(12.0, Rect2i::new(Vector2i::ZERO, Vector2i::ZERO));
        assert!(stroke.append(&[sample(-9.0, 3.0, 1.0)]).is_ok());
        assert!(!stroke.preview.is_empty());
        assert!(stroke.acknowledge(true));
        let before = match &stroke.strategy {
            StrokeStrategy::Hard { covered, .. } => covered.clone(),
            _ => unreachable!(),
        };
        assert!(
            stroke
                .append(&[sample(0.0, 1.0, 1.0), sample(f32::NAN, 2.0, 1.0)])
                .is_err()
        );
        assert!(stroke.pending.is_none());
        assert_eq!(stroke.batches, 1);
        assert_eq!(
            match &stroke.strategy {
                StrokeStrategy::Hard { covered, .. } => covered,
                _ => unreachable!(),
            },
            &before
        );
    }

    #[test]
    fn unified_hard_pressure_mask_clip_and_rollback_are_exact() {
        let clip = Rect2i::new(Vector2i::new(-16, -16), Vector2i::new(32, 32));
        let mut stroke = hard_stroke(18.0, clip);
        let batch = [sample(-6.5, -3.5, 0.5), sample(7.5, 2.5, 1.0)];
        stroke.append(&batch).unwrap();
        let expected = stroke.preview.clone();
        assert!(expected.len() > 100);
        assert!(
            expected
                .as_chunks::<2>()
                .0
                .iter()
                .all(|pixel| { (-16..16).contains(&pixel[0]) && (-16..16).contains(&pixel[1]) })
        );
        assert!(
            stroke.append(&batch).is_err(),
            "pending batch must be acknowledged"
        );
        assert!(stroke.acknowledge(false));
        assert_eq!(stroke.batches, 0);
        stroke.append(&batch).unwrap();
        assert_eq!(
            stroke.preview, expected,
            "rollback replay is byte-identical"
        );
        assert!(stroke.acknowledge(true));
        stroke.append(&batch).unwrap();
        assert!(stroke.preview.is_empty(), "hard overlap is once per stroke");
        assert!(stroke.acknowledge(true));
        let mut full = hard_stroke(18.0, clip);
        full.append(&[sample(-6.5, -3.5, 1.0)]).unwrap();
        assert!(
            full.preview.len() > expected.len() / 4,
            "pressure must affect footprint"
        );
        assert!(full.acknowledge(true));
        stroke.append(&[sample(0.0, 0.0, 0.0)]).unwrap();
        assert!(stroke.preview.is_empty());
        assert!(stroke.acknowledge(true));
        stroke.append(&[sample(-13.0, 12.5, 1.0)]).unwrap();
        assert!(stroke.acknowledge(true));
        assert_eq!(stroke.batches, 4);
        assert_eq!(stroke.input_floats, 32);
    }

    #[test]
    fn unified_preset_batch_rollback_preserves_state_surface_and_quantized_export() {
        let mut brush = hokusai::myb::from_str(include_str!(
            "../../../addons/drawing/brushes/hard_round.myb"
        ))
        .expect("bundled preset must be parseable");
        brush.set(
            BrushSetting::Radius,
            SettingValue::constant((12.0_f32).ln()),
        );
        let preset = PresetStroke {
            brush,
            state: BrushState::new(1000),
            surface: TrackedSurface::default(),
            published: HashMap::new(),
        };
        let mut stroke = hard_stroke(24.0, Rect2i::new(Vector2i::ZERO, Vector2i::ZERO));
        stroke.strategy = StrokeStrategy::Preset(Box::new(preset));
        let batch = [sample(-2.5, 3.5, 0.7), sample(3.5, -5.5, 1.0)];
        stroke.append(&batch).unwrap();
        let expected = stroke.preview.clone();
        assert!(!expected.is_empty());
        assert_eq!(expected.len() % 3, 0);
        assert!(stroke.acknowledge(false));
        stroke.append(&batch).unwrap();
        assert_eq!(
            stroke.preview, expected,
            "state RNG and tile cache rollback replay"
        );
        assert!(stroke.acknowledge(true));
        stroke.append(&[sample(5.0, 10.0, 0.1)]).unwrap();
        assert!(stroke.acknowledge(true));
        assert_eq!(stroke.batches, 2);
    }

    #[test]
    fn large_hard_batch_budget_rejects_before_stroke_changes() {
        let mut stroke = hard_stroke(1024.0, Rect2i::new(Vector2i::ZERO, Vector2i::ZERO));
        let bad = [sample(-500.0, -500.0, 1.0), sample(500.0, 500.0, 1.0)];
        assert!(stroke.append(&bad).is_err());
        assert!(stroke.pending.is_none());
        assert!(stroke.preview.is_empty());
        stroke.width = 10.0;
        assert!(stroke.append(&[sample(-4.5, -4.5, 1.0)]).is_ok());
        assert!(stroke.acknowledge(true));
    }
}
