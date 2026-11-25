"""Compare live Godot output against immutable beta2 native parity fixtures.

Only the engine-version label is allowed to differ. Historical fixture SHA-256
pins remain enforced by the individual native test modules; no byte or geometry
field can be regenerated or ignored to make a failing parity test green.
"""

from __future__ import annotations

from typing import Any

LEGACY_ENGINE = "4.8-beta2 (official)"
CURRENT_ENGINE = "4.8-beta4 (official)"


def require_current_engine_matches_pinned_beta2(
    pinned: dict[str, Any], regenerated: dict[str, Any],
) -> None:
    """Assert complete fixture equality after one explicit metadata substitution.

    Parameters
    ----------
    pinned : dict[str, Any]
        SHA-pinned historical Godot 4.8 beta2 fixture content.
    regenerated : dict[str, Any]
        Parsed output from the live pinned Godot generator.

    Raises
    ------
    AssertionError
        If the engine pair is wrong or any case, field, byte, count or ordering
        differs after replacing the one known engine-version string.
    """
    if not isinstance(pinned, dict) or not isinstance(regenerated, dict):
        raise AssertionError("Both Godot fixtures must be JSON objects")
    if pinned.get("godot_version") != LEGACY_ENGINE:
        raise AssertionError("Historical fixture is not the pinned beta2 source")
    if regenerated.get("godot_version") != CURRENT_ENGINE:
        raise AssertionError(f"Regenerated fixture is not from pinned {CURRENT_ENGINE}")
    normalized = {**regenerated, "godot_version": LEGACY_ENGINE}
    if normalized != pinned:
        raise AssertionError("Regenerated fixture differs beyond engine metadata")

# T-277: native-attached documents cannot publish the historical >2^53
# coordinates.  The relocated live probe still covers a far signed location;
# the beta2 fixture's historical anchors and every raster result stay pinned.
BRUSH_NATIVE_ANCHORS = ("1125899906842625", "-1125899906842625")


def require_native_brush_matches_pinned_beta2(
    pinned: dict[str, Any], regenerated: dict[str, Any],
) -> None:
    """Verify legal live anchors and exact historical brush raster parity.

    Unlike unrelated quad fixtures, this one intentionally relocates the two
    absolute anchors to the native-publishable range.  No coverage, channel,
    digest, case ordering, or other field is exempt from strict comparison.
    """
    if (regenerated.get("anchor_x"), regenerated.get("anchor_y")) != BRUSH_NATIVE_ANCHORS:
        raise AssertionError("Native brush anchor pair differs from the pinned legal probe")
    if (pinned.get("anchor_x"), pinned.get("anchor_y")) != (
        "9007199254740993", "-9007199254740993",
    ):
        raise AssertionError("Historical brush anchor pair was modified")
    relocated = {
        **regenerated,
        "anchor_x": pinned["anchor_x"],
        "anchor_y": pinned["anchor_y"],
    }
    require_current_engine_matches_pinned_beta2(pinned, relocated)
