"""Reject inferred GDScript declarations in owned source and bundled skill examples.

Run with `python3 tests/check_explicit_types.py` from the repository root.
Preloaded script handles (`const Name = preload(...)`) intentionally retain their
original static-script member resolution; see docs/Tickets/T-001.md.
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOTS = ("scripts", "prefab", "tests")
SKILLS_ROOT = ROOT / ".agents" / "skills"

INFERRED_DECLARATION = re.compile(r"\b(?:var|const)\s+[A-Za-z_]\w*\s*:=")
UNTYPED_VARIABLE = re.compile(r"\bvar\s+[A-Za-z_]\w*\s*(?:=(?!=)|$)")
UNTYPED_RETURN = re.compile(r"\bfunc\s+[A-Za-z_]\w*\([^\n]*\)\s*:")
GDSCRIPT_FENCE = re.compile(r"^\s*```gdscript\s*$", re.IGNORECASE)
FENCE_END = re.compile(r"^\s*```\s*$")


def scan_code(path: Path, lines: list[tuple[int, str]]) -> list[str]:
    """Find declarations that contradict the project's explicit typing policy."""
    errors: list[str] = []
    for number, line in lines:
        code = line.split("#", maxsplit=1)[0]
        for pattern, problem in (
            (INFERRED_DECLARATION, "inferred declaration"),
            (UNTYPED_VARIABLE, "untyped variable"),
            (UNTYPED_RETURN, "missing explicit function return type"),
        ):
            if pattern.search(code):
                errors.append(f"{path.relative_to(ROOT)}:{number}: {problem}: {line.strip()}")
    return errors


def gdscript_examples(path: Path) -> list[tuple[int, str]]:
    """Only examine runnable GDScript examples, not explanatory Markdown."""
    in_gdscript = False
    lines: list[tuple[int, str]] = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not in_gdscript and GDSCRIPT_FENCE.match(line):
            in_gdscript = True
        elif in_gdscript and FENCE_END.match(line):
            in_gdscript = False
        elif in_gdscript:
            lines.append((number, line))
    return lines


def main() -> int:
    errors: list[str] = []
    source_files = sorted(
        path for directory in SOURCE_ROOTS
        for path in (ROOT / directory).rglob("*.gd")
    )
    for path in source_files:
        lines = list(enumerate(path.read_text().splitlines(), start=1))
        errors.extend(scan_code(path, lines))
    skill_files = sorted(SKILLS_ROOT.rglob("*.md"))
    for path in skill_files:
        errors.extend(scan_code(path, gdscript_examples(path)))

    if errors:
        print("\n".join(errors))
        return 1
    print(f"Explicit typing check passed: {len(source_files)} project scripts, "
          f"{len(skill_files)} skill documents")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
