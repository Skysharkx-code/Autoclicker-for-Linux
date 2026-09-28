#!/bin/bash
# Установщик Автокликера для Fedora.
# Установка:  sudo bash autoclicker-fedora-install.sh
# Удаление:   sudo bash autoclicker-fedora-install.sh uninstall
set -e

if [ "$(id -u)" -ne 0 ]; then
    if command -v pkexec >/dev/null 2>&1 && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
        exec pkexec env DISPLAY="$DISPLAY" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" bash "$(readlink -f "$0")" "$@"
    fi
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

if [ "$1" = "uninstall" ]; then
    rm -f /usr/bin/autoclicker \
          /usr/share/applications/autoclicker.desktop \
          /usr/share/icons/hicolor/scalable/apps/autoclicker.svg \
          /etc/udev/rules.d/60-autoclicker.rules \
          /etc/modules-load.d/autoclicker.conf
    udevadm control --reload-rules 2>/dev/null || true
    update-desktop-database -q 2>/dev/null || true
    echo "Автокликер удалён."
    exit 0
fi

echo "==> Установка зависимостей..."
dnf install -y python3 python3-tkinter python3-evdev polkit

echo "==> Установка программы..."
install -d /usr/bin /usr/share/applications /usr/share/icons/hicolor/scalable/apps /etc/udev/rules.d /etc/modules-load.d

cat > /usr/bin/autoclicker <<'APP_EOF'
#!/usr/bin/python3
"""
Autoclicker for Linux: minimal pure-black GUI (X11 and Wayland).

Dependencies:  python3-tkinter, python3-evdev
Run:           autoclicker
"""
import random
import select
import threading
import tkinter as tk
from tkinter import messagebox, ttk

try:
    import evdev
    from evdev import UInput, ecodes as e
except ImportError:
    raise SystemExit("python-evdev is not installed.")

VIRTUAL_NAME = "py-autoclicker-virtual-mouse"

BUTTONS = {
    "Left": e.BTN_LEFT,
    "Right": e.BTN_RIGHT,
    "Middle": e.BTN_MIDDLE,
}

HOTKEYS = {
    **{f"F{i}": getattr(e, f"KEY_F{i}") for i in range(1, 13)},
    "Pause": e.KEY_PAUSE,
    "Scroll Lock": e.KEY_SCROLLLOCK,
    "Insert": e.KEY_INSERT,
    "Home": e.KEY_HOME,
    "End": e.KEY_END,
}

# ---- palette: Pure Black ----
BG = "#000000"
FG = "#FFFFFF"
DIM = "#8A8A8A"
BORDER = "#333333"
LINE = "#1F1F1F"
HOVER = "#1A1A1A"
FONT = "Sans"


class Engine:
    """Clicks through a virtual mouse and listens for the hotkey."""

    def __init__(self):
        self.ui = None
        self.keyboards = []
        self.active = threading.Event()
        self.stop_flag = threading.Event()
        self.clicks = 0

        # parameters the GUI can change on the fly
        self.cps = 10.0
        self.button = e.BTN_LEFT
        self.hotkey = e.KEY_F6
        self.hold = False
        self.jitter = 0.0
        self.limit = 0

    def start(self):
        cap = {
            e.EV_KEY: list(BUTTONS.values()),
            e.EV_REL: [e.REL_X, e.REL_Y],
        }
        self.ui = UInput(cap, name=VIRTUAL_NAME)  # may raise PermissionError
        self.keyboards = self._find_keyboards()
        threading.Thread(target=self._click_loop, daemon=True).start()
        threading.Thread(target=self._key_loop, daemon=True).start()

    def shutdown(self):
        self.stop_flag.set()
        self.active.clear()
        if self.ui:
            try:
                self.ui.close()
            except OSError:
                pass

    def set_active(self, value):
        if value:
            self.clicks = 0
            self.active.set()
        else:
            self.active.clear()

    @staticmethod
    def _find_keyboards():
        result = []
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            if dev.name == VIRTUAL_NAME:
                continue
            keys = dev.capabilities().get(e.EV_KEY, [])
            if e.KEY_A in keys and e.KEY_ENTER in keys:
                result.append(dev)
        return result

    def _key_loop(self):
        devs = list(self.keyboards)
        while not self.stop_flag.is_set() and devs:
            try:
                ready, _, _ = select.select(devs, [], [], 0.2)
            except (OSError, ValueError):
                break
            for dev in ready:
                try:
                    events = list(dev.read())
                except OSError:  # device unplugged
                    devs.remove(dev)
                    continue
                for ev in events:
                    if ev.type != e.EV_KEY or ev.code != self.hotkey:
                        continue
                    if self.hold:
                        if ev.value == 1:
                            self.set_active(True)
                        elif ev.value == 0:
                            self.set_active(False)
                    elif ev.value == 1:
                        self.set_active(not self.active.is_set())

    def _click_loop(self):
        while not self.stop_flag.is_set():
            if not self.active.wait(0.1):
                continue

            button = self.button
            base = 1.0 / max(self.cps, 0.1)
            press = min(0.01, base / 2)

            self.ui.write(e.EV_KEY, button, 1)
            self.ui.syn()
            self.stop_flag.wait(press)
            self.ui.write(e.EV_KEY, button, 0)
            self.ui.syn()
            self.clicks += 1

            if self.limit and self.clicks >= self.limit:
                self.active.clear()
                continue

            delay = base - press
            if self.jitter:
                delay *= 1 + random.uniform(-self.jitter, self.jitter)
            self.stop_flag.wait(max(delay, 0.001))


def setup_style(root):
    root.configure(bg=BG)

    # dropdown list of the combobox
    root.option_add("*TCombobox*Listbox.background", BG)
    root.option_add("*TCombobox*Listbox.foreground", FG)
    root.option_add("*TCombobox*Listbox.selectBackground", FG)
    root.option_add("*TCombobox*Listbox.selectForeground", BG)
    root.option_add("*TCombobox*Listbox.borderWidth", 0)
    root.option_add("*TCombobox*Listbox.font", (FONT, 10))

    s = ttk.Style(root)
    s.theme_use("clam")

    s.configure(".", background=BG, foreground=FG, font=(FONT, 10),
                borderwidth=0, focuscolor=BG, troughcolor=BG)
    s.configure("TFrame", background=BG)
    s.configure("TLabel", background=BG, foreground=FG)
    s.configure("Dim.TLabel", foreground=DIM)

    field = dict(fieldbackground=BG, background=BG, foreground=FG,
                 bordercolor=BORDER, lightcolor=BG, darkcolor=BG,
                 arrowcolor=FG, insertcolor=FG,
                 selectbackground=FG, selectforeground=BG)

    s.configure("TSpinbox", padding=(8, 5), arrowsize=13, **field)
    s.map("TSpinbox",
          bordercolor=[("focus", FG)],
          background=[("active", HOVER)])

    s.configure("TCombobox", padding=(8, 5), arrowsize=13, **field)
    s.map("TCombobox",
          fieldbackground=[("readonly", BG)],
          foreground=[("readonly", FG)],
          selectbackground=[("readonly", BG)],
          selectforeground=[("readonly", FG)],
          bordercolor=[("focus", FG), ("active", FG)],
          background=[("active", HOVER)])

    # segmented toggle buttons
    s.configure("Seg.Toolbutton", background=BG, foreground=DIM,
                bordercolor=BORDER, lightcolor=BG, darkcolor=BG,
                padding=(14, 5), anchor="center")
    s.map("Seg.Toolbutton",
          background=[("selected", FG), ("active", HOVER)],
          foreground=[("selected", BG), ("active", FG)],
          bordercolor=[("selected", FG)])


class App:
    def __init__(self, root, engine):
        self.root = root
        self.engine = engine
        self.countdown_id = None
        self.last_state = None

        root.title("Autoclicker")
        root.resizable(False, False)
        setup_style(root)

        self.cps_var = tk.DoubleVar(value=10.0)
        self.btn_var = tk.StringVar(value="Left")
        self.key_var = tk.StringVar(value="F6")
        self.mode_var = tk.StringVar(value="toggle")
        self.jitter_var = tk.IntVar(value=0)
        self.limit_var = tk.IntVar(value=0)
        self.top_var = tk.BooleanVar(value=False)
        self.top_text = tk.StringVar(value="Off")

        frm = ttk.Frame(root, padding=(30, 26, 30, 24))
        frm.grid()
        frm.columnconfigure(0, minsize=170)
        frm.columnconfigure(1, minsize=130)

        # ---- header: status + counter ----
        self.status = ttk.Label(frm, text="STOPPED", style="Dim.TLabel",
                                font=(FONT, 9, "bold"))
        self.status.grid(row=0, column=0, columnspan=2)

        self.counter = ttk.Label(frm, text="0", font=(FONT, 44))
        self.counter.grid(row=1, column=0, columnspan=2, pady=(2, 0))

        ttk.Label(frm, text="clicks", style="Dim.TLabel").grid(
            row=2, column=0, columnspan=2, pady=(0, 18))

        self._line(frm, 3)

        # ---- settings ----
        r = 4
        self._label(frm, "Clicks per second", r)
        ttk.Spinbox(frm, from_=0.5, to=100, increment=0.5, width=7,
                    textvariable=self.cps_var, justify="right",
                    command=self.apply).grid(row=r, column=1, sticky="e")

        r += 1
        self._label(frm, "Mouse button", r)
        cb = ttk.Combobox(frm, values=list(BUTTONS), textvariable=self.btn_var,
                          state="readonly", width=8, justify="right")
        cb.grid(row=r, column=1, sticky="e")
        cb.bind("<<ComboboxSelected>>", lambda _e: self._picked())

        r += 1
        self._label(frm, "Hotkey", r)
        cb = ttk.Combobox(frm, values=list(HOTKEYS), textvariable=self.key_var,
                          state="readonly", width=8, justify="right")
        cb.grid(row=r, column=1, sticky="e")
        cb.bind("<<ComboboxSelected>>", lambda _e: self._picked())

        r += 1
        self._label(frm, "Hotkey mode", r)
        seg = ttk.Frame(frm)
        seg.grid(row=r, column=1, sticky="e")
        ttk.Radiobutton(seg, text="Toggle", value="toggle", style="Seg.Toolbutton",
                        variable=self.mode_var, command=self.apply).pack(side="left")
        ttk.Radiobutton(seg, text="Hold", value="hold", style="Seg.Toolbutton",
                        variable=self.mode_var, command=self.apply).pack(side="left")

        r += 1
        self._label(frm, "Interval jitter, %", r)
        ttk.Spinbox(frm, from_=0, to=50, width=7, textvariable=self.jitter_var,
                    justify="right", command=self.apply).grid(row=r, column=1, sticky="e")

        r += 1
        self._label(frm, "Click limit (0 = none)", r)
        ttk.Spinbox(frm, from_=0, to=1000000, width=7, textvariable=self.limit_var,
                    justify="right", command=self.apply).grid(row=r, column=1, sticky="e")

        r += 1
        self._label(frm, "Always on top", r)
        ttk.Checkbutton(frm, textvariable=self.top_text, variable=self.top_var,
                        style="Seg.Toolbutton", width=5,
                        command=self.toggle_top).grid(row=r, column=1, sticky="e")

        r += 1
        self._line(frm, r, pady=(14, 18))

        # ---- start / stop ----
        r += 1
        self.btn = tk.Button(frm, text="Start", font=(FONT, 11, "bold"),
                             relief="flat", bd=0, cursor="hand2", pady=10,
                             highlightthickness=1, command=self.on_button)
        self.btn.grid(row=r, column=0, columnspan=2, sticky="ew")
        self._style_button(running=False)

        r += 1
        self.hint = ttk.Label(frm, style="Dim.TLabel", justify="center",
                              font=(FONT, 9))
        self.hint.grid(row=r, column=0, columnspan=2, pady=(14, 0))

        for var in (self.cps_var, self.jitter_var, self.limit_var):
            var.trace_add("write", lambda *_: self.apply())

        self.apply()
        self.refresh()
        root.after(50, root.focus_set)

    # ---- small layout helpers ----
    @staticmethod
    def _label(parent, text, row):
        ttk.Label(parent, text=text).grid(row=row, column=0, sticky="w", pady=7)

    @staticmethod
    def _line(parent, row, pady=(0, 12)):
        tk.Frame(parent, height=1, bg=LINE).grid(
            row=row, column=0, columnspan=2, sticky="ew", pady=pady)

    def _style_button(self, running):
        if running:
            self.btn.config(bg=BG, fg=FG, activebackground=HOVER, activeforeground=FG,
                            highlightbackground=FG, highlightcolor=FG)
        else:
            self.btn.config(bg=FG, fg=BG, activebackground="#CCCCCC", activeforeground=BG,
                            highlightbackground=FG, highlightcolor=FG)

    # ---- logic ----
    def _picked(self):
        self.apply()
        self.root.focus_set()

    def apply(self):
        """Pass form values to the engine (tolerant to half-typed input)."""
        try:
            self.engine.cps = min(max(float(self.cps_var.get()), 0.5), 100.0)
        except (tk.TclError, ValueError):
            pass
        try:
            self.engine.jitter = min(max(int(self.jitter_var.get()), 0), 50) / 100
        except (tk.TclError, ValueError):
            pass
        try:
            self.engine.limit = max(int(self.limit_var.get()), 0)
        except (tk.TclError, ValueError):
            pass
        self.engine.button = BUTTONS[self.btn_var.get()]
        self.engine.hotkey = HOTKEYS[self.key_var.get()]
        self.engine.hold = self.mode_var.get() == "hold"

        key = self.key_var.get()
        if self.engine.hold:
            action = f"Hold {key} to click."
        else:
            action = f"Press {key} to start / stop."
        self.hint.config(text=f"{action}\nClicks land under the cursor.")

    def toggle_top(self):
        on = self.top_var.get()
        self.top_text.set("On" if on else "Off")
        self.root.attributes("-topmost", on)

    def on_button(self):
        if self.countdown_id is not None:      # countdown running: cancel
            self.root.after_cancel(self.countdown_id)
            self.countdown_id = None
            return
        if self.engine.active.is_set():        # running: stop
            self.engine.set_active(False)
            return
        self.tick(3)

    def tick(self, n):
        if n > 0:
            self.btn.config(text=f"Cancel  ({n})")
            self.countdown_id = self.root.after(1000, self.tick, n - 1)
        else:
            self.countdown_id = None
            self.engine.set_active(True)

    def refresh(self):
        if self.engine.active.is_set():
            state = "running"
        elif self.countdown_id is not None:
            state = "starting"
        else:
            state = "stopped"

        if state != self.last_state:
            self.last_state = state
            if state == "running":
                self.status.config(text="RUNNING", foreground=FG)
                self.btn.config(text="Stop")
                self._style_button(running=True)
            elif state == "starting":
                self.status.config(text="STARTING", foreground=DIM)
                self._style_button(running=True)
            else:
                self.status.config(text="STOPPED", foreground=DIM)
                self.btn.config(text="Start")
                self._style_button(running=False)

        self.counter.config(text=str(self.engine.clicks))
        self.root.after(100, self.refresh)


def access_help():
    """Figure out what is missing for input access and offer to fix it."""
    import getpass
    import grp
    import os
    import subprocess

    user = getpass.getuser()
    try:
        grp_input = grp.getgrnam("input")
    except KeyError:
        return
    if user in grp_input.gr_mem and grp_input.gr_gid not in os.getgroups():
        messagebox.showinfo(
            "Almost done",
            "Input access has been granted but takes effect after re-login.\n\n"
            "Log out and back in (or reboot), then start Autoclicker again.")
        return
    if messagebox.askyesno(
            "Access required",
            "Autoclicker needs access to input devices.\n"
            "Grant it now? (administrator password required)"):
        result = subprocess.run(["pkexec", "usermod", "-aG", "input", user])
        if result.returncode == 0:
            messagebox.showinfo(
                "Done",
                "Access granted. Log out and back in, then start Autoclicker again.")
        else:
            messagebox.showerror("Failed", "Access was not granted.")


def main():
    engine = Engine()
    root = tk.Tk()
    root.withdraw()

    try:
        engine.start()
    except PermissionError:
        access_help()
        return
    except FileNotFoundError:
        messagebox.showerror(
            "uinput module not loaded",
            "Reboot your computer: the module will be loaded automatically.")
        return
    except OSError as err:
        messagebox.showerror("Error", f"Could not create the virtual mouse:\n{err}")
        return

    if not engine.keyboards:
        # Hotkey unavailable, but the Start button still works
        access_help()

    App(root, engine)
    root.deiconify()

    def on_close():
        engine.shutdown()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
APP_EOF
chmod 755 /usr/bin/autoclicker

cat > /usr/share/applications/autoclicker.desktop <<'DESK_EOF'
[Desktop Entry]
Type=Application
Name=Autoclicker
Name[ru]=Автокликер
Comment=Automatic mouse clicks
Comment[ru]=Автоматические клики мыши
Exec=autoclicker
Icon=autoclicker
Terminal=false
Categories=Utility;
Keywords=click;mouse;autoclicker;автокликер;
DESK_EOF

cat > /usr/share/icons/hicolor/scalable/apps/autoclicker.svg <<'ICON_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#2d6cdf"/>
  <path d="M22 14 L22 44 L29 38 L34 50 L39 48 L34 36 L44 36 Z" fill="#fff"/>
  <circle cx="46" cy="18" r="4" fill="none" stroke="#fff" stroke-width="2.5"/>
  <circle cx="46" cy="18" r="9" fill="none" stroke="#fff" stroke-width="2" opacity=".5"/>
</svg>
ICON_EOF

cat > /etc/udev/rules.d/60-autoclicker.rules <<'RULE_EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"
RULE_EOF
echo "uinput" > /etc/modules-load.d/autoclicker.conf

echo "==> Настройка доступа к устройствам ввода..."
modprobe uinput 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=misc --action=change 2>/dev/null || true
getent group input >/dev/null || groupadd -r input
getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1}' | while read -r u; do
    usermod -aG input "$u" 2>/dev/null || true
done

update-desktop-database -q 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true

echo
echo "Готово! Выйдите из системы и войдите снова (один раз),"
echo "затем найдите «Автокликер» в меню приложений."
