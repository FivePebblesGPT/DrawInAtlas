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
    page.mouse.click(100, 74)  # Save campaign (below New board)
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


def set_number(page: Page, x: int, y: int, value: str) -> None:
    page.mouse.click(x, y)
    page.wait_for_timeout(100)  # SpinBox starts text editing through a deferred input step.
    page.keyboard.press("Control+a")
    page.keyboard.type(value)
    page.keyboard.press("Enter")
    page.wait_for_timeout(100)


def select_option(page: Page, x: int, y: int, label: str) -> None:
    page.mouse.click(x, y)
    page.wait_for_timeout(100)
    page.mouse.move(900, 100)
    # Space activates PopupMenu entries, so search by the unambiguous first word.
    page.keyboard.type(label.split(" ", 1)[0], delay=50)
    page.keyboard.press("Enter")
    page.wait_for_timeout(300)


def check_board_creation(page: Page, output: Path, source: dict[str, Any]) -> dict[str, Any]:
    """Create a real board through the dialog and edit its overlay without changing ink."""
    original_maps: dict[str, Any] = {item["id"]: item for item in source["campaign"]["maps"]}
    page.mouse.click(24, 16)
    page.mouse.click(100, 48)
    page.wait_for_timeout(150)
    page.screenshot(path=str(output / "new-board.png"))
    page.mouse.click(600, 142)
    page.keyboard.press("Control+a")
    page.keyboard.type("Exploration")
    select_option(page, 650, 208, "Pointy hex")
    set_number(page, 600, 298, "96")
    set_number(page, 520, 362, "12.5")
    set_number(page, 720, 362, "-20.25")
    set_number(page, 600, 426, "37")
    set_number(page, 520, 490, "3")
    select_option(page, 730, 490, "mi")
    page.screenshot(path=str(output / "new-board-configured.png"))
    # Enter in the registered name input is independent of platform OK/Cancel ordering.
    page.mouse.click(600, 142)
    page.keyboard.press("Enter")
    page.wait_for_timeout(150)
    created: dict[str, Any] = save_snapshot(page)
    documents: list[dict[str, Any]] = created["campaign"]["maps"]
    board: dict[str, Any] = next(item for item in documents if item["name"] == "Exploration")
    assert len(documents) == len(original_maps) + 1
    assert board["grid"]["kind"] == 2 and board["grid"]["cell_size"] == 96.0
    assert board["grid"]["distance_per_cell"] == 3.0 and board["grid"]["distance_unit"] == "mi"
    assert board["grid"]["origin"] == [12.5, -20.25]
    assert board["floors"][0]["terrain"] == {} and board["floors"][0]["strokes"] == []
    assert created["campaign"]["links"] == source["campaign"]["links"]
    for item in documents:
        if item["id"] in original_maps:
            assert item == original_maps[item["id"]]
    board_id: str = board["id"]
    page.screenshot(path=str(output / "blank-board.png"))
    page.mouse.move(460, 330)
    page.mouse.down()
    page.mouse.move(760, 330, steps=12)
    page.mouse.up()
    drawn: dict[str, Any] = save_snapshot(page)
    ink: list[dict[str, Any]] = next(item for item in drawn["campaign"]["maps"] if item["id"] == board_id)["floors"][0]["strokes"]
    assert len(ink) == 1
    set_number(page, 1100, 440, "128")
    select_option(page, 1150, 350, "Square")
    set_number(page, 1080, 504, "40.5")
    set_number(page, 1190, 504, "-12.25")
    set_number(page, 1100, 568, "22")
    page.mouse.click(1050, 382)  # Hide overlay
    changed: dict[str, Any] = save_snapshot(page)
    board = next(item for item in changed["campaign"]["maps"] if item["id"] == board_id)
    assert board["grid"]["kind"] == 1 and board["grid"]["cell_size"] == 128.0
    assert board["grid"]["origin"] == [40.5, -12.25] and not board["grid"]["visible"]
    assert board["floors"][0]["strokes"] == ink
    page.screenshot(path=str(output / "independent-grid.png"))
    page.keyboard.press("Control+z")
    undone: dict[str, Any] = save_snapshot(page)
    assert next(item for item in undone["campaign"]["maps"] if item["id"] == board_id)["grid"]["visible"]
    page.keyboard.press("Control+Shift+z")
    redone: dict[str, Any] = save_snapshot(page)
    assert redone["campaign"] == changed["campaign"]
    return redone


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
        set_number(page, 1100, 633, "7.5")
        select_option(page, 1200, 633, "km")
        persisted: dict[str, Any] = save_snapshot(page)
        saved_maps: dict[str, Any] = {
            item["id"]: item for item in persisted["campaign"]["maps"]
        }
        assert saved_maps["greyhaven"]["grid"]["distance_per_cell"] == 7.5
        assert saved_maps["greyhaven"]["grid"]["distance_unit"] == "km"
        assert saved_maps["world"]["grid"]["distance_per_cell"] == 3.0
        assert saved_maps["world"]["grid"]["distance_unit"] == "mi"
        persisted = check_board_creation(page, output, persisted)
        page.reload()
        page.wait_for_function("document.querySelector('#status') === null", timeout=60000)
        restored: dict[str, Any] = save_snapshot(page)
        assert restored["campaign"] == persisted["campaign"]
        assert world_floor(restored)["strokes"] == erased_ink
        page.mouse.click(124, 16)  # View
        page.screenshot(path=str(output / "view-menu.png"))
        page.mouse.click(150, 72)  # Toggle grid overlay
        page.screenshot(path=str(output / "grid-toggled.png"))
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
            "board_creation_and_grid_edits": "passed",
            "grid_artwork_invariance": "passed",
            "cross_origin_isolated": page.evaluate("crossOriginIsolated"),
            "console": messages,
            "screenshots": str(output),
        }, indent=2))
        page.close()
        browser.close()


if __name__ == "__main__":
    main()
