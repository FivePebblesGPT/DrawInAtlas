class_name AtlasProjectorCalibration
extends RefCounted
## T-040: measured physical display width and grid-cell size are presentation
## inputs, not artwork transforms or projector frame state. Never infer DPI.

var physical_output_width_mm: float = 0.0
var target_cell_mm: float = 25.0


func set_measurements(output_width_mm: float, cell_mm: float) -> bool:
	if not is_finite(output_width_mm) or not is_finite(cell_mm) \
			or output_width_mm <= 0.0 or cell_mm <= 0.0 \
			or output_width_mm > 100000.0 or cell_mm > output_width_mm:
		return false
	physical_output_width_mm = output_width_mm
	target_cell_mm = cell_mm
	return true


## Board width that would display each document grid cell at target_cell_mm.
## This is a suggestion only; callers must explicitly resize the GM frame.
func suggested_frame_width(grid_cell_units: float) -> float:
	if physical_output_width_mm <= 0.0 or not is_finite(grid_cell_units) or grid_cell_units <= 0.0:
		return NAN
	return physical_output_width_mm * grid_cell_units / target_cell_mm


## Physical on-screen size of a rendered grid cell for the current camera.
## Native OS scaling and projector overscan may require remeasurement.
func actual_cell_mm(frame_width_units: float, grid_cell_units: float) -> float:
	if physical_output_width_mm <= 0.0 or not is_finite(frame_width_units) \
			or not is_finite(grid_cell_units) or frame_width_units <= 0.0 or grid_cell_units <= 0.0:
		return NAN
	return physical_output_width_mm * grid_cell_units / frame_width_units


func pixels_per_mm(output_width_pixels: int) -> float:
	if physical_output_width_mm <= 0.0 or output_width_pixels <= 0:
		return NAN
	return float(output_width_pixels) / physical_output_width_mm
