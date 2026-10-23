# Godot GDScript: Advanced Patterns

Advanced patterns for scene management, save systems, performance optimization, and best practices.

## Pattern 6: Scene Management

```gdscript
# scene_manager.gd (Autoload)
extends Node

signal scene_loading_started(scene_path: String)
signal scene_loading_progress(progress: float)
signal scene_loaded(scene: Node)
signal transition_started
signal transition_finished

@export var transition_scene: PackedScene
@export var loading_scene: PackedScene

var _current_scene: Node
var _transition: CanvasLayer

func _ready() -> void:
    _current_scene = get_tree().current_scene

    if transition_scene:
        _transition = transition_scene.instantiate() as CanvasLayer
        add_child(_transition)
        _transition.visible = false

func change_scene(scene_path: String, with_transition: bool = true) -> void:
    if with_transition:
        await _play_transition_out()

    _load_scene(scene_path)

func change_scene_packed(scene: PackedScene, with_transition: bool = true) -> void:
    if with_transition:
        await _play_transition_out()

    _swap_scene(scene.instantiate())

func _load_scene(path: String) -> void:
    scene_loading_started.emit(path)

    # Check if already loaded
    if ResourceLoader.has_cached(path):
        var scene: PackedScene = load(path) as PackedScene
        _swap_scene(scene.instantiate())
        return

    # Async loading
    ResourceLoader.load_threaded_request(path)

    while true:
        var progress: Array[float] = []
        var status: int = ResourceLoader.load_threaded_get_status(path, progress)

        match status:
            ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                scene_loading_progress.emit(progress[0])
                await get_tree().process_frame
            ResourceLoader.THREAD_LOAD_LOADED:
                var scene: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
                _swap_scene(scene.instantiate())
                return
            _:
                push_error("Failed to load scene: %s" % path)
                return

func _swap_scene(new_scene: Node) -> void:
    if _current_scene:
        _current_scene.queue_free()

    _current_scene = new_scene
    get_tree().root.add_child(_current_scene)
    get_tree().current_scene = _current_scene

    scene_loaded.emit(_current_scene)
    await _play_transition_in()

func _play_transition_out() -> void:
    if not _transition:
        return

    transition_started.emit()
    _transition.visible = true

    if _transition.has_method("transition_out"):
        await _transition.transition_out()
    else:
        await get_tree().create_timer(0.3).timeout

func _play_transition_in() -> void:
    if not _transition:
        transition_finished.emit()
        return

    if _transition.has_method("transition_in"):
        await _transition.transition_in()
    else:
        await get_tree().create_timer(0.3).timeout

    _transition.visible = false
    transition_finished.emit()
```

## Pattern 7: Save System

The save format is heterogeneous JSON: `Dictionary` types the outer
container, but not every stored value. `JSON.parse_string()` returns a
`Variant`; check it is a dictionary before using it. For stronger schema
checks, translate JSON into typed `Resource` objects.


```gdscript
# save_manager.gd (Autoload)
extends Node

const SAVE_PATH := "user://savegame.save"
const ENCRYPTION_KEY := "your_secret_key_here"

signal save_completed
signal load_completed
signal save_error(message: String)

func save_game(data: Dictionary) -> void:
    var file: FileAccess = FileAccess.open_encrypted_with_pass(
        SAVE_PATH,
        FileAccess.WRITE,
        ENCRYPTION_KEY
    )

    if file == null:
        save_error.emit("Could not open save file")
        return

    var json: String = JSON.stringify(data)
    file.store_string(json)
    file.close()

    save_completed.emit()

func load_game() -> Dictionary:
    if not FileAccess.file_exists(SAVE_PATH):
        return {}

    var file: FileAccess = FileAccess.open_encrypted_with_pass(
        SAVE_PATH,
        FileAccess.READ,
        ENCRYPTION_KEY
    )

    if file == null:
        save_error.emit("Could not open save file")
        return {}

    var json: String = file.get_as_text()
    file.close()

    var parsed: Variant = JSON.parse_string(json)
    if not (parsed is Dictionary):
        save_error.emit("Could not parse save data")
        return {}

    var parsed_data: Dictionary = parsed
    load_completed.emit()
    return parsed_data

func delete_save() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        DirAccess.remove_absolute(SAVE_PATH)

func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)
```

```gdscript
# saveable.gd (Attach to saveable nodes)
class_name Saveable
extends Node

@export var save_id: String

func _ready() -> void:
    if save_id.is_empty():
        save_id = str(get_path())

func get_save_data() -> Dictionary:
    var parent: Node = get_parent()
    var data: Dictionary = {"id": save_id}

    if parent is Node2D:
        var node_2d: Node2D = parent as Node2D
        data["position"] = {"x": node_2d.position.x, "y": node_2d.position.y}

    if parent.has_method("get_custom_save_data"):
        var custom_data: Variant = parent.call("get_custom_save_data")
        if custom_data is Dictionary:
            var custom_dictionary: Dictionary = custom_data
            data.merge(custom_dictionary)

    return data

func load_save_data(data: Dictionary) -> void:
    var parent: Node = get_parent()

    if data.has("position") and parent is Node2D:
        var node_2d: Node2D = parent as Node2D
        var position_data: Dictionary = data["position"]
        node_2d.position = Vector2(float(position_data["x"]), float(position_data["y"]))

    if parent.has_method("load_custom_save_data"):
        parent.call("load_custom_save_data", data)
```

## Performance Tips

```gdscript
# 1. Cache node references
@onready var sprite: Sprite2D = $Sprite2D  # Good
# $Sprite2D in _process()  # Bad - repeated lookup

# 2. Use object pooling for frequent spawning
# See Pattern 4 in the main skill

# 3. Avoid allocations in hot paths
var _reusable_array: Array[int] = []

func _process(_delta: float) -> void:
    _reusable_array.clear()  # Reuse instead of creating new

# 4. Use static typing
func calculate(value: float) -> float:  # Good
    return value * 2.0

# 5. Disable processing when not needed
func _on_off_screen() -> void:
    set_process(false)
    set_physics_process(false)
```

## Best Practices

### Do's

- **Use signals for decoupling** - Avoid direct references
- **Prefer static types** - Type locals, parameters, returns, and collections; validate external data at runtime
- **Use resources for data** - Separate data from logic
- **Pool frequently spawned objects** - Avoid GC hitches
- **Use Autoloads sparingly** - Only for truly global systems

### Don'ts

- **Don't use `get_node()` in loops** - Cache references
- **Don't couple scenes tightly** - Use signals
- **Don't put logic in resources** - Keep them data-only
- **Don't ignore the Profiler** - Monitor performance
- **Don't fight the scene tree** - Work with Godot's design
