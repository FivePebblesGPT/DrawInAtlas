---
name: godot-gdscript-patterns
description: Master Godot 4 GDScript patterns including signals, scenes, state machines, and optimization. Use when building Godot games, implementing game systems, or learning GDScript best practices.
---

# Godot GDScript Patterns

Production patterns for Godot 4.4+ game development with statically typed GDScript, covering architecture, signals, scenes, and optimization.

## When to Use This Skill

- Building games with Godot 4
- Implementing game systems in GDScript
- Designing scene architecture
- Managing game state
- Optimizing GDScript performance
- Learning Godot best practices

## Core Concepts

### 1. Godot Architecture

```
Node: Base building block
├── Scene: Reusable node tree (saved as .tscn)
├── Resource: Data container (saved as .tres)
├── Signal: Event communication
└── Group: Node categorization
```

### 2. GDScript Basics

```gdscript
class_name Player
extends CharacterBody2D

# Signals
signal health_changed(new_health: int)
signal died

# Exports (Inspector-editable)
@export var speed: float = 200.0
@export var max_health: int = 100
@export_range(0, 1) var damage_reduction: float = 0.0
@export_group("Combat")
@export var attack_damage: int = 10
@export var attack_cooldown: float = 0.5

# Onready (initialized when ready)
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var hitbox: Area2D = $Hitbox

# Private variables (convention: underscore prefix)
var _health: int
var _can_attack: bool = true

func _ready() -> void:
    _health = max_health

func _physics_process(delta: float) -> void:
    var direction: Vector2 = Input.get_vector("left", "right", "up", "down")
    velocity = direction * speed
    move_and_slide()

func take_damage(amount: int) -> void:
    var actual_damage: int = int(amount * (1.0 - damage_reduction))
    _health = max(_health - actual_damage, 0)
    health_changed.emit(_health)

    if _health <= 0:
        died.emit()
```

## Static Typing (Godot 4.4+)

Prefer statically typed GDScript throughout examples and generated code. Type
member variables, local variables, parameters, and return values (including
`-> void`). Type inference with `:=` is also static when the initializer has
a known type, but explicit annotations make instructional examples easier to
read. Prefer precise built-in or custom classes and typed collections:
`Array[ElementType]` and `Dictionary[KeyType, ValueType]`. **Typed
dictionaries require Godot 4.4+**.

Type hints improve error detection, completion, and code comprehension; the
engine can optimize some operations with known static types. Prefer typed
built-ins such as `maxf`, `mini`, and `clampf` where appropriate.

**Nested type parameters are not supported.** `Array[Array[int]]` and
`Dictionary[String, Array[int]]` are invalid. Use `Array[Array]` or
`Dictionary[String, Array]` when necessary, noting their inner elements
remain unchecked, or model the nested data with a small typed `Resource` /
`RefCounted` class. Individual array and dictionary literal elements cannot
have their own type annotations either.

JSON payloads and heterogeneous message dictionaries are dynamic *data
boundaries*, even when the outer variable is declared as `Dictionary`.
Validate their values with `is`, use explicit conversion at the boundary,
and avoid using `Variant` for values whose concrete types are known.

## Official Godot Demo Projects

For practical examples of how Godot features work together, consult the
[official Godot demo projects](https://github.com/godotengine/godot-demo-projects).
The demos provide runnable projects showing scene trees, node configuration,
signals, input, and complete implementations. When an example is relevant,
inspect the project's `project.godot`, scene files (`.tscn`), and scripts
rather than relying on an isolated snippet.

Choose the demo repository branch matching the project's **stable Godot
version**; the demo repository's default `master` branch targets Godot's
development version and may not work with the installed stable editor.
Treat demos as reference implementations, not mandatory architecture. Adapt
patterns to the project's needs and this skill's static typing rules rather
than copying dynamically typed code unchanged.

## Detailed patterns and worked examples

Detailed pattern documentation lives in `references/details.md`. Read that file when the navigation tier above is insufficient.

