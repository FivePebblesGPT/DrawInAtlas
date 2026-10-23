"""Exercise the exported Web UI and its IndexedDB save slot using Playwright.

Run against a served release export at a fixed 1280x720 viewport. Python is
optional test tooling; application/runtime code remains entirely GDScript.
"""

import argparse
import json
from pathlib import Path
from typing import Any

from playwright.sync_api import Page, sync_playwright

READ_CAMPAIGN_JS = """async () => {
    const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('/userfs');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
    });
    return await new Promise((resolve, reject) => {
        const result = [];
        const cursor = db.transaction('FILE_DATA').objectStore('FILE_DATA').openCursor();
        cursor.onsuccess = () => {
            const entry = cursor.result;
            if (!entry) { db.close(); resolve(result); return; }
            if (String(entry.key).endsWith('drawinatlas_campaign.json')) {
                result.push({
                    campaign: JSON.parse(new TextDecoder().decode(entry.value.contents)),
                    timestamp: entry.value.timestamp.toISOString(),
                });
            }
            entry.continue();
        };
        cursor.onerror = () => reject(cursor.error);
    });
}"""


def save_snapshot(page: Page) -> dict[str, Any]:
    """Save through the UI and wait for a newly flushed IndexedDB file."""
    previous: list[dict[str, Any]] = page.evaluate(READ_CAMPAIGN_JS)
    timestamp: str | None = previous[0]["timestamp"] if previous else None
    page.mouse.click(24, 16)  # File
    page.mouse.click(100, 48)  # Save campaign
    page.wait_for_function(
        f"async (previous) => {{ const entries = await ({READ_CAMPAIGN_JS})(); "
        "return entries.length === 1 && entries[0].timestamp !== previous; }",
        arg=timestamp, timeout=15000,
    )
    saved: list[dict[str, Any]] = page.evaluate(READ_CAMPAIGN_JS)
    return saved[0]


def world_floor(snapshot: dict[str, Any]) -> dict[str, Any]:
    """Read the source board's canonical floor from a flushed save."""
    world: dict[str, Any] = next(item for item in snapshot["campaign"]["maps"] if item["id"] == "world")
    return world["floors"][0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8765/index.html")
    parser.add_argument("--output", type=Path, default=Path("build/validation/browser"))
    args = parser.parse_args()
    output: Path = args.output
    output.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        )
        # A fresh context isolates saves from the user's real browser profile.
        context = browser.new_context(viewport={"width": 1280, "height": 720})
        page = context.new_page()
        errors: list[str] = []
        messages: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda message: messages.append(f"{message.type}: {message.text}"))
        page.goto(args.url)
        page.wait_for_function("document.querySelector('#status') === null", timeout=60000)
        page.screenshot(path=str(output / "expanded.png"))
        # Exercise View early and keep the drawing loop light on software WebGL.
        page.mouse.click(124, 16)
        page.mouse.click(150, 72)
        page.mouse.move(460, 330)
        page.mouse.down()
        for x, y in [(520, 280), (600, 330), (680, 280), (760, 330)]:
            page.mouse.move(x, y, steps=4)
        page.mouse.up()
        drawn: dict[str, Any] = save_snapshot(page)
        original_ink: list[dict[str, Any]] = world_floor(drawn)["strokes"]
        assert len(original_ink) == 1 and len(original_ink[0]["points"]) > 4
        page.screenshot(path=str(output / "freehand.png"))
        page.mouse.click(72, 16)  # Edit
        page.screenshot(path=str(output / "edit-menu.png"))
        page.mouse.click(110, 48)  # Undo drawing
        assert world_floor(save_snapshot(page))["strokes"] == []
        page.mouse.click(72, 16)
        page.mouse.click(110, 72)  # Redo drawing
        assert world_floor(save_snapshot(page))["strokes"] == original_ink
        page.keyboard.press("e")
        page.mouse.move(600, 240)
        page.mouse.down()
        page.mouse.move(600, 380, steps=8)
        page.mouse.up()
        erased: dict[str, Any] = save_snapshot(page)
        erased_ink: list[dict[str, Any]] = world_floor(erased)["strokes"]
        assert len(erased_ink) == 2 and erased_ink != original_ink
        assert world_floor(erased)["terrain"] == world_floor(drawn)["terrain"]
        page.screenshot(path=str(output / "erased.png"))
        page.keyboard.press("Control+z")
        assert world_floor(save_snapshot(page))["strokes"] == original_ink
        page.screenshot(path=str(output / "undo-erase.png"))
        page.keyboard.press("Control+Shift+z")
        assert world_floor(save_snapshot(page))["strokes"] == erased_ink
        page.mouse.click(24, 56)
        page.wait_for_timeout(300)
        page.screenshot(path=str(output / "collapsed.png"))
        page.keyboard.press("Control+b")
        page.wait_for_timeout(150)  # Godot dispatches button shortcuts after the input frame.
        page.mouse.click(24, 104)
        page.keyboard.type("Greyhaven")
        page.wait_for_timeout(300)
        page.screenshot(path=str(output / "search.png"))
        page.mouse.dblclick(140, 197)
        page.wait_for_timeout(300)
        page.screenshot(path=str(output / "city.png"))
        page.mouse.click(1100, 377)
        page.keyboard.press("Control+a")
        page.keyboard.type("7.5")
        page.keyboard.press("Enter")
        page.mouse.click(1120, 415)
        page.screenshot(path=str(output / "unit-picker.png"))
        page.mouse.click(1100, 470)  # km in the native-unit popup
        persisted: dict[str, Any] = save_snapshot(page)
        saved_maps: dict[str, Any] = {
            item["id"]: item for item in persisted["campaign"]["maps"]
        }
        assert saved_maps["greyhaven"]["grid"]["distance_per_cell"] == 7.5
        assert saved_maps["greyhaven"]["grid"]["distance_unit"] == "km"
        assert saved_maps["world"]["grid"]["distance_per_cell"] == 3.0
        assert saved_maps["world"]["grid"]["distance_unit"] == "mi"
        page.reload()
        page.wait_for_function("document.querySelector('#status') === null", timeout=60000)
        restored: dict[str, Any] = save_snapshot(page)
        assert restored["campaign"] == persisted["campaign"]
        assert world_floor(restored)["strokes"] == erased_ink
        page.mouse.click(124, 16)  # View
        page.screenshot(path=str(output / "view-menu.png"))
        page.mouse.click(150, 72)  # Toggle grid overlay
        page.screenshot(path=str(output / "grid-hidden.png"))
        page.mouse.click(24, 16)
        page.screenshot(path=str(output / "file-menu.png"))
        page.keyboard.press("Escape")
        assert not errors, errors
        assert not any(
            line.startswith("error:") or "SCRIPT ERROR:" in line or "Parse Error:" in line
            for line in messages
        ), messages
        print(json.dumps({
            "result": "ATLAS_BROWSER_PASSED",
            "indexeddb_reload": "passed",
            "independent_native_units": "passed",
            "stroke_erase_undo_redo": "passed",
            "file_edit_view_menus": "passed",
            "cross_origin_isolated": page.evaluate("crossOriginIsolated"),
            "console": messages,
            "screenshots": str(output),
        }, indent=2))
        page.close()
        browser.close()


if __name__ == "__main__":
    main()
