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

struct PresetStroke {
    brush: Brush,
    state: BrushState,
    surface: TrackedSurface,
    /// Last exported straight-alpha RGBA8 pixels; pixel-equal repeats never
    /// re-enter slow GDScript staging or preview generation.
    published: HashMap<(i32, i32), Vec<u32>>,
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
        let radius = width * 0.5;
        let mut output = PackedInt32Array::new();
        let mut last = self.last_hard;
        for &end in points.as_slice() {
            if !end.x.is_finite()
                || !end.y.is_finite()
                || end.x.abs() >= 1_000_000_000.0
                || end.y.abs() >= 1_000_000_000.0
            {
                result.set("ok", false);
                result.set("error", "Brush position exceeds safe coordinates");
                return result;
            }
            let begin = last.unwrap_or(end);
            let left = (begin.x.min(end.x) - radius - 0.5).floor() as i32;
            let right = (begin.x.max(end.x) + radius + 0.5).ceil() as i32;
            let top = (begin.y.min(end.y) - radius - 0.5).floor() as i32;
            let bottom = (begin.y.max(end.y) + radius + 0.5).ceil() as i32;
            let (mut left, mut right, mut top, mut bottom) = (left, right, top, bottom);
            if clip.size.x > 0 && clip.size.y > 0 {
                left = left.max(clip.position.x);
                right = right.min(clip.position.x.saturating_add(clip.size.x));
                top = top.max(clip.position.y);
                bottom = bottom.min(clip.position.y.saturating_add(clip.size.y));
            }
            let columns = i64::from(right) - i64::from(left);
            let rows = i64::from(bottom) - i64::from(top);
            if columns > 0 && rows > 0 {
                if columns * rows > 1_048_576 {
                    result.set("ok", false);
                    result.set(
                        "error",
                        "Native brush candidate window exceeds safety limit",
                    );
                    return result;
                }
                let delta = end - begin;
                let squared = delta.length_squared();
                for y in top..bottom {
                    for x in left..right {
                        if self.covered.contains(&(x, y)) {
                            continue;
                        }
                        let center = Vector2::new(x as f32 + 0.5, y as f32 + 0.5);
                        let fraction = if squared > 0.0 {
                            ((center - begin).dot(delta) / squared).clamp(0.0, 1.0)
                        } else {
                            0.0
                        };
                        let distance = center - (begin + delta * fraction);
                        if distance.length_squared() <= radius * radius {
                            self.covered.insert((x, y));
                            output.push(x);
                            output.push(y);
                        }
                    }
                }
            }
            last = Some(end);
        }
        self.last_hard = last;
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
        for &point in points.as_slice() {
            if !point.x.is_finite()
                || !point.y.is_finite()
                || point.x.abs() >= 1_000_000_000.0
                || point.y.abs() >= 1_000_000_000.0
            {
                return PackedInt32Array::new();
            }
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
            let published = stroke
                .published
                .entry((tx, ty))
                .or_insert_with(|| vec![0; TILE_SIZE * TILE_SIZE]);
            for (row, tile_row) in tile.iter().enumerate() {
                for (column, pixel) in tile_row.iter().enumerate() {
                    let alpha = hokusai::fix15::to_f32(pixel[3]).clamp(0.0, 1.0);
                    let mut rgba = 0_u32;
                    for (index, &channel) in pixel.iter().take(3).enumerate() {
                        let linear = if alpha > 0.0 {
                            hokusai::fix15::to_f32(channel) / alpha
                        } else {
                            0.0
                        };
                        let value = (hokusai::color::linear_to_srgb(linear).clamp(0.0, 1.0) * 255.0)
                            .round() as u32;
                        rgba |= value << (8 * index);
                    }
                    rgba |= ((alpha * 255.0).round() as u32) << 24;
                    let index = row * TILE_SIZE + column;
                    if rgba != published[index] {
                        published[index] = rgba;
                        output.push(tx * TILE_SIZE as i32 + column as i32);
                        output.push(ty * TILE_SIZE as i32 + row as i32);
                        output.push(rgba as i32);
                    }
                }
            }
        }
        output
    }
}

struct DrawingBrushExtension;

// No Godot scene APIs are used by this Rust class outside the engine main thread.
#[gdextension]
unsafe impl ExtensionLibrary for DrawingBrushExtension {}
