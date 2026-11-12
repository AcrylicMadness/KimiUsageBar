# KimiUsageBar

<img src="Resources/AppIcon.png" alt="KimiUsageBar app icon" width="128">

**Kimi Code usage, right from your Mac menu bar.**

A lightweight, privacy-focused macOS app for keeping an eye on your Kimi Code limits—without copying cookies, tokens, or API keys.

## Features

- See your 5-hour usage at a glance with a green, orange, or red menu-bar icon.
- View 5-hour, legacy weekly, and monthly limits, reset times, and the monthly Kimi/Kimi Code split.
- Track your Extra Usage balance and monthly spending cap.
- Refresh automatically every 1, 5, or 15 minutes, or refresh manually.
- Receive optional notifications as usage crosses 25%, 50%, 75%, and 90%.
- Enjoy native Dark Mode support and a layered Liquid Glass app icon.
- Choose Kimi.com or Kimi.ai and optionally launch at login.

## Install

Requires macOS 13 or later.

Download `KimiUsageBar-1.0.0.dmg` from [GitHub Releases](https://github.com/AcrylicMadness/KimiUsageBar/releases), open it, and drag KimiUsageBar to Applications. Launch the app and look for the moon icon in your menu bar. Release builds are universal, signed with Developer ID, and notarized by Apple.

## Setup

If you are already signed in to the Kimi CLI, KimiUsageBar uses that existing login automatically. Otherwise, run `kimi login` in Terminal, then refresh the app. The region is inferred from the CLI configuration when possible and can be changed in Settings.

## Build from source

With Xcode command line tools installed, run:

```sh
swift test
bash build.sh
```

The build script creates an ad hoc signed universal app at `build/KimiUsageBar.app`.

## Privacy and security

KimiUsageBar reads the Kimi CLI OAuth credential from your local Kimi Code directory. It requests usage and refreshes credentials through Kimi's API and OAuth endpoints; refreshed tokens are held in memory only and are not written back to the credential file. The app also honors endpoint settings in the CLI configuration, so use a trusted configuration.

## Disclaimer

KimiUsageBar is an unofficial project and is not affiliated with or endorsed by Kimi or Moonshot AI.
