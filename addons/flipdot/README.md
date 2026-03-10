# Flipdot

A Godot 4 plugin that makes animations look like stop motion — in the editor and at runtime.

Flipdot provides a **FlipdotPlayer** node that you add as a child of any AnimationPlayer. It applies FPS-capped, frame-by-frame playback to the target player without replacing or modifying it — making it work even in instanced scenes where the AnimationPlayer is not directly editable.

---

## Installation

1. Copy the `addons/flipdot` folder into your project.
2. Open **Project → Project Settings → Plugins**.
3. Enable **Flipdot**.

---

## Usage

Add a **FlipdotPlayer** node as a child of any AnimationPlayer.

```
AnimationPlayer
└── FlipdotPlayer   ← add this
```

If no target is set, FlipdotPlayer automatically controls its parent. You can also set the **Target** property to point at any AnimationPlayer in the scene — useful when the player lives inside a non-editable instanced scene.

Select the FlipdotPlayer node to see its controls in the inspector:

| Control | Description |
|---|---|
| **On / Off** toggle | Enables or disables stop motion |
| **Max FPS** | How many times per second the animation advances (e.g. 12 for classic stop motion) |
| **Interpolation** | Track interpolation mode applied while active |
| **Target** | The AnimationPlayer to control (auto-set to parent if left empty) |

### Interpolation modes

- **Nearest** — Snaps directly to keyframe values with no blending. The classic stop motion / paper cutout look.
- **Linear** — Smooth linear interpolation between keyframes, updated at the target FPS.
- **Cubic** — Smooth cubic easing, updated at the target FPS.

Original track interpolation is automatically restored when disabled.

---

## Instanced scenes

Because FlipdotPlayer is a plain Node, you can add it to a scene even when the AnimationPlayer is inside a sub-scene with non-editable children. Add FlipdotPlayer somewhere accessible in your own scene and point its **Target** property at the AnimationPlayer inside the sub-scene.

```
MyScene
├── Character (instanced, non-editable)
│   └── AnimationPlayer    ← target this
└── FlipdotPlayer          ← lives here, Target = Character/AnimationPlayer
```

---

## How it works

FlipdotPlayer is a `@tool` node. When stop motion is enabled it sets the target AnimationPlayer to **manual process mode**, then uses its own `_process` to advance the animation at the target FPS — accumulating real delta time and stepping forward only when a full stop-motion frame has elapsed. When disabled, the original process mode is restored.

Because the node is `@tool`, the same code runs in both the editor preview and at runtime. No autoloads, no metadata, no hidden state.

---

## Animation library support

Works with both inline animations and imported **AnimationLibrary** assets. `AnimationPlayer.get_animation_list()` enumerates all animations regardless of source, so interpolation overrides apply everywhere.

---

## Notes

- Interpolation changes are non-destructive — original track values are saved in memory and restored when stop motion is disabled.
- Disabling the plugin removes the custom type registration. Existing FlipdotPlayer nodes will continue to work (the script is still present) but won't appear under the custom type name until re-enabled.
