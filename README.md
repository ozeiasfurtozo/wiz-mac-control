# WiZ Light Bar

A native SwiftUI macOS app for controlling a WiZ light bar over the local network.

## Features

- Local UDP discovery for WiZ devices.
- Manual IP fallback.
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

## Packaging

```bash
bash Scripts/package_app.sh
```

The app is created at:

```text
.build/app/WiZ Light Bar.app
```

On first launch, macOS may ask for local network permission.

## Notes

WiZ uses local UDP communication between devices and apps. If discovery does not find the light bar, enter the IP address shown by your router or the WiZ app.
