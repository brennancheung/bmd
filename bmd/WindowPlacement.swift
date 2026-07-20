import AppKit
import SwiftUI

enum MainWindowPlacement {
    static func frame(
        in visibleFrame: NSRect,
        widthPreset: WindowWidthPreset
    ) -> NSRect {
        let width = min(widthPreset.targetWidth, visibleFrame.width)
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        ).integral
    }

    static func bestVisibleFrame(
        for windowFrame: NSRect,
        availableFrames: [NSRect]
    ) -> NSRect? {
        availableFrames.max { left, right in
            intersectionArea(windowFrame, left) < intersectionArea(windowFrame, right)
        }
    }

    private static func intersectionArea(_ first: NSRect, _ second: NSRect) -> Double {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

struct MainWindowPlacementView: NSViewRepresentable {
    let widthPreset: WindowWidthPreset

    func makeNSView(context: Context) -> MainWindowPlacementNSView {
        MainWindowPlacementNSView(frame: .zero)
    }

    func updateNSView(_ view: MainWindowPlacementNSView, context: Context) {
        view.update(widthPreset: widthPreset)
    }
}

final class MainWindowPlacementNSView: NSView {
    private var widthPreset = AppPreferences.Defaults.windowWidthPreset
    private var initialPlacementScheduled = false
    private var screenObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.placeWindow()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleInitialPlacementIfNeeded()
    }

    func update(widthPreset: WindowWidthPreset) {
        let changed = self.widthPreset != widthPreset
        self.widthPreset = widthPreset
        if changed, window != nil {
            placeWindow()
        } else {
            scheduleInitialPlacementIfNeeded()
        }
    }

    private func scheduleInitialPlacementIfNeeded() {
        guard window != nil, !initialPlacementScheduled else { return }
        initialPlacementScheduled = true

        DispatchQueue.main.async { [weak self] in
            self?.placeWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.placeWindow()
        }
    }

    private func placeWindow() {
        guard let window else { return }
        window.isRestorable = false
        window.setFrameAutosaveName("")

        let screens = NSScreen.screens.map(\.visibleFrame)
        let visibleFrame = window.screen?.visibleFrame
            ?? MainWindowPlacement.bestVisibleFrame(
                for: window.frame,
                availableFrames: screens
            )
            ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }

        window.setFrame(
            MainWindowPlacement.frame(
                in: visibleFrame,
                widthPreset: widthPreset
            ),
            display: true
        )
    }
}
