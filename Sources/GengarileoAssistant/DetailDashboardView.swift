import SwiftUI

struct DetailDashboardView: View {
    @ObservedObject var store: ScheduleStore

    @State private var selectedCategory: ScheduleCategory = .all
    @State private var isAddingNew: Bool = false
    @State private var showingBackupAlert: Bool = false
    @State private var backupMessage: String = ""
    @State private var isSyncing: Bool = false

    // 입력 필드 상태
    @State private var quickInputText: String = ""
    @State private var newTitle: String = ""
    @State private var newCategory: ScheduleCategory = .personal
    @State private var newDate: Date = Date()
    @State private var newIsDDay: Bool = true
    @State private var newMemo: String = ""

    var filteredItems: [ScheduleItem] {
        let baseItems: [ScheduleItem]
        if selectedCategory == .all {
            baseItems = store.items
        } else {
            baseItems = store.items.filter { $0.category == selectedCategory }
        }
        return baseItems.sorted {
            if $0.isCompleted != $1.isCompleted {
                return !$0.isCompleted && $1.isCompleted
            }
            return $0.date < $1.date
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 상단 헤더
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Text("개인비서 Blanc")
                        .font(.system(size: 14, weight: .bold))

                    // 전역 단축키 힌트 배지
                    Text("⌥ Space")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }

                Spacer()

                // 전체 동기화 버튼 (웹 수집 -> 카테고리별 캘린더 등록)
                Button(action: {
                    isSyncing = true
                    store.performFullAutoSync { success, message in
                        isSyncing = false
                        backupMessage = message
                        showingBackupAlert = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(isSyncing ? "동기화 중..." : "전체 동기화")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAddingNew.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isAddingNew ? "minus" : "plus")
                        Text(isAddingNew ? "접기" : "새 일정")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // MARK: - 스마트 빠른 자연어 등록 바 (Fantastical 스타일)
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)

                    TextField("⚡ 스마트 등록: '내일 7시 저녁', '10/25 엔비디아 실적'...", text: $quickInputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .onSubmit {
                            submitQuickInput()
                        }

                    if !quickInputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: {
                            submitQuickInput()
                        }) {
                            Text("등록")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(7)

                // 실시간 자연어 파싱 미리보기 힌트
                if !quickInputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    let parsed = ScheduleStore.parseNaturalLanguage(input: quickInputText)
                    HStack(spacing: 6) {
                        Text("미리보기:")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)

                        Label(parsed.category.rawValue, systemImage: parsed.category.iconName)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(parsed.category.color.opacity(0.15))
                            .foregroundColor(parsed.category.color)
                            .cornerRadius(3)

                        Text("📅 \(formattedDateShort(parsed.date))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        if let t = parsed.timeString {
                            Text("⏰ \(t)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("⏎ Enter로 즉시 추가")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue.opacity(0.85))
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // MARK: - 빠른 환경설정 배너 (위젯, 부팅 자동실행, 아이폰 동기화, 아침 알림)
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Toggle(isOn: $store.isWidgetVisible) {
                        Text("바탕화면 위젯")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    if store.isWidgetVisible {
                        Toggle("항상 위", isOn: $store.widgetAlwaysOnTop)
                            .font(.system(size: 10))
                            .toggleStyle(.checkbox)
                    }

                    Spacer()

                    Toggle(isOn: $store.launchAtLogin) {
                        Text("부팅 시 자동실행")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                HStack(spacing: 12) {
                    Toggle(isOn: $store.autoSyncEnabled) {
                        HStack(spacing: 3) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.system(size: 10))
                            Text("아이폰 자동 동기화")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Spacer()

                    Toggle(isOn: $store.morningBriefingEnabled) {
                        HStack(spacing: 3) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 10))
                            Text("아침 9시 알림")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.025))

            Divider()

            // MARK: - 새 일정 등록 폼 (토글형)
            if isAddingNew {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("일정/Todo 입력 (예: 삼성전자 실적 발표, 청약 접수)", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    HStack(spacing: 10) {
                        Picker("분류", selection: $newCategory) {
                            ForEach(ScheduleCategory.allCases.filter { $0 != .all }) { cat in
                                Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 105)

                        DatePicker("", selection: $newDate, displayedComponents: [.date])
                            .labelsHidden()

                        Toggle("D-Day", isOn: $newIsDDay)
                            .font(.system(size: 11))
                            .toggleStyle(.checkbox)

                        Spacer()

                        Button("등록") {
                            addNewItem()
                        }
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    TextField("메모 (선택 사항)", text: $newMemo)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                .padding(12)
                .background(Color.primary.opacity(0.03))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.08)), alignment: .bottom)
            }

            // MARK: - 카테고리 필터 탭
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ScheduleCategory.allCases) { cat in
                        Button(action: {
                            selectedCategory = cat
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: cat.iconName)
                                    .font(.system(size: 10))
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: selectedCategory == cat ? .bold : .regular))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(selectedCategory == cat ? cat.color.opacity(0.2) : Color.primary.opacity(0.05))
                            .foregroundColor(selectedCategory == cat ? (cat == .all ? .primary : cat.color) : .secondary)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()

            // MARK: - 일정 리스트
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("등록된 일정이 없습니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("상단의 [+ 새 일정]을 눌러 첫 일정을 등록해 보세요!")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            ScheduleRowView(item: item, store: store)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            // MARK: - 하단 액션 툴바
            HStack(spacing: 6) {
                Button(action: {
                    store.openDataFolderInFinder()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                        Text("폴더")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: {
                    CalendarSyncManager.shared.syncSchedulesToAppleCalendar(items: store.items) { success, message in
                        backupMessage = message
                        showingBackupAlert = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "iphone")
                        Text("아이폰 동기화")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.indigo)

                Button(action: {
                    NotificationManager.shared.sendImmediateTestNotification(items: store.items) { success, message in
                        backupMessage = message
                        showingBackupAlert = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "bell")
                        Text("알림 테스트")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: {
                    store.openConfigFile()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "gearshape")
                        Text("관심설정")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Menu {
                    Button("아이폰 클라우드 구독 페이지 열기") {
                        let indexPath = "/Users/declan/Desktop/GengarileoAssistant/public/index.html"
                        NSWorkspace.shared.open(URL(fileURLWithPath: indexPath))
                    }
                    Button("📢 텔레그램 모바일 브리핑 지금 발송") {
                        store.sendTelegramBriefing { success, message in
                            backupMessage = message
                            showingBackupAlert = true
                        }
                    }
                    Divider()
                    Button("지금 파일로 백업") {
                        if let backup = store.createBackupSnapshot() {
                            backupMessage = "백업 완료:\n\(backup.lastPathComponent)"
                            showingBackupAlert = true
                        }
                    }
                    Button("샘플 데이터로 초기화") {
                        store.resetToSamples()
                    }
                    Button("전체 일정 비우기 (초기화)") {
                        store.clearAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)

                Spacer()

                Button("앱 종료") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 440, height: 560)
        .alert(isPresented: $showingBackupAlert) {
            Alert(
                title: Text("알림"),
                message: Text(backupMessage),
                dismissButton: .default(Text("확인"))
            )
        }
    }

    private func submitQuickInput() {
        let trimmed = quickInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addNaturalLanguageItem(input: trimmed)
        quickInputText = ""
    }

    private func formattedDateShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "M/d(E)"
        return df.string(from: date)
    }

    private func addNewItem() {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addItem(
            title: newTitle.trimmingCharacters(in: .whitespaces),
            category: newCategory,
            date: newDate,
            isDDay: newIsDDay,
            memo: newMemo.trimmingCharacters(in: .whitespaces)
        )
        newTitle = ""
        newMemo = ""
        isAddingNew = false
    }
}

// MARK: - Row View (디테일 정보 & 원클릭 브라우저 링크 지원)
struct ScheduleRowView: View {
    let item: ScheduleItem
    @ObservedObject var store: ScheduleStore
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 완료 토글 버튼
            Button(action: {
                withAnimation {
                    store.toggleCompleted(id: item.id)
                }
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // 본문 내용
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.isDDay && !item.isCompleted {
                        Text(item.dDayText)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(item.dDayBadgeColor.opacity(0.18))
                            .foregroundColor(item.dDayBadgeColor)
                            .cornerRadius(4)
                    }

                    Image(systemName: item.category.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(item.category.color)

                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .strikethrough(item.isCompleted)
                        .foregroundColor(item.isCompleted ? .secondary : .primary)
                        .lineLimit(2)

                    // 시간대 디테일 배지 (예: 장마감후, 1순위 등)
                    if let detail = item.timeDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.formattedDateText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if !item.memo.isEmpty {
                        Text("• " + item.memo)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openURLSafely(item.linkURL)
            }
            .help(item.category == .realEstate ? "클릭하여 \(item.portalButtonTitle) 공식 사이트 열기" : (item.linkURL != nil ? "클릭하여 상세 정보 웹페이지 열기" : ""))

            Spacer()

            HStack(spacing: 6) {
                // 원클릭 공고글 / 실적 / 웹 링크 버튼
                if let urlString = item.linkURL {
                    if item.category == .realEstate {
                        Button(action: {
                            openURLSafely(urlString)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 9))
                                Text(item.portalButtonTitle)
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("\(item.portalButtonTitle) 공식 공고 및 접수처 바로가기")
                    } else if item.category == .stock {
                        Button(action: {
                            openURLSafely(urlString)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 9))
                                Text("실적")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("실적 발표 및 기업 공시 상세 보기")
                    } else {
                        Button(action: {
                            openURLSafely(urlString)
                        }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundColor(.blue.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("웹에서 상세 정보 보기")
                    }
                }

                // 삭제 버튼
                Button(action: {
                    withAnimation {
                        store.deleteItem(id: item.id)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1.0 : 0.0)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(isHovered ? 0.05 : 0.02))
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if let urlString = item.linkURL {
                Button("🏛 \(item.portalButtonTitle) 공식 사이트 열기") {
                    openURLSafely(urlString)
                }
            }
            if let search = item.searchURL {
                Button("🔍 네이버 상세 분석 & 공고 요약글 보기") {
                    openURLSafely(search)
                }
            }
            Divider()
            Button(item.isCompleted ? "미완료로 변경" : "완료로 체크") {
                withAnimation {
                    store.toggleCompleted(id: item.id)
                }
            }
            Button("일정 삭제", role: .destructive) {
                withAnimation {
                    store.deleteItem(id: item.id)
                }
            }
        }
    }
}
