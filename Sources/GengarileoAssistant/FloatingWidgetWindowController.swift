import AppKit
import SwiftUI
import Combine

class FloatingWidgetWindowController: NSObject {
    private var window: NSPanel?
    private var store = ScheduleStore.shared
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupWindow()
        setupSubscribers()
    }

    private func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 280),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = store.widgetAlwaysOnTop ? .floating : .normal
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: FloatingWidgetView(store: store))
        panel.contentView = hostingView

        // 화면 우측 상단 기본 위치 배치
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 270
            let y = screenFrame.maxY - 320
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = panel

        if store.isWidgetVisible {
            panel.orderFront(nil)
        }
    }

    private func setupSubscribers() {
        store.$isWidgetVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                if visible {
                    self?.window?.orderFront(nil)
                } else {
                    self?.window?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        store.$widgetAlwaysOnTop
            .receive(on: RunLoop.main)
            .sink { [weak self] alwaysOnTop in
                self?.window?.level = alwaysOnTop ? .floating : .normal
            }
            .store(in: &cancellables)
    }

    func toggleVisibility() {
        store.isWidgetVisible.toggle()
    }
}
