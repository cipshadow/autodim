import Cocoa
import CoreGraphics

func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
}
