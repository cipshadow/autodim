# DisplayFilter
![SS 2024-10-03 at 5 02 08 AM](https://github.com/user-attachments/assets/576469a0-4713-4c09-b23a-0d9778651bd1)


DisplayFilter is a minimalist macOS app that combines features similar to MonitorControl and f.lux. It allows users to adjust screen brightness and apply color filters to reduce eye strain and improve visual comfort. Lives in your menubar.

## Main Focus of this app
- Simple software brightness control and color filters, not for changing the actual brightness of the display hardware. 
- This tool lets you control the brightness over the hardware limitations of your Mac's display, when you are using an external display.

## Features

- Built-in daily schedule: full brightness and no filter from 07:00, then three progressively dimmer and warmer evening phases (defaults 20:00, 22:00, 23:00), each fading in over 10 minutes; all times, brightness and color temperatures are editable
- Manual changes hold until the next scheduled boundary, then the schedule resumes
- Optional launch at login (needed for the schedule to run)
- Adjust screen brightness
- Apply color filters (Orange, Red, Green, Blue)
- Control filter intensity
- Accessible from the menu bar
- Applies to all connected displays

## Installation

1. Download the latest release from the [Releases](https://github.com/uyasarkocal/DisplayFilter/releases) page.
2. Unzip the downloaded file.
3. Drag the DisplayFilter app to your Applications folder.
4. Launch DisplayFilter from your Applications folder or using Spotlight.

## Usage

1. Click on the DisplayFilter icon in the menu bar to open the control panel.
2. Use the brightness slider to adjust screen brightness. (This is a software brightness control, not for changing the actual brightness of the display hardware.)
3. Click on a color dot to apply a color filter.
4. Use the intensity slider to adjust the strength of the color filter.
5. Click the reset button to return to default settings.

## Building from Source

To build DisplayFilter from source:

1. Clone this repository:
   ```
   git clone https://github.com/uyasarkocal/DisplayFilter.git
   ```
2. Open the project in Xcode.
3. Build and run the project (Cmd + R).

Without Xcode, `./build.sh` compiles the app with the Swift toolchain from the Command Line Tools and ad-hoc signs it into `build/DisplayFilter.app`. `./build.sh debug` adds `--simulate-time HH:MM` and `--debug-window` launch arguments for testing the schedule; `./build.sh check` runs the schedule math checks.

## Requirements

- macOS 15.0 or later
- Xcode, or just the Command Line Tools (use `./build.sh`)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

The app does not have an icon, I will be happy to add one if you send me a nice one.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [MonitorControl](https://github.com/MonitorControl/MonitorControl) and [f.lux](https://justgetflux.com/). Both are great software and I am grateful for their existence, but also I was tired of running two apps to control my displays.
- Built with SwiftUI

## Support

If you encounter any issues or have questions, please [open an issue](https://github.com/uyasarkocal/DisplayFilter/issues) on GitHub. I am not a Swift developer and made this app for my own needs, so I appreciate any help.
