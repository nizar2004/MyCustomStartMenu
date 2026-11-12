<div align="center">

# Custom Start Menu

**A fast, keyboard-first app dashboard for KDE Plasma 6.**

Search, pinned apps, categories, drag-and-drop, a phone panel, system & media
cards and power controls — all in one popup.

![KDE Plasma 6](https://img.shields.io/badge/KDE-Plasma%206-1d99f3?logo=kde&logoColor=white)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](metadata.json)

<img src="docs/widget.png" alt="Custom Start Menu" width="820">

</div>

## ✨ Features

- 🔍 **Instant search** — multi-word matching across name, GenericName,
  keywords, command and category. The first result is selected for you, so
  **Enter** launches it.
- 📌 **Overview tab** — an icon-only grid of your pinned apps (press and hold a
  tile to drag & reorder it; the order is saved to your Plasma favourites in
  `klauncherrc`), with a **Recently Used** list below it showing the apps you
  launched last, each with its one-line description.
- 🗂️ **Category rail** — Pinned, All Apps and every menu category, one click
  away, with bundled SVG icons.
- 🖱️ **Tile context menu** — right-click any app to launch it, pin/unpin it,
  open its containing folder, or copy its command.
- 🧲 **Drag & drop** — drag any app out of the menu onto the taskbar, the
  desktop or another window (native KDE application drag), or drag it inside
  the Pinned grid to reorder with a live Kickoff-style shuffle.
- 📱 **Phone panel** — KDE Connect control, grouped into three rows:
  **ACTIONS** (Ring / Ping / Mirror), **FROM PHONE** (notifications, SMS) and
  **SEND TO PHONE** (file, clipboard, browse), plus send-a-link and
  type-on-phone inputs and a device switcher.
- 🖥️ **Mirror the phone** — the *Mirror* action shows the phone on the desktop
  with **scrcpy** over Wi-Fi, no cable: the widget discovers the
  wireless-debugging endpoint, reconnects adb and launches scrcpy detached.
  It flips to *Stop* while mirroring — and stays available even when KDE
  Connect reports the phone as offline, since it works over adb.
- 💬 **Messages & Alerts** — read the phone's SMS (via the KDE Connect SMS
  app) and its active notifications without leaving the panel.
- 📊 **System card** — uptime, memory, disk and network at a glance; click for
  the full detail view (per-core CPU/GPU, temperatures, swap, battery…).
- 🎵 **Media card** — MPRIS controls and album art for whatever is playing;
  click the art to raise the player.
- ⏻ **Power buttons** — log out, reboot and shut down, each with a yes/no
  confirmation.
- 🪶 **Light on CPU** — the system poll is paused/slowed while the menu is
  closed and the app scan is cached, so an idle desktop stays quiet.

## 🆕 What's new

- **Phone mirroring** — a **Mirror** action in the phone panel's ACTIONS row runs scrcpy over Wi-Fi through `contents/code/scrcpy.sh` (it flips to *Stop* while mirroring); `install.sh` now installs scrcpy + adb for you, asking for the sudo password up front.
- **Phone panel rework** — actions are grouped into **ACTIONS / FROM PHONE / SEND TO PHONE**, with clearer icons (ringing bell, paper plane, monitor, bell, speech bubble, Android folder). The remote-touchpad and phone-media controls were dropped and *Run commands* was replaced by **Messages** (opens the KDE Connect SMS app). The **Clipboard** action now uses the daemon's clipboard plugin (the applet's own call) instead of `kdeconnect-cli`, which often failed to read the clipboard under Wayland. Also fixes the collapsible sections that never expanded.
- **Right-click context menu** on every tile: Launch · Pin/Unpin · Open Containing Folder · Copy Command.
- **`Tab` / `Shift+Tab`** to cycle categories and **`PageUp` / `PageDown`** to page through apps.
- **Lower idle cost** — the 1.5 s system poll drops to a slow idle tick when the popup is closed, and the app scan is cached.
- **Cleaner codebase** — `AppsTab.qml` split into `AppTile.qml`, `PhonePanel.qml` and `SystemDetails.qml` (3184 → ~1870 lines).
- **No more layout warning** — the phone toast is an overlay instead of a `ColumnLayout` child.

## ⌨️ Keyboard

| Key | Action |
| --- | :- |
| type | search apps instantly |
| `↑` `↓` `←` `→` · `Home` `End` | move the selection across the grid |
| `Tab` / `Shift+Tab` | switch to the next / previous category |
| `PageUp` / `PageDown` | jump a screenful of apps |
| `Enter` | launch the selected app — or confirm a power action |
| `Esc` | clear the selection → close the menu |

## 📦 Install

**One command** (fresh Arch + KDE):

```bash
curl -fsSL https://raw.githubusercontent.com/nizar2004/MyCustomStartMenu/main/install.sh | bash
```

The script installs the widget **per-user (no root)** and, if phone mirroring
dependencies are missing, installs `scrcpy` + `adb` as system packages — it
asks for your **sudo password up front**, once, for those. Everything else
happens without root.

**From a clone:**

```bash
git clone https://github.com/nizar2004/MyCustomStartMenu.git
cd MyCustomStartMenu && ./install.sh
```

Then add it to your panel: **right-click the panel → Add Widgets → Custom Start Menu**.

## ⚙️ Customize

<img src="docs/cards.png" alt="System and media cards" width="220" align="right">

Right-click the widget → **Configure…** to change the panel icon, accent colour,
default category, refresh interval and which cards are shown.

**Requirements** — KDE Plasma 6, `systemd`, `glib2`. Optional: `lspci` for the
GPU line, `kdeconnect` for the phone panel, and `scrcpy` + `adb`
(`android-tools` + `android-udev`) for phone mirroring. The widget itself
installs per user; only the optional packages need sudo.

**Uninstall:**

```bash
rm -rf ~/.local/share/plasma/plasmoids/com.nizar.dashboard
systemctl --user restart plasma-plasmashell.service
```

<br clear="right">

## 🗂️ Project layout

```
contents/
├── code/          helper scripts (executable data engine)
│   ├── scanapps.sh    desktop-file scanner
│   ├── sysmon.sh      CPU / RAM / disk / network
│   ├── sysinfo.sh     static system info
│   ├── launchapp.sh   Kickoff-style launching via systemd-run
│   ├── phone.sh       KDE Connect bridge
│   ├── scrcpy.sh      Wi-Fi phone mirroring (scrcpy)
│   └── readfavs.sh / osid.sh
├── ui/
│   ├── main.qml         PlasmoidItem, panel button, popup lifecycle
│   ├── AppsTab.qml      rail + app grid + search + selection
│   ├── AppTile.qml      one application tile (drag, menu, pin)
│   ├── PhonePanel.qml   KDE Connect panel
│   ├── SystemDetails.qml  detailed system view
│   └── DashState.qml    shared singleton state
└── icons/         distro logos and category SVGs
```

## 📄 License

GPL-3.0 — see [metadata.json](metadata.json).
