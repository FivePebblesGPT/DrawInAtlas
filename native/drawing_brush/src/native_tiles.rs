//! T-148 native canonical RGBA8 tile store. Godot may import authorized source
//! tiles and read immutable byte copies, but painting and history live in Rust.
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};

use godot::classes::IRefCounted;
use godot::prelude::*;

static NEXT_EDIT: AtomicU64 = AtomicU64::new(1);
const MAX_ACTIVE_TILES: usize = 128;
const MAX_TILE_BYTES: usize = 2048 * 2048 * 4;
const MAX_STORED_BYTES: usize = 256 * 1024 * 1024;
const MAX_HISTORY: usize = 64;
const SAFE_COORD: i64 = 1 << 60;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct TileId {
    layer: String,
    x: i64,
    y: i64,
}

#[derive(Clone, PartialEq, Eq)]
struct Tile {
    rgba: Vec<u8>,
    generation: u64,
}

type PackedTileChanges = HashMap<(i64, i64), Vec<(usize, usize, u32)>>;

#[derive(Clone, Copy, PartialEq, Eq)]
struct Dirty {
    left: usize,
    top: usize,
    right: usize,
    bottom: usize,
}
impl Dirty {
    fn include(&mut self, x: usize, y: usize) {
        self.left = self.left.min(x);
        self.top = self.top.min(y);
        self.right = self.right.max(x + 1);
        self.bottom = self.bottom.max(y + 1);
    }
}

struct Edit {
    id: i64,
    layer: String,
    base_revision: u64,
    selection_required: bool,
    masks: HashMap<TileId, Vec<u8>>,
    before: HashMap<TileId, Tile>,
    draft: HashMap<TileId, Tile>,
    dirty: HashMap<TileId, Dirty>,
    batches: u64,
}

struct History {
    token: i64,
    layer: String,
    before: HashMap<TileId, Tile>,
    after: HashMap<TileId, Tile>,
}

/// A separate source authorization set prevents an omitted/lazy/corrupt tile
/// from silently becoming transparent black. Blank tiles must be authorized.
#[derive(Default)]
pub(super) struct TileStore {
    stride: usize,
    revision: u64,
    tiles: HashMap<TileId, Tile>,
    authorized: HashSet<TileId>,
    /// Removed but undoable raster layers retain canonical pixels and tokens.
    parked_layers: HashSet<String>,
    editable_layers: HashMap<String, bool>,
    active: Option<Edit>,
    undo: Vec<History>,
    redo: Vec<History>,
    pub(super) ffi_calls: u64,
    bytes_imported: u64,
    bytes_exported: u64,
    external_bytes_received: u64,
    pixel_stream_calls: u64,
}

impl TileStore {
    pub(super) fn transaction_matches(&self, transaction: i64, revision: i64, layer: &str) -> bool {
        revision >= 0
            && self.active.as_ref().is_some_and(|edit| {
                edit.id == transaction
                    && edit.layer == layer
                    && edit.base_revision == revision as u64
                    && self.revision == revision as u64
            })
    }
    fn stride_bytes(&self) -> Result<usize, &'static str> {
        self.stride
            .checked_mul(self.stride)
            .and_then(|pixels| pixels.checked_mul(4))
            .filter(|len| *len > 0 && *len <= MAX_TILE_BYTES)
            .ok_or("Invalid or unconfigured tile stride")
    }
    fn allowed(&self, layer: &str) -> bool {
        self.editable_layers.get(layer).copied().unwrap_or(false)
    }
    fn bytes_used(&self) -> usize {
        let resident = self.tiles.values().map(|t| t.rgba.len()).sum::<usize>();
        let current = self.active.as_ref().map_or(0, |a| {
            a.draft.values().map(|t| t.rgba.len()).sum::<usize>()
                + a.before.values().map(|t| t.rgba.len()).sum::<usize>()
                + a.masks.values().map(Vec::len).sum::<usize>()
        });
        let history = self
            .undo
            .iter()
            .chain(self.redo.iter())
            .map(|h| {
                h.before
                    .values()
                    .chain(h.after.values())
                    .map(|t| t.rgba.len())
                    .sum::<usize>()
            })
            .sum::<usize>();
        resident.saturating_add(current).saturating_add(history)
    }
    fn import(&mut self, id: TileId, revision: u64, rgba: &[u8]) -> Result<(), &'static str> {
        let len = self.stride_bytes()?;
        if revision != self.revision
            || (!rgba.is_empty() && rgba.len() != len)
            || id.layer.is_empty()
            || id.x.unsigned_abs() > SAFE_COORD as u64
            || id.y.unsigned_abs() > SAFE_COORD as u64
            || self.authorized.contains(&id)
            || self.parked_layers.contains(&id.layer)
            || self
                .active
                .as_ref()
                .is_some_and(|a| a.draft.contains_key(&id))
        {
            return Err("Source revision, identity or RGBA8 tile buffer rejected");
        }
        if self.bytes_used().saturating_add(len) > MAX_STORED_BYTES {
            return Err("Source tile memory budget exceeded");
        }
        let data = if rgba.is_empty() {
            vec![0; len]
        } else {
            rgba.to_vec()
        };
        self.tiles.insert(
            id.clone(),
            Tile {
                rgba: data,
                generation: 0,
            },
        );
        self.authorized.insert(id);
        self.bytes_imported += rgba.len() as u64;
        Ok(())
    }
    fn begin(
        &mut self,
        layer: &str,
        revision: u64,
        selection_required: bool,
    ) -> Result<i64, &'static str> {
        if revision != self.revision
            || !self.allowed(layer)
            || self.parked_layers.contains(layer)
            || self.active.is_some()
        {
            return Err("Stale revision, locked/hidden layer or active edit");
        }
        let id = NEXT_EDIT.fetch_add(1, Ordering::Relaxed) as i64;
        self.active = Some(Edit {
            id,
            layer: layer.to_owned(),
            base_revision: revision,
            selection_required,
            masks: HashMap::new(),
            before: HashMap::new(),
            draft: HashMap::new(),
            dirty: HashMap::new(),
            batches: 0,
        });
        Ok(id)
    }
    fn mask(&mut self, transaction: i64, id: TileId, mask: &[u8]) -> Result<(), &'static str> {
        let len = self.stride_bytes()? / 4;
        let active = self.active.as_ref().ok_or("No active tile transaction")?;
        if active.id != transaction
            || active.layer != id.layer
            || !active.selection_required
            || mask.len() != len
            || active.draft.contains_key(&id)
            || active.masks.contains_key(&id)
            || !self.authorized.contains(&id)
            || active.masks.len() >= MAX_ACTIVE_TILES
            || self.bytes_used().saturating_add(len) > MAX_STORED_BYTES
        {
            return Err("Invalid, unauthorized or over-budget selection tile mask");
        }
        self.active
            .as_mut()
            .expect("active preflight")
            .masks
            .insert(id, mask.to_vec());
        Ok(())
    }
    /// Called *inside Rust* with NativeStroke's pending output, never across
    /// Godot as pixel coordinates. The whole batch is preflighted and cloned
    /// into a detached working set before modifying the active transaction.
    #[allow(clippy::too_many_arguments)] // Native ABI context is explicit.
    pub(super) fn stage(
        &mut self,
        transaction: i64,
        revision: u64,
        anchor_x: i64,
        anchor_y: i64,
        deltas: &[i32],
        pigment: bool,
        brush_rgba: u32,
        erase: bool,
        clip: Rect2i,
    ) -> Result<usize, &'static str> {
        let step = if pigment { 3 } else { 2 };
        if !deltas.len().is_multiple_of(step) || deltas.len() > 3 * 1_048_576 {
            return Err("Invalid native sample output");
        }
        let active = self.active.as_ref().ok_or("No tile transaction")?;
        if active.id != transaction
            || active.base_revision != revision
            || self.revision != revision
            || !self.allowed(&active.layer)
        {
            return Err("Stale revision or unavailable tile layer");
        }
        let mut grouped: PackedTileChanges = HashMap::new();
        let stride = self.stride as i64;
        for delta in deltas.chunks_exact(step) {
            if clip.size.x > 0
                && clip.size.y > 0
                && !clip.contains_point(Vector2i::new(delta[0], delta[1]))
            {
                continue;
            }
            let x = anchor_x
                .checked_add(i64::from(delta[0]))
                .ok_or("Signed X overflow")?;
            let y = anchor_y
                .checked_add(i64::from(delta[1]))
                .ok_or("Signed Y overflow")?;
            if x.unsigned_abs() > SAFE_COORD as u64 || y.unsigned_abs() > SAFE_COORD as u64 {
                return Err("Signed native sample outside tile bounds");
            }
            let coords = (x.div_euclid(stride), y.div_euclid(stride));
            let ix = x.rem_euclid(stride) as usize;
            let iy = y.rem_euclid(stride) as usize;
            let pigment_rgba = if pigment { delta[2] as u32 } else { brush_rgba };
            let rgba = if pigment {
                let alpha = ((pigment_rgba >> 24) & 255) * ((brush_rgba >> 24) & 255);
                (pigment_rgba & 0xffffff) | (((alpha + 127) / 255) << 24)
            } else {
                pigment_rgba
            };
            grouped.entry(coords).or_default().push((ix, iy, rgba));
        }
        let active = self.active.as_ref().expect("checked above");
        let new_count = grouped
            .keys()
            .filter(|&&(x, y)| {
                !active.draft.contains_key(&TileId {
                    layer: active.layer.clone(),
                    x,
                    y,
                })
            })
            .count();
        if active.draft.len() + new_count > MAX_ACTIVE_TILES {
            return Err("Native edit exceeds touched-tile budget");
        }
        let bytes = self.stride_bytes()?;
        if self
            .bytes_used()
            .saturating_add(new_count * bytes * 2 + grouped.len() * bytes)
            > MAX_STORED_BYTES
        {
            return Err("Native edit exceeds memory budget");
        }
        let mut updated: HashMap<TileId, Tile> = HashMap::new();
        let mut dirty: HashMap<TileId, Dirty> = HashMap::new();
        for ((tx, ty), changes) in grouped {
            let id = TileId {
                layer: active.layer.clone(),
                x: tx,
                y: ty,
            };
            if !self.authorized.contains(&id) {
                return Err("Source tile not authorized or read failed");
            }
            let mask = if active.selection_required {
                Some(active.masks.get(&id).ok_or("Selection mask not loaded")?)
            } else {
                None
            };
            let mut tile = active
                .draft
                .get(&id)
                .or_else(|| self.tiles.get(&id))
                .ok_or("Source tile not resident")?
                .clone();
            let mut tile_dirty: Option<Dirty> = None;
            for (x, y, rgba) in changes {
                if mask.is_some_and(|selection| selection[y * self.stride + x] == 0) {
                    continue;
                }
                let offset = (y * self.stride + x) * 4;
                let dest = u32::from_le_bytes(
                    tile.rgba[offset..offset + 4]
                        .try_into()
                        .expect("RGBA8 offset"),
                );
                let next = if erase && pigment {
                    // Erase using the same MyPaint dab alpha as Brush, rebased
                    // onto immutable source across successive preview batches.
                    // Keep hidden RGB when the source was already transparent.
                    let original = u32::from_le_bytes(
                        self.tiles.get(&id).expect("authorized source").rgba[offset..offset + 4]
                            .try_into()
                            .expect("source RGBA8"),
                    );
                    let strength = (rgba >> 24) & 255;
                    let original_alpha = (original >> 24) & 255;
                    let remaining = (original_alpha * (255 - strength) + 127) / 255;
                    (original & 0x00ff_ffff) | (remaining << 24)
                } else if erase {
                    0
                } else if pigment {
                    // Hokusai's pigment is rebased against immutable source,
                    // not repeatedly blended over the previous preview.
                    let source = &self.tiles.get(&id).expect("authorized source").rgba;
                    let original = u32::from_le_bytes(
                        source[offset..offset + 4].try_into().expect("source RGBA8"),
                    );
                    blend(rgba, original)
                } else {
                    blend(rgba, dest)
                };
                if next != dest {
                    tile.rgba[offset..offset + 4].copy_from_slice(&next.to_le_bytes());
                    if let Some(area) = &mut tile_dirty {
                        area.include(x, y);
                    } else {
                        tile_dirty = Some(Dirty {
                            left: x,
                            top: y,
                            right: x + 1,
                            bottom: y + 1,
                        });
                    }
                }
            }
            if let Some(area) = tile_dirty {
                dirty.insert(id.clone(), area);
                updated.insert(id, tile);
            }
        }
        let touched = dirty.len();
        let active = self.active.as_mut().expect("checked above");
        for (id, tile) in updated {
            active
                .before
                .entry(id.clone())
                .or_insert_with(|| self.tiles.get(&id).expect("authorized").clone());
            active.draft.insert(id, tile);
        }
        for (id, area) in dirty {
            active
                .dirty
                .entry(id)
                .and_modify(|b| {
                    b.include(area.left, area.top);
                    b.include(area.right - 1, area.bottom - 1);
                })
                .or_insert(area);
        }
        active.batches += 1;
        Ok(touched)
    }
    /// A no-op gesture does not advance the canonical revision or create
    /// history. Only the paired native brush commit path consumes it.
    pub(super) fn finish_noop(&mut self, transaction: i64, revision: u64) -> bool {
        let Some(edit) = self.active.as_ref() else {
            return false;
        };
        if edit.id != transaction
            || edit.base_revision != revision
            || self.revision != revision
            || !self.allowed(&edit.layer)
        {
            return false;
        }
        if edit
            .draft
            .iter()
            .any(|(id, draft)| self.tiles.get(id).is_none_or(|src| src.rgba != draft.rgba))
        {
            return false;
        }
        self.active = None;
        true
    }
    pub(super) fn commit(
        &mut self,
        transaction: i64,
        revision: u64,
    ) -> Result<usize, &'static str> {
        let edit = self.active.as_ref().ok_or("No native edit")?;
        if edit.id != transaction
            || edit.base_revision != revision
            || self.revision != revision
            || !self.allowed(&edit.layer)
        {
            return Err("Stale, inaccessible or mismatched edit");
        }
        if edit.draft.is_empty()
            || edit
                .draft
                .iter()
                .all(|(id, draft)| self.tiles.get(id).is_some_and(|t| t.rgba == draft.rgba))
        {
            return Err("Edit has no changed tiles");
        }
        if self.bytes_used() > MAX_STORED_BYTES {
            return Err("History memory budget exceeded");
        }
        let mut edit = self.active.take().expect("checked above");
        let mut after = HashMap::new();
        for (id, mut tile) in edit.draft.drain() {
            if self.tiles.get(&id).is_some_and(|old| old.rgba == tile.rgba) {
                edit.before.remove(&id);
                continue;
            }
            tile.generation = self.tiles.get(&id).map_or(1, |old| old.generation + 1);
            after.insert(id.clone(), tile.clone());
            self.tiles.insert(id, tile);
        }
        let count = after.len();
        self.undo.push(History {
            token: edit.id,
            layer: edit.layer,
            before: edit.before,
            after,
        });
        self.redo.clear();
        if self.undo.len() > MAX_HISTORY {
            self.undo.remove(0);
        }
        self.revision += 1;
        Ok(count)
    }
    /// Atomically adopt an already-preflighted, non-brush raster publication.
    /// Each input names a complete before/after tile. Absent source tiles are
    /// authorized only by this explicit before image; resident sources must
    /// match byte-for-byte. No store bytes, revision, or history change on error.
    fn adopt_external(
        &mut self,
        layer: &str,
        revision: u64,
        changes: Vec<(TileId, Vec<u8>, Vec<u8>)>,
    ) -> Result<(i64, usize), &'static str> {
        self.apply_external_tiles(layer, revision, changes, true)
    }

    /// Check a detached snapshot against resident or explicitly supplied source
    /// without inventing a Rust undo token outside the document timeline.
    /// The current native source must match every expected tile. On success,
    /// all older Rust tokens are invalidated, but unrelated canonical tiles
    /// remain resident and the shared revision advances exactly once.
    fn replay_detached(
        &mut self,
        layer: &str,
        revision: u64,
        changes: Vec<(TileId, Vec<u8>, Vec<u8>)>,
    ) -> Result<usize, &'static str> {
        self.apply_external_tiles(layer, revision, changes, false)
            .map(|(_, count)| count)
    }

    fn apply_external_tiles(
        &mut self,
        layer: &str,
        revision: u64,
        changes: Vec<(TileId, Vec<u8>, Vec<u8>)>,
        record_history: bool,
    ) -> Result<(i64, usize), &'static str> {
        let len = self.stride_bytes()?;
        if self.revision != revision
            || self.active.is_some()
            || !self.allowed(layer)
            || self.parked_layers.contains(layer)
        {
            return Err("Stale revision, active transaction or inaccessible layer");
        }
        if changes.is_empty() || changes.len() > MAX_ACTIVE_TILES || revision == i64::MAX as u64 {
            return Err("External edit exceeds bounded tile transaction");
        }
        let count = changes.len();
        let mut seen = HashSet::new();
        let mut new_tiles = 0usize;
        let mut prepared = Vec::with_capacity(count);
        for (id, original, replacement) in changes {
            if id.layer != layer
                || id.x.unsigned_abs() > SAFE_COORD as u64
                || id.y.unsigned_abs() > SAFE_COORD as u64
                || !seen.insert(id.clone())
                || !(original.is_empty() || original.len() == len)
                || !(replacement.len() == len || (!record_history && replacement.is_empty()))
            {
                return Err("Invalid, repeated or malformed external tile");
            }
            let before_bytes = if original.is_empty() {
                vec![0; len]
            } else {
                original
            };
            let after_bytes = if replacement.is_empty() {
                vec![0; len]
            } else {
                replacement
            };
            if before_bytes == after_bytes {
                return Err("External tile did not change");
            }
            let existing = self.tiles.get(&id);
            if self.authorized.contains(&id) != existing.is_some()
                || existing.is_some_and(|source| source.rgba != before_bytes)
            {
                return Err("External source differs from authorized native tile");
            }
            if existing.is_none() {
                new_tiles += 1;
            }
            let generation = existing.map_or(0, |t| t.generation);
            let next = generation
                .checked_add(1)
                .ok_or("Tile generation overflow")?;
            prepared.push((
                id,
                Tile {
                    rgba: before_bytes,
                    generation,
                },
                Tile {
                    rgba: after_bytes,
                    generation: next,
                },
            ));
        }
        // Check resident growth and (for a normal edit) both history images
        // before touching canonical source, revision or either history stack.
        let extra_tiles = new_tiles.saturating_add(if record_history {
            count.saturating_mul(2)
        } else {
            0
        });
        if self
            .bytes_used()
            .saturating_add(extra_tiles.saturating_mul(len))
            > MAX_STORED_BYTES
        {
            return Err("External edit exceeds native raster memory budget");
        }
        let token = if record_history {
            NEXT_EDIT.fetch_add(1, Ordering::Relaxed) as i64
        } else {
            0
        };
        let mut before = HashMap::with_capacity(if record_history { count } else { 0 });
        let mut after = HashMap::with_capacity(if record_history { count } else { 0 });
        for (id, original, replacement) in prepared {
            self.authorized.insert(id.clone());
            if record_history {
                before.insert(id.clone(), original);
                after.insert(id.clone(), replacement.clone());
            }
            self.tiles.insert(id, replacement);
        }
        if record_history {
            self.undo.push(History {
                token,
                layer: layer.to_owned(),
                before,
                after,
            });
            self.redo.clear();
            if self.undo.len() > MAX_HISTORY {
                self.undo.remove(0);
            }
        } else {
            self.undo.clear();
            self.redo.clear();
        }
        self.revision += 1;
        Ok((token, count))
    }
    /// External (non-brush) edits retain the document revision as the sole
    /// serialized source of truth. Rebase *only* at a quiescent boundary:
    /// all previously imported tiles/history become invalid and must be
    /// reauthorized from the current document before another native stroke.
    fn rebase_external(&mut self, expected: u64, next: u64) -> Result<(), &'static str> {
        if self.active.is_some()
            || self.revision != expected
            || next <= expected
            || next > i64::MAX as u64
        {
            return Err("Active transaction, stale or non-increasing external revision");
        }
        self.tiles.clear();
        self.authorized.clear();
        self.undo.clear();
        self.redo.clear();
        self.parked_layers.clear();
        self.revision = next;
        Ok(())
    }

    /// Mirror a document-only metadata/tree revision without touching canonical
    /// raster bytes or their reversible native history. New edits invalidate
    /// native redo; history replay only advances the shared revision stamp.
    /// Source-changing tree operations must use the conservative rebase path.
    fn advance_metadata(&mut self, expected: u64, discard_redo: bool) -> Result<(), &'static str> {
        if self.active.is_some() || self.revision != expected || expected >= i64::MAX as u64 {
            return Err("Active transaction, stale or overflowing metadata revision");
        }
        if discard_redo {
            self.redo.clear();
        }
        self.revision = expected + 1;
        Ok(())
    }

    /// A raster layer that has never been imported into this store can be
    /// removed/restored as a structural edit: no canonical tile or reversible
    /// history event belongs to it. Unlike an unconditional metadata advance,
    /// this fails closed for even an authorized *blank* tile and for redo.
    fn advance_unreferenced_layers(
        &mut self,
        expected: u64,
        layers: &[String],
        discard_redo: bool,
    ) -> Result<(), &'static str> {
        if self.active.is_some() || self.revision != expected || expected >= i64::MAX as u64 {
            return Err("Active edit, stale or overflowing structural revision");
        }
        if layers.is_empty() || layers.len() > MAX_ACTIVE_TILES {
            return Err("Invalid structural raster-layer count");
        }
        let mut names = HashSet::with_capacity(layers.len());
        if layers
            .iter()
            .any(|name| name.is_empty() || !names.insert(name.as_str()))
        {
            return Err("Invalid or repeated structural raster-layer ID");
        }
        if self
            .parked_layers
            .iter()
            .any(|layer| names.contains(layer.as_str()))
            || self
                .tiles
                .keys()
                .any(|id| names.contains(id.layer.as_str()))
            || self
                .authorized
                .iter()
                .any(|id| names.contains(id.layer.as_str()))
            || self.undo.iter().chain(self.redo.iter()).any(|entry| {
                names.contains(entry.layer.as_str())
                    || entry
                        .before
                        .keys()
                        .chain(entry.after.keys())
                        .any(|id| names.contains(id.layer.as_str()))
            })
        {
            return Err("Raster layer has native tile ownership or history");
        }
        self.advance_metadata(expected, discard_redo)
    }

    /// An unrecorded structural removal has no future tree Undo to restore its
    /// pixels. Retire only the specified layer IDs, including their native
    /// source authorization and tile history; unrelated layer tokens survive.
    /// All validation happens before a single mutation boundary.
    fn retire_layers(
        &mut self,
        expected: u64,
        layers: &[String],
        discard_redo: bool,
    ) -> Result<(), &'static str> {
        if self.active.is_some() || self.revision != expected || expected >= i64::MAX as u64 {
            return Err("Active edit, stale or overflowing retire revision");
        }
        if layers.is_empty() || layers.len() > MAX_ACTIVE_TILES {
            return Err("Invalid retired raster-layer count");
        }
        let mut ids = HashSet::with_capacity(layers.len());
        if layers
            .iter()
            .any(|id| id.is_empty() || !ids.insert(id.as_str()) || self.parked_layers.contains(id))
        {
            return Err("Invalid, repeated or parked retired raster-layer ID");
        }
        self.tiles
            .retain(|tile, _| !ids.contains(tile.layer.as_str()));
        self.authorized
            .retain(|tile| !ids.contains(tile.layer.as_str()));
        self.editable_layers
            .retain(|id, _| !ids.contains(id.as_str()));
        self.undo.retain(|event| {
            !ids.contains(event.layer.as_str())
                && !event
                    .before
                    .keys()
                    .chain(event.after.keys())
                    .any(|tile| ids.contains(tile.layer.as_str()))
        });
        if discard_redo {
            self.redo.clear();
        } else {
            self.redo.retain(|event| {
                !ids.contains(event.layer.as_str())
                    && !event
                        .before
                        .keys()
                        .chain(event.after.keys())
                        .any(|tile| ids.contains(tile.layer.as_str()))
            });
        }
        self.revision = expected + 1;
        Ok(())
    }

    /// Park or restore a history-backed raster subtree as a reversible tree
    /// mutation. Canonical tile bytes, authorizations and Undo/Redo tokens are
    /// deliberately not released: history can only address a parked layer
    /// after structural Undo restores it. Every ID is checked before mutation.
    fn advance_parked_layers(
        &mut self,
        expected: u64,
        layers: &[String],
        restore: bool,
        discard_redo: bool,
    ) -> Result<(), &'static str> {
        if self.active.is_some() || self.revision != expected || expected >= i64::MAX as u64 {
            return Err("Active edit, stale or overflowing parked-layer revision");
        }
        if layers.is_empty() || layers.len() > MAX_ACTIVE_TILES {
            return Err("Invalid parked layer count");
        }
        let mut seen = HashSet::with_capacity(layers.len());
        for layer in layers {
            if layer.is_empty()
                || !seen.insert(layer)
                || self.parked_layers.contains(layer) != restore
            {
                return Err("Duplicate ID or wrong parked-layer lifecycle");
            }
        }
        if !restore {
            if self.parked_layers.len().saturating_add(layers.len()) > MAX_ACTIVE_TILES {
                return Err("Too many retained parked-layer identities");
            }
            // Unreferenced layers use the metadata-only structural bridge.
            // Never accumulate tombstones for arbitrary empty layer names.
            let owned = self.authorized.iter().any(|id| seen.contains(&id.layer))
                || self.tiles.keys().any(|id| seen.contains(&id.layer))
                || self
                    .undo
                    .iter()
                    .chain(self.redo.iter())
                    .any(|entry| seen.contains(&entry.layer));
            if !owned {
                return Err("Structural subtree has no native-owned source or history");
            }
        }
        if restore {
            for layer in layers {
                self.parked_layers.remove(layer);
            }
        } else {
            for layer in layers {
                self.parked_layers.insert(layer.clone());
            }
        }
        if discard_redo {
            self.redo.clear();
        }
        self.revision = expected + 1;
        Ok(())
    }

    fn history_matches(&self, token: i64, undo: bool) -> bool {
        if token <= 0 || self.active.is_some() {
            return false;
        }
        let stack = if undo { &self.undo } else { &self.redo };
        stack
            .last()
            .is_some_and(|event| event.token == token && !self.parked_layers.contains(&event.layer))
    }

    /// Validate the detached document history payload against the live Rust
    /// event *and* canonical source. Godot's history buffers are caller-owned
    /// and may be modified independently of the opaque native token. Replay
    /// must never publish a Godot projection different from Rust's history.
    fn history_tiles_match(
        &self,
        token: i64,
        undo: bool,
        layer: &str,
        entries: &[(TileId, Vec<u8>, Vec<u8>)],
    ) -> bool {
        if !self.history_matches(token, undo)
            || entries.is_empty()
            || entries.len() > MAX_ACTIVE_TILES
        {
            return false;
        }
        let Some(event) = (if undo { &self.undo } else { &self.redo }).last() else {
            return false;
        };
        if event.layer != layer
            || event.before.len() != entries.len()
            || event.after.len() != entries.len()
        {
            return false;
        }
        let Ok(length) = self.stride_bytes() else {
            return false;
        };
        let matches_bytes = |native: &[u8], provided: &[u8]| {
            (provided.is_empty() && native.iter().all(|byte| *byte == 0))
                || (provided.len() == length && native == provided)
        };
        let mut ids = HashSet::with_capacity(entries.len());
        for (id, expected, replacement) in entries {
            if id.layer != layer
                || id.x.unsigned_abs() > SAFE_COORD as u64
                || id.y.unsigned_abs() > SAFE_COORD as u64
                || !ids.insert(id)
            {
                return false;
            }
            let (from, to) = if undo {
                (&event.after, &event.before)
            } else {
                (&event.before, &event.after)
            };
            let (Some(source), Some(target), Some(current)) =
                (from.get(id), to.get(id), self.tiles.get(id))
            else {
                return false;
            };
            if !matches_bytes(&source.rgba, expected)
                || !matches_bytes(&target.rgba, replacement)
                || current.rgba != source.rgba
            {
                return false;
            }
        }
        true
    }

    fn undo_or_redo(&mut self, undo: bool) -> Result<usize, &'static str> {
        if self.active.is_some() {
            return Err("Cannot replay while a tile transaction is open");
        }
        let (from, to) = if undo {
            (&mut self.undo, &mut self.redo)
        } else {
            (&mut self.redo, &mut self.undo)
        };
        let entry = from.last().ok_or("No native history entry")?;
        if self.parked_layers.contains(&entry.layer)
            || !self
                .editable_layers
                .get(&entry.layer)
                .copied()
                .unwrap_or(false)
        {
            return Err("History layer is locked/hidden");
        }
        let entry = from.pop().expect("checked above");
        let (replacements, count) = if undo {
            (&entry.before, entry.before.len())
        } else {
            (&entry.after, entry.after.len())
        };
        for (id, tile) in replacements {
            let mut copy = tile.clone();
            copy.generation = self.tiles.get(id).map_or(1, |old| old.generation + 1);
            self.tiles.insert(id.clone(), copy);
        }
        to.push(entry);
        self.revision += 1;
        Ok(count)
    }
    fn read(&self, id: &TileId, pending: bool) -> Option<&Tile> {
        if pending
            && let Some(edit) = self.active.as_ref()
            && let Some(tile) = edit.draft.get(id)
        {
            return Some(tile);
        }
        self.tiles.get(id)
    }
}

fn blend(source: u32, dest: u32) -> u32 {
    let a = ((source >> 24) & 255) as f64;
    if a == 0.0 {
        return dest;
    }
    if a == 255.0 || (dest >> 24) == 0 {
        return source;
    }
    let da = ((dest >> 24) & 255) as f64 / 255.0;
    let sa = a / 255.0;
    let out_a = sa + da * (1.0 - sa);
    let mut out = ((out_a * 255.0).round() as u32).min(255) << 24;
    for channel in 0..3 {
        let shift = channel * 8;
        let s = ((source >> shift) & 255) as f64;
        let d = ((dest >> shift) & 255) as f64;
        let c = ((s * sa + d * da * (1.0 - sa)) / out_a).round() as u32;
        out |= c.min(255) << shift;
    }
    out
}

fn err(message: &str) -> Dictionary<Variant, Variant> {
    let mut result = Dictionary::new();
    result.set("ok", false);
    result.set("error", message);
    result
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub(super) struct DrawingNativeTiles {
    base: Base<RefCounted>,
    pub(super) store: TileStore,
}

#[godot_api]
impl IRefCounted for DrawingNativeTiles {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            store: TileStore::default(),
        }
    }
}

#[godot_api]
impl DrawingNativeTiles {
    #[func]
    fn tile_abi_version(&self) -> i32 {
        1
    }

    #[func]
    fn configure(&mut self, stride: i64, revision: i64) -> bool {
        if self.store.stride != 0 || !(16..=2048).contains(&stride) || revision < 0 {
            return false;
        }
        self.store.stride = stride as usize;
        self.store.revision = revision as u64;
        true
    }

    /// This is a checked bridge for changes made by *other* document APIs.
    /// Native tiles remain canonical between native gestures; an external
    /// mutation invalidates imports rather than silently reusing old pixels.
    #[func]
    fn rebase_external_revision(&mut self, expected: i64, next: i64) -> bool {
        self.store.ffi_calls += 1;
        expected >= 0
            && next >= 0
            && self
                .store
                .rebase_external(expected as u64, next as u64)
                .is_ok()
    }

    /// Quiescent, single-step non-raster revision bridge. The document must
    /// call this only for mutations that leave canonical RGBA8 source unchanged.
    /// A rejection cannot mutate native revision, tiles or history.
    #[func]
    fn advance_metadata_revision(&mut self, expected: i64, discard_redo: bool) -> bool {
        self.store.ffi_calls += 1;
        expected >= 0
            && self
                .store
                .advance_metadata(expected as u64, discard_redo)
                .is_ok()
    }

    /// Structural creation/deletion/restore of previously unimported raster
    /// layers only. This is not a bulk tile-delete API; it never alters pixels.
    #[func]
    fn advance_unreferenced_layers_revision(
        &mut self,
        expected: i64,
        layers: PackedStringArray,
        discard_redo: bool,
    ) -> bool {
        self.store.ffi_calls += 1;
        if expected < 0 || layers.is_empty() || layers.len() > MAX_ACTIVE_TILES {
            return false;
        }
        let ids: Vec<String> = layers.as_slice().iter().map(|id| id.to_string()).collect();
        self.store
            .advance_unreferenced_layers(expected as u64, &ids, discard_redo)
            .is_ok()
    }

    /// A direct unrecorded deletion permanently retires the named raster
    /// layers. Their history tokens cannot later be replayed; other raster
    /// layers retain their canonical bytes and reversible native events.
    #[func]
    fn retire_layers_revision(
        &mut self,
        expected: i64,
        layers: PackedStringArray,
        discard_redo: bool,
    ) -> bool {
        self.store.ffi_calls += 1;
        if expected < 0 || layers.is_empty() || layers.len() > MAX_ACTIVE_TILES {
            return false;
        }
        let ids: Vec<String> = layers.as_slice().iter().map(|id| id.to_string()).collect();
        self.store
            .retire_layers(expected as u64, &ids, discard_redo)
            .is_ok()
    }

    /// Quiescent structural removal/restoration of raster layers already
    /// owned by Rust. No bytes leave Rust; parked layers cannot be painted,
    /// imported or replayed until structural Undo restores the same IDs.
    #[func]
    fn advance_parked_layers_revision(
        &mut self,
        expected: i64,
        layers: PackedStringArray,
        restore: bool,
        discard_redo: bool,
    ) -> bool {
        self.store.ffi_calls += 1;
        if expected < 0 || layers.is_empty() || layers.len() > MAX_ACTIVE_TILES {
            return false;
        }
        let ids: Vec<String> = layers.as_slice().iter().map(|id| id.to_string()).collect();
        self.store
            .advance_parked_layers(expected as u64, &ids, restore, discard_redo)
            .is_ok()
    }

    #[func]
    fn is_layer_parked(&self, layer: GString) -> bool {
        self.store.parked_layers.contains(&layer.to_string())
    }

    /// One bounded FFI call for a preflighted external raster edit. The
    /// document installs detached display/save tiles only after this returns.
    /// Entries: tile_x/y, before/after PackedByteArray (empty before = blank).
    #[func]
    fn adopt_external_edit(
        &mut self,
        layer: GString,
        expected_revision: i64,
        tiles: Array<Dictionary<Variant, Variant>>,
    ) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        if expected_revision < 0 || tiles.is_empty() || tiles.len() > MAX_ACTIVE_TILES {
            return err("Invalid external edit revision or tile count");
        }
        let mut changes = Vec::with_capacity(tiles.len());
        for entry in tiles.iter_shared() {
            let Some((x, y, before, after)) = (|| {
                Some((
                    entry.get("tile_x")?.try_to::<i64>().ok()?,
                    entry.get("tile_y")?.try_to::<i64>().ok()?,
                    entry.get("before")?.try_to::<PackedByteArray>().ok()?,
                    entry.get("after")?.try_to::<PackedByteArray>().ok()?,
                ))
            })() else {
                return err("Malformed external tile descriptor");
            };
            self.store.external_bytes_received = self
                .store
                .external_bytes_received
                .saturating_add(before.len().saturating_add(after.len()) as u64);
            changes.push((
                TileId {
                    layer: layer.to_string(),
                    x,
                    y,
                },
                before.as_slice().to_vec(),
                after.as_slice().to_vec(),
            ));
        }
        match self
            .store
            .adopt_external(&layer.to_string(), expected_revision as u64, changes)
        {
            Ok((token, count)) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("history_token", token);
                result.set("tiles", count as i64);
                result.set("revision", self.store.revision as i64);
                result
            }
            Err(message) => err(message),
        }
    }

    #[func]
    fn has_source(&self, layer: GString, x: i64, y: i64, revision: i64) -> bool {
        revision >= 0
            && revision as u64 == self.store.revision
            && self.store.authorized.contains(&TileId {
                layer: layer.to_string(),
                x,
                y,
            })
    }

    /// Cheap, side-effect-free history identity probe. The document may have
    /// older detached history events after a non-raster revision rebase;
    /// those can safely replay through their saved tile snapshots instead.
    #[func]
    fn has_history_token(&self, transaction: i64, expected_revision: i64, undo: bool) -> bool {
        expected_revision >= 0
            && self.store.revision == expected_revision as u64
            && self.store.history_matches(transaction, undo)
    }

    /// Checked detached-history replay when the original Rust token has been
    /// evicted or detached. Unlike adopt_external_edit this does not invent a
    /// token absent from the document's chronological timeline. Any older
    /// native history is invalidated after the atomic canonical tile update.
    #[func]
    fn replay_detached_history(
        &mut self,
        layer: GString,
        expected_revision: i64,
        tiles: Array<Dictionary<Variant, Variant>>,
    ) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        if expected_revision < 0 || tiles.is_empty() || tiles.len() > MAX_ACTIVE_TILES {
            return err("Invalid detached history revision or tile count");
        }
        let layer = layer.to_string();
        let mut changes = Vec::with_capacity(tiles.len());
        for entry in tiles.iter_shared() {
            let Some((x, y, before, after)) = (|| {
                Some((
                    entry.get("tile_x")?.try_to::<i64>().ok()?,
                    entry.get("tile_y")?.try_to::<i64>().ok()?,
                    entry.get("expected")?.try_to::<PackedByteArray>().ok()?,
                    entry.get("replacement")?.try_to::<PackedByteArray>().ok()?,
                ))
            })() else {
                return err("Malformed detached history tile descriptor");
            };
            self.store.external_bytes_received = self
                .store
                .external_bytes_received
                .saturating_add(before.len().saturating_add(after.len()) as u64);
            changes.push((
                TileId {
                    layer: layer.clone(),
                    x,
                    y,
                },
                before.as_slice().to_vec(),
                after.as_slice().to_vec(),
            ));
        }
        match self
            .store
            .replay_detached(&layer, expected_revision as u64, changes)
        {
            Ok(count) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("tiles", count as i64);
                result.set("revision", self.store.revision as i64);
                result
            }
            Err(message) => err(message),
        }
    }

    /// Tokenized replay validates the entire detached RGBA8 payload in the
    /// same call that consumes the native history event. A valid token alone
    /// cannot authorize a caller-mutated replacement tile or stale source.
    /// Entries: tile_x/y, expected/replacement PackedByteArray (empty=blank).
    #[func]
    fn replay_history_token(
        &mut self,
        transaction: i64,
        expected_revision: i64,
        undo: bool,
        layer: GString,
        tiles: Array<Dictionary<Variant, Variant>>,
    ) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        if expected_revision < 0
            || self.store.revision != expected_revision as u64
            || tiles.is_empty()
            || tiles.len() > MAX_ACTIVE_TILES
        {
            return err("Stale revision or invalid native history tile count");
        }
        let layer = layer.to_string();
        let mut entries = Vec::with_capacity(tiles.len());
        for item in tiles.iter_shared() {
            let Some((x, y, expected, replacement)) = (|| {
                Some((
                    item.get("tile_x")?.try_to::<i64>().ok()?,
                    item.get("tile_y")?.try_to::<i64>().ok()?,
                    item.get("expected")?.try_to::<PackedByteArray>().ok()?,
                    item.get("replacement")?.try_to::<PackedByteArray>().ok()?,
                ))
            })() else {
                return err("Malformed native history tile descriptor");
            };
            entries.push((
                TileId {
                    layer: layer.clone(),
                    x,
                    y,
                },
                expected.as_slice().to_vec(),
                replacement.as_slice().to_vec(),
            ));
        }
        if !self
            .store
            .history_tiles_match(transaction, undo, &layer, &entries)
        {
            return err("Native history tile snapshots or canonical source differ");
        }
        match self.store.undo_or_redo(undo) {
            Ok(count) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("token", transaction);
                result.set("tiles", count as i64);
                result.set("revision", self.store.revision as i64);
                result
            }
            Err(message) => err(message),
        }
    }

    #[func]
    fn set_layer_editable(&mut self, layer: GString, editable: bool) -> bool {
        let layer = layer.to_string();
        if layer.is_empty() {
            return false;
        }
        self.store.editable_layers.insert(layer, editable);
        true
    }

    #[func]
    fn import_source(
        &mut self,
        layer: GString,
        x: i64,
        y: i64,
        source_revision: i64,
        bytes: PackedByteArray,
    ) -> bool {
        self.store.ffi_calls += 1;
        if source_revision < 0
            || x.unsigned_abs() > SAFE_COORD as u64
            || y.unsigned_abs() > SAFE_COORD as u64
        {
            return false;
        }
        self.store
            .import(
                TileId {
                    layer: layer.to_string(),
                    x,
                    y,
                },
                source_revision as u64,
                bytes.as_slice(),
            )
            .is_ok()
    }

    #[func]
    fn begin_edit(
        &mut self,
        layer: GString,
        source_revision: i64,
        selection_required: bool,
    ) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        if source_revision < 0 {
            return err("Negative revision");
        }
        match self.store.begin(
            &layer.to_string(),
            source_revision as u64,
            selection_required,
        ) {
            Ok(id) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("transaction", id);
                result
            }
            Err(message) => err(message),
        }
    }

    #[func]
    fn import_mask(
        &mut self,
        transaction: i64,
        layer: GString,
        tile_x: i64,
        tile_y: i64,
        mask: PackedByteArray,
    ) -> bool {
        self.store.ffi_calls += 1;
        self.store
            .mask(
                transaction,
                TileId {
                    layer: layer.to_string(),
                    x: tile_x,
                    y: tile_y,
                },
                mask.as_slice(),
            )
            .is_ok()
    }

    #[func]
    fn discard_edit(&mut self, transaction: i64) -> bool {
        self.store.ffi_calls += 1;
        if self
            .store
            .active
            .as_ref()
            .is_some_and(|e| e.id == transaction)
        {
            self.store.active = None;
            true
        } else {
            false
        }
    }

    #[func]
    fn commit_edit(
        &mut self,
        transaction: i64,
        source_revision: i64,
    ) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        if source_revision < 0 {
            return err("Negative revision");
        }
        match self.store.commit(transaction, source_revision as u64) {
            Ok(count) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("dirty_tiles", count as i64);
                result.set("revision", self.store.revision as i64);
                result
            }
            Err(message) => err(message),
        }
    }

    #[func]
    fn undo_edit(&mut self) -> Dictionary<Variant, Variant> {
        self.replay(true)
    }
    #[func]
    fn redo_edit(&mut self) -> Dictionary<Variant, Variant> {
        self.replay(false)
    }

    #[func]
    fn read_tile(
        &mut self,
        layer: GString,
        x: i64,
        y: i64,
        preview: bool,
    ) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        let id = TileId {
            layer: layer.to_string(),
            x,
            y,
        };
        let Some(tile) = self.store.read(&id, preview) else {
            return err("Tile not imported or not resident");
        };
        let mut result = Dictionary::new();
        result.set("ok", true);
        result.set("format", "straight_rgba8");
        result.set("stride_bytes", (self.store.stride * 4) as i64);
        let drafted = preview
            && self
                .store
                .active
                .as_ref()
                .is_some_and(|edit| edit.draft.contains_key(&id));
        result.set("generation", (tile.generation + u64::from(drafted)) as i64);
        result.set("bytes", &PackedByteArray::from(tile.rgba.as_slice()));
        self.store.bytes_exported += tile.rgba.len() as u64;
        result
    }

    /// Page over canonical layer/tile identities for bulk persistence. The
    /// result omits pixel bytes; read_tile copies exactly one RGBA8 span.
    /// A bounded page size avoids unbounded Godot Array allocations even with
    /// extremely sparse 16px storage tiles.
    #[func]
    fn list_tiles(&mut self, offset: i64, limit: i64) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        if offset < 0 || !(1..=128).contains(&limit) {
            return err("Invalid tile list page bounds");
        }
        let mut keys = self.store.tiles.keys().collect::<Vec<_>>();
        keys.sort_by_key(|id| (&id.layer, id.y, id.x));
        let total = keys.len();
        let start = (offset as usize).min(total);
        let end = start.saturating_add(limit as usize).min(total);
        let mut items = Array::<Dictionary<Variant, Variant>>::new();
        for id in &keys[start..end] {
            let mut item = Dictionary::new();
            item.set("layer", id.layer.as_str());
            item.set("tile_x", id.x);
            item.set("tile_y", id.y);
            item.set(
                "generation",
                self.store.tiles.get(*id).expect("resident tile").generation as i64,
            );
            items.push(&item);
        }
        let mut result = Dictionary::new();
        result.set("ok", true);
        result.set("tiles", &items);
        result.set("total", total as i64);
        result.set("next_offset", if end == total { -1 } else { end as i64 });
        result.set("revision", self.store.revision as i64);
        result
    }

    #[func]
    fn dirty_tiles(&self, transaction: i64) -> Array<Dictionary<Variant, Variant>> {
        let mut result = Array::new();
        let Some(edit) = self
            .store
            .active
            .as_ref()
            .filter(|edit| edit.id == transaction)
        else {
            return result;
        };
        let mut items = edit.dirty.iter().collect::<Vec<_>>();
        items.sort_by_key(|(id, _)| (&id.layer, id.y, id.x));
        for (id, rect) in items {
            let mut item = Dictionary::new();
            item.set("layer", id.layer.as_str());
            item.set("tile_x", id.x);
            item.set("tile_y", id.y);
            item.set(
                "dirty",
                Rect2i::new(
                    Vector2i::new(rect.left as i32, rect.top as i32),
                    Vector2i::new(
                        (rect.right - rect.left) as i32,
                        (rect.bottom - rect.top) as i32,
                    ),
                ),
            );
            item.set("base_revision", edit.base_revision as i64);
            item.set(
                "generation",
                self.store.tiles.get(id).map_or(0, |t| t.generation as i64) + 1,
            );
            result.push(&item);
        }
        result
    }

    #[func]
    fn stats(&self) -> Dictionary<Variant, Variant> {
        let mut result = Dictionary::new();
        result.set("revision", self.store.revision as i64);
        result.set("stride", self.store.stride as i64);
        result.set("tiles", self.store.tiles.len() as i64);
        result.set("parked_layers", self.store.parked_layers.len() as i64);
        result.set("bytes_used", self.store.bytes_used() as i64);
        result.set("ffi_calls", self.store.ffi_calls as i64);
        result.set("bytes_imported", self.store.bytes_imported as i64);
        result.set("bytes_exported", self.store.bytes_exported as i64);
        result.set(
            "external_bytes_received",
            self.store.external_bytes_received as i64,
        );
        result.set("pixel_stream_calls", self.store.pixel_stream_calls as i64);
        result.set("undo", self.store.undo.len() as i64);
        result.set("redo", self.store.redo.len() as i64);
        result
    }
}

impl DrawingNativeTiles {
    fn replay(&mut self, undo: bool) -> Dictionary<Variant, Variant> {
        self.store.ffi_calls += 1;
        match self.store.undo_or_redo(undo) {
            Ok(count) => {
                let mut result = Dictionary::new();
                result.set("ok", true);
                result.set("tiles", count as i64);
                result.set("revision", self.store.revision as i64);
                result
            }
            Err(message) => err(message),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn initialized(stride: usize) -> TileStore {
        let mut store = TileStore {
            stride,
            ..TileStore::default()
        };
        store.editable_layers.insert("ink".to_owned(), true);
        store
    }
    fn blank(store: &mut TileStore, x: i64, y: i64) {
        let id = TileId {
            layer: "ink".to_owned(),
            x,
            y,
        };
        store.import(id, store.revision, &[]).unwrap();
    }
    #[test]
    fn hokusai_eraser_uses_dab_alpha_and_preserves_hidden_rgb_and_history() {
        let mut store = initialized(16);
        let id = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let mut source = vec![0; 16 * 16 * 4];
        let painted_offset = (4 * 16 + 4) * 4;
        let hidden_offset = (4 * 16 + 5) * 4;
        source[painted_offset..painted_offset + 4].copy_from_slice(&0xc8123456_u32.to_le_bytes());
        source[hidden_offset..hidden_offset + 4].copy_from_slice(&0x00123456_u32.to_le_bytes());
        store.import(id.clone(), 0, &source).unwrap();
        let transaction = store.begin("ink", 0, false).unwrap();
        // MyPaint output supplies per-dab alpha; it is not an opaque
        // hard-circle erase. Hidden RGB at alpha zero must survive.
        let changed = store
            .stage(
                transaction,
                0,
                0,
                0,
                &[4, 4, 0x8000ff00_u32 as i32, 5, 4, 0xff00ff00_u32 as i32],
                true,
                0xff000000,
                true,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
            )
            .unwrap();
        assert_eq!(changed, 1);
        let preview = store.read(&id, true).unwrap().rgba.clone();
        let painted = u32::from_le_bytes(
            preview[painted_offset..painted_offset + 4]
                .try_into()
                .unwrap(),
        );
        let hidden = u32::from_le_bytes(
            preview[hidden_offset..hidden_offset + 4]
                .try_into()
                .unwrap(),
        );
        assert_eq!(painted & 0xffffff, 0x123456);
        assert_eq!(painted >> 24, 100); // 200 * (255 - 128) / 255
        assert_eq!(hidden, 0x00123456);
        store.commit(transaction, 0).unwrap();
        assert_eq!(store.undo_or_redo(true).unwrap(), 1);
        assert_eq!(store.read(&id, false).unwrap().rgba, source);
        assert_eq!(store.undo_or_redo(false).unwrap(), 1);
        assert_eq!(store.read(&id, false).unwrap().rgba, preview.clone());
    }

    #[test]
    fn external_raster_adoption_is_atomic_and_joins_brush_history() {
        let mut store = initialized(16);
        blank(&mut store, 0, 0);
        let id = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let brush = store.begin("ink", 0, false).unwrap();
        store
            .stage(
                brush,
                0,
                0,
                0,
                &[0, 0],
                false,
                0xff443322,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
            )
            .unwrap();
        store.commit(brush, 0).unwrap();
        let original = store.read(&id, false).unwrap().rgba.clone();
        let mut changed = original.clone();
        changed[8..12].copy_from_slice(&0x00aabbcc_u32.to_le_bytes());
        let unknown = TileId {
            layer: "ink".into(),
            x: -(1 << 42),
            y: 1 << 42,
        };
        let mut secondary = vec![0; changed.len()];
        secondary[0..4].copy_from_slice(&0xf0557799_u32.to_le_bytes());
        let entries = vec![
            (id.clone(), original.clone(), changed.clone()),
            (unknown.clone(), vec![], secondary.clone()),
        ];
        let head = store.bytes_used();
        for invalid in [
            vec![(id.clone(), vec![1; original.len()], changed.clone())],
            vec![(id.clone(), original.clone(), original.clone())],
            vec![
                (id.clone(), original.clone(), changed.clone()),
                (unknown.clone(), vec![], vec![1; 3]),
            ],
            vec![
                (id.clone(), original.clone(), changed.clone()),
                (id.clone(), original.clone(), changed.clone()),
            ],
        ] {
            assert!(store.adopt_external("ink", 1, invalid).is_err());
            assert_eq!(store.revision, 1);
            assert_eq!(store.bytes_used(), head);
            assert!(!store.authorized.contains(&unknown));
            assert!(store.history_matches(brush, true));
        }
        assert!(store.adopt_external("ink", 0, entries.clone()).is_err());
        let (external, count) = store.adopt_external("ink", 1, entries).unwrap();
        assert_eq!(count, 2);
        assert_eq!(store.revision, 2);
        assert_eq!(store.read(&id, false).unwrap().rgba, changed);
        assert_eq!(store.read(&unknown, false).unwrap().rgba, secondary);
        assert!(store.history_matches(external, true));
        assert_eq!(store.undo_or_redo(true).unwrap(), 2);
        assert_eq!(store.read(&id, false).unwrap().rgba, original);
        assert_eq!(
            store.read(&unknown, false).unwrap().rgba,
            vec![0; secondary.len()]
        );
        assert!(store.history_matches(brush, true));
        assert_eq!(store.undo_or_redo(true).unwrap(), 1);
        assert_eq!(store.undo_or_redo(false).unwrap(), 1);
        assert_eq!(store.undo_or_redo(false).unwrap(), 2);
        assert_eq!(store.read(&id, false).unwrap().rgba, changed);
    }

    #[test]
    fn detached_replay_checks_all_tiles_then_retires_old_tokens() {
        let mut store = initialized(16);
        let signed = TileId {
            layer: "ink".into(),
            x: -(1 << 42),
            y: 1 << 42,
        };
        let other = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let blank = vec![0; 16 * 16 * 4];
        let mut hidden = blank.clone();
        hidden[..4].copy_from_slice(&0x00123456_u32.to_le_bytes());
        store.import(signed.clone(), 0, &hidden).unwrap();
        store.import(other.clone(), 0, &blank).unwrap();
        let mut painted = hidden.clone();
        painted[4..8].copy_from_slice(&0xff445566_u32.to_le_bytes());
        let (original_token, _) = store
            .adopt_external(
                "ink",
                0,
                vec![(signed.clone(), hidden.clone(), painted.clone())],
            )
            .unwrap();
        let mut next = blank.clone();
        next[8..12].copy_from_slice(&0xf0887766_u32.to_le_bytes());
        let good = vec![
            (signed.clone(), painted.clone(), hidden.clone()),
            (other.clone(), blank.clone(), next.clone()),
        ];
        for rejected in [
            vec![
                (signed.clone(), vec![7; hidden.len()], hidden.clone()),
                (other.clone(), blank.clone(), next.clone()),
            ],
            vec![
                (signed.clone(), painted.clone(), hidden.clone()),
                (other.clone(), blank.clone(), vec![0; 17]),
            ],
            vec![
                (signed.clone(), painted.clone(), hidden.clone()),
                (signed.clone(), painted.clone(), hidden.clone()),
            ],
        ] {
            assert!(store.replay_detached("ink", 1, rejected).is_err());
            assert_eq!(store.revision, 1);
            assert_eq!(store.read(&signed, false).unwrap().rgba, painted);
            assert_eq!(store.read(&other, false).unwrap().rgba, blank);
            assert!(store.history_matches(original_token, true));
        }
        assert!(store.replay_detached("ink", 0, good.clone()).is_err());
        assert_eq!(store.replay_detached("ink", 1, good).unwrap(), 2);
        assert_eq!(store.revision, 2);
        assert_eq!(store.read(&signed, false).unwrap().rgba, hidden);
        assert_eq!(store.read(&other, false).unwrap().rgba, next);
        assert!(store.undo.is_empty() && store.redo.is_empty());
        assert!(!store.history_matches(original_token, true));
        assert!(store.authorized.contains(&signed) && store.authorized.contains(&other));
        assert!(
            store
                .replay_detached("ink", 2, vec![(other.clone(), next, Vec::new())])
                .is_ok()
        );
        assert_eq!(store.read(&other, false).unwrap().rgba, blank);
        assert_eq!(store.revision, 3);
    }

    #[test]
    fn token_replay_rejects_detached_payload_tampering_atomically() {
        let mut store = initialized(16);
        let first = TileId {
            layer: "ink".into(),
            x: -(1 << 42),
            y: 3,
        };
        let second = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let blank = vec![0; 16 * 16 * 4];
        let mut red = blank.clone();
        red[..4].copy_from_slice(&0xff112233_u32.to_le_bytes());
        let mut hidden_rgb = blank.clone();
        hidden_rgb[..4].copy_from_slice(&0x00123456_u32.to_le_bytes());
        let (token, _) = store
            .adopt_external(
                "ink",
                0,
                vec![
                    (first.clone(), vec![], red.clone()),
                    (second.clone(), vec![], hidden_rgb.clone()),
                ],
            )
            .unwrap();
        let undo = vec![
            (first.clone(), red.clone(), vec![]),
            (second.clone(), hidden_rgb.clone(), vec![]),
        ];
        assert!(store.history_tiles_match(token, true, "ink", &undo));
        let mut invalid = undo.clone();
        invalid[1].2 = red.clone(); // A valid-length but unauthorized replacement.
        assert!(!store.history_tiles_match(token, true, "ink", &invalid));
        invalid = undo.clone();
        invalid[1].1[3] = 0xff; // Source snapshot changes, including hidden alpha.
        assert!(!store.history_tiles_match(token, true, "ink", &invalid));
        invalid = undo.clone();
        invalid[1].0 = invalid[0].0.clone(); // Duplicate key, not two tiles.
        assert!(!store.history_tiles_match(token, true, "ink", &invalid));
        assert!(!store.history_tiles_match(token, true, "ink", &undo[..1]));
        assert!(!store.history_tiles_match(token, true, "other", &undo));
        assert!(!store.history_tiles_match(token, false, "ink", &undo));
        // Canonical Rust source is also part of replay authorization.
        store.tiles.get_mut(&first).unwrap().rgba[0] ^= 0x01;
        assert!(!store.history_tiles_match(token, true, "ink", &undo));
        store.tiles.get_mut(&first).unwrap().rgba = red.clone();
        assert_eq!(store.revision, 1);
        assert!(store.history_matches(token, true));
        assert_eq!(store.read(&second, false).unwrap().rgba, hidden_rgb);
        assert!(store.history_tiles_match(token, true, "ink", &undo));
        assert_eq!(store.undo_or_redo(true).unwrap(), 2);
        let redo = vec![
            (second.clone(), vec![], hidden_rgb.clone()),
            (first.clone(), vec![], red.clone()),
        ];
        assert!(store.history_tiles_match(token, false, "ink", &redo));
        let mut bad_redo = redo.clone();
        bad_redo[0].2[1] = 0;
        assert!(!store.history_tiles_match(token, false, "ink", &bad_redo));
        assert_eq!(store.revision, 2);
        assert!(store.history_tiles_match(token, false, "ink", &redo));
        assert_eq!(store.undo_or_redo(false).unwrap(), 2);
        assert_eq!(store.read(&first, false).unwrap().rgba, red);
        assert_eq!(store.read(&second, false).unwrap().rgba, hidden_rgb);
    }

    #[test]
    fn unreferenced_raster_structure_preserves_unrelated_native_history() {
        let mut store = initialized(16);
        blank(&mut store, 0, 0);
        let paint = store.begin("ink", 0, false).unwrap();
        store
            .stage(
                paint,
                0,
                0,
                0,
                &[0, 0],
                false,
                0xff114477,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
            )
            .unwrap();
        store.commit(paint, 0).unwrap();
        let bytes = store
            .read(
                &TileId {
                    layer: "ink".into(),
                    x: 0,
                    y: 0,
                },
                false,
            )
            .unwrap()
            .rgba
            .clone();
        let memory = store.bytes_used();
        let empty = vec!["unimported".to_owned(), "nested".to_owned()];
        store.advance_unreferenced_layers(1, &empty, true).unwrap();
        assert_eq!(store.revision, 2);
        assert_eq!(store.bytes_used(), memory);
        assert!(store.history_matches(paint, true));
        assert_eq!(
            store
                .read(
                    &TileId {
                        layer: "ink".into(),
                        x: 0,
                        y: 0
                    },
                    false
                )
                .unwrap()
                .rgba,
            bytes
        );
        assert!(store.advance_unreferenced_layers(1, &empty, false).is_err());
        assert!(store.advance_unreferenced_layers(2, &[], false).is_err());
        assert!(
            store
                .advance_unreferenced_layers(2, &["nested".into(), "nested".into()], false)
                .is_err()
        );
        assert!(
            store
                .advance_unreferenced_layers(2, &[String::new()], false)
                .is_err()
        );
        assert!(
            store
                .advance_unreferenced_layers(2, &vec!["n".into(); MAX_ACTIVE_TILES + 1], false)
                .is_err()
        );
        assert_eq!(store.revision, 2);
        // Imported blank counts as resident source, even with no painted pixels.
        store
            .import(
                TileId {
                    layer: "nested".into(),
                    x: -1,
                    y: 0,
                },
                2,
                &[],
            )
            .unwrap();
        assert!(store.advance_unreferenced_layers(2, &empty, false).is_err());
        let active = store.begin("ink", 2, false).unwrap();
        assert!(
            store
                .advance_unreferenced_layers(2, &["fresh".into()], false)
                .is_err()
        );
        assert!(store.transaction_matches(active, 2, "ink"));
        store.active = None;
        // Undo/redo history for an affected raster layer also blocks metadata
        // treatment, including when its tile bytes become blank after Undo.
        store.undo_or_redo(true).unwrap();
        assert!(store.history_matches(paint, false));
        assert!(
            store
                .advance_unreferenced_layers(3, &["ink".into()], true)
                .is_err()
        );
        store
            .advance_unreferenced_layers(3, &["fresh".into()], false)
            .unwrap();
        assert!(store.history_matches(paint, false));
        assert_eq!(store.revision, 4);
    }

    #[test]
    fn unrecorded_retirement_preserves_unrelated_tokens_without_leaking_sources() {
        let mut store = initialized(16);
        store.editable_layers.insert("removed".into(), true);
        let ink = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let removed = TileId {
            layer: "removed".into(),
            x: -1,
            y: 1,
        };
        blank(&mut store, 0, 0);
        store.import(removed.clone(), 0, &[]).unwrap();
        let mut paint = |layer: &str, revision: u64, x: i32| {
            let token = store.begin(layer, revision, false).unwrap();
            store
                .stage(
                    token,
                    revision,
                    if layer == "removed" { -16 } else { 0 },
                    if layer == "removed" { 16 } else { 0 },
                    &[x, 1],
                    false,
                    0xffaabbcc,
                    false,
                    Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
                )
                .unwrap();
            store.commit(token, revision).unwrap();
            token
        };
        let first = paint("ink", 0, 1);
        let removed_token = paint("removed", 1, 1);
        let last = paint("ink", 2, 4);
        assert_eq!(store.undo.len(), 3);
        let ink_bytes = store.read(&ink, false).unwrap().rgba.clone();
        let used = store.bytes_used();
        for (revision, layers) in [
            (2, vec!["removed".into()]),
            (3, vec!["removed".into(), "removed".into()]),
            (3, vec![String::new()]),
            (3, vec!["removed".into(); MAX_ACTIVE_TILES + 1]),
        ] {
            assert!(store.retire_layers(revision, &layers, true).is_err());
            assert_eq!(store.revision, 3);
            assert_eq!(store.bytes_used(), used);
            assert_eq!(store.undo.len(), 3);
        }
        let active = store.begin("ink", 3, false).unwrap();
        assert!(store.retire_layers(3, &["removed".into()], true).is_err());
        assert!(store.transaction_matches(active, 3, "ink"));
        store.active = None;
        store.retire_layers(3, &["removed".into()], true).unwrap();
        assert_eq!(store.revision, 4);
        assert_eq!(store.undo.len(), 2);
        assert!(!store.authorized.contains(&removed));
        assert!(!store.tiles.contains_key(&removed));
        assert!(!store.editable_layers.contains_key("removed"));
        assert!(!store.history_matches(removed_token, true));
        assert!(store.bytes_used() < used);
        assert_eq!(store.read(&ink, false).unwrap().rgba, ink_bytes);
        assert!(store.history_matches(last, true));
        store.undo_or_redo(true).unwrap();
        assert!(store.history_matches(first, true));
        store.undo_or_redo(true).unwrap();
        assert!(store.history_matches(first, false));
        store.undo_or_redo(false).unwrap();
        store.undo_or_redo(false).unwrap();
        assert_eq!(store.read(&ink, false).unwrap().rgba, ink_bytes);
        // The old ID may be safely reused: no parked tombstone, stale bytes,
        // authorization or history entry survives its permanent retirement.
        store.retire_layers(8, &["fresh".into()], true).unwrap();
        store.import(removed.clone(), 9, &[]).unwrap();
        assert!(store.authorized.contains(&removed));
        assert!(
            store
                .read(&removed, false)
                .unwrap()
                .rgba
                .iter()
                .all(|pixel| *pixel == 0)
        );
    }

    #[test]
    fn parked_raster_layers_retain_history_and_reject_mutation_until_restored() {
        let mut store = initialized(16);
        blank(&mut store, 0, 0);
        let id = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let stroke = store.begin("ink", 0, false).unwrap();
        store
            .stage(
                stroke,
                0,
                0,
                0,
                &[1, 1],
                false,
                0xff112233,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
            )
            .unwrap();
        store.commit(stroke, 0).unwrap();
        let pixels = store.read(&id, false).unwrap().rgba.clone();
        let bytes = store.bytes_used();
        let ids = vec!["ink".into(), "never-imported".into()];
        assert!(store.advance_parked_layers(0, &ids, false, true).is_err());
        assert!(
            store
                .advance_parked_layers(1, &["ink".into(), "ink".into()], false, true)
                .is_err()
        );
        assert!(
            store
                .advance_parked_layers(1, &[String::new()], false, true)
                .is_err()
        );
        assert_eq!(store.revision, 1);
        assert!(
            store
                .advance_parked_layers(1, &["empty".into()], false, false)
                .is_err()
        );
        assert!(
            store
                .advance_parked_layers(1, &vec!["ink".into(); MAX_ACTIVE_TILES + 1], false, false)
                .is_err()
        );
        let open = store.begin("ink", 1, false).unwrap();
        assert!(store.advance_parked_layers(1, &ids, false, true).is_err());
        assert!(store.transaction_matches(open, 1, "ink"));
        store.active = None;
        store.advance_parked_layers(1, &ids, false, true).unwrap();
        assert_eq!(store.revision, 2);
        assert_eq!(store.bytes_used(), bytes);
        assert_eq!(store.read(&id, false).unwrap().rgba, pixels);
        assert!(!store.history_matches(stroke, true));
        assert!(store.begin("ink", 2, false).is_err());
        assert!(
            store
                .import(
                    TileId {
                        layer: "ink".into(),
                        x: 2,
                        y: 2
                    },
                    2,
                    &[]
                )
                .is_err()
        );
        assert!(store.undo_or_redo(true).is_err());
        assert!(store.advance_parked_layers(2, &ids, false, false).is_err());
        assert!(
            store
                .advance_parked_layers(2, &["ink".into()], true, false)
                .is_ok()
        );
        assert!(
            store
                .advance_parked_layers(3, &["never-imported".into()], true, false)
                .is_ok()
        );
        assert_eq!(store.revision, 4);
        assert_eq!(store.bytes_used(), bytes);
        assert!(store.history_matches(stroke, true));
        store.undo_or_redo(true).unwrap();
        assert!(store.history_matches(stroke, false));
        assert!(store.advance_parked_layers(5, &ids, false, false).is_ok());
        assert!(store.advance_parked_layers(6, &ids, true, false).is_ok());
        assert!(store.history_matches(stroke, false));
        store.undo_or_redo(false).unwrap();
        assert_eq!(store.read(&id, false).unwrap().rgba, pixels);
        // A rebased store must release tombstones, not accidentally authorize
        // pixels from deleted document layers after another producer changes them.
        store.advance_parked_layers(8, &ids, false, true).unwrap();
        store.rebase_external(9, 10).unwrap();
        assert!(store.parked_layers.is_empty());
        assert!(store.tiles.is_empty());
        assert!(store.undo.is_empty());
    }

    #[test]
    fn metadata_revisions_keep_native_history_and_reject_stale_or_active_advances() {
        let mut store = initialized(16);
        blank(&mut store, 0, 0);
        let tile_id = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let stroke = store.begin("ink", 0, false).unwrap();
        store
            .stage(
                stroke,
                0,
                0,
                0,
                &[1, 1],
                false,
                0xff663322,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
            )
            .unwrap();
        store.commit(stroke, 0).unwrap();
        let painted = store.read(&tile_id, false).unwrap().rgba.clone();
        let allocated = store.bytes_used();
        assert!(store.advance_metadata(0, true).is_err());
        assert_eq!(store.revision, 1);
        store.advance_metadata(1, true).unwrap();
        assert_eq!(store.revision, 2);
        assert_eq!(store.read(&tile_id, false).unwrap().rgba, painted);
        assert_eq!(store.bytes_used(), allocated);
        assert!(store.history_matches(stroke, true));
        let active = store.begin("ink", 2, false).unwrap();
        assert!(store.advance_metadata(2, true).is_err());
        assert_eq!(store.revision, 2);
        store.active = None;
        let mut at_limit = initialized(16);
        at_limit.revision = i64::MAX as u64;
        assert!(at_limit.advance_metadata(i64::MAX as u64, true).is_err());
        assert_eq!(at_limit.revision, i64::MAX as u64);
        assert!(store.advance_metadata(2, true).is_ok());
        assert!(store.history_matches(stroke, true));
        store.undo_or_redo(true).unwrap();
        assert!(store.history_matches(stroke, false));
        store.advance_metadata(4, false).unwrap();
        assert!(store.history_matches(stroke, false));
        store.undo_or_redo(false).unwrap();
        assert_eq!(store.read(&tile_id, false).unwrap().rgba, painted);
        store.undo_or_redo(true).unwrap();
        store.advance_metadata(7, true).unwrap();
        assert!(!store.history_matches(stroke, false));
        assert_eq!(store.revision, 8);
        assert!(store.read(&tile_id, false).is_some());
        let _ = active;
    }

    #[test]
    fn persistent_transactions_rebase_and_history_tokens() {
        let mut store = initialized(16);
        blank(&mut store, 0, 0);
        let original = TileId {
            layer: "ink".to_owned(),
            x: 0,
            y: 0,
        };
        for revision in 0..2 {
            let transaction = store.begin("ink", revision, false).unwrap();
            store
                .stage(
                    transaction,
                    revision,
                    0,
                    0,
                    &[revision as i32, 0],
                    false,
                    0xff002233,
                    false,
                    Rect2i::new(Vector2i::ZERO, Vector2i::ZERO),
                )
                .unwrap();
            assert_eq!(store.commit(transaction, revision).unwrap(), 1);
            assert!(store.history_matches(transaction, true));
            assert!(store.authorized.contains(&original));
        }
        let last = store.undo.last().unwrap().token;
        assert!(!store.history_matches(last + 42, true));
        assert_eq!(store.undo_or_redo(true).unwrap(), 1);
        assert!(store.history_matches(last, false));
        assert_eq!(store.undo_or_redo(false).unwrap(), 1);
        assert_eq!(store.revision, 4);
        let _active = store.begin("ink", 4, false).unwrap();
        assert!(store.rebase_external(4, 5).is_err());
        assert!(!store.history_matches(last, true)); // active edit
        store.active = None;
        assert!(store.rebase_external(3, 5).is_err());
        assert!(store.rebase_external(4, 4).is_err());
        assert_eq!(
            store.read(&original, false).unwrap().rgba[0..4],
            [0x33, 0x22, 0, 255]
        );
        store.rebase_external(4, 5).unwrap();
        assert!(store.tiles.is_empty() && store.authorized.is_empty());
        assert!(store.undo.is_empty() && store.redo.is_empty());
        assert_eq!(store.revision, 5);
        assert!(store.begin("ink", 4, false).is_err());
        assert!(store.import(original, 5, &vec![0x5a; 16 * 16 * 4]).is_ok());
    }

    #[test]
    fn signed_seams_mask_hidden_rgb_and_cancel() {
        let mut s = initialized(16);
        blank(&mut s, -1, -1);
        blank(&mut s, 0, 0);
        let mask_id = TileId {
            layer: "ink".to_owned(),
            x: -1,
            y: -1,
        };
        let tx = s.begin("ink", 0, true).unwrap();
        let mut mask = vec![0; 256];
        mask[15 * 16 + 15] = 255;
        s.mask(tx, mask_id.clone(), &mask).unwrap();
        // Rejected missing mask/source does not alter even the earlier pixel.
        assert!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[-1, -1, 0, 0],
                false,
                0xff4837a1,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .is_err()
        );
        assert!(s.active.as_ref().unwrap().draft.is_empty());
        let id0 = TileId {
            layer: "ink".to_owned(),
            x: 0,
            y: 0,
        };
        s.mask(tx, id0.clone(), &vec![255; 256]).unwrap();
        assert_eq!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[-1, -1, 0, 0],
                false,
                0xff4837a1,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .unwrap(),
            2
        );
        assert_eq!(
            s.read(&mask_id, true).unwrap().rgba[(255 * 4)..(255 * 4 + 4)],
            [0xa1, 0x37, 0x48, 0xff]
        );
        assert_eq!(s.read(&id0, false).unwrap().rgba[0..4], [0, 0, 0, 0]);
        s.active = None;
        assert_eq!(
            s.read(&mask_id, false).unwrap().rgba[255 * 4..255 * 4 + 4],
            [0, 0, 0, 0]
        );
    }
    #[test]
    fn atomic_undo_redo_and_locked_rejection() {
        let mut s = initialized(16);
        blank(&mut s, -1, 0);
        blank(&mut s, 0, 0);
        let tx = s.begin("ink", 0, false).unwrap();
        assert!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[-1, 0, 0, 0],
                false,
                0xff030201,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .is_ok()
        );
        s.editable_layers.insert("ink".into(), false);
        assert!(s.commit(tx, 0).is_err());
        assert_eq!(s.revision, 0);
        assert_eq!(
            s.tiles
                .values()
                .flat_map(|t| t.rgba.iter())
                .filter(|&&b| b != 0)
                .count(),
            0
        );
        s.editable_layers.insert("ink".into(), true);
        assert_eq!(s.commit(tx, 0).unwrap(), 2);
        assert_eq!(s.revision, 1);
        assert_eq!(s.undo_or_redo(true).unwrap(), 2);
        assert_eq!(s.revision, 2);
        assert_eq!(s.undo_or_redo(false).unwrap(), 2);
        assert_eq!(s.revision, 3);
        assert_eq!(
            s.tiles
                .values()
                .flat_map(|t| t.rgba.iter())
                .filter(|&&b| b != 0)
                .count(),
            8
        );
    }
    #[test]
    fn hidden_rgb_and_alpha_roundtrip() {
        let mut s = initialized(16);
        let id = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        let mut bytes = vec![0; 16 * 16 * 4];
        bytes[0..4].copy_from_slice(&[0x11, 0x22, 0x33, 0]);
        s.import(id.clone(), 0, &bytes).unwrap();
        let tx = s.begin("ink", 0, false).unwrap();
        assert_eq!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[1, 0],
                false,
                0x80443322,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .unwrap(),
            1
        );
        assert_eq!(s.read(&id, true).unwrap().rgba[0..4], bytes[0..4]);
        assert_eq!(
            s.read(&id, true).unwrap().rgba[4..8],
            [0x22, 0x33, 0x44, 0x80]
        );
        s.commit(tx, 0).unwrap();
        s.undo_or_redo(true).unwrap();
        assert_eq!(
            s.read(&id, false).unwrap().rgba[0..4],
            [0x11, 0x22, 0x33, 0]
        );
        s.undo_or_redo(false).unwrap();
        assert_eq!(
            s.read(&id, false).unwrap().rgba[4..8],
            [0x22, 0x33, 0x44, 0x80]
        );
    }
    #[test]
    fn large_signed_tile_identity_and_layer_isolation() {
        let mut s = initialized(16);
        let world_x = 1_i64 << 42;
        let world_y = -(1_i64 << 42);
        blank(&mut s, world_x.div_euclid(16), world_y.div_euclid(16));
        let id = TileId {
            layer: "ink".into(),
            x: world_x.div_euclid(16),
            y: world_y.div_euclid(16),
        };
        let tx = s.begin("ink", 0, false).unwrap();
        assert_eq!(
            s.stage(
                tx,
                0,
                world_x,
                world_y,
                &[0, 0],
                false,
                0xff112233,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .unwrap(),
            1
        );
        assert_eq!(s.read(&id, false).unwrap().rgba[0..4], [0, 0, 0, 0]);
        assert_eq!(
            s.read(&id, true).unwrap().rgba[0..4],
            [0x33, 0x22, 0x11, 0xff]
        );
        assert!(s.begin("ink", 0, false).is_err());
        s.commit(tx, 0).unwrap();
        s.editable_layers.insert("other".into(), true);
        let other = TileId {
            layer: "other".into(),
            x: id.x,
            y: id.y,
        };
        s.import(other.clone(), 1, &[]).unwrap();
        assert_eq!(s.read(&other, false).unwrap().rgba[0..4], [0, 0, 0, 0]);
        assert_eq!(
            s.read(&id, false).unwrap().rgba[0..4],
            [0x33, 0x22, 0x11, 0xff]
        );
        s.undo_or_redo(true).unwrap();
        assert_eq!(s.read(&id, false).unwrap().rgba[0..4], [0, 0, 0, 0]);
        assert_eq!(s.read(&other, false).unwrap().rgba[0..4], [0, 0, 0, 0]);
    }
    #[test]
    fn missing_source_masks_and_budget_fail_closed() {
        let mut s = initialized(16);
        let tx = s.begin("ink", 0, true).unwrap();
        let id = TileId {
            layer: "ink".into(),
            x: 0,
            y: 0,
        };
        assert!(s.mask(tx, id.clone(), &vec![255; 256]).is_err());
        blank(&mut s, 0, 0);
        assert!(s.mask(tx, id.clone(), &vec![255; 256]).is_ok());
        assert!(s.mask(tx, id.clone(), &vec![255; 256]).is_err());
        assert_eq!(s.bytes_used(), 16 * 16 * 4 + 16 * 16);
        s.editable_layers.insert("ink".into(), false);
        assert!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[0, 0],
                false,
                0xff0000ff,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .is_err()
        );
        assert!(s.active.as_ref().unwrap().draft.is_empty());
    }
    #[test]
    fn no_op_paint_does_not_create_revision_or_history() {
        let mut s = initialized(16);
        blank(&mut s, 0, 0);
        let tx = s.begin("ink", 0, false).unwrap();
        assert_eq!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[0, 0],
                false,
                0x00000000,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .unwrap(),
            0
        );
        assert!(s.finish_noop(tx, 0));
        assert_eq!(s.revision, 0);
        assert!(s.undo.is_empty());
        assert!(s.active.is_none());
    }
    #[test]
    fn stale_unauthorized_oversized_and_zero_change_fail_closed() {
        let mut s = initialized(16);
        blank(&mut s, 0, 0);
        assert!(
            s.import(
                TileId {
                    layer: "ink".into(),
                    x: 0,
                    y: 0
                },
                0,
                &[]
            )
            .is_err()
        );
        assert!(s.begin("ink", 1, false).is_err());
        let tx = s.begin("ink", 0, false).unwrap();
        assert!(
            s.stage(
                tx,
                0,
                0,
                0,
                &[16, 0],
                false,
                0xff010203,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .is_err()
        );
        assert!(
            s.stage(
                tx,
                0,
                i64::MAX,
                0,
                &[0, 0],
                false,
                0xff010203,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .is_err()
        );
        assert!(s.commit(tx, 0).is_err());
        assert!(
            s.stage(
                tx,
                1,
                0,
                0,
                &[0, 0],
                false,
                0xff010203,
                false,
                Rect2i::new(Vector2i::ZERO, Vector2i::ZERO)
            )
            .is_err()
        );
    }
}
