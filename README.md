<div align="center">

# Custom Start Menu

**A fast, keyboard-first app dashboard for KDE Plasma 6.**

Search, pinned apps, categories, system & media cards, and power controls — all in one popup.

![KDE Plasma 6](https://img.shields.io/badge/KDE-Plasma%206-1d99f3?logo=kde&logoColor=white)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](metadata.json)

<img src="docs/widget.png" alt="Custom Start Menu" width="820">

</div>

## ✨ Features

- 🔍 **Instant search** — multi-word matching across name, keywords and category. The first result is selected for you, so **Enter** launches it.
- 📌 **Pinned tab** — press and hold a tile to drag & reorder it; the order is saved to your Plasma favourites.
- 🗂️ **Category rail** — All Apps, Pinned and every menu category, one click away.
- 📊 **System card** — uptime, memory, disk and network at a glance (click for detail).
- 🎵 **Media card** — MPRIS controls and album art for whatever is playing.
- ⏻ **Power buttons** — lock, log out, suspend, reboot, shut down — with confirmation.

## ⌨️ Keyboard

| Key | Action |
| --- | :- |
| type | search apps instantly |
| `↑` `↓` `←` `→` · `Home` `End` | move the selection across the grid |
| `Enter` | launch the selected app — or confirm a power action |
| `Esc` | clear the selection → close the menu |

## 📦 Install

**One command** (fresh Arch + KDE):

```bash
curl -fsSL https://raw.githubusercontent.com/nizar2004/MyCustomStartMenu/main/install.sh | bash
```

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

**Requirements** — KDE Plasma 6, `systemd`, `glib2`. Optional: `lspci` for the GPU
line. No root needed, it installs per user.

**Uninstall:**

```bash
rm -rf ~/.local/share/plasma/plasmoids/com.nizar.dashboard
systemctl --user restart plasma-plasmashell.service
```

<br clear="right">

## 📄 License

GPL-3.0 — see [metadata.json](metadata.json).
