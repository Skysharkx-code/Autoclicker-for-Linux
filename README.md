<div align="center">

<img src="icon.svg" width="120" alt="Autoclicker logo">

<h1>Autoclicker for Linux</h1>

<p><b>A minimal pure-black autoclicker with a clean GUI.</b><br>
<i>Works on X11 and Wayland. No terminal tinkering required.</i></p>

<p>
<a href="#features">Features</a> •
<a href="#installation">Installation</a> •
<a href="#usage">Usage</a> •
<a href="#how-it-works">How it works</a>
</p>

<p>
<img src="https://img.shields.io/badge/PLATFORM-LINUX-000000?style=for-the-badge&logo=linux&logoColor=white" alt="Platform: Linux">
<img src="https://img.shields.io/badge/PYTHON-3-000000?style=for-the-badge&logo=python&logoColor=white" alt="Python 3">
<img src="https://img.shields.io/badge/X11%20%2B%20WAYLAND-000000?style=for-the-badge" alt="X11 and Wayland">
<img src="https://img.shields.io/github/stars/Skysharkx-code/Autoclicker-for-Linux?style=for-the-badge&color=000000&labelColor=000000" alt="Stars">
</p>

</div>

---

## ✨ Features

- **Adjustable speed**: from 0.5 up to 100 clicks per second
- **Any mouse button**: left, right or middle
- **Global hotkey**: works even when the window is not focused (Toggle or Hold mode)
- **Interval jitter**: randomize the delay between clicks
- **Click limit**: stop automatically after N clicks
- **Pure black UI**: minimalist, easy on the eyes
- **X11 and Wayland**: clicks are sent through `/dev/uinput`, so it works everywhere

<!--
Add a screenshot: upload screenshot.png to the repo and uncomment the next line.
<div align="center"><img src="screenshot.png" width="360" alt="Screenshot"></div>
-->

---

## 📦 Installation

### Fedora

1. Download `autoclicker-fedora-install.sh` from this repository.
2. Run it:

```bash
bash autoclicker-fedora-install.sh
```

### Ubuntu / Debian / Linux Mint

1. Open the **Releases** page and download the `.deb` file.
2. Double-click it and press **Install**.

### After installing

Log out and back in **once** (this applies the input-device permissions).
Then launch **Autoclicker** from your application menu.

### Uninstall (Fedora)

```bash
bash autoclicker-fedora-install.sh uninstall
```

---

## 🚀 Usage

1. Set the speed, mouse button and hotkey.
2. Move the cursor over the target.
3. Press the hotkey (default **F6**) to start. Press it again to stop.

> [!NOTE]
> Clicks are performed at the current cursor position.
> The **Start** button in the window has a 3-second countdown so you can move the cursor away first.

| Setting | Description |
|---|---|
| Clicks per second | 0.5 – 100 |
| Mouse button | Left / Right / Middle |
| Hotkey | F1–F12, Pause, Scroll Lock, Insert, Home, End |
| Hotkey mode | **Toggle** (press to start / stop) or **Hold** (click while held) |
| Interval jitter | Random variation of the delay, 0 – 50 % |
| Click limit | Stop after N clicks (0 = unlimited) |

---

## ⚙️ How it works

The app creates a virtual mouse via `/dev/uinput` and sends click events through it,
which is why it works on both X11 and Wayland. The hotkey is read from `/dev/input/*`.
For that reason the installer adds your user to the `input` group.

> [!WARNING]
> Membership in the `input` group lets programs running as your user read keyboard events.
> This is required for global hotkeys on Wayland. If you don't want that, just use the
> **Start** button in the window instead of the hotkey.

---

## 🛠 Requirements

- Linux with `python3`, `python3-tkinter` and `python3-evdev` (the installers set these up automatically)
- Access to `/dev/uinput` and `/dev/input/*`
