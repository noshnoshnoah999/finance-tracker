// BudgetWidgets.swift — Budget widget (Home + Lock Screen)
// Read-only glance: fetches the shared Supabase blob directly in the timeline provider
// (no App Group needed) and shows next paycheck + room left to earn.

import WidgetKit
import SwiftUI

private let SUPA = "https://ipjwpkqcuztahumijici.supabase.co"
private let ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlwandwa3FjdXp0YWh1bWlqaWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMTg0NjAsImV4cCI6MjA5MjU5NDQ2MH0.aCrIwHvNLkCtA_RXPdzIybRp2EMCrBeIVS5ABCtjl48"
private let UKEY = "f7e2a914-3b8c-4d5e-9a1f-6c2d7b0e8f3a"

struct BudgetEntry: TimelineEntry {
    let date: Date
    let payLabel: String
    let payTotal: Double
    let daysToPay: Int
    let payPD: Int
    let roomLeft: Double
    let freeToSpend: Double
    let placeholder: Bool
}

private func sampleEntry() -> BudgetEntry {
    BudgetEntry(date: Date(), payLabel: "June", payTotal: 93527, daysToPay: 1, payPD: 15,
                roomLeft: 541022, freeToSpend: 19883, placeholder: true)
}

private struct Row: Decodable { var data: FinanceBlob }

private func fetchBlob() async -> FinanceBlob? {
    guard let u = URL(string: "\(SUPA)/rest/v1/finance_data?user_key=eq.\(UKEY)&select=data") else { return nil }
    var req = URLRequest(url: u)
    req.setValue(ANON, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(ANON)", forHTTPHeaderField: "Authorization")
    guard let (data, _) = try? await URLSession.shared.data(for: req),
          let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
    return rows.first?.data
}

private func computeEntry() async -> BudgetEntry {
    guard let blob = await fetchBlob() else { return sampleEntry() }
    let c = Calc(se: blob.settings, data: blob.data)
    let cal = Calendar.current
    let now = Date()
    let curMK = currentMonthKeyClamped()
    let curPD = c.payday(curMK)
    let day = cal.component(.day, from: now)
    let miCur = MONTHS.firstIndex { $0.key == curMK } ?? 0
    let payMK = (day <= curPD) ? curMK : (miCur < MONTHS.count - 1 ? MONTHS[miCur + 1].key : curMK)
    let payPD = c.payday(payMK)
    let parts = payMK.split(separator: "-").compactMap { Int($0) }
    let payDate = cal.date(from: DateComponents(year: parts.first ?? 2026, month: parts.count > 1 ? parts[1] : 1, day: payPD)) ?? now
    let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: payDate)).day ?? 0)
    return BudgetEntry(date: now, payLabel: monthMeta(payMK)?.label ?? "", payTotal: c.monthlyPay(payMK),
                       daysToPay: days, payPD: payPD, roomLeft: c.roomLeft, freeToSpend: c.freeToSpend(curMK), placeholder: false)
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry { sampleEntry() }
    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        Task { completion(await computeEntry()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        Task {
            let e = await computeEntry()
            let next = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date().addingTimeInterval(10800)
            completion(Timeline(entries: [e], policy: .after(next)))
        }
    }
}

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: BudgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT PAY · \(entry.payLabel.uppercased())").font(.caption2).fontWeight(.semibold)
                Text(yen(entry.payTotal)).font(.headline).fontWeight(.bold)
                Text(entry.daysToPay == 0 ? "today" : "in \(entry.daysToPay)d · the \(entry.payPD)th").font(.caption2)
            }
        case .accessoryInline:
            Text("💰 \(yen(entry.payTotal)) · \(entry.daysToPay == 0 ? "today" : "\(entry.daysToPay)d")")
        default:
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT PAYCHECK · \(entry.payLabel.uppercased())").font(.caption2).fontWeight(.semibold).foregroundStyle(.white.opacity(0.8))
            Text(yen(entry.payTotal)).font(.system(size: 26, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            Text(entry.daysToPay == 0 ? "Payday today 🎉" : "in \(entry.daysToPay) day\(entry.daysToPay == 1 ? "" : "s") · the \(entry.payPD)th")
                .font(.caption2).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            HStack {
                stat("Room left", yen(entry.roomLeft))
                Spacer()
                stat("Free", yen(entry.freeToSpend))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(hex: "5a7330"), Color(hex: "455a25")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    private func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l.uppercased()).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
            Text(v).font(.caption).fontWeight(.bold).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
        }
    }
}

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgetWidget", provider: Provider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Paycheck")
        .description("Your next paycheck, room left to earn, and free to spend.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BudgetWidgetsBundle: WidgetBundle {
    var body: some Widget { BudgetWidget() }
}
