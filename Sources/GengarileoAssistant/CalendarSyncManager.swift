import Foundation
import EventKit
import AppKit

class CalendarSyncManager {
    static let shared = CalendarSyncManager()
    private let eventStore = EKEventStore()

    // 카테고리별 독립 캘린더 정의
    struct CategoryCalendarConfig {
        let title: String
        let color: NSColor
    }

    private func config(for category: ScheduleCategory) -> CategoryCalendarConfig {
        switch category {
        case .stock:
            return CategoryCalendarConfig(title: "📈 [Blanc] 주식·실적", color: .systemGreen)
        case .realEstate:
            return CategoryCalendarConfig(title: "🏠 [Blanc] 부동산·청약", color: .systemOrange)
        case .personal:
            return CategoryCalendarConfig(title: "💼 [Blanc] 개인·업무", color: .systemBlue)
        case .todo:
            return CategoryCalendarConfig(title: "✅ [Blanc] 할 일", color: .systemPurple)
        case .all:
            return CategoryCalendarConfig(title: "📌 [Blanc] 기타", color: .systemGray)
        }
    }

    func syncSchedulesToAppleCalendar(items: [ScheduleItem], completion: @escaping (Bool, String) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if granted {
                        self.processCategorizedSync(items: items, completion: completion)
                    } else {
                        self.exportAndOpenCategorizedICS(items: items, completion: completion)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if granted {
                        self.processCategorizedSync(items: items, completion: completion)
                    } else {
                        self.exportAndOpenCategorizedICS(items: items, completion: completion)
                    }
                }
            }
        }
    }

    private func getOrCreateCalendar(for config: CategoryCalendarConfig) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == config.title }) {
            return existing
        }

        let newCal = EKCalendar(for: .event, eventStore: eventStore)
        newCal.title = config.title

        // iCloud 소스 우선 검색
        if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.contains("iCloud") }) {
            newCal.source = iCloudSource
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            newCal.source = localSource
        } else {
            newCal.source = eventStore.defaultCalendarForNewEvents?.source
        }

        newCal.color = config.color
        do {
            try eventStore.saveCalendar(newCal, commit: true)
            return newCal
        } catch {
            print("[!] Failed to create calendar for \(config.title): \(error)")
            return nil
        }
    }

    private func processCategorizedSync(items: [ScheduleItem], completion: @escaping (Bool, String) -> Void) {
        do {
            // 이전 통합 캘린더가 존재한다면 과거 이벤트 삭제하여 정리
            if let oldUnified = eventStore.calendars(for: .event).first(where: { $0.title == "개인 비서 (실적·청약)" }) {
                let startDate = Date().addingTimeInterval(-86400 * 7)
                let endDate = Date().addingTimeInterval(86400 * 90)
                let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [oldUnified])
                for ev in eventStore.events(matching: predicate) {
                    try? eventStore.remove(ev, span: .thisEvent, commit: false)
                }
                // 이전 단일 캘린더 삭제 시도
                try? eventStore.removeCalendar(oldUnified, commit: false)
            }

            let uncompletedItems = items.filter { !$0.isCompleted }
            let cal = Calendar.current
            let targetCategories: [ScheduleCategory] = [.stock, .realEstate, .personal, .todo]

            var registeredCount = 0
            var categoryBreakdown: [String: Int] = [:]

            for category in targetCategories {
                let catConfig = config(for: category)
                guard let calendar = getOrCreateCalendar(for: catConfig) else { continue }

                // 해당 카테고리 캘린더의 기존 등록 이벤트 정리 (중복 방지)
                let startDate = Date().addingTimeInterval(-86400)
                let endDate = Date().addingTimeInterval(86400 * 60)
                let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
                let existingEvents = eventStore.events(matching: predicate)
                for event in existingEvents {
                    try? eventStore.remove(event, span: .thisEvent, commit: false)
                }

                // 해당 카테고리 아이템만 등록
                let itemsForCategory = uncompletedItems.filter { $0.category == category }
                for item in itemsForCategory {
                    let event = EKEvent(eventStore: eventStore)
                    event.calendar = calendar
                    event.title = item.title
                    event.notes = "\(item.memo)\n\n[PersonalAssistant 자동 비서]"

                    let startOfDay = cal.startOfDay(for: item.date)
                    event.startDate = startOfDay
                    event.endDate = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                    event.isAllDay = true

                    // 전날 오전 9시 알람 & 당일 오전 9시 알람 (아이폰 푸시)
                    event.addAlarm(EKAlarm(relativeOffset: -86400 + 32400)) // 전날 09:00
                    event.addAlarm(EKAlarm(relativeOffset: 32400))          // 당일 09:00

                    try eventStore.save(event, span: .thisEvent, commit: false)
                    registeredCount += 1
                }
                categoryBreakdown[catConfig.title] = itemsForCategory.count
            }

            try eventStore.commit()

            let summaryText = categoryBreakdown.compactMap { key, val in
                val > 0 ? "• \(key): \(val)건" : nil
            }.joined(separator: "\n")

            completion(true, "총 \(registeredCount)건이 카테고리별 전용 캘린더로 각각 분류 등록되었습니다!\n\n\(summaryText)\n\niCloud를 통해 '아이폰 16 프로'의 캘린더 목록에서 원하는 카테고리만 개별 선택/해제하여 확인하실 수 있습니다.")
        } catch {
            print("[!] EventKit categorized sync error: \(error)")
            exportAndOpenCategorizedICS(items: items, completion: completion)
        }
    }

    /// 표준 .ics 캘린더 파일 생성 및 기본 캘린더 앱으로 열기
    func exportAndOpenCategorizedICS(items: [ScheduleItem], completion: @escaping (Bool, String) -> Void) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var ics = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//PersonalAssistant//KO\nCALSCALE:GREGORIAN\nMETHOD:PUBLISH\n"

        let uncompleted = items.filter { !$0.isCompleted }
        for item in uncompleted {
            let dateStr = formatter.string(from: item.date)
            let uid = UUID().uuidString
            let catTitle = config(for: item.category).title

            ics += "BEGIN:VEVENT\n"
            ics += "UID:\(uid)\n"
            ics += "DTSTAMP:\(dateStr)T000000Z\n"
            ics += "DTSTART;VALUE=DATE:\(dateStr)\n"
            ics += "SUMMARY:[\(item.category.shortEmoji)] \(item.title)\n"
            ics += "CATEGORIES:\(catTitle)\n"
            ics += "DESCRIPTION:\(item.memo)\n"
            ics += "BEGIN:VALARM\nTRIGGER:-PT15H\nACTION:DISPLAY\nDESCRIPTION:D-Day 알림\nEND:VALARM\n"
            ics += "END:VEVENT\n"
        }
        ics += "END:VCALENDAR\n"

        let icsPath = "/Users/declan/Desktop/GengarileoAssistant/data/GengarileoAssistant.ics"
        do {
            try ics.write(toFile: icsPath, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(URL(fileURLWithPath: icsPath))
            completion(true, "카테고리가 분리된 캘린더 파일(ICS)이 생성되었습니다.\nApple 캘린더 앱에서 원하시는 캘린더로 추가하시면 아이폰 16 프로에 실시간 반영됩니다.")
        } catch {
            completion(false, "ICS 파일 생성 실패: \(error.localizedDescription)")
        }
    }
}
