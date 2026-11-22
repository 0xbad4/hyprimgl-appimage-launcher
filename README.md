# hyprimgl-appimage-launcher

A small floating search box for launching AppImages on Hyprland. Type to filter, press Return to run.

<p align="center">
  <img src="docs/screenshot.png" alt="hyprimgl showing a search field above a grid of app icons" width="468">
</p>

- No window header, just a search field and an icon grid
- Shows each app's official name and icon, read from the AppImage itself
- Opens from `APPIMAGE_DIR`, or `~/Applications` when unset
- Closes when it loses focus, after launching an app, or on Escape
- Written in QML (Quickshell) with a short Python helper; nothing stays resident
- Window placement and size are controlled from your Hyprland Lua config

The command is called `hyprimgl`.

## Requirements

- Hyprland 0.55 or newer, using the Lua config (`~/.config/hypr/hyprland.lua`)
- [Quickshell](https://quickshell.org/)
- Python 3 (standard library only)

## Install

```sh
git clone https://github.com/0xbad4/hyprimgl-appimage-launcher.git
cd hyprimgl-appimage-launcher
./install.sh
```

The script copies the config to `~/.config/quickshell/hyprimgl/`, installs the `hyprimgl` command to `~/.local/bin/`, and prints the Lua config to add to Hyprland. Print it again at any time with `./install.sh --instructions`.

Options: `--dest DIR`, `--bin-dir DIR`, `--reset-settings`, `--instructions`, `--help`.

Re-running the installer keeps your edited `LauncherSettings.qml`. New defaults are saved next to it as `LauncherSettings.qml.dist`; use `--reset-settings` to overwrite it.

## Hyprland config

Add this to `~/.config/hypr/hyprland.lua`, then run `hyprctl reload`:

```lua
hl.window_rule({
    name  = "hyprimgl",
    match = { title = "^hyprimgl$" },

    float       = true,
    center      = true,
    rounding    = 12,
    border_size = 2,

    -- size    = "420 320",
    -- size    = { "monitor_w * 0.3", "monitor_h * 0.35" },
    -- opacity = "0.95 0.95",
})

hl.bind("SUPER + A", hl.dsp.exec_cmd("~/.local/bin/hyprimgl"))

-- Scan another folder (default: ~/Applications)
-- hl.env("APPIMAGE_DIR", "/home/you/Apps")
```

Without the window rule Hyprland tiles the window instead of floating it.

## Usage

| Key | Action |
| --- | --- |
| Type | Filter by name (prefix matches first) |
| Arrow keys | Move the selection |
| Return | Launch the selected app |
| Click | Launch that app |
| Escape | Clear the search; press again to quit |

Launching closes the launcher. If an AppImage is not executable, the launcher sets the execute bit first.

## Customize

### Window (Lua)

Edit the `hl.window_rule` above. Any property that Hyprland's window rules support can be added there. Hyprland's `size` rule overrides the size requested by `LauncherSettings.qml`.

### Look and behavior

Edit `~/.config/quickshell/hyprimgl/LauncherSettings.qml`:

| Property | Default | Meaning |
| --- | --- | --- |
| `title` | `hyprimgl` | Window title; the Lua rule matches on it |
| `width`, `height` | `420`, `320` | Initial size in pixels |
| `padding` | `10` | Space around the search box and grid |
| `searchHeight` | `38` | Height of the search field |
| `iconSize` | `40` | Icon size in pixels |
| `tileWidth`, `tileHeight` | `100`, `88` | Grid cell size; columns adapt to the width |
| `radius` | `10` | Corner radius of tiles and the search field |
| `fontSize`, `fontFamily` | `12`, `""` | Text size; empty family uses the system default |
| `placeholder` | `Search AppImages` | Search field hint |
| `closeOnLaunch` | `true` | Quit after starting an app |
| `closeOnEscape` | `true` | Escape quits when the search is empty |
| `closeOnFocusLoss` | `true` | Quit when the window loses focus |
| `background`, `surface`, `tile`, `accent`, `text`, `muted` | Nord palette | Colors |

If you change `title`, change the `match` in the Lua rule to the same value.

### Folder

Set `APPIMAGE_DIR` in the environment Hyprland starts the launcher from (see the `hl.env` line above), or run `APPIMAGE_DIR=/path hyprimgl`.

## How it works

`scripts/appimage-index.py` lists `*.AppImage` files (case-insensitive) and prints one JSON line per file. For each new file it runs the AppImage's own `--appimage-extract` option, which unpacks files without starting the app, to read:

- `Name=` from the embedded `.desktop` entry (using your locale's `Name[xx]` when present)
- the icon from `.DirIcon`, falling back to `<Icon>.png` or `<Icon>.svg`

Results are cached in `~/.cache/hyprimgl/`, keyed by path, size, mtime and mode, so each file is only unpacked once. Until a file has been read, the grid shows its file name and a letter tile. Files that are not executable, or type 1 AppImages that do not support extraction, keep the file name.

`src/shell.qml` is the Quickshell window. It starts the helper, fills the grid as lines arrive, and launches the selected file.

## Troubleshooting

- **Window is tiled:** the window rule is missing or the title does not match. Check with `hyprctl clients | grep -i title`.
- **Names or icons missing:** run the helper directly to see its output: `python3 ~/.config/quickshell/hyprimgl/scripts/appimage-index.py`. Delete `~/.cache/hyprimgl/` to force a re-read.
- **Nothing happens on the bind:** the command prevents a second instance from starting while one is open. Run `hyprimgl` in a terminal to see Quickshell's errors.
- **Closes immediately:** focus left the window as it opened, for example because of a focus rule. Set `closeOnFocusLoss` to `false`.

## Uninstall

```sh
rm -rf ~/.config/quickshell/hyprimgl ~/.cache/hyprimgl ~/.local/bin/hyprimgl
```

Then remove the Lua block from your Hyprland config.

## License

[MIT](LICENSE)
