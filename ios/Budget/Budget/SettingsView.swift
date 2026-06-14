// SettingsView.swift — Budget (iOS/Mac)
// Phase 2: editable settings — wage/limit, transport, food, FX rate (+live), budget
// extras, work schedule, fixed expenses, and Subscribe & Save. Writes to the shared blob.
// (Web-push notifications + theme switching are web-only / Phase 3 for the native app.)

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var nfName = ""; @State private var nfAmount = ""; @State private var nfVariable = false
    @State private var nsName = ""; @State private var nsPrice = ""

    var body: some View {
        let c = store.calc
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                wageLimits()
                transport(c)
                food()
                exchange(c)
                budgetExtras()
                schedule(c)
                fixedExpenses(c)
                subItems(c)
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    // MARK: Wage & limits
    @ViewBuilder private func wageLimits() -> some View {
        card("Wage & Limits", T.greenD) {
            field("HOURLY WAGE", "¥", set("hourlyWage"))
            field("ANNUAL LIMIT", "¥", set("annualLimit"))
        }
    }
    @ViewBuilder private func transport(_ c: Calc) -> some View {
        card("Transport", T.blueD) {
            field("COMMUTE ONE-WAY", "¥", set("commuteOneWay"))
            HStack(spacing: 10) {
                fieldCol("BEFORE 14 MAR", "¥", set("trBefore"))
                fieldCol("AFTER 14 MAR", "¥", set("trAfter"))
            }
            Text("Round trip: \(yen(c.rt))").font(.caption).foregroundStyle(T.sub)
        }
    }
    @ViewBuilder private func food() -> some View {
        card("Food Budget", T.peachD) {
            HStack(spacing: 10) {
                fieldCol("4-WEEK", "¥", set("food4wk"))
                fieldCol("5-WEEK", "¥", set("food5wk"))
            }
            Text("5-week months: Mar, Jun, Aug, Nov").font(.caption2).foregroundStyle(T.muted)
        }
    }
    @ViewBuilder private func exchange(_ c: Calc) -> some View {
        card("Exchange Rate", T.greenD) {
            Text("GBP TO JPY").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
            HStack(spacing: 10) {
                HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("0", value: set("gbpToJpy"), format: .number).keyboardType(.decimalPad) }.modifier(FieldStyle())
                Button { Task { await store.fetchRate() } } label: {
                    Text(store.fxLoading ? "…" : "Live rate").fontWeight(.bold).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10).background(T.blueD).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(store.fxLoading)
            }
            Text("£1 = ¥\(c.gbpToJpy.clean) · tap Live rate to fetch today's rate").font(.caption2).foregroundStyle(T.sub)
        }
    }
    @ViewBuilder private func budgetExtras() -> some View {
        card("Budget extras", T.lavD) {
            Text("Built-in lines on the Fixed Expenses list. Turn off any you track elsewhere.").font(.caption2).foregroundStyle(T.sub)
            toggleRow("Skin Treatment", "showSkin")
            toggleRow("General Savings", "showGenSav")
        }
    }
    @ViewBuilder private func schedule(_ c: Calc) -> some View {
        card("Work Schedule", T.blueD) {
            Text("Your default shift times.").font(.caption2).foregroundStyle(T.sub)
            ForEach(["1", "2", "0"], id: \.self) { day in
                let sh = store.blob.settings["shifts"]?[day]
                VStack(alignment: .leading, spacing: 6) {
                    Text(sh?.s("label") ?? day).font(.footnote).fontWeight(.semibold)
                    HStack(spacing: 8) {
                        TextField("09:00", text: shiftText(day, "start")).modifier(FieldStyle())
                        Text("to").foregroundStyle(T.muted)
                        TextField("16:00", text: shiftText(day, "end")).modifier(FieldStyle())
                    }
                    HStack(spacing: 6) {
                        Text("Break").font(.caption2).foregroundStyle(T.sub)
                        TextField("0", value: shiftNum(day, "breakMin"), format: .number).keyboardType(.numberPad).modifier(FieldStyle()).frame(width: 80)
                        Text("min").font(.caption2).foregroundStyle(T.muted)
                        Spacer()
                        Text("\(c.shiftHours(sh).clean)h").fontWeight(.bold).foregroundStyle(T.blueD)
                    }
                }
                .padding(.vertical, 4).overlay(Divider().overlay(T.border), alignment: .bottom)
            }
        }
    }
    @ViewBuilder private func fixedExpenses(_ c: Calc) -> some View {
        card("Fixed Expenses", T.lavD) {
            ForEach(Array(c.fixed.enumerated()), id: \.offset) { _, f in
                let id = c.idStr(f["id"])
                HStack(spacing: 8) {
                    Text(f.s("name")).font(.footnote)
                    Spacer()
                    Text(f.b("variable") ? "varies" : yen(f.d("amount"))).font(.footnote).foregroundStyle(f.b("variable") ? T.sub : T.text)
                    Button { store.removeFixed(id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.roseD)
                }
                .padding(.vertical, 4).overlay(Divider().overlay(T.border), alignment: .bottom)
            }
            VStack(spacing: 8) {
                TextField("New expense name", text: $nfName).modifier(FieldStyle())
                HStack(spacing: 8) {
                    HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("Amount", text: $nfAmount).keyboardType(.numberPad) }.modifier(FieldStyle())
                    Toggle("Monthly", isOn: $nfVariable).labelsHidden()
                    Text("Varies").font(.caption2).foregroundStyle(T.sub)
                    Button {
                        if !nfName.isEmpty { store.addFixed(name: nfName, amount: Double(nfAmount) ?? 0, variable: nfVariable); nfName = ""; nfAmount = ""; nfVariable = false }
                    } label: { Image(systemName: "plus").fontWeight(.bold).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 10).background(T.lavD).clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }
    @ViewBuilder private func subItems(_ c: Calc) -> some View {
        card("Subscribe & Save", T.peachD) {
            if c.subItems.isEmpty { Text("No items yet.").font(.footnote).foregroundStyle(T.muted) }
            ForEach(Array(c.subItems.enumerated()), id: \.offset) { _, s in
                let id = c.idStr(s["id"])
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.s("name")).font(.footnote)
                        Text((s.i("everyN", 1) <= 1 ? "every month" : "every \(s.i("everyN", 1)) months")).font(.caption2).foregroundStyle(T.sub)
                    }
                    Spacer()
                    Text(yen(s.d("price"))).font(.footnote).fontWeight(.semibold)
                    Button { store.removeSubItem(id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.roseD)
                }
                .padding(.vertical, 4).overlay(Divider().overlay(T.border), alignment: .bottom)
            }
            HStack(spacing: 8) {
                TextField("Item name", text: $nsName).modifier(FieldStyle())
                HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("0", text: $nsPrice).keyboardType(.numberPad) }.modifier(FieldStyle()).frame(width: 100)
                Button {
                    if !nsName.isEmpty { store.addSubItem(name: nsName, price: Double(nsPrice) ?? 0, everyN: 1); nsName = ""; nsPrice = "" }
                } label: { Image(systemName: "plus").fontWeight(.bold).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 10).background(T.peachD).clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    // MARK: helpers
    @ViewBuilder private func card<V: View>(_ title: String, _ color: Color, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 18); Text(title).font(.headline) }
            content()
        }
        .card()
    }
    private func set(_ field: String) -> Binding<Double> {
        Binding(get: { store.blob.settings[field]?.double ?? 0 }, set: { store.setSetting(field, .number($0)) })
    }
    private func shiftText(_ day: String, _ field: String) -> Binding<String> {
        Binding(get: { store.blob.settings["shifts"]?[day]?[field]?.string ?? "" },
                set: { store.setShift(day, field, .string($0)) })
    }
    private func shiftNum(_ day: String, _ field: String) -> Binding<Double> {
        Binding(get: { store.blob.settings["shifts"]?[day]?[field]?.double ?? 0 },
                set: { store.setShift(day, field, .number($0)) })
    }
    private func field(_ label: String, _ prefix: String, _ binding: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
            HStack(spacing: 6) { Text(prefix).foregroundStyle(T.sub); TextField("0", value: binding, format: .number).keyboardType(.numberPad) }.modifier(FieldStyle())
        }
    }
    private func fieldCol(_ label: String, _ prefix: String, _ binding: Binding<Double>) -> some View {
        field(label, prefix, binding).frame(maxWidth: .infinity)
    }
    private func toggleRow(_ label: String, _ key: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.blob.settings[key]?.bool != false },
                set: { store.setSetting(key, .bool($0)) }
            )).labelsHidden().tint(T.greenD)
        }
    }
}

extension Double {
    /// Trim a trailing .0 (e.g. 214.0 -> "214", 214.5 -> "214.5").
    var clean: String { self == rounded() ? String(Int(self)) : String(self) }
}
