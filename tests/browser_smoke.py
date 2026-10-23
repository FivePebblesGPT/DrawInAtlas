"""Exercise the exported Web UI and its IndexedDB save slot using Playwright.

Run against a served release export at a fixed 1280x720 viewport. Python is
optional test tooling; application/runtime code remains entirely GDScript.
"""

import argparse
import json
from pathlib import Path
from typing import Any

from playwright.sync_api import sync_playwright

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
        page.mouse.click(24, 56)
        page.wait_for_timeout(300)
        page.screenshot(path=str(output / "collapsed.png"))
        page.keyboard.press("Control+b")
        page.mouse.click(24, 104)
        page.keyboard.type("Greyhaven")
        page.wait_for_timeout(300)
        page.screenshot(path=str(output / "search.png"))
        page.mouse.dblclick(140, 197)
        page.wait_for_timeout(300)
        page.screenshot(path=str(output / "city.png"))
        page.mouse.click(1100, 276)
        page.keyboard.press("Control+a")
        page.keyboard.type("7.5")
        page.keyboard.press("Enter")
        page.mouse.click(1120, 307)
        page.mouse.click(1100, 358)  # km in the native-unit popup
        page.mouse.click(326, 45)  # Save
        page.wait_for_function(
            f"async () => (await ({READ_CAMPAIGN_JS})()).length === 1", timeout=15000,
        )
        persisted: list[dict[str, Any]] = page.evaluate(READ_CAMPAIGN_JS)
        saved_maps: dict[str, Any] = {
            item["id"]: item for item in persisted[0]["campaign"]["maps"]
        }
        assert saved_maps["greyhaven"]["grid"]["distance_per_cell"] == 7.5
        assert saved_maps["greyhaven"]["grid"]["distance_unit"] == "km"
        assert saved_maps["world"]["grid"]["distance_per_cell"] == 3.0
        assert saved_maps["world"]["grid"]["distance_unit"] == "mi"
        page.reload()
        page.wait_for_function("document.querySelector('#status') === null", timeout=60000)
        page.mouse.click(326, 45)
        page.wait_for_function(
            f"async (previous) => {{ const entries = await ({READ_CAMPAIGN_JS})(); "
            "return entries.length === 1 && entries[0].timestamp !== previous; }",
            arg=persisted[0]["timestamp"], timeout=15000,
        )
        restored: list[dict[str, Any]] = page.evaluate(READ_CAMPAIGN_JS)
        assert restored[0]["campaign"] == persisted[0]["campaign"]
        assert not errors, errors
        assert not any(
            line.startswith("error:") or "SCRIPT ERROR:" in line or "Parse Error:" in line
            for line in messages
        ), messages
        print(json.dumps({
            "result": "ATLAS_BROWSER_PASSED",
            "indexeddb_reload": "passed",
            "independent_native_units": "passed",
            "cross_origin_isolated": page.evaluate("crossOriginIsolated"),
            "console": messages,
            "screenshots": str(output),
        }, indent=2))
        browser.close()


if __name__ == "__main__":
    main()
