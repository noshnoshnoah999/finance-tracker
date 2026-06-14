// WageView.swift — Budget (iOS/Mac)
// Phase 2: log hours/days per month + see the pay breakdown. Edits write back to the
// shared blob via store.setMonth(...) (lossless JSON-tree mutation, debounced push).

import SwiftUI

struct WageView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var expanded: Set<String> = []

    var body: some View {
        let c = store.calc
        let earned = MONTHS.reduce(0.0) { $0 + c.taxable($1.key) }
        let remaining = c.annualLimit - earned
        let pct = c.annualLimit > 0 ? min(1, earned / c.annualLimit) : 0
        let monthsLeft = max(1, 12 - c.currentMonthNumber + 1)
        let perMonth = floor(remaining / Double(monthsLeft))

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("INCOME THIS YEAR").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                            Text(yen(earned)).font(.system(size: 32, weight: .bold)).foregroundStyle(T.text)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(yen(remaining)) left").font(.subheadline).fontWeight(.bold)
                                .foregroundStyle(remaining < 0 ? T.roseD : T.greenD)
                            Text("~\(yen(perMonth))/mo").font(.caption2).foregroundStyle(T.sub)
                        }
                    }
                    ProgressBar(fraction: pct, color: pct > 0.85 ? T.roseD : T.blueD)
                }
                .card()

                Text("Tap a month to log hours").font(.caption).foregroundStyle(T.sub).padding(.leading, 2)

                ForEach(MONTHS) { mo in monthCard(c, mo) }
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    // MARK: - One month
    @ViewBuilder private func monthCard(_ c: Calc, _ mo: MonthMeta) -> some View {
        let d = c.month(mo.key)
        let hasHours = d.d("hours") > 0
        let wage = c.wage(mo.key)
        let tr = c.transport(mo.key)
        let total = c.taxable(mo.key) + tr
        let isOpen = expanded.contains(mo.key)

        VStack(spacing: 0) {
            Button {
                if isOpen { expanded.remove(mo.key) } else { expanded.insert(mo.key) }
            } label: {
                HStack {
                    Circle().fill(wage > 0 || d.d("wageOverride") > 0 ? T.greenD : T.border).frame(width: 10, height: 10)
                    Text("\(mo.label) \(c.payday(mo.key))th").fontWeight(.semibold).foregroundStyle(T.text)
                    Spacer()
                    Text(total > 0 ? yen(total) : "—").fontWeight(.semibold)
                        .foregroundStyle(total > 0 ? T.text : T.muted)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(T.muted)
                }
                .padding(.vertical, 16).padding(.horizontal, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().overlay(T.border)

                    // Hours worked (previous month label, like the web)
                    fieldLabel("Hours worked in \(prevLabel(mo.key))")
                    HStack(spacing: 10) {
                        labeledField("Hours") {
                            TextField("0", value: hoursWhole(mo.key), format: .number)
                                .modifier(FieldStyle()).keyboardType(.numberPad)
                        }
                        labeledField("Minutes") {
                            TextField("0", value: minutes(mo.key), format: .number)
                                .modifier(FieldStyle()).keyboardType(.numberPad)
                        }
                    }
                    Text("= \(fmtHours(d.d("hours")))h × \(yen(c.hourlyWage)) = \(yen((d.d("hours") * c.hourlyWage).rounded()))")
                        .font(.caption).foregroundStyle(T.sub)

                    if !hasHours {
                        fieldLabel("Manual wage")
                        TextField("0", value: dbl(mo.key, "wageOverride"), format: .number)
                            .modifier(FieldStyle()).keyboardType(.numberPad)
                    }

                    fieldLabel("Days worked")
                    TextField("0", value: dbl(mo.key, "days"), format: .number)
                        .modifier(FieldStyle()).keyboardType(.numberPad)

                    // Breakdown
                    VStack(spacing: 8) {
                        breakdownRow("Wage", yen(wage), bold: false)
                        if c.paidLeaveYen(mo.key) > 0 {
                            breakdownRow("Paid leave", yen(c.paidLeaveYen(mo.key)), color: T.blueD)
                        }
                        breakdownRow("Transport (\(Int(d.d("days")))d)", yen(tr), bold: false)
                        Divider().overlay(T.border)
                        breakdownRow("Total pay", yen(total), bold: true)
                    }
                    .padding(14).background(T.cardAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Commute
                    breakdownRow("Commute (\(c.suicaDays(mo.key))d × \(yen(c.rt)))", yen(c.commute(mo.key)), bold: false)
                        .padding(14).background(T.cardAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Cumulative vs limit
                    if wage > 0 || d.d("wageOverride") > 0 {
                        cumulative(c, mo)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
        .background(T.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(T.border, lineWidth: 1))
    }

    @ViewBuilder private func cumulative(_ c: Calc, _ mo: MonthMeta) -> some View {
        let idx = MONTHS.firstIndex { $0.key == mo.key } ?? 0
        let cum = MONTHS.prefix(idx + 1).reduce(0.0) { $0 + c.taxable($1.key) }
        let onTrack = cum <= c.annualLimit / 12 * Double(idx + 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Earned so far").foregroundStyle(.white.opacity(0.85)); Spacer()
                Text("\(yen(cum)) / \(yen(c.annualLimit))").fontWeight(.bold).foregroundStyle(.white) }
            HStack { Text("Remaining").foregroundStyle(.white.opacity(0.85)); Spacer()
                Text(yen(c.annualLimit - cum)).fontWeight(.bold).foregroundStyle(.white) }
        }
        .font(.footnote)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(onTrack ? T.greenD : T.roseD)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Bindings (read/write the shared blob)
    private func dbl(_ mk: String, _ field: String) -> Binding<Double> {
        Binding(
            get: { store.blob.data[mk]?[field]?.double ?? 0 },
            set: { store.setMonth(mk, field, .number($0)) }
        )
    }
    private func hoursWhole(_ mk: String) -> Binding<Int> {
        Binding(
            get: { Int(store.blob.data[mk]?["hours"]?.double ?? 0) },
            set: { newH in
                let cur = store.blob.data[mk]?["hours"]?.double ?? 0
                let frac = cur - Double(Int(cur))
                store.setMonth(mk, "hours", .number(Double(newH) + frac))
            }
        )
    }
    private func minutes(_ mk: String) -> Binding<Int> {
        Binding(
            get: { let h = store.blob.data[mk]?["hours"]?.double ?? 0; return Int(((h - Double(Int(h))) * 60).rounded()) },
            set: { newM in
                let cur = store.blob.data[mk]?["hours"]?.double ?? 0
                let whole = Double(Int(cur))
                store.setMonth(mk, "hours", .number(whole + Double(newM) / 60))
            }
        )
    }

    // MARK: - Small bits
    private func prevLabel(_ mk: String) -> String {
        guard let i = MONTHS.firstIndex(where: { $0.key == mk }) else { return monthMeta(mk)?.label ?? "" }
        return i > 0 ? MONTHS[i - 1].label : "December"
    }
    private func fmtHours(_ h: Double) -> String {
        h == h.rounded() ? String(Int(h)) : String(format: "%.2f", h)
    }
    private func fieldLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub).tracking(0.5)
    }
    private func labeledField<V: View>(_ label: String, @ViewBuilder _ field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(T.muted)
            field()
        }
        .frame(maxWidth: .infinity)
    }
    private func breakdownRow(_ label: String, _ value: String, bold: Bool = false, color: Color = T.text) -> some View {
        HStack {
            Text(label).foregroundStyle(T.sub)
            Spacer()
            Text(value).fontWeight(bold ? .bold : .semibold).foregroundStyle(color)
        }
        .font(.footnote)
    }
}

/// Shared number-field look.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(T.cardAlt)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.border, lineWidth: 1))
            .foregroundStyle(T.text)
    }
}
