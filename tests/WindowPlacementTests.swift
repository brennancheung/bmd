import AppKit
import Darwin
import Foundation

@main
enum WindowPlacementTests {
    static func main() {
        let desktop = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let wide = MainWindowPlacement.frame(in: desktop, widthPreset: .wide)
        expect(wide == NSRect(x: 220, y: 23, width: 1480, height: 1057),
               "Wide should be centered and use the full visible height")

        let laptop = NSRect(x: 0, y: 25, width: 1280, height: 775)
        let clamped = MainWindowPlacement.frame(in: laptop, widthPreset: .extraWide)
        expect(clamped == laptop,
               "a window should clamp to a smaller display instead of going off-screen")

        let leftDisplay = NSRect(x: -2560, y: 0, width: 2560, height: 1415)
        let centeredLeft = MainWindowPlacement.frame(in: leftDisplay, widthPreset: .comfortable)
        expect(centeredLeft == NSRect(x: -1920, y: 0, width: 1280, height: 1415),
               "placement should respect a secondary display's coordinate space")

        let oldWindow = NSRect(x: -1800, y: 100, width: 1000, height: 800)
        expect(
            MainWindowPlacement.bestVisibleFrame(
                for: oldWindow,
                availableFrames: [desktop, leftDisplay]
            ) == leftDisplay,
            "monitor changes should select the display containing most of the old window"
        )

        print("WindowPlacementTests passed")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("Test failed: \(message)\n".utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
