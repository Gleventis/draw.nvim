# draw.nvim

A lightweight, Neovim-native diagram editor for drawing directly inside text buffers.

`draw.nvim` lets you create architecture diagrams, flowcharts, boxes, connectors, and labels using Unicode characters without leaving Neovim.

It is designed to feel like a real drawing mode rather than a diagram language such as Mermaid.

```text
┌─────────────────┐
│   API Gateway   │
└────────┬────────┘
         │
         ▼
╭─────────────────╮
│     Backend     │
╰────────┬────────╯
         │
         ▼
       ╱   ╲
      ╱ DB? ╲
      ╲     ╱
       ╲   ╱
```

## Features

Current functionality includes:

* topology-aware line drawing
* automatic corners and intersections
* rectangles
* rounded rectangles
* diamonds
* constrained text editing inside shapes
* word wrapping
* shape-aware navigation
* erase mode
* safe row deletion
* automatic shape discovery after reopening files
* smart orthogonal connectors
* bidirectional connectors
* whole-shape deletion
* automatic connector cleanup when deleting shapes
* undo/redo synchronization with Draw state

## Why?

Existing approaches often require either:

* generating diagrams from another syntax
* manually managing whitespace and visual blocks
* leaving Neovim for a graphical editor

`draw.nvim` instead provides an interactive drawing mode directly inside the buffer.

Start Draw mode with:

```vim
:Draw
```

Then draw using the keyboard.

## Requirements

* Neovim

The plugin currently targets modern Neovim versions and is being developed primarily with NvChad.

## Installation

### lazy.nvim

```lua
{
  "Gleventis/draw.nvim",
  config = function()
    require("draw").setup()
  end,
}
```

## Usage

Enter Draw mode:

```vim
:Draw
```

Exit Draw mode with `q`.

## Drawing

Use the arrow keys to draw lines:

```text
← → ↑ ↓
```

For example:

```text
──────┐
      │
      └──────
```

### Move without drawing

Use `Shift + Arrow` to move the cursor without changing the canvas.

## Shapes

### Rectangle

Press `B`, move to the opposite corner, then press `B` again.

```text
┌──────────────────┐
│                  │
│                  │
└──────────────────┘
```

### Rounded rectangle

Press `R`, move to the opposite corner, then press `R` again.

```text
╭──────────────────╮
│                  │
│                  │
╰──────────────────╯
```

### Diamond

Press `D`, move to define the size, then press `D` again.

```text
       ╱╲
      ╱  ╲
     ╱    ╲
     ╲    ╱
      ╲  ╱
       ╲╱
```

## Labels

Move inside a tracked shape and press `i`.

This enters LABEL mode.

LABEL mode edits only the writable area inside the shape and protects the border.

```text
┌────────────────────┐
│ Payment API        │
│ Handles checkout   │
└────────────────────┘
```

Word wrapping is supported, including inside variable-width shapes such as diamonds.

## Shape navigation

Navigation is based on spatial relationships rather than creation order.

For example, from a shape in the middle of a diagram:

```text
hb    jump to the nearest shape on the left
jb    jump to the nearest shape below
kb    jump to the nearest shape above
lb    jump to the nearest shape on the right
```

## Smart connectors

Connect the current shape to nearby shapes using directional connector commands.

```text
┌────────────┐              ┌────────────┐
│ API        │─────────────▶│ Worker     │
└────────────┘              └────────────┘
```

Offset shapes are connected using orthogonal routes:

```text
┌────────────┐
│ API        │───────┐
└────────────┘       │
                     │
                     └──────▶┌────────────┐
                             │ Worker     │
                             └────────────┘
```

Existing connector topology is reused when possible.

Bidirectional connections are also supported:

```text
┌────────────┐              ┌────────────┐
│ API        │◀────────────▶│ Worker     │
└────────────┘              └────────────┘
```

## Erasing

Press `x` to enter ERASE mode.

The current cell is erased immediately. Move using the arrow keys to continue erasing.

Press `x` again to return to DRAW mode.

## Moving shapes

Move the cursor inside a tracked shape and press `m`.

This enters MOVE mode.

In MOVE mode the entire shape moves one cell per arrow key press. Connectors attached to the shape are detached on entry and re-routed when MOVE mode is exited.

Press `m` or `Esc` to exit MOVE mode.

## Safe deletion

Normal Vim `dd` would delete an entire buffer line, which could destroy unrelated diagram elements.

Inside Draw mode, `dd` clears only the writable portion of the current shape row.

To delete an entire shape, use:

```text
db
```

This removes:

* the shape outline
* its contents
* attached connectors
* its tracked metadata

Unrelated shapes and connector topology are preserved.

## Undo / Redo

Normal Neovim undo and redo work inside Draw mode:

```text
u
Ctrl-r
```

After each undo or redo, `draw.nvim` rediscovers shapes from the buffer so its internal state remains synchronized with what is visible.

## Shape persistence

Shape information is normally stored in memory while Draw mode is active.

When reopening an existing diagram and running:

```vim
:Draw
```

`draw.nvim` scans the buffer and reconstructs supported shapes automatically.

Currently detected:

* rectangles
* rounded rectangles
* diamonds

No separate metadata file is required.

## Keymaps

| Keymap          | Behavior                                                    |
| --------------- | ----------------------------------------------------------- |
| `:Draw`         | Toggle Draw mode                                            |
| `←` `→` `↑` `↓` | Draw topology-aware lines                                   |
| `Shift + Arrow` | Move the cursor without drawing                             |
| `B ... B`       | Create a rectangle                                          |
| `R ... R`       | Create a rounded rectangle                                  |
| `D ... D`       | Create a diamond                                            |
| `i`             | Enter LABEL mode while inside a shape                       |
| `Esc`           | Leave LABEL mode or cancel an unfinished shape              |
| `Enter`         | Move to the next writable row in LABEL mode                 |
| `Backspace`     | Clear the previous character in LABEL mode                  |
| `Delete`        | Clear the current character in LABEL mode                   |
| `x`             | Toggle ERASE mode                                           |
| `m`             | Toggle MOVE mode while inside a shape                       |
| `dd`            | Clear the writable portion of the current shape row         |
| `db`            | Delete the entire current shape and its attached connectors |
| `hb`            | Jump to the nearest shape on the left                       |
| `jb`            | Jump to the nearest shape below                             |
| `kb`            | Jump to the nearest shape above                             |
| `lb`            | Jump to the nearest shape on the right                      |
| `hc`            | Connect the current shape to the nearest shape on the left  |
| `jc`            | Connect the current shape to the nearest shape below        |
| `kc`            | Connect the current shape to the nearest shape above        |
| `lc`            | Connect the current shape to the nearest shape on the right |
| `LA`            | Place a left arrowhead `◀`                                  |
| `RA`            | Place a right arrowhead `▶`                                 |
| `UA`            | Place an up arrowhead `▲`                                   |
| `DA`            | Place a down arrowhead `▼`                                  |
| `u`             | Undo and resynchronize Draw shape state                     |
| `Ctrl-r`        | Redo and resynchronize Draw shape state                     |
| `q`             | Exit Draw mode                                              |

## Roadmap

Planned next:

* drawing safely inside comments in source files
* clear all contents of a shape
* resize shapes
* centered labels
* additional shape types
* improved obstacle-aware connector routing
* shape selection
* better Draw-mode statusline

## Status

`draw.nvim` is currently under active development.

The API, mappings, drawing behavior, and internal architecture may change while the plugin matures.

## License

MIT

