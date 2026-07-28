# Tidal Wave

A Quickshell/QML dynamic island shell for Hyprland, forked from the original tide-island. Features a wallpaper hub, video wallpaper support, pywal color integration, idle overlay, media controls, and more. A few perosnal featues like a gamemode (animtion remover) was scrapped for public release because you'd need ml4w or to fork the script. This shell also features IPC calling for standalone wallpaper picker, and search tool.

This was made for arch based systems, I use cachyos so no I have 0 clue if this works anywhere else.

---

## Dependencies

**Required:**
- Quickshell — (duh)
- [tide-island base](https://github.com/end-4/dots-hyprland) — provides the `IslandBackend` QML module this shell depends on + settings application im too lazy to fork over.
- [pywal](https://github.com/dylanaraps/pywal) — color theme-ing from wallpapers, not neccessary, as you can just run it as black.
- [imagemagick](https://imagemagick.org/) (`magick` / `convert`) — wallpaper color sampling and thumbnail generation
- `mvpaper` and `awww` — wallpaper setter (called by the post-command after selecting a wallpaper)

**For video wallpapers only:**
- [ffmpeg](https://ffmpeg.org/) — video conversion


---

## Fonts

The FlexRounded font ships in `fonts/` and is loaded automatically. No manual font installation needed.

If you prefer to install it system-wide instead:
```bash
cp fonts/*.ttf ~/.local/share/fonts/
fc-cache -f
```

---

## Setup

Git clone the repo im not smart enough to make an install bro

### 0. Forking

Download the latest tide-island and then copy over my files to the usr/share directory, this is a FORK so im just overwriting what's been made. Then in your pkg manager just ignore any pkg updates for tide-island so it doesnt overwrite my fork. 

### 1. Edit IslandConfiguration.qml

Open `qml/shared/IslandConfiguration.qml` and replace `yourname` with your actual username (or use full paths). This is the **only file** you need to edit for a basic install.

| Property | What it is | Default |
|---|---|---|
| `wallpaperFolder` | Where your wallpapers live | `~/.config/ml4w/wallpapers` |
| `thumbCacheDir` | Thumbnail cache (auto-generated) | `~/.cache/tide-island/thumbs` |
| `postCommand` | Script run after setting a wallpaper (not needed) | `~/.local/bin/wal-video-fix` |
| `videoFolder` | Where converted videos are stored | `~/Videos/wallpaper-videos` |
| `walColorsFile` | Pywal colors output | `~/.cache/wal/colors.sh` |
| `colorCacheFile` | Per-wallpaper accent color cache | `~/.cache/quickshell/wallpaper-colors.json` |

> **Tip:** `thumbCacheDir` and `colorCacheFile` directories are created automatically. You don't need to make them.

### 2. Create the thumbnail cache directory

```bash
mkdir -p ~/.cache/tide-island/thumbs
```

### 3. Set up video wallpaper conversion (optional)

If you want to use video wallpapers, run the interactive installer. This is entirely optional to do but it requires systemd:

```bash
bash bin/setup-video-converter.sh
```

It will ask you for three folders (watch, output, archive), install the conversion script, and enable a systemd user service that automatically converts videos you drop into the watch folder. It also updates `videoFolder` in `IslandConfiguration.qml` for you.

To uninstall the watcher later:
```bash
bash bin/setup-video-converter.sh --uninstall
```

### 4. Launch

```bash
quickshell -c shell.qml
```

Or add it to your Hyprland config:
```
exec-once = quickshell -c /path/to/island/shell.qml
```

---

## Customization

**Motion and feel** — edit `qml/shared/IslandMotion.qml` to adjust animation durations, easing curves, and text color hierarchy.

**Paths and integrations** — edit `qml/shared/IslandConfiguration.qml`.

**Theme-ing** Has pywal support and also (soon) custom hardcode themeing like nord, gruvbox, etc. Files have already been made but I haven't rewrote it so stay tuned. Will need: Kitty (terminal)

These are the only two files you need, as ngl ts is vibecoded so dont ask me where anything is but atleast its tokenized so its easy.

---

## Acknowledgements

Forked from the original [tide-island](https://github.com/end-4/dots-hyprland) by end-4. FlexRounded font by [?] — free for personal and commercial use. I also took inspiration + parts from other various shells to add to by own, I forgot where I got half of the things from so lets just say give no credit to me!
