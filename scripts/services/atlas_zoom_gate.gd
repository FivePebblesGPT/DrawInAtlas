class_name AtlasZoomGate
extends RefCounted

## Only call for logical wheel steps that occur *after* the camera hits a limit.
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
