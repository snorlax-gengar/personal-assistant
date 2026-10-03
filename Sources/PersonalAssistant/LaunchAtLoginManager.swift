import Foundation
import ServiceManagement
import AppKit

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: "launchAtLogin")
            }
        }
        set {
            setLaunchAtLogin(enabled: newValue)
        }
    }

    func setLaunchAtLogin(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                        print("[+] Launch at Login 등록 성공 (SMAppService)")
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        print("[+] Launch at Login 해제 성공 (SMAppService)")
                    }
                }
            } catch {
                print("[!] SMAppService 설정 실패: \(error), fallback LaunchAgent 설정 시도")
                setupLaunchAgentFallback(enabled: enabled)
            }
        } else {
            setupLaunchAgentFallback(enabled: enabled)
        }
    }

    private func setupLaunchAgentFallback(enabled: Bool) {
        let fileManager = FileManager.default
        let launchAgentsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDir.appendingPathComponent("com.declan.PersonalAssistant.plist")

        if enabled {
            try? fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            let appPath = "/Users/declan/Desktop/PersonalAssistant/PersonalAssistant.app/Contents/MacOS/PersonalAssistant"
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.declan.PersonalAssistant</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            print("[+] LaunchAgent plist 생성 완료: \(plistURL.path)")
        } else {
            try? fileManager.removeItem(at: plistURL)
            print("[+] LaunchAgent plist 제거 완료")
        }
    }
}
