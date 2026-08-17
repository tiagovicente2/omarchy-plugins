#!/usr/bin/env python3
"""kbd-rgb tray icon helper & hardware brightness synchronizer.

Registers a freedesktop StatusNotifierItem so the Omarchy tray host
(omarchy.tray) renders a crisp keyboard icon colored with the active
keyboard backlight color (or rainbow gradient in rainbow mode).

Also monitors hardware keyboard backlight state (via UPower DBus signals
and /sys/class/leds/asus::kbd_backlight) and syncs both ways:
  - Hardware hotkey pressed -> outputs 'hw_brightness <percent>' to stdout
  - Plugin slider moved     -> receives 'set_hw_brightness <percent>' on stdin

Control commands from stdin:
  mode <static|rainbow|off> [RRGGBB]  render keyboard icon with mode and color
  color <RRGGBB>                      render static keyboard icon in color
  tooltip <text>                      set the tooltip subtitle
  name <icon-name>                    fall back to themed icon name
  set_hw_brightness <0-100>           sync brightness level to UPower / sysfs
  quit                                unregister and exit
"""

import math
import os
import subprocess
import sys
import threading
from pathlib import Path

try:
    import cairo
    HAS_CAIRO = True
except ImportError:
    HAS_CAIRO = False

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ID = "omarchy-kbd-rgb"
BUS_NAME = "org.kde.StatusNotifierItem-{}-{}".format(os.getpid(), 1)
OBJ_PATH = "/StatusNotifierItem"
IFACE = "org.kde.StatusNotifierItem"
PROPS = "org.freedesktop.DBus.Properties"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"

UPOWER_DEST = "org.freedesktop.UPower"
UPOWER_PATH = "/org/freedesktop/UPower/KbdBacklight"
UPOWER_IFACE = "org.freedesktop.UPower.KbdBacklight"
SYSFS_PATH = Path("/sys/class/leds/asus::kbd_backlight")

PIXMAP_SIZE = 22


def open_panel():
    try:
        subprocess.Popen(
            ["omarchy-shell", "omarchy-kbd-rgb", "toggle"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


_PIXMAP_CACHE = {}


def render_keyboard_icon(color_hex="FFFFFF", mode="static", size=PIXMAP_SIZE):
    """Renders a 22x22 ARGB32 keyboard icon with current color or rainbow gradient."""
    cache_key = ((color_hex or "FFFFFF").strip().upper(), mode, size)
    if cache_key in _PIXMAP_CACHE:
        return _PIXMAP_CACHE[cache_key]

    if not HAS_CAIRO:
        # Fallback solid color
        hexstr = (color_hex or "FFFFFF").strip().lstrip("#")
        if len(hexstr) != 6:
            hexstr = "FFFFFF"
        try:
            r = int(hexstr[0:2], 16)
            g = int(hexstr[2:4], 16)
            b = int(hexstr[4:6], 16)
        except ValueError:
            r, g, b = 255, 255, 255
        pixel = bytes((255, r, g, b))
        res = (size, size, pixel * (size * size))
        _PIXMAP_CACHE[cache_key] = res
        return res

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    ctx.set_operator(cairo.OPERATOR_CLEAR)
    ctx.paint()
    ctx.set_operator(cairo.OPERATOR_OVER)

    if mode == "rainbow":
        pattern = cairo.LinearGradient(2.0, 0.0, 20.0, 0.0)
        pattern.add_color_stop_rgb(0.0, 1.0, 0.1, 0.2)   # Red
        pattern.add_color_stop_rgb(0.2, 1.0, 0.5, 0.0)   # Orange
        pattern.add_color_stop_rgb(0.4, 1.0, 0.85, 0.0)  # Yellow
        pattern.add_color_stop_rgb(0.6, 0.0, 0.9, 0.4)   # Green
        pattern.add_color_stop_rgb(0.8, 0.0, 0.7, 1.0)   # Cyan/Blue
        pattern.add_color_stop_rgb(1.0, 0.8, 0.1, 1.0)   # Magenta
        ctx.set_source(pattern)
    elif mode == "off":
        ctx.set_source_rgba(0.55, 0.55, 0.55, 0.35)
    else:
        hexstr = (color_hex or "FFFFFF").strip().lstrip("#")
        if len(hexstr) != 6:
            hexstr = "FFFFFF"
        try:
            r = int(hexstr[0:2], 16) / 255.0
            g = int(hexstr[2:4], 16) / 255.0
            b = int(hexstr[4:6], 16) / 255.0
        except ValueError:
            r, g, b = 1.0, 1.0, 1.0
        ctx.set_source_rgb(r, g, b)

    # Keyboard outer chassis with rounded corners
    x, y, w, h, radius = 1.5, 4.5, 19.0, 13.0, 2.2
    ctx.set_line_width(1.2)
    ctx.new_sub_path()
    ctx.arc(x + w - radius, y + radius, radius, -math.pi / 2, 0)
    ctx.arc(x + w - radius, y + h - radius, radius, 0, math.pi / 2)
    ctx.arc(x + radius, y + h - radius, radius, math.pi / 2, math.pi)
    ctx.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    ctx.close_path()
    ctx.stroke()

    # Individual keycaps (Row 1, Row 2, Row 3 with spacebar)
    keys = [
        # Row 1 (4 keys)
        (3.5, 6.5, 2.5, 2.0),
        (7.0, 6.5, 2.5, 2.0),
        (10.5, 6.5, 2.5, 2.0),
        (14.0, 6.5, 4.5, 2.0),
        # Row 2 (4 keys)
        (3.5, 9.5, 3.5, 2.0),
        (8.0, 9.5, 2.5, 2.0),
        (11.5, 9.5, 2.5, 2.0),
        (15.0, 9.5, 3.5, 2.0),
        # Row 3 (Spacebar & modifier keys)
        (3.5, 12.5, 3.0, 2.0),
        (7.5, 12.5, 7.0, 2.0),
        (15.5, 12.5, 3.0, 2.0),
    ]
    for kx, ky, kw, kh in keys:
        ctx.rectangle(kx, ky, kw, kh)
        ctx.fill()

    # Convert Cairo BGRA memory to DBus SNI network byte order (ARGB32)
    raw = bytes(surface.get_data())
    out = bytearray(len(raw))
    out[0::4] = raw[3::4]  # A
    out[1::4] = raw[2::4]  # R
    out[2::4] = raw[1::4]  # G
    out[3::4] = raw[0::4]  # B
    res = (size, size, bytes(out))
    _PIXMAP_CACHE[cache_key] = res
    return res


class KbdBrightnessSync:
    """Synchronizes hardware keyboard brightness hotkeys via UPower & sysfs."""

    def __init__(self, sys_bus):
        self.sys_bus = sys_bus
        self.iface = None
        self.max_brightness = 3
        self.last_val = None
        self.pending_val = None

        # Read max brightness from sysfs if available
        try:
            max_file = SYSFS_PATH / "max_brightness"
            if max_file.exists():
                self.max_brightness = max(1, int(max_file.read_text().strip()))
        except Exception:
            pass

        # Connect to UPower DBus interface
        if self.sys_bus:
            try:
                obj = self.sys_bus.get_object(UPOWER_DEST, UPOWER_PATH)
                self.iface = dbus.Interface(obj, UPOWER_IFACE)
                try:
                    dbus_max = int(self.iface.GetMaxBrightness())
                    if dbus_max > 0:
                        self.max_brightness = dbus_max
                except Exception:
                    pass

                self.sys_bus.add_signal_receiver(
                    self.on_brightness_changed,
                    signal_name="BrightnessChanged",
                    dbus_interface=UPOWER_IFACE,
                    path=UPOWER_PATH,
                )
                self.sys_bus.add_signal_receiver(
                    self.on_brightness_changed,
                    signal_name="BrightnessChangedWithSource",
                    dbus_interface=UPOWER_IFACE,
                    path=UPOWER_PATH,
                )
            except Exception:
                self.iface = None

        # Record initial value
        init_val = self._read_current_raw()
        if init_val is not None:
            self.last_val = init_val

        # 750ms fallback timer to catch direct ACPI sysfs changes without waking CPU unnecessarily
        GLib.timeout_add(750, self._poll_sysfs)

    def _read_current_raw(self):
        try:
            bri_file = SYSFS_PATH / "brightness"
            if bri_file.exists():
                return int(bri_file.read_text().strip())
        except Exception:
            pass
        if self.iface:
            try:
                return int(self.iface.GetBrightness())
            except Exception:
                pass
        return None

    def get_percent(self):
        val = self._read_current_raw()
        if val is not None:
            return int(round(val * 100.0 / self.max_brightness))
        return None

    def set_percent(self, percent):
        try:
            percent = max(0, min(100, int(percent)))
            target_val = int(round(percent * self.max_brightness / 100.0))
            if self.last_val == target_val:
                return
            self.pending_val = target_val
            self.last_val = target_val

            if self.iface:
                try:
                    self.iface.SetBrightness(target_val)
                    return
                except Exception:
                    pass

            # Fallback to brightnessctl if available
            try:
                subprocess.Popen(
                    ["brightnessctl", "--device=asus::kbd_backlight", "set", str(target_val)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass
        except Exception:
            pass

    def on_brightness_changed(self, val, *args):
        try:
            val = int(val)
            if self.pending_val is not None and self.pending_val == val:
                self.pending_val = None
                return
            self.pending_val = None
            if self.last_val == val:
                return
            self.last_val = val
            percent = int(round(val * 100.0 / self.max_brightness))
            sys.stdout.write("hw_brightness {}\n".format(percent))
            sys.stdout.flush()
        except Exception:
            pass

    def _poll_sysfs(self):
        val = self._read_current_raw()
        if val is not None and val != self.last_val:
            if self.pending_val is not None and self.pending_val == val:
                self.pending_val = None
                self.last_val = val
            else:
                self.last_val = val
                percent = int(round(val * 100.0 / self.max_brightness))
                sys.stdout.write("hw_brightness {}\n".format(percent))
                sys.stdout.flush()
        return GLib.SOURCE_CONTINUE


class Sni(dbus.service.Object):
    def __init__(self, bus, path):
        super().__init__(bus, path)
        self.icon_name = ""
        self.current_hex = "FFFFFF"
        self.current_mode = "static"
        self.icon_pixmap = self._build_pixmap("FFFFFF", "static")
        self.tooltip_subtitle = "Keyboard RGB"

    # ------------------------------------------------------------- helpers

    def _build_pixmap(self, hexcolor, mode="static"):
        w, h, data = render_keyboard_icon(hexcolor, mode, PIXMAP_SIZE)
        item = dbus.Struct(
            (dbus.Int32(w), dbus.Int32(h), dbus.ByteArray(data)),
            signature="iiay",
        )
        return dbus.Array([item], signature="(iiay)")

    def _props(self):
        return {
            "Category": dbus.String("ApplicationStatus"),
            "Id": dbus.String(ID),
            "Title": dbus.String("Keyboard RGB"),
            "Status": dbus.String("Active"),
            "WindowId": dbus.UInt32(0),
            "IconName": dbus.String(self.icon_name),
            "IconPixmap": self.icon_pixmap,
            "ToolTip": dbus.Struct(
                ("omarchy-kbd-rgb",
                 dbus.Array([], signature="(iiay)"),
                 "Keyboard RGB",
                 self.tooltip_subtitle),
                signature="sa(iiay)ss"),
            "ItemIsMenu": dbus.Boolean(False),
            "Menu": dbus.ObjectPath("/MenuBar"),
        }

    def _emit(self):
        props = self._props()
        self.PropertiesChanged(IFACE, {
            "IconName": props["IconName"],
            "IconPixmap": props["IconPixmap"],
            "ToolTip": props["ToolTip"],
        }, [])

    # ------------------------------------------------------- stdin control

    def set_tooltip(self, text):
        self.tooltip_subtitle = (text or "Keyboard RGB").strip() or "Keyboard RGB"
        self._emit()

    def set_color(self, hexcolor):
        self.current_hex = (hexcolor or "FFFFFF").strip()
        self.current_mode = "static"
        self.icon_name = ""
        self.icon_pixmap = self._build_pixmap(self.current_hex, "static")
        self._emit()

    def set_mode(self, mode, hexcolor=""):
        self.current_mode = (mode or "static").strip().lower()
        if hexcolor:
            self.current_hex = hexcolor.strip()
        self.icon_name = ""
        self.icon_pixmap = self._build_pixmap(self.current_hex, self.current_mode)
        self._emit()

    def set_icon_name(self, name):
        self.icon_name = name or "input-keyboard"
        self.icon_pixmap = dbus.Array([], signature="(iiay)")
        self._emit()

    # -------------------------------------------------- StatusNotifierItem

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        if interface == IFACE:
            props = self._props()
            if prop in props:
                return props[prop]
        raise dbus.exceptions.DBusException(
            "org.freedesktop.DBus.Error.UnknownProperty", prop)

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return self._props() if interface == IFACE else {}

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, interface, prop, value):
        pass

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    @dbus.service.method(IFACE, in_signature="ii")
    def Activate(self, x, y):
        open_panel()

    @dbus.service.method(IFACE, in_signature="ii")
    def SecondaryActivate(self, x, y):
        open_panel()

    @dbus.service.method(IFACE, in_signature="ii")
    def ContextMenu(self, x, y):
        open_panel()

    @dbus.service.method(IFACE, in_signature="iib")
    def Scroll(self, delta, orientation, state):
        pass


def main():
    DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()
    sys_bus = None
    try:
        sys_bus = dbus.SystemBus()
    except Exception:
        pass

    _bus_name = dbus.service.BusName(BUS_NAME, session_bus)
    sni = Sni(session_bus, OBJ_PATH)
    brightness_sync = KbdBrightnessSync(sys_bus)

    # Emit initial hardware brightness if available
    init_pct = brightness_sync.get_percent()
    if init_pct is not None:
        sys.stdout.write("hw_brightness {}\n".format(init_pct))
        sys.stdout.flush()

    def ensure_registered():
        try:
            watcher = session_bus.get_object(WATCHER, WATCHER_PATH)
            watcher.RegisterStatusNotifierItem(BUS_NAME, dbus_interface=WATCHER)
            return True
        except dbus.DBusException:
            return False

    def retry():
        if not ensure_registered():
            return GLib.SOURCE_CONTINUE
        return GLib.SOURCE_REMOVE

    GLib.timeout_add_seconds(1, retry)

    def owner_changed(name, old_owner, new_owner):
        if name == WATCHER and new_owner != "":
            ensure_registered()

    session_bus.add_signal_receiver(
        owner_changed,
        signal_name="NameOwnerChanged",
        dbus_interface="org.freedesktop.DBus",
        path="/org/freedesktop/DBus",
        arg0=WATCHER,
    )

    loop = GLib.MainLoop()

    def stdin_reader():
        for line in sys.stdin:
            parts = line.strip().split(None, 2)
            if not parts:
                continue
            command = parts[0]
            if command == "mode":
                mode = parts[1] if len(parts) > 1 else "static"
                hexcol = parts[2] if len(parts) > 2 else ""
                GLib.idle_add(sni.set_mode, mode, hexcol)
            elif command == "color":
                arg = parts[1] if len(parts) > 1 else "FFFFFF"
                GLib.idle_add(sni.set_color, arg)
            elif command == "tooltip":
                arg = line.strip().split(None, 1)[1] if len(line.strip().split(None, 1)) > 1 else ""
                GLib.idle_add(sni.set_tooltip, arg)
            elif command == "name":
                arg = parts[1] if len(parts) > 1 else ""
                GLib.idle_add(sni.set_icon_name, arg)
            elif command == "set_hw_brightness":
                arg = parts[1] if len(parts) > 1 else ""
                if brightness_sync and arg.isdigit():
                    GLib.idle_add(brightness_sync.set_percent, int(arg))
            elif command == "quit":
                GLib.idle_add(loop.quit)
                return
        GLib.idle_add(loop.quit)

    threading.Thread(target=stdin_reader, daemon=True).start()
    loop.run()


if __name__ == "__main__":
    main()