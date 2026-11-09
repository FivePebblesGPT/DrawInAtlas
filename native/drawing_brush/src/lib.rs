//! Batched Drawing GDExtension. The legacy path remains available until parity,
//! packaging and owner-device latency are verified.
use std::collections::{HashMap, HashSet};

use godot::classes::IRefCounted;
use godot::prelude::*;
use hokusai::mapping::SettingValue;
use hokusai::tile_mem::MemSurface;
use hokusai::{Brush, BrushSetting, BrushState, TILE_SIZE, TiledSurface};

/// MemSurface with per-batch dirty tracking, independent of Hokusai's
/// internally nested atomic sections.
#[derive(Default)]
struct TrackedSurface {
    inner: MemSurface,
    changed: HashSet<(i32, i32)>,
}

impl TiledSurface for TrackedSurface {
    fn tile_request_start(&mut self, x: i32, y: i32) -> &mut hokusai::tile::TilePixels {
        self.changed.insert((x, y));
        self.inner.tile_request_start(x, y)
    }

    fn tile_request_end(&mut self, x: i32, y: i32) {
        self.inner.tile_request_end(x, y);
    }

    fn tile_lookup(&self, x: i32, y: i32) -> Option<&hokusai::tile::TilePixels> {
        self.inner.tile_lookup(x, y)
    }

    fn begin_atomic(&mut self) {
        self.inner.begin_atomic();
    }

    fn end_atomic(&mut self) -> Vec<(i32, i32)> {
        self.inner.end_atomic()
    }
}

/// Quantized output plus the last observed native fixed-point pixels. Most
/// Hokusai dabs touch only a small part of an already painted 64px tile.
/// Comparing the cheap fixed-point values before sRGB conversion avoids
/// converting all 4096 pixels again at every native batch boundary.
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

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct DrawingNativeBrush {
    base: Base<RefCounted>,
    last_hard: Option<Vector2>,
    covered: HashSet<(i32, i32)>,
    preset: Option<PresetStroke>,
}

#[godot_api]
impl IRefCounted for DrawingNativeBrush {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            last_hard: None,
            covered: HashSet::new(),
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
        self.preset = None;
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
        let mut output = PackedInt32Array::new();
        for window in windows {
            let delta = window.end - window.begin;
            let squared = delta.length_squared();
            for y in window.top..window.bottom {
                for x in window.left..window.right {
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
                        output.push(x);
                        output.push(y);
                    }
                }
            }
            self.last_hard = Some(window.end);
        }
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
        });
        self.covered.clear();
        self.last_hard = None;
        true
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
            let Some(tile) = stroke.surface.inner.tile(tx, ty) else {
                continue;
            };
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
