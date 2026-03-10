# Flipdot

A Godot 4 editor plugin that makes AnimationPlayer look like stop motion.

Flipdot adds a control panel to the top of the inspector whenever an AnimationPlayer is selected. Toggle stop motion on, set your target FPS, pick an interpolation mode, and your animations will update frame-by-frame instead of every render frame.

---

## Installation

1. Copy the `addons/stop_motion_interpolation` folder into your project.
2. Open **Project → Project Settings → Plugins**.
3. Enable **Flipdot**.

---

## Usage

Select any **AnimationPlayer** node. The Flipdot panel appears at the top of the Inspector.

| Control | Description |
|---|---|
| **On / Off** toggle | Enables or disables stop motion for this AnimationPlayer |
| **Max FPS** | How many times per second the animation advances (e.g. 12 for classic stop motion) |
| **Interpolation** | Track interpolation mode applied while active — Nearest, Linear, or Cubic |

Settings are saved per-node as metadata and persist across editor sessions.

### Interpolation modes

- **Nearest** — Snaps directly to keyframe values with no blending. The classic stop motion / paper cutout look.
- **Linear** — Smooth linear interpolation between keyframes, but only updated at the target FPS.
- **Cubic** — Smooth cubic easing, updated at the target FPS.

Original track interpolation is automatically restored when the toggle is turned off.

---

## AnimationTree support

If the selected AnimationPlayer is driven by an **AnimationTree**, Flipdot detects this automatically and controls the tree instead of the player directly. A notice appears in the panel when a tree is found.

---

## Animation library support

Works with both inline animations and imported **AnimationLibrary** assets. Flipdot uses `AnimationPlayer.get_animation_list()` internally, which enumerates all animations regardless of source.

---

## Notes

- Stop motion is an **editor-preview** feature. Flipdot controls playback timing via the editor's process loop, so the effect is visible when previewing animations in the editor.
- No nodes are added to your scene tree.
- Interpolation changes are non-destructive — original values are stored and restored on disable.
