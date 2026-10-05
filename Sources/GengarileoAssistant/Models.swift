import Foundation
import SwiftUI
import AppKit

// MARK: - Safe URL Opener (브라우저를 화면 최상단으로 강제 활성화)
func openURLSafely(_ urlString: String?) {
    guard let urlString = urlString else { return }
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let targetURL: URL?
    if let direct = URL(string: trimmed) {
        targetURL = direct
    } else if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let direct = URL(string: encoded) {
        targetURL = direct
    } else {
        targetURL = nil
    }

    guard let url = targetURL else {
        print("[!] URL 변환 실패: \(trimmed)")
        return
    }

    print("[*] URL 열기 실행: \(url.absoluteString)")

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    config.addsToRecentItems = false

    NSWorkspace.shared.open(url, configuration: config) { app, error in
        if let error = error {
            print("[!] NSWorkspace 열기 오류: \(error.localizedDescription), 폴백 시도")
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        } else {
            print("[+] 브라우저 활성화 완료: \(app?.localizedName ?? "Browser")")
        }
    }
}

// MARK: - Category
enum ScheduleCategory: String, Codable, CaseIterable, Identifiable {
    case all = "전체"
    case personal = "개인/업무"
    case realEstate = "부동산"
    case stock = "주식/금융"
    case todo = "할 일"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .personal: return "person.fill"
        case .realEstate: return "building.2.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .todo: return "checklist"
        }
    }

    var shortEmoji: String {
        switch self {
        case .all: return "📌"
        case .personal: return "💼"
        case .realEstate: return "🏠"
        case .stock: return "📈"
        case .todo: return "✅"
        }
    }

    var color: Color {
        switch self {
        case .all: return .secondary
        case .personal: return .blue
        case .realEstate: return .orange
        case .stock: return .green
        case .todo: return .purple
        }
    }
}

// MARK: - Schedule Item
struct ScheduleItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: ScheduleCategory
    var date: Date
    var isCompleted: Bool = false
    var isDDay: Bool = true
    var memo: String = ""
    var linkURL: String? = nil
    var timeDetail: String? = nil
    var createdAt: Date = Date()

    // MARK: - Date Helpers
    var dDayDays: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTarget = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget)
        return components.day ?? 0
    }

    var dDayText: String {
        let days = dDayDays
        if days == 0 {
            return "D-Day"
        } else if days > 0 {
            return "D-\(days)"
        } else {
            return "D+\(abs(days))"
        }
    }

    var dDayBadgeColor: Color {
        let days = dDayDays
        if days == 0 {
            return .red
        } else if days > 0 && days <= 3 {
            return .orange
        } else if days > 0 && days <= 7 {
            return .blue
        } else {
            return .gray
        }
    }

    var formattedDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Store (ObservableObject)
class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()

    @Published var items: [ScheduleItem] = [] {
        didSet {
            save()
        }
    }

    @Published var isWidgetVisible: Bool = true {
        didSet {
            UserDefaults.standard.set(isWidgetVisible, forKey: "isWidgetVisible")
        }
    }

    @Published var widgetAlwaysOnTop: Bool = false {
        didSet {
            UserDefaults.standard.set(widgetAlwaysOnTop, forKey: "widgetAlwaysOnTop")
        }
    }

    @Published var autoSyncEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled")
            if autoSyncEnabled {
                startAutoSyncScheduler()
            } else {
                periodicTimer?.invalidate()
                periodicTimer = nil
            }
        }
    }

    @Published var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled {
        didSet {
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    @Published var morningBriefingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(morningBriefingEnabled, forKey: "morningBriefingEnabled")
            if morningBriefingEnabled {
                NotificationManager.shared.scheduleDailyMorningBriefing(items: items)
            }
        }
    }

    private var periodicTimer: Timer?
    private var calendarSyncDebounceItem: DispatchWorkItem?

    let dataDirectory: URL
    let saveURL: URL
    let backupDirectory: URL

    init() {
        // 프로젝트 폴더 내 data 디렉토리 우선 사용
        let projectDataDir = URL(fileURLWithPath: "/Users/declan/Desktop/GengarileoAssistant/data", isDirectory: true)
        let fileManager = FileManager.default

        if (try? fileManager.createDirectory(at: projectDataDir, withIntermediateDirectories: true)) != nil {
            self.dataDirectory = projectDataDir
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let fallback = appSupport.appendingPathComponent("GengarileoAssistant", isDirectory: true)
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            self.dataDirectory = fallback
        }

        self.saveURL = self.dataDirectory.appendingPathComponent("schedules.json")
        self.backupDirectory = self.dataDirectory.appendingPathComponent("backups", isDirectory: true)
        try? fileManager.createDirectory(at: self.backupDirectory, withIntermediateDirectories: true)

        if UserDefaults.standard.object(forKey: "isWidgetVisible") != nil {
            self.isWidgetVisible = UserDefaults.standard.bool(forKey: "isWidgetVisible")
        }
        self.widgetAlwaysOnTop = UserDefaults.standard.bool(forKey: "widgetAlwaysOnTop")

        if UserDefaults.standard.object(forKey: "autoSyncEnabled") != nil {
            self.autoSyncEnabled = UserDefaults.standard.bool(forKey: "autoSyncEnabled")
        }

        if UserDefaults.standard.object(forKey: "morningBriefingEnabled") != nil {
            self.morningBriefingEnabled = UserDefaults.standard.bool(forKey: "morningBriefingEnabled")
        }

        load()

        if self.autoSyncEnabled {
            startAutoSyncScheduler()
        }

        if self.morningBriefingEnabled {
            NotificationManager.shared.scheduleDailyMorningBriefing(items: items)
        }
    }

    func addItem(title: String, category: ScheduleCategory, date: Date, isDDay: Bool = true, memo: String = "") {
        let item = ScheduleItem(
            title: title,
            category: category == .all ? .personal : category,
            date: date,
            isDDay: isDDay,
            memo: memo
        )
        items.append(item)
        triggerDebouncedCalendarSync()
    }

    // MARK: - Smart Natural Language Parser (Fantastical 스타일 빠른 등록)
    static func parseNaturalLanguage(input: String) -> (title: String, category: ScheduleCategory, date: Date, isDDay: Bool, timeString: String?) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        var targetDate = Date()
        var detectedCategory: ScheduleCategory = .personal
        var detectedTimeStr: String? = nil

        // 1. 카테고리 태그 및 키워드 감지
        if text.contains("#할일") || text.contains("#todo") || text.contains("체크리스트") {
            detectedCategory = .todo
            text = text.replacingOccurrences(of: "#할일", with: "").replacingOccurrences(of: "#todo", with: "")
        } else if text.contains("#주식") || text.contains("실적 발표") || text.contains("실적발표") || text.contains("실발") || text.contains("어닝") {
            detectedCategory = .stock
            text = text.replacingOccurrences(of: "#주식", with: "")
        } else if text.contains("#부동산") || text.contains("청약") || text.contains("분양") || text.contains("신희타") || text.contains("무순위") || text.contains("줍줍") {
            detectedCategory = .realEstate
            text = text.replacingOccurrences(of: "#부동산", with: "")
        } else if text.contains("#업무") || text.contains("#개인") {
            detectedCategory = .personal
            text = text.replacingOccurrences(of: "#업무", with: "").replacingOccurrences(of: "#개인", with: "")
        }

        // 2. 날짜 키워드 감지
        if text.contains("내일") {
            targetDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            text = text.replacingOccurrences(of: "내일", with: "")
        } else if text.contains("모레") {
            targetDate = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()
            text = text.replacingOccurrences(of: "모레", with: "")
        } else if text.contains("글피") {
            targetDate = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
            text = text.replacingOccurrences(of: "글피", with: "")
        } else if text.contains("오늘") {
            targetDate = Date()
            text = text.replacingOccurrences(of: "오늘", with: "")
        } else if let match = text.range(of: "(\\d+)일\\s*(뒤|후)", options: .regularExpression) {
            let matchedStr = String(text[match])
            if let num = Int(matchedStr.filter { $0.isNumber }) {
                targetDate = calendar.date(byAdding: .day, value: num, to: Date()) ?? Date()
            }
            text.removeSubrange(match)
        } else if let match = text.range(of: "(\\d{1,2})월\\s*(\\d{1,2})일", options: .regularExpression) {
            let matchedStr = String(text[match])
            let numbers = matchedStr.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if numbers.count >= 2 {
                var comps = calendar.dateComponents([.year], from: Date())
                comps.month = numbers[0]
                comps.day = numbers[1]
                if let d = calendar.date(from: comps) {
                    targetDate = d
                }
            }
            text.removeSubrange(match)
        } else if let match = text.range(of: "(\\d{1,2})/(\\d{1,2})", options: .regularExpression) {
            let matchedStr = String(text[match])
            let parts = matchedStr.split(separator: "/").compactMap { Int($0) }
            if parts.count >= 2 {
                var comps = calendar.dateComponents([.year], from: Date())
                comps.month = parts[0]
                comps.day = parts[1]
                if let d = calendar.date(from: comps) {
                    targetDate = d
                }
            }
            text.removeSubrange(match)
        }

        // 3. 시간대 추출 (예: 저녁 7시, 오후 3시, 14시 등)
        if let match = text.range(of: "(오전|오후|저녁|아침|밤)?\\s*(\\d{1,2})시", options: .regularExpression) {
            let matchedStr = String(text[match]).trimmingCharacters(in: .whitespaces)
            detectedTimeStr = matchedStr
            text.removeSubrange(match)
        }

        let cleanTitle = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-,:/")))
        let finalTitle = cleanTitle.isEmpty ? "새 일정" : cleanTitle

        return (
            title: finalTitle,
            category: detectedCategory,
            date: targetDate,
            isDDay: true,
            timeString: detectedTimeStr
        )
    }

    /// 자연어 한 줄 입력으로 즉시 일정 추가 (키보드 Enter 한 번으로 등록)
    @discardableResult
    func addNaturalLanguageItem(input: String) -> ScheduleItem {
        let parsed = ScheduleStore.parseNaturalLanguage(input: input)
        let memoText = parsed.timeString != nil ? "시간: \(parsed.timeString!)" : ""
        let item = ScheduleItem(
            title: parsed.title,
            category: parsed.category,
            date: parsed.date,
            isDDay: parsed.isDDay,
            memo: memoText,
            timeDetail: parsed.timeString
        )
        items.append(item)
        triggerDebouncedCalendarSync()
        return item
    }

    func toggleCompleted(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isCompleted.toggle()
            triggerDebouncedCalendarSync()
        }
    }

    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        triggerDebouncedCalendarSync()
    }

    func clearAll() {
        createBackupSnapshot() // 지우기 전 자동 백업 생성
        items.removeAll()
    }

    func resetToSamples() {
        createBackupSnapshot() // 초기화 전 자동 백업 생성
        loadInitialSampleData()
    }

    // MARK: - Smart Short Title & Rolling Summaries for Menu Bar
    static func smartShortTitle(for item: ScheduleItem) -> String {
        var title = item.title

        // 대괄호 분양 유형 태그 추출 및 축약
        var prefixTag = ""
        if title.contains("[신혼희망타운]") {
            prefixTag = "신희타 "
        } else if title.contains("[무순위]") {
            prefixTag = "줍줍 "
        } else if title.contains("[공공분양]") {
            prefixTag = "공공 "
        }

        // [태그] 제거
        if let regex = try? NSRegularExpression(pattern: "\\[.*?\\]\\s*") {
            title = regex.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: title.utf16.count), withTemplate: "")
        }

        // 불필요한 공통 단어 정리하여 핵심 명칭 부각
        title = title.replacingOccurrences(of: " 청약 접수", with: "")
        title = title.replacingOccurrences(of: " 청약", with: "")
        title = title.replacingOccurrences(of: " 실적 발표", with: " 실발")
        title = title.replacingOccurrences(of: "블록", with: "")
        title = title.replacingOccurrences(of: "신혼희망타운", with: "")
        title = title.replacingOccurrences(of: "공공분양", with: "")
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // 적정 길이 제한 (최대 10글자)
        if title.count > 10 {
            title = String(title.prefix(9)) + ".."
        }

        return "\(item.category.shortEmoji) \(prefixTag)\(title) \(item.dDayText)"
    }

    var menuBarRollingSummaries: [String] {
        let active = items.filter { !$0.isCompleted && $0.isDDay && $0.dDayDays >= 0 }
            .sorted { $0.dDayDays < $1.dDayDays }

        guard !active.isEmpty else {
            let todayUncompleted = todayItems.filter { !$0.isCompleted }.count
            if todayUncompleted > 0 {
                return ["📋 오늘 할 일 \(todayUncompleted)건"]
            }
            return ["✨ 일정 없음"]
        }

        // 임박한 상위 최대 6개 일정 순환
        return active.prefix(6).map { ScheduleStore.smartShortTitle(for: $0) }
    }

    // 하위 호환용 단일 요약
    var menuBarUrgentSummary: String? {
        menuBarRollingSummaries.first
    }

    // MARK: - Query Lists
    var upcomingDDayItems: [ScheduleItem] {
        items.filter { !$0.isCompleted && $0.isDDay && $0.dDayDays >= 0 }
            .sorted { $0.dDayDays < $1.dDayDays }
    }

    var todayItems: [ScheduleItem] {
        items.filter { $0.isToday }
            .sorted { $0.isCompleted && !$1.isCompleted }
    }

    var urgentDDayCount: Int {
        items.filter { !$0.isCompleted && $0.isDDay && $0.dDayDays >= 0 && $0.dDayDays <= 3 }.count
    }

    // MARK: - Persistence & Backup
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackIso = ISO8601DateFormatter()

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let dateStr = try? container.decode(String.self) {
                if let d = isoFormatter.date(from: dateStr) { return d }
                if let d = fallbackIso.date(from: dateStr) { return d }
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let d = df.date(from: dateStr) { return d }
                df.dateFormat = "yyyy-MM-dd"
                if let d = df.date(from: dateStr) { return d }
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid date format"))
        }
        return decoder
    }

    private func save() {
        do {
            let data = try makeEncoder().encode(items)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save schedules: \(error)")
        }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            self.items = []
            return
        }

        do {
            let data = try Data(contentsOf: saveURL)
            self.items = try makeDecoder().decode([ScheduleItem].self, from: data)
            print("Successfully loaded \(self.items.count) schedules.")
        } catch {
            print("Failed to load schedules: \(error)")
            self.items = []
        }
    }

    /// 파이썬 자동 수집기(sync_collector.py)를 백그라운드에서 실행하고 최신 데이터 갱신
    func syncAutoCollector(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let scriptPath = "/Users/declan/Desktop/GengarileoAssistant/scripts/sync_collector.py"
            let pythonBin = "/opt/homebrew/bin/python3"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: pythonBin) ? pythonBin : "/usr/bin/python3")
            process.arguments = [scriptPath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    self.load()
                    if process.terminationStatus == 0 {
                        completion(true, "주식 실적발표 및 부동산 청약 일정이 최신으로 동기화되었습니다!")
                    } else {
                        completion(false, "동기화 중 오류가 발생했습니다: \(output)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "수집기 실행 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 설정 파일(config.json)을 기본 텍스트 편집기로 열기
    func openConfigFile() {
        let configPath = "/Users/declan/Desktop/GengarileoAssistant/config.json"
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    /// 텔레그램 모바일 아침 브리핑 즉시 전송
    func sendTelegramBriefing(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = "/Users/declan/Desktop/GengarileoAssistant/scripts/telegram_briefing.py"
            let pythonBin = "/opt/homebrew/bin/python3"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: pythonBin) ? pythonBin : "/usr/bin/python3")
            process.arguments = [scriptPath]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    if output.contains("전송 성공") {
                        completion(true, "텔레그램으로 모바일 브리핑이 성공적으로 전송되었습니다! 📱")
                    } else if output.contains("토큰 또는 Chat ID가 설정되지 않아") {
                        completion(false, "텔레그램 봇 토큰과 Chat ID가 아직 설정되지 않았습니다.\nconfig.json 또는 GitHub Secrets에 등록해 주세요.")
                    } else {
                        completion(false, "전송 결과:\n\(output)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "텔레그램 스크립트 실행 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Auto-Sync Scheduler
    private func startAutoSyncScheduler() {
        periodicTimer?.invalidate()

        // 1. 앱 실행 4초 후 첫 1회 전체 자동 동기화 (웹 수집 -> 캘린더 반영)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self, self.autoSyncEnabled else { return }
            print("[*] Performing initial auto-sync on launch...")
            self.performFullAutoSync()
        }

        // 2. 6시간마다 주기적 백그라운드 자동 수집 및 동기화 (21600초)
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
            guard let self = self, self.autoSyncEnabled else { return }
            print("[*] Performing periodic 6-hour auto-sync...")
            self.performFullAutoSync()
        }
    }

    /// 웹 수집기 실행 -> 캘린더 동기화까지 원스톱 전자동 수행
    func performFullAutoSync(completion: ((Bool, String) -> Void)? = nil) {
        syncAutoCollector { [weak self] success, message in
            guard let self = self else { return }
            if success {
                CalendarSyncManager.shared.syncSchedulesToAppleCalendar(items: self.items) { calSuccess, calMessage in
                    completion?(calSuccess, calMessage)
                }
            } else {
                completion?(false, message)
            }
        }
    }

    /// 개인 일정 추가/삭제/완료 시 캘린더 자동 업데이트 (디바운스 1.5초)
    private func triggerDebouncedCalendarSync() {
        guard autoSyncEnabled else { return }
        calendarSyncDebounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            CalendarSyncManager.shared.syncSchedulesToAppleCalendar(items: self.items) { _, _ in }
        }
        calendarSyncDebounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    /// 수동 또는 주요 작업 전 백업 스냅샷 파일 자동 생성
    @discardableResult
    func createBackupSnapshot() -> URL? {
        guard !items.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupFile = backupDirectory.appendingPathComponent("backup_\(timestamp).json")

        do {
            let data = try makeEncoder().encode(items)
            try data.write(to: backupFile, options: .atomic)
            print("Backup created at: \(backupFile.path)")
            return backupFile
        } catch {
            print("Failed to create backup: \(error)")
            return nil
        }
    }

    /// Finder에서 데이터 및 백업 폴더 열기
    func openDataFolderInFinder() {
        NSWorkspace.shared.selectFile(saveURL.path, inFileViewerRootedAtPath: dataDirectory.path)
    }

    private func loadInitialSampleData() {
        let calendar = Calendar.current
        let today = Date()

        let samples: [ScheduleItem] = [
            ScheduleItem(
                title: "삼성전자 3Q 실적 발표",
                category: .stock,
                date: calendar.date(byAdding: .day, value: 1, to: today) ?? today,
                isCompleted: false,
                isDDay: true,
                memo: "잠정 실적 공시 확인 및 컨퍼런스콜 메모"
            ),
            ScheduleItem(
                title: "래미안 신축 청약 특별공급 접수",
                category: .realEstate,
                date: calendar.date(byAdding: .day, value: 3, to: today) ?? today,
                isCompleted: false,
                isDDay: true,
                memo: "청약홈 로그인 인증서 사전 점검"
            ),
            ScheduleItem(
                title: "엔비디아(NVDA) 실적 발표",
                category: .stock,
                date: calendar.date(byAdding: .day, value: 7, to: today) ?? today,
                isCompleted: false,
                isDDay: true,
                memo: "새벽 장 마감 후 컨퍼런스콜"
            ),
            ScheduleItem(
                title: "오늘 주간 프로젝트 기획서 검토",
                category: .personal,
                date: today,
                isCompleted: false,
                isDDay: false,
                memo: "팀 피드백 취합"
            ),
            ScheduleItem(
                title: "가계부 결산 및 통장 정리",
                category: .todo,
                date: today,
                isCompleted: true,
                isDDay: false,
                memo: "월 고정지출 내역 확인"
            )
        ]
        self.items = samples
    }
}
