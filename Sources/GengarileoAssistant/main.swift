import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var floatingWidgetController: FloatingWidgetWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘을 숨기고 메뉴바 및 위젯 에이전트로 설정
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
        floatingWidgetController = FloatingWidgetWindowController()

        // 전역 단축키 (Option + Space) 핸들러 연결
        HotKeyManager.shared.onHotKeyPressed = { [weak self] in
            self?.statusBarController?.toggleDetailPopover()
        }
        HotKeyManager.shared.registerDefaultHotKey()

        // 아침 알림 권한 사전 요청
        NotificationManager.shared.requestAuthorization()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }
}
