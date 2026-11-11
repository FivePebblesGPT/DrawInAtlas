//! Batched Drawing GDExtension. The legacy path remains available until parity,
//! packaging and owner-device latency are verified.
use std::collections::{HashMap, HashSet};

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
    pending: Option<PresetBatch>,
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

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct DrawingNativeBrush {
    base: Base<RefCounted>,
    last_hard: Option<Vector2>,
    covered: HashSet<(i32, i32)>,
    pending_hard: Option<HardBatch>,
    preset: Option<PresetStroke>,
}

#[godot_api]
impl IRefCounted for DrawingNativeBrush {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            last_hard: None,
            covered: HashSet::new(),
            pending_hard: None,
            preset: None,
        }
    }
}

#[godot_api]
impl DrawingNativeBrush {
    /// Per-stroke coverage is never shared between sessions or committed edits.
    #[func]
    fn reset_hard(&mut self) {
        self.covered.clear();
        self.last_hard = None;
        self.pending_hard = None;
        self.preset = None;
    }

    /// Begin the native half of a GDScript sample transaction. Source tile
    /// loads can fail *after* rasterization; until acknowledged, all newly
    /// covered pixels and the last sweep endpoint must remain reversible.
    #[func]
    fn begin_hard_batch(&mut self) -> bool {
        if self.pending_hard.is_some() {
            return false;
        }
        self.pending_hard = Some(HardBatch {
            last_hard: self.last_hard,
            inserted: Vec::new(),
        });
        true
    }

    #[func]
    fn commit_hard_batch(&mut self) {
        self.pending_hard = None;
    }

    #[func]
    fn rollback_hard_batch(&mut self) {
        if let Some(batch) = self.pending_hard.take() {
            batch.rollback(&mut self.covered, &mut self.last_hard);
        }
    }

    /// Returns only *new* pixel positions, not an RGBA buffer for every dab.
    /// Signed positions are relative to the DrawingEditSession anchor.
    #[func]
    fn hard_segments(
        &mut self,
        points: PackedVector2Array,
        width: f32,
        clip: Rect2i,
    ) -> Dictionary<Variant, Variant> {
        let mut result = Dictionary::new();
        if !width.is_finite() || width <= 0.0 || points.is_empty() {
            result.set("ok", false);
            result.set("error", "Invalid hard-brush width or path");
            return result;
        }
        // Validate *all* segment bounds and the cumulative raster budget
        // before touching self.covered or self.last_hard. A late malformed
        // point, unsafe bound or oversized batch must be retryable.
        let windows = match validate_hard_windows(points.as_slice(), width, clip, self.last_hard) {
            Ok(windows) => windows,
            Err(message) => {
                result.set("ok", false);
                result.set("error", message);
                return result;
            }
        };
        let radius_squared = (width * 0.5) * (width * 0.5);
        // Accumulate coordinates in contiguous native memory, then transfer
        // once to the Godot packed array. Pushing two Godot elements per hit
        // crosses the extension API boundary tens of thousands of times for
        // a single 60px sweep; conversion retains exact y/x insertion order.
        let mut coordinates: Vec<i32> = Vec::new();
        for window in windows {
            let delta = window.end - window.begin;
            let squared = delta.length_squared();
            for y in window.top..window.bottom {
                let (row_left, row_right) = hard_row_bounds(&window, y, width * 0.5);
                for x in row_left..row_right {
                    if self.covered.contains(&(x, y)) {
                        continue;
                    }
                    let center = Vector2::new(x as f32 + 0.5, y as f32 + 0.5);
                    let fraction = if squared > 0.0 {
                        ((center - window.begin).dot(delta) / squared).clamp(0.0, 1.0)
                    } else {
                        0.0
                    };
                    let distance = center - (window.begin + delta * fraction);
                    if distance.length_squared() <= radius_squared {
                        self.covered.insert((x, y));
                        if let Some(batch) = self.pending_hard.as_mut() {
                            batch.inserted.push((x, y));
                        }
                        coordinates.push(x);
                        coordinates.push(y);
                    }
                }
            }
            self.last_hard = Some(window.end);
        }
        let output = PackedInt32Array::from(coordinates);
        result.set("ok", true);
        result.set("points", &output);
        result
    }

    /// Hokusai parses unmodified .myb text; only authoring size and HSV color
    /// are overridden. Brush alpha is applied during canonical composition.
    #[func]
    fn configure_preset(&mut self, myb: GString, width: f32, rgba: i64) -> bool {
        if !width.is_finite() || width <= 0.0 || width > 4096.0 {
            return false;
        }
        let Ok(mut brush) = hokusai::myb::from_str(&myb.to_string()) else {
            return false;
        };
        let r = (rgba & 255) as f32 / 255.0;
        let g = ((rgba >> 8) & 255) as f32 / 255.0;
        let b = ((rgba >> 16) & 255) as f32 / 255.0;
        let hsv = hokusai::color::rgb_to_hsv(r, g, b);
        brush.set(BrushSetting::ColorH, SettingValue::constant(hsv.h));
        brush.set(BrushSetting::ColorS, SettingValue::constant(hsv.s));
        brush.set(BrushSetting::ColorV, SettingValue::constant(hsv.v));
        // MyPaint's radius_logarithmic is the log of the dab's pixel radius.
        brush.set(
            BrushSetting::Radius,
            SettingValue::constant((width / 2.0).ln()),
        );
        self.preset = Some(PresetStroke {
            brush,
            state: BrushState::new(1000),
            surface: TrackedSurface::default(),
            published: HashMap::new(),
            pending: None,
        });
        self.covered.clear();
        self.last_hard = None;
        self.pending_hard = None;
        true
    }

    /// GDScript acknowledges the batch only after validating every source tile.
    /// A rejected GDScript read must rewind native pigment, dab RNG/cursor and
    /// the cached quantized output; retrying must be byte-identical.
    #[func]
    fn begin_preset_batch(&mut self) -> bool {
        let Some(stroke) = self.preset.as_mut() else {
            return false;
        };
        if stroke.pending.is_some() {
            return false;
        }
        stroke.pending = Some(PresetBatch {
            state: stroke.state.clone(),
            published: HashMap::new(),
        });
        stroke.surface.begin_batch();
        true
    }

    #[func]
    fn commit_preset_batch(&mut self) {
        if let Some(stroke) = self.preset.as_mut()
            && stroke.pending.take().is_some()
        {
            stroke.surface.commit_batch();
        }
    }

    #[func]
    fn rollback_preset_batch(&mut self) {
        if let Some(stroke) = self.preset.as_mut()
            && let Some(snapshot) = stroke.pending.take()
        {
            stroke.surface.rollback_batch();
            stroke.state = snapshot.state;
            for (position, exported) in snapshot.published {
                if let Some(exported) = exported {
                    stroke.published.insert(position, exported);
                } else {
                    stroke.published.remove(&position);
                }
            }
        }
    }

    /// One FFI call per sample batch. Only changed **quantized RGBA8** pixels
    /// cross the boundary, including reversions to transparent. Full 64x64
    /// Hokusai tiles stay native and are never restaged in their entirety.
    /// Result is [signed_x, signed_y, straight_rgba_le_as_i32] repeated.
    #[func]
    fn preset_segments(&mut self, points: PackedVector2Array, pressure: f32) -> PackedInt32Array {
        let mut output = PackedInt32Array::new();
        let Some(stroke) = self.preset.as_mut() else {
            return output;
        };
        // Check the entire batch before calling into the stateful brush.
        // Returning an empty array halfway through the loop used to leave
        // native pigment and pending dirty tiles behind for the next call,
        // while GDScript saw a harmless empty delta rather than a failed edit.
        if !pressure.is_finite()
            || points.as_slice().iter().any(|point| {
                !point.x.is_finite()
                    || !point.y.is_finite()
                    || point.x.abs() >= 1_000_000_000.0
                    || point.y.abs() >= 1_000_000_000.0
            })
        {
            return output;
        }
        for &point in points.as_slice() {
            stroke.brush.stroke_to(
                &mut stroke.state,
                &mut stroke.surface,
                point.x,
                point.y,
                pressure.clamp(0.0, 1.0),
                0.0,
                0.0,
                0.01,
            );
        }
        let mut dirty: Vec<_> = stroke.surface.changed.drain().collect();
        dirty.sort_unstable();
        for (tx, ty) in dirty {
            let Some(tile) = stroke.surface.tile(tx, ty) else {
                continue;
            };
            if let Some(batch) = stroke.pending.as_mut() {
                batch
                    .published
                    .entry((tx, ty))
                    .or_insert_with(|| stroke.published.get(&(tx, ty)).cloned());
            }
            let published = stroke.published.entry((tx, ty)).or_default();
            scan_changed_pixels(tile, published, |index, rgba| {
                output.push(tx * TILE_SIZE as i32 + (index % TILE_SIZE) as i32);
                output.push(ty * TILE_SIZE as i32 + (index / TILE_SIZE) as i32);
                output.push(rgba as i32);
            });
        }
        output
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
}
