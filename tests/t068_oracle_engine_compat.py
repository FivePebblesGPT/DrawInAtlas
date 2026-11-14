"""Compare live beta3 Godot output against immutable beta2 native parity fixtures.

Only the engine-version label is allowed to differ. Historical fixture SHA-256
pins remain enforced by the individual native test modules; no byte or geometry
field can be regenerated or ignored to make a failing parity test green.
"""

from __future__ import annotations

from typing import Any

LEGACY_ENGINE = "4.8-beta2 (official)"
CURRENT_ENGINE = "4.8-beta3 (official)"


def require_beta3_matches_pinned_beta2(
    pinned: dict[str, Any], regenerated: dict[str, Any],
) -> None:
    """Assert complete fixture equality after one explicit metadata substitution.

    Parameters
    ----------
    pinned : dict[str, Any]
        SHA-pinned historical Godot 4.8 beta2 fixture content.
    regenerated : dict[str, Any]
        Parsed output from the live pinned Godot 4.8 beta3 generator.

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
        raise AssertionError("Regenerated fixture is not from pinned beta3")
    normalized = {**regenerated, "godot_version": LEGACY_ENGINE}
    if normalized != pinned:
        raise AssertionError("Regenerated beta3 fixture differs beyond engine metadata")
