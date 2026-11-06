# Godot GDScript Patterns — static typing

Standalone agent skill for **Godot 4.4+**, covering signals, state machines,
resources, Autoloads, 2D object pooling, components, scene management, saves,
and performance.

Derived from [wshobson/agents: godot-gdscript-patterns](https://github.com/wshobson/agents/tree/main/plugins/game-development/skills/godot-gdscript-patterns),
originally by Seth Hobson. Used under the MIT License; see [LICENSE](LICENSE).

## Install (skills.sh)

```sh
npx skills add FivePebblesGPT/godot-gdscript-patterns --skill godot-gdscript-patterns
```

Add `-g` for installation across projects, or `-a <agent-name>` to
select a supported coding agent.

## Changes from upstream

- Replaces implicitly and dynamically typed variable declarations with
  explicit annotations in the main and reference examples.
- Prefers typed arrays and dictionaries, and documents typed dictionaries'
  Godot 4.4 minimum version.
- Documents unsupported nested type parameters and safe alternatives.
- Checks dynamic boundaries such as JSON parsing and optional runtime hooks.

## Files

- [SKILL.md](SKILL.md) — metadata, quick example, and static typing guidance
- [references/details.md](references/details.md) — core patterns
- [references/advanced-patterns.md](references/advanced-patterns.md) — advanced patterns

These are worked examples, not a complete runnable Godot project.