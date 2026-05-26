# WiZ Light Bar

A native SwiftUI macOS menu bar app for controlling a WiZ light bar over the local network.

## Features

- Local UDP discovery for WiZ devices.
- Manual IP fallback.
- Remembers the last connected device.
- Two-zone Ambilight mode for WiZ Gradient Bars, mapping the left screen corners to Zone A and the right screen corners to Zone B.
- Power toggle.
- Brightness control.
- White temperature control.
- RGB color control.
- Built-in WiZ scene presets such as Ocean, Fireplace, Deep dive, and Candlelight.

## Requirements

- macOS 13 or later.
- Xcode/Swift installed.
- Mac and light bar on the same local network.
- Local communication enabled in the WiZ app.

## Development

```bash
swift run WiZLightBar
```

The app appears as a light bulb in the macOS menu bar. Use the menu bar panel to discover devices, enter an IP address manually, control the light, or quit the app.

## Packaging

```bash
bash Scripts/package_app.sh
```

The app is created at:

```text
.build/app/WiZ Light Bar.app
```

The packaged app runs as a menu bar utility, so it does not show a Dock icon. On first launch, macOS may ask for local network permission. Ambilight mode also requires Screen Recording permission in macOS System Settings.

## Notes

WiZ uses local UDP communication between devices and apps. If discovery does not find the light bar, enter the IP address shown by your router or the WiZ app.
