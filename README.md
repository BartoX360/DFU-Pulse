<p align="center"><img src="docs/images/icon.png" width="160" alt="DFU Pulse icon"></p>

![DFU Pulse](docs/images/banner.jpg)

# DFU Pulse

A free, open-source macOS app to revive or restore a Mac, iPhone or iPad in DFU mode, from a Mac.

*Une app libre et gratuite pour raviver ou restaurer un Mac, un iPhone ou un iPad en mode DFU depuis un Mac. L'interface est en français et en anglais.*

## What it does

- **Flash**: detects a Mac, iPhone or iPad connected in DFU mode. A Mac can be revived (keeps data) or restored (erased) with the macOS version you pick; an iPhone or iPad is restored with an iOS or iPadOS version Apple still signs.
- **Automatic DFU entry**: one click puts the other Mac into DFU over USB-C, without touching its keyboard (Apple silicon to Apple silicon, through both DFU ports).
- **Library**: every macOS version Apple still signs, as one universal IPSW per version (each lists the Macs it supports), and the signed iOS and iPadOS images for each iPhone and iPad model. Downloads resume, are checked against their checksum, and stay on your Mac. Verify, import, or trash them.
- **Port guide**: shows which USB-C port is the DFU port on each Mac, the key sequence to enter DFU by hand, and the button sequence for each iPhone and iPad.
- **Liquid Glass** interface, native SwiftUI.

## Requirements

- macOS 26 or later, on Apple silicon.
- [Apple Configurator](https://apps.apple.com/app/apple-configurator/id1037126344) (free). DFU Pulse drives its `cfgutil` tool for the actual revive and restore.
- A USB-C cable that carries data and charging. Thunderbolt 3 cables are not supported.
- About 60 GB of free space for a restore.

## Install

Download the latest `DFU-Pulse-x.y.z.dmg` from [Releases](https://github.com/BartoX360/DFU-Pulse/releases) and drag **DFU Pulse** to Applications. The app is signed with a Developer ID and notarized by Apple, so it opens like any other.

## Where things come from

- Firmware list: [ipsw.me](https://ipsw.me) for the full history and SHA-256 checksums, falling back to Apple's own feed. Files are only ever downloaded from Apple's servers: any other host is refused.
- IPSW files are stored in `~/Library/Application Support/DFU Pulse/IPSW` (configurable). Interrupted downloads resume.
- Automatic DFU entry uses [macvdmtool](https://github.com/AsahiLinux/macvdmtool) by the Asahi Linux contributors (Apache-2.0), bundled in `Vendor/`. It needs root, so macOS asks for an administrator password each time, unless you enable the helper in **Settings**: a small daemon inside the app, registered with `SMAppService` and switched on once in **System Settings → General → Login Items & Extensions**. launchd starts it on demand; it only accepts connections from DFU Pulse signed by the same team, checks the signature of `macvdmtool` before running it, and does nothing but `macvdmtool dfu`.

## Build

```sh
brew install xcodegen
xcodegen generate
open DFUPulse.xcodeproj
```

`scripts/package.sh` builds a DMG signed with the Developer ID certificate and has it notarized; `--publish` also creates the GitHub release. GitHub Actions runs the tests on each push.

## License

[GPL-3.0](LICENSE). DFU Pulse is free software: any distributed derivative must stay free too. `Vendor/macvdmtool` keeps its Apache-2.0 license.

DFU Pulse is not affiliated with Apple. Restoring erases the device: use it at your own risk.
