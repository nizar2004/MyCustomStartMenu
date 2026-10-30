# MyCustomStartMenu

A KDE Plasma 6 applet that works as a full custom start menu: searchable app
launcher with a pinned favourites tab, system monitor, media controls and
power buttons — all in one popup.

## Features

- **App launcher** — *All Apps*, *Pinned* and category views in the left rail,
  instant search, arrow-key navigation and Enter to launch.
- **Pinned tab with drag reordering** — press and hold a tile for **0.6 s** to
  lift it, then move it to a new slot; a floating ghost and an insertion bar
  show where it will land. A quick tap still launches the app, and moving the
  pointer early cancels the hold so the grid stays scrollable. The order is
  saved to your Plasma favourites (`klauncherrc`).
- **System card** — uptime, memory, disk and GPU usage, click for detail.
- **Media card** — MPRIS playback controls and album art (click the art to
  open the player).
- **Power buttons** — lock, log out, suspend, reboot and shut down. Reboot,
  shut down and log out ask for a small **Yes / No confirmation** first, and
  the pending prompt is dropped automatically when the menu closes.

## Keyboard

| Key | Action |
| --- | --- |
| type | search apps immediately |
| `↑` `↓` `←` `→` / `Home` `End` | move the selection across the grid |
| `Enter` | launch the selected app — or confirm a pending power action |
| `Esc` | cancel the power prompt → drop the selection → close the menu |
| hold a pinned tile 0.6 s | lift it to reorder (drag & drop) |
- **Configurable** — accent colour override, default category, which cards
  are shown, refresh interval and panel icon.

## Requirements

- KDE Plasma 6 (`X-Plasma-API-Minimum-Version: 6.0`) — Arch Linux or any
  other distro.
- `systemd` (used to launch apps and run power actions), `glib2` for the
  `gio`/`gtk-launch` fallbacks.
- Optional: `lspci` for the GPU line, `nvidia-smi` for NVIDIA memory usage.
- No root needed — it installs per user.

## Install — one command

On a fresh Arch + KDE machine:

```bash
curl -fsSL https://raw.githubusercontent.com/nizar2004/MyCustomStartMenu/main/install.sh | bash
```

The script downloads the widget, copies it to
`~/.local/share/plasma/plasmoids/com.nizar.dashboard` (backing up any previous
install to `~/.local/share/plasma/plasmoids-backup/`) and restarts plasmashell.

Then add it to your panel: **right-click the panel → Add Widgets →
Custom Start Menu**.

## Install — from a clone

```bash
git clone https://github.com/nizar2004/MyCustomStartMenu.git
cd MyCustomStartMenu
./install.sh
```

Options:

| Flag | Effect |
| --- | --- |
| `--no-restart` | install files but don't restart plasmashell |
| `-h`, `--help` | show usage |

## Uninstall

```bash
rm -rf ~/.local/share/plasma/plasmoids/com.nizar.dashboard
systemctl --user restart plasma-plasmashell.service
```

## Configuration

Right-click the widget → **Configure…**:

| Setting | Default |
| --- | --- |
| `panelIcon` | `dashboard-show` |
| `refreshInterval` | `1500` ms |
| `defaultCategory` | `all` |
| `accentOverride` | theme highlight |
| `showUserCard` | on |
| `showSystemCard` | on |
| `showMediaCard` | on |
| `showPowerButtons` | on |

## Repository layout

```
metadata.json          Plasma applet manifest (id: com.nizar.dashboard)
install.sh             per-user installer (works from a clone or piped from GitHub)
contents/ui/           QML: main popup, AppsTab, DashState, config UI
contents/config/       config schema (main.xml) and config layout (config.qml)
contents/code/         shell helpers: app scan, app launch, sysinfo, sysmon
contents/icons/        custom category SVGs
```

## License

GPL-3.0 (as declared in `metadata.json`).
