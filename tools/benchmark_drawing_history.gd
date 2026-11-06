extends SceneTree
## Diagnostic only: compare detached sparse layer snapshots with compact edits.
## No timing assertions: backend/tile-size selection is owned by T-067/T-068.


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	for stride: int in [256, 512, 1024, 2048]:
		var tile: DrawingRasterTile = DrawingRasterTile.new(stride)
		for index: int in range(500):
			tile.set_rgba(index % stride, index / stride, 0xff112233)
		var begin: int = Time.get_ticks_usec()
		for iteration: int in range(40):
			var detached: DrawingRasterTile = tile.detached_copy()
			assert(detached.pixel_count() == tile.pixel_count())
		var copy_us: int = Time.get_ticks_usec() - begin
		var document: DrawingDocument = DrawingDocument.new("bench-%d" % stride, stride)
		var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Benchmark").value)
		begin = Time.get_ticks_usec()
		for index: int in range(40):
			var edit: DrawingEditSession = document.begin_edit(layer, document.revision).value as DrawingEditSession
			assert(edit.fill_rect(Rect2i(index, 1, 1, 1), 0xdeadbeef).ok)
			assert(edit.commit().ok)
		var delta_us: int = Time.get_ticks_usec() - begin
		print("T054_BENCH stride=%d sparse_snapshot_40_us=%d gesture_commit_40_us=%d" % [
			stride, copy_us, delta_us])
	quit()
