import SwiftUI

struct BriefingTooltipView: View {
    @ObservedObject var store: ScheduleStore

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gengarileo 데일리 브리핑")
                        .font(.system(size: 13, weight: .bold))
                    Text(todayString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // 1. 임박한 D-Day 섹션 (부동산, 주식, 주요 일정)
            let upcomingDDay = store.upcomingDDayItems.prefix(3)
            if !upcomingDDay.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("주요 D-Day 알림")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    ForEach(Array(upcomingDDay)) { item in
                        HStack(spacing: 8) {
                            // D-Day 배지
                            Text(item.dDayText)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.dDayBadgeColor.opacity(0.15))
                                .foregroundColor(item.dDayBadgeColor)
                                .cornerRadius(4)

                            // 카테고리 아이콘
                            Image(systemName: item.category.iconName)
                                .font(.system(size: 11))
                                .foregroundColor(item.category.color)

                            // 제목
                            Text(item.title)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            // 2. 오늘의 일정 및 할 일 요약
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(.blue)
                        .font(.system(size: 11))
                    Text("오늘의 일정 & 할 일")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    let completed = store.todayItems.filter { $0.isCompleted }.count
                    Text("\(completed)/\(store.todayItems.count) 완료")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                if store.todayItems.isEmpty {
                    Text("오늘 예정된 일정이 없습니다. 편안한 하루 보내세요!")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.todayItems.prefix(4)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundColor(item.isCompleted ? .secondary : item.category.color)

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

            Divider()

            // 하단 안내
            HStack {
                Spacer()
                Text("💡 클릭하면 상세 일정 관리창이 열립니다")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}
