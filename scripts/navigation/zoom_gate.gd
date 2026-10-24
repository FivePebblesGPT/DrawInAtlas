class_name AtlasZoomGate
extends RefCounted

## Three consecutive logical wheel steps in the same direction, targeting the
## same link, are required AFTER the camera reaches its zoom limit.
## This stops ordinary zooming from accidentally opening neighboring maps.
const REQUIRED_STEPS: int = 3
const RESET_TIMEOUT_MS: int = 900

var direction: int = 0
var candidate_id: String = ""
var count: int = 0
var last_step_ms: int = -1


func reset() -> void:
	direction = 0
	candidate_id = ""
	count = 0
	last_step_ms = -1


## A direction/target change or a pause resets the gesture. After the third
## accepted blocked step, reset so another navigation requires a fresh gesture.
func accept_blocked_step(next_direction: int, next_candidate: String, now_ms: int) -> bool:
	if next_direction == 0 or next_candidate.is_empty():
		reset()
		return false
	var expired := last_step_ms >= 0 and now_ms - last_step_ms > RESET_TIMEOUT_MS
	if expired or direction != next_direction or candidate_id != next_candidate:
		reset()
		direction = next_direction
		candidate_id = next_candidate
	count += 1
	last_step_ms = now_ms
	if count >= REQUIRED_STEPS:
		reset()
		return true
	return false
