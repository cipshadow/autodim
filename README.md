# AutoDim

AutoDim is a macOS menu bar app that dims your screen and removes blue light on a daily schedule, so your display winds down before bedtime.

## Credit

AutoDim is a fork of [DisplayFilter](https://github.com/uyasarkocal/DisplayFilter) by Yaşar Koçal (MIT licensed). The menu bar app, gamma-table dimming and color filters are his work; the daily schedule, color-temperature phases, persistence, launch at login and multi-display fixes were added on top. The original copyright notice is kept in `LICENSE`. DisplayFilter was inspired by [MonitorControl](https://github.com/MonitorControl/MonitorControl) and [f.lux](https://justgetflux.com/).

## Features

- Built-in daily schedule: full brightness and no filter from 07:00, then three progressively dimmer and warmer evening phases (defaults 20:00, 22:00, 23:00), each fading in over 10 minutes; all times, brightness and color temperatures are editable
- Manual changes hold until the next scheduled boundary, then the schedule resumes
- Optional launch at login (needed for the schedule to run)
- Software brightness control below the display's native level, and manual color filters (Orange, Red, Green, Blue) with adjustable intensity
- Applies to all connected displays
- Lives in the menu bar

Brightness is a software gamma adjustment. It does not change the display's hardware backlight.

## Install

Requires macOS 15.0 or later.

1. Clone this repository.
2. Run `./build.sh` (needs only the Xcode Command Line Tools, not full Xcode). It builds and ad-hoc signs `build/AutoDim.app`.
3. Copy `build/AutoDim.app` to `/Applications` and open it.
4. Turn on "Launch at login" in the popover.

Other gamma-based tools such as f.lux change the same display settings; run only one at a time.

## Development

- `./build.sh debug` adds the `--simulate-time HH:MM` and `--debug-window` launch arguments for testing the schedule.
- `./build.sh check` runs the schedule math checks.
- The Xcode project (`DisplayFilter.xcodeproj`) also builds the app but has not been built on the maintainer's machine.

## License

MIT, see [LICENSE](LICENSE).
