import Foundation
import UserNotifications
import AppKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[!] 알림 권한 요청 실패: \(error)")
                }
                completion?(granted)
            }
        }
    }

    /// 매일 오전 09:00 모닝 브리핑 예약 등록
    func scheduleDailyMorningBriefing(items: [ScheduleItem]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["DailyMorningBriefing"])

        let content = UNMutableNotificationContent()
        content.title = "☀️ 오늘의 비서 데일리 브리핑"
        content.sound = .default

        let urgentItems = items.filter { !$0.isCompleted && $0.isDDay && $0.dDayDays >= 0 }
            .sorted { $0.dDayDays < $1.dDayDays }
            .prefix(3)

        var lines: [String] = []
        if urgentItems.isEmpty {
            lines.append("오늘은 예정된 주요 D-Day가 없습니다.")
        } else {
            for item in urgentItems {
                lines.append("• \(ScheduleStore.smartShortTitle(for: item))")
            }
        }

        let todayRemaining = items.filter { $0.isToday && !$0.isCompleted }.count
        if todayRemaining > 0 {
            lines.append("• 📋 오늘 할 일 \(todayRemaining)건 대기 중")
        }

        content.body = lines.joined(separator: "\n")

        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "DailyMorningBriefing", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("[!] 모닝 브리핑 예약 실패: \(error)")
            } else {
                print("[+] 매일 오전 09:00 모닝 브리핑 예약 완료")
            }
        }
    }

    /// 즉시 테스트 알림 전송 (배너 확인용)
    func sendImmediateTestNotification(items: [ScheduleItem], completion: @escaping (Bool, String) -> Void) {
        requestAuthorization { granted in
            guard granted else {
                completion(false, "알림 권한이 꺼져 있습니다. 시스템 설정 > 알림에서 권한을 허용해 주세요.")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "☀️ [테스트] 오늘의 비서 브리핑"
            content.sound = .default

            let urgentItems = items.filter { !$0.isCompleted && $0.isDDay && $0.dDayDays >= 0 }
                .sorted { $0.dDayDays < $1.dDayDays }
                .prefix(3)

            var lines: [String] = []
            for item in urgentItems {
                lines.append("• \(ScheduleStore.smartShortTitle(for: item))")
            }
            let todayRemaining = items.filter { $0.isToday && !$0.isCompleted }.count
            if todayRemaining > 0 {
                lines.append("• 📋 오늘 할 일: \(todayRemaining)건")
            }

            content.body = lines.joined(separator: "\n")

            // 1초 뒤 알림 발송
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "알림 전송 오류: \(error.localizedDescription)")
                    } else {
                        completion(true, "화면 우측 상단에 테스트 알림 배너가 전송되었습니다!")
                    }
                }
            }
        }
    }

    // 앱이 포그라운드/활성 상태일 때도 배너 표시
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
