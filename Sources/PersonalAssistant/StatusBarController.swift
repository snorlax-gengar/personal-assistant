import AppKit
import SwiftUI
import Combine
import QuartzCore

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var briefingPopover: NSPopover!
    private var detailPopover: NSPopover!
    private var store = ScheduleStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var hoverTimer: Timer?
    private var rollingTimer: Timer?
    private var rollingIndex: Int = 0
    private var rollingSummaries: [String] = []

    override init() {
        super.init()
        setupStatusItem()
        setupPopovers()
        setupSubscribers()
        reloadRollingData()
        startRollingTicker()
    }

    private func setupStatusItem() {
        // 전광판 롤링 시 메뉴바 아이콘들이 좌우로 흔들리지 않도록 고정 너비(155pt) 지정
        statusItem = NSStatusBar.system.statusItem(withLength: 155)

        guard let button = statusItem.button else { return }

        button.wantsLayer = true
        button.alignment = .left
        button.imagePosition = .imageLeft
        updateButtonIconOnly()

        // 커스텀 호버 & 클릭 오버레이 뷰 장착
        let overlay = HoverOverlayView(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onMouseEnter = { [weak self] in
            self?.handleMouseEntered()
        }
        overlay.onMouseExit = { [weak self] in
            self?.handleMouseExited()
        }
        overlay.onClick = { [weak self] in
            self?.handleClicked()
        }
        button.addSubview(overlay)
    }

    private func setupPopovers() {
        // 1. 호버용 데일리 브리핑 팝오버
        briefingPopover = NSPopover()
        briefingPopover.contentSize = NSSize(width: 290, height: 260)
        briefingPopover.behavior = .transient
        briefingPopover.animates = true
        let briefingView = BriefingTooltipView(store: store)
        briefingPopover.contentViewController = NSHostingController(rootView: briefingView)

        // 2. 클릭용 상세 대시보드 팝오버
        detailPopover = NSPopover()
        detailPopover.contentSize = NSSize(width: 440, height: 530)
        detailPopover.behavior = .transient
        detailPopover.animates = true
        let detailView = DetailDashboardView(store: store)
        detailPopover.contentViewController = NSHostingController(rootView: detailView)
    }

    private func setupSubscribers() {
        // 데이터 변경 시 롤링 목록 갱신
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadRollingData()
            }
            .store(in: &cancellables)
    }

    private func reloadRollingData() {
        rollingSummaries = store.menuBarRollingSummaries
        rollingIndex = 0
        updateButtonDisplay(animated: false)
    }

    private func startRollingTicker() {
        rollingTimer?.invalidate()
        // 3.5초마다 다음 일정으로 자동 회전 전환
        rollingTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            self?.advanceRollingTicker()
        }
    }

    private func advanceRollingTicker() {
        guard !rollingSummaries.isEmpty else { return }
        rollingIndex = (rollingIndex + 1) % rollingSummaries.count
        updateButtonDisplay(animated: true)
    }

    private func updateButtonIconOnly() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Assistant")?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
    }

    private func updateButtonDisplay(animated: Bool = false) {
        guard let button = statusItem.button else { return }

        updateButtonIconOnly()

        guard !rollingSummaries.isEmpty else {
            button.title = ""
            return
        }

        let currentText = rollingSummaries[rollingIndex % rollingSummaries.count]

        if animated {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = .fromBottom
            transition.duration = 0.35
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(transition, forKey: "rollingAnimation")
        }

        button.title = " \(currentText)"
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        button.attributedTitle = NSAttributedString(
            string: " \(currentText)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    // MARK: - Event Handlers
    private func handleMouseEntered() {
        guard !detailPopover.isShown else { return }

        // 호버 중에는 롤링 잠시 일시정지
        rollingTimer?.invalidate()

        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self = self,
                  let button = self.statusItem.button,
                  !self.detailPopover.isShown else { return }

            self.briefingPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func handleMouseExited() {
        hoverTimer?.invalidate()
        hoverTimer = nil

        if briefingPopover.isShown {
            briefingPopover.close()
        }

        // 마우스가 나가면 롤링 타이머 재개
        startRollingTicker()
    }

    private func handleClicked() {
        toggleDetailPopover()
    }

    /// 전역 단축키나 클릭 시 호출되는 대시보드 팝오버 토글 메서드
    func toggleDetailPopover() {
        hoverTimer?.invalidate()
        hoverTimer = nil

        if briefingPopover.isShown {
            briefingPopover.close()
        }

        guard let button = statusItem.button else { return }

        if detailPopover.isShown {
            detailPopover.close()
            startRollingTicker()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            detailPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

// MARK: - Hover & Click Overlay View
class HoverOverlayView: NSView {
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    var onClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
