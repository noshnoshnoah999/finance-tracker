// SavingsView.swift — Budget (iOS/Mac)
// Phase 2: cash savings per month + silver/investment tracking (USD). Editable; writes
// to the shared blob.

import SwiftUI

struct SavingsView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var view = "cash"   // "cash" | "silver"

    var body: some View {
        let c = store.calc
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                toggle()
                if view == "cash" { cashSection(c) } else { silverSection(c) }
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    // MARK: Toggle
    @ViewBuilder private func toggle() -> some View {
        HStack(spacing: 6) {
            seg("💴 Cash", "cash", T.blueD)
            seg("🪙 Silver", "silver", T.peachD)
        }
        .padding(4).background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private func seg(_ label: String, _ key: String, _ color: Color) -> some View {
        Button { view = key } label: {
            Text(label).font(.subheadline).fontWeight(view == key ? .bold : .semibold)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(view == key ? color : .clear)
                .foregroundStyle(view == key ? .white : T.sub)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Cash
    @ViewBuilder private func cashSection(_ c: Calc) -> some View {
        let total = MONTHS.reduce(0.0) { $0 + c.month($1.key).d("savings") + c.genSav($1.key) }
        let cMN = max(1, c.currentMonthNumber)
        let avg = total / Double(cMN)
        let goal = store.blob.settings["savingsGoal"]?.double ?? 0

        // Hero
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL SAVED IN 2026").font(.caption2).fontWeight(.semibold).foregroundStyle(.white.opacity(0.7))
            Text(yen(total)).font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
            if goal > 0 {
                HStack {
                    Text("Goal: \(yen(goal))").font(.caption).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("\(Int(min(100, total / goal * 100)))%").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                ProgressBar(fraction: min(1, total / goal), color: .white.opacity(0.9))
                Text(total >= goal ? "Goal reached!" : "\(yen(goal - total)) to go").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            Text("avg \(yen(avg))/month").font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(T.blueD).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        // Stats
        if total > 0 {
            HStack(spacing: 10) {
                statTile("Avg / Month", yen(avg))
                statTile("Projected Year", yen(avg * 12))
            }
        }

        // Monthly entries
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Monthly Savings", T.blueD)
            ForEach(MONTHS) { mo in
                let s = c.month(mo.key).d("savings")
                let gs = c.genSav(mo.key)
                let t = s + gs
                let isFut = mo.key > (MONTHS[safe: cMN - 1]?.key ?? "")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(mo.label).font(.footnote).fontWeight(.semibold).foregroundStyle(t > 0 ? T.text : T.muted)
                        Spacer()
                        if t > 0 { Text(yen(t)).font(.footnote).fontWeight(.bold).foregroundStyle(T.blueD) }
                    }
                    yenField(mo.key, "savings", placeholder: isFut ? "Future…" : "Enter amount…")
                    if gs > 0 { Text("+ \(yen(gs)) general savings (from budget)").font(.caption2).foregroundStyle(T.sub) }
                }
                .opacity(isFut ? 0.55 : 1)
            }
            Divider().overlay(T.border)
            HStack { Text("Total saved").fontWeight(.bold); Spacer(); Text(yen(total)).fontWeight(.bold).foregroundStyle(T.blueD) }
                .font(.subheadline)
        }
        .card()

        // Goal
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Savings Goal", T.greenD)
            Text("TARGET AMOUNT").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
            settingYenField("savingsGoal", placeholder: "e.g. 500000")
            if goal > 0 {
                if total >= goal {
                    Text("Goal reached!").fontWeight(.bold).foregroundStyle(T.greenD).frame(maxWidth: .infinity)
                } else {
                    row("Still needed", yen(goal - total), color: T.blueD)
                    if avg > 0 { row("At current rate", "\(Int(ceil((goal - total) / avg))) more months") }
                }
            }
        }
        .card()
    }

    // MARK: Silver
    @ViewBuilder private func silverSection(_ c: Calc) -> some View {
        let oz = MONTHS.reduce(0.0) { $0 + c.month($1.key).d("silverOz") }
        let usdIn = MONTHS.reduce(0.0) { $0 + c.silverUsd($1.key) }
        let avgCost = oz > 0 ? usdIn / oz : 0
        let spot = store.blob.settings["silverSpot"]?.double ?? 0
        let rate = store.blob.settings["usdToJpy"]?.double ?? DS.usdToJpy
        let value = spot > 0 ? oz * spot : 0
        let gain = value > 0 ? value - usdIn : 0
        let gainPct = value > 0 && usdIn > 0 ? gain / usdIn * 100 : 0
        let cMN = max(1, c.currentMonthNumber)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("Silver · Investments", T.peachD)
                Spacer(); Text("🪙").font(.title3)
            }
            HStack(spacing: 10) {
                VStack(spacing: 5) {
                    Text("STACK").font(.caption2).foregroundStyle(T.sub)
                    Text(String(format: "%.2f", oz) + " oz").font(.title3).fontWeight(.bold).foregroundStyle(T.peachD)
                }.frame(maxWidth: .infinity).padding(14).background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(spacing: 5) {
                    Text("INVESTED").font(.caption2).foregroundStyle(T.sub)
                    Text(usd(usdIn)).font(.title3).fontWeight(.bold).foregroundStyle(T.peachD)
                    Text("≈ \(yen(usdIn * rate))").font(.caption2).foregroundStyle(T.muted)
                }.frame(maxWidth: .infinity).padding(14).background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if spot > 0 {
                VStack(spacing: 6) {
                    HStack { Text("Current value").font(.caption).foregroundStyle(T.sub); Spacer()
                        Text(usd(value)).font(.title3).fontWeight(.bold).foregroundStyle(gain >= 0 ? T.greenD : T.roseD) }
                    HStack { Text("≈ \(yen(value * rate)) · @ $\(String(format: "%.2f", spot))/oz").font(.caption2).foregroundStyle(T.muted); Spacer()
                        Text("\(gain >= 0 ? "▲" : "▼") \(usd(abs(gain))) (\(gain >= 0 ? "+" : "")\(String(format: "%.1f", gainPct))%)")
                            .font(.footnote).fontWeight(.bold).foregroundStyle(gain >= 0 ? T.greenD : T.roseD) }
                }
                .padding(14).background(gain >= 0 ? T.greenBg : T.roseBg).clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Per-month entries
            ForEach(MONTHS) { mo in
                let mOz = c.month(mo.key).d("silverOz"), mUsd = c.silverUsd(mo.key)
                let fromBudget = c.silverInvest(mo.key) > 0
                let isFut = mo.key > (MONTHS[safe: cMN - 1]?.key ?? "")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(mo.label).font(.footnote).fontWeight(.semibold).foregroundStyle(mUsd > 0 ? T.text : T.muted)
                        Spacer()
                        if mUsd > 0 { Text("\(String(format: "%.2f", mOz)) oz · \(usd(mUsd))").font(.caption2).fontWeight(.semibold).foregroundStyle(T.peachD) }
                    }
                    HStack(spacing: 8) {
                        labeledDoubleField(mo.key, "silverOz", placeholder: isFut ? "—" : "Ounces…")
                        if fromBudget {
                            HStack(spacing: 4) { Text("$").foregroundStyle(T.sub).font(.caption); Text("\(Int(mUsd))"); Spacer(); Text("from budget").font(.caption2).foregroundStyle(T.muted) }
                                .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 10).background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            labeledDoubleField(mo.key, "silverUsd", placeholder: isFut ? "—" : "Spent…")
                        }
                    }
                }
                .opacity(isFut ? 0.55 : 1)
            }

            if oz > 0 {
                Divider().overlay(T.border)
                HStack { Text("Avg cost").fontWeight(.bold); Spacer(); Text("$\(String(format: "%.2f", avgCost))/oz").fontWeight(.bold).foregroundStyle(T.peachD) }
                    .font(.subheadline)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SILVER SPOT (USD/OZ)").font(.caption2).foregroundStyle(T.sub)
                    settingDoubleField("silverSpot", placeholder: "e.g. 31.50")
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("USD → JPY RATE").font(.caption2).foregroundStyle(T.sub)
                    settingDoubleField("usdToJpy", placeholder: "e.g. 155")
                }.frame(maxWidth: .infinity)
            }
            Text("Set the spot price to see your stack's live value & gain.").font(.caption2).foregroundStyle(T.muted)
        }
        .card()
    }

    // MARK: Fields & bits
    private func yenField(_ mk: String, _ field: String, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text("¥").foregroundStyle(T.sub)
            TextField(placeholder, value: monthBinding(mk, field), format: .number).keyboardType(.numberPad)
        }
        .modifier(FieldStyle())
    }
    private func labeledDoubleField(_ mk: String, _ field: String, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text(field == "silverOz" ? "oz" : "$").foregroundStyle(T.sub).font(.caption)
            TextField(placeholder, value: monthBinding(mk, field), format: .number).keyboardType(.decimalPad)
        }
        .modifier(FieldStyle())
    }
    private func settingYenField(_ field: String, placeholder: String) -> some View {
        HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField(placeholder, value: settingBinding(field), format: .number).keyboardType(.numberPad) }
            .modifier(FieldStyle())
    }
    private func settingDoubleField(_ field: String, placeholder: String) -> some View {
        TextField(placeholder, value: settingBinding(field), format: .number).keyboardType(.decimalPad).modifier(FieldStyle())
    }
    private func monthBinding(_ mk: String, _ field: String) -> Binding<Double> {
        Binding(get: { store.blob.data[mk]?[field]?.double ?? 0 },
                set: { store.setMonth(mk, field, .number($0)) })
    }
    private func settingBinding(_ field: String) -> Binding<Double> {
        Binding(get: { store.blob.settings[field]?.double ?? 0 },
                set: { store.setSetting(field, .number($0)) })
    }
    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(T.sub)
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(T.blueD)
        }.frame(maxWidth: .infinity).card(padding: 16)
    }
    private func sectionHeader(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 18); Text(title).font(.headline).foregroundStyle(T.text) }
    }
    private func row(_ label: String, _ value: String, color: Color = T.text) -> some View {
        HStack { Text(label).foregroundStyle(T.sub); Spacer(); Text(value).fontWeight(.semibold).foregroundStyle(color) }.font(.footnote)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
