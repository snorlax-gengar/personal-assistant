import SwiftUI

struct FloatingWidgetView: View {
    @ObservedObject var store: ScheduleStore
    @State private var isCollapsed: Bool = false

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - 위젯 헤더 (드래그 핸들 역할)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                        .font(.system(size: 13, weight: .bold))
                    Text("개인비서 Blanc 위젯")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                // 접기/펼치기 버튼
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // 위젯 닫기 버튼
                Button(action: {
                    store.isWidgetVisible = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text(todayString)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if !isCollapsed {
                Divider()

                // MARK: - 1. D-Day 하이라이트 (주식 / 부동산 / 주요 일정)
                let urgentItems = Array(store.upcomingDDayItems.prefix(3))
                if !urgentItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("주요 D-Day")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        ForEach(urgentItems) { item in
                            HStack(spacing: 6) {
                                Text(item.dDayText)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(item.dDayBadgeColor.opacity(0.2))
                                    .foregroundColor(item.dDayBadgeColor)
                                    .cornerRadius(4)

                                Image(systemName: item.category.iconName)
                                    .font(.system(size: 10))
                                    .foregroundColor(item.category.color)

                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openURLSafely(item.linkURL)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }

                // MARK: - 2. 오늘의 할 일 & 스케줄
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("오늘의 할 일")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        let completed = store.todayItems.filter { $0.isCompleted }.count
                        Text("\(completed)/\(store.todayItems.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if store.todayItems.isEmpty {
                        Text("오늘 예정된 일정이 없습니다.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(store.todayItems.prefix(4)) { item in
                            HStack(spacing: 6) {
                                Button(action: {
                                    withAnimation {
                                        store.toggleCompleted(id: item.id)
                                    }
                                }) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundColor(item.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(item.title)
                                    .font(.system(size: 11))
                                    .strikethrough(item.isCompleted)
                                    .foregroundColor(item.isCompleted ? .secondary : .primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 250)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}
