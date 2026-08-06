// SettingsView.swift — Budget (iOS/Mac)
// Phase 2: editable settings — wage/limit, transport, food, FX rate (+live), budget
// extras, work schedule, fixed expenses, and Subscribe & Save. Writes to the shared blob.
// (Web-push notifications + theme switching are web-only / Phase 3 for the native app.)

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: BudgetStore
    @EnvironmentObject var lock: BiometricLock
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var nfName = ""; @State private var nfAmount = ""; @State private var nfVariable = false
    // Send-to-Mum new-item form
    @State private var nmName = ""; @State private var nmAmount = ""
    @State private var nmStartMonth = 0; @State private var nmStartYear = ""
    @State private var nmEndMonth = 0; @State private var nmEndYear = ""
    @State private var nsName = ""; @State private var nsPrice = ""; @State private var nsEveryN = 1
    @State private var notifsOn = Notifs.isEnabled
    // Work Schedule: weekday chosen in the "add a day" picker (-1 = none chosen), and the
    // weekday awaiting removal confirmation.
    @State private var newShiftDow = -1
    @State private var pendingRemove: Int? = nil
    @AppStorage(Notifs.deniedKey) private var notifDenied = false

    var body: some View {
        let c = store.calc
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                privacyAlerts()
                wageLimits()
                transport(c)
                food()
                exchange(c)
                budgetExtras()
                schedule(c)
                fixedExpenses(c)
                sendToMumItems(c)
                subItems(c)
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .keyboardDoneBar()
        .onAppear { if notifsOn { Notifs.refreshAuthState() } }
    }

    // MARK: Privacy & alerts
    @ViewBuilder private func privacyAlerts() -> some View {
        card("Privacy & Alerts", T.accent) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications").font(.subheadline)
                    Text("Payday, SUICA & bill reminders on this device").font(.caption2).foregroundStyle(T.sub)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { notifsOn },
                    set: { on in notifsOn = on; if on { Notifs.enable(store) } else { Notifs.disable() } }
                )).labelsHidden().tint(T.greenD)
            }
            if notifsOn && notifDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off for Budget in iOS Settings — reminders won't be delivered.")
                        .font(.caption2).foregroundStyle(T.roseD)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Text("Open iOS Settings").font(.caption).fontWeight(.semibold).foregroundStyle(T.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.border))
                    }.buttonStyle(.plain)
                }
            }
            if notifsOn {
                Button { Notifs.sendTest() } label: {
                    Text("Send test notification").font(.caption).fontWeight(.semibold).foregroundStyle(T.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.border))
                }.buttonStyle(.plain)
            }
            Divider().overlay(T.border)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Lock (Face ID)").font(.subheadline)
                    Text("Require Face ID / passcode to open").font(.caption2).foregroundStyle(T.sub)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { lock.enabled }, set: { on in if on { lock.enableWithPrompt() } else { lock.setEnabled(false) } })).labelsHidden().tint(T.greenD)
            }
        }
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
            // "Before 14 Mar" rate is hidden here by request — no longer relevant day-to-day,
            // but se.trBefore / DS.trBefore stay in Models.swift and transportRate(_:) still
            // uses it for any month key <= 2026-03.
            field("CURRENT RATE", "¥", set("trAfter"))
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
            toggleRow("Silver Investment", "showSilver")
            if store.blob.settings["showGenSav"]?.bool != false {
                field("General savings — monthly amount", "¥", set("genSavAmount"))
            }
        }
    }
    @ViewBuilder private func schedule(_ c: Calc) -> some View {
        card("Work Schedule", T.blueD) {
            Text("Your default shift times. The days listed here are the days the calendar counts as work days.")
                .font(.caption2).foregroundStyle(T.sub)
            let setDays = DOW_ORDER.filter { store.blob.settings["shifts"]?[String($0)] != nil }
            ForEach(setDays, id: \.self) { dow in
                let day = String(dow)
                let sh = store.blob.settings["shifts"]?[day]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(sh?.s("label") ?? DOW_LABELS[dow]).font(.footnote).fontWeight(.semibold)
                        Spacer()
                        Button(role: .destructive) { pendingRemove = dow } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(T.roseD)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(DOW_FULL[dow]) shift")
                    }
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
            if setDays.isEmpty {
                Text("No shifts set — add a day below.").font(.footnote).foregroundStyle(T.muted)
            }
            let freeDays = DOW_ORDER.filter { store.blob.settings["shifts"]?[String($0)] == nil }
            if !freeDays.isEmpty {
                HStack(spacing: 8) {
                    Picker("Add a day", selection: $newShiftDow) {
                        Text("Add a day…").tag(-1)
                        ForEach(freeDays, id: \.self) { Text(DOW_FULL[$0]).tag($0) }
                    }
                    .pickerStyle(.menu).tint(T.blueD)
                    Spacer()
                    Button("+ Add shift") {
                        guard newShiftDow >= 0 else { return }
                        store.addShift(newShiftDow)
                        newShiftDow = -1
                    }
                    .buttonStyle(.borderedProminent).tint(T.blueD)
                    .disabled(newShiftDow < 0)
                }
                .padding(.top, 6)
            }
            HStack {
                Text("Weekly total").fontWeight(.semibold)
                Spacer()
                Text("\(setDays.reduce(0.0) { $0 + c.shiftHours(store.blob.settings["shifts"]?[String($1)]) }.clean)h")
                    .fontWeight(.bold).foregroundStyle(T.blueD)
            }
            .padding(.top, 8)
            Divider().overlay(T.border)
            VStack(alignment: .leading, spacing: 6) {
                Text("Default break for new shifts").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                HStack(spacing: 6) {
                    TextField("60", value: defaultBreakBinding, format: .number)
                        .keyboardType(.numberPad).modifier(FieldStyle())
                    Text("min").font(.caption2).foregroundStyle(T.muted)
                    ForEach([30, 60], id: \.self) { m in
                        Button("\(m)") { store.setSetting("defaultBreak", .number(Double(m))) }
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Int(c.defaultBreak) == m ? T.blueD : T.cardAlt)
                            .foregroundStyle(Int(c.defaultBreak) == m ? Color.white : T.sub)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                Text("Applied to any new shift day you add above, and to new rows in the Limit page's shift planner. Your existing shifts keep the break they already have — edit those individually.")
                    .font(.caption2).foregroundStyle(T.sub)
            }
            .padding(.top, 4)
        }
        .alert("Remove the \(pendingRemove.map { DOW_FULL[$0] } ?? "") shift?",
               isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })) {
            Button("Cancel", role: .cancel) { pendingRemove = nil }
            Button("Remove", role: .destructive) {
                if let d = pendingRemove { store.removeShift(d) }
                pendingRemove = nil
            }
        } message: {
            let nm = pendingRemove.map { DOW_FULL[$0] } ?? ""
            Text("Past \(nm)s up to today stay counted as work days, so your logged hours and transport for previous months don't change. Future \(nm)s stop counting as work days.")
        }
    }
    @ViewBuilder private func fixedExpenses(_ c: Calc) -> some View {
        card("Fixed Expenses", T.lavD) {
            let cmk = String(format: "%04d-%02d", Calendar.current.component(.year, from: Date()), Calendar.current.component(.month, from: Date()))
            ForEach(Array(c.fixed.enumerated()), id: \.offset) { _, f in
                let id = c.idStr(f["id"])
                HStack(spacing: 8) {
                    Text(f.s("name")).font(.footnote)
                    if f.b("paidyDerived") { Text("from Paidy").font(.caption2).foregroundStyle(T.sub) }
                    Spacer()
                    Text(f.b("paidyDerived") ? yen(c.paidyMonthly(cmk)) : (f.b("variable") ? "varies" : yen(f.d("amount"))))
                        .font(.footnote).foregroundStyle(f.b("variable") || f.b("paidyDerived") ? T.sub : T.text)
                    if f.b("paidyDerived") {
                        Button { if hSize == .regular { store.selectedTab = 4 } else { store.openPaidy = true } } label: { Image(systemName: "chevron.right").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.muted)
                    } else {
                        Button { store.removeFixed(id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.roseD)
                    }
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
    // MARK: Send to Mum (reminders with an optional month window; blank end = ongoing)
    @ViewBuilder private func sendToMumItems(_ c: Calc) -> some View {
        card("Send to Mum", T.roseD) {
            Text("Reminders for money you send Mum. Each item shows only within its month window. Leave the end blank for an ongoing item. These are reminders and don’t change your budget totals.")
                .font(.caption2).foregroundStyle(T.sub).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            ForEach(Array(c.se.arr("mumItems").enumerated()), id: \.offset) { _, m in
                let id = c.idStr(m["id"])
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(m.s("name")).font(.footnote)
                        Spacer()
                        Text(yen(m.d("amount"))).font(.footnote).foregroundStyle(T.text)
                        Button { store.removeMumItem(id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.roseD)
                    }
                    Text(mumWindowLabel(m)).font(.caption2).foregroundStyle(T.sub)
                }
                .padding(.vertical, 4).overlay(Divider().overlay(T.border), alignment: .bottom)
            }
            VStack(spacing: 8) {
                TextField("Name", text: $nmName).modifier(FieldStyle())
                HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("Amount", text: $nmAmount).keyboardType(.numberPad) }.modifier(FieldStyle())
                HStack(spacing: 8) {
                    Text("Start").font(.caption2).foregroundStyle(T.sub).frame(width: 34, alignment: .leading)
                    Picker("", selection: $nmStartMonth) { Text("Month").tag(0); ForEach(1...12, id: \.self) { Text(MO_SHORT[$0 - 1]).tag($0) } }.pickerStyle(.menu).tint(T.text)
                    TextField("Year", text: $nmStartYear).keyboardType(.numberPad).modifier(FieldStyle()).frame(width: 70)
                }
                HStack(spacing: 8) {
                    Text("End").font(.caption2).foregroundStyle(T.sub).frame(width: 34, alignment: .leading)
                    Picker("", selection: $nmEndMonth) { Text("Ongoing").tag(0); ForEach(1...12, id: \.self) { Text(MO_SHORT[$0 - 1]).tag($0) } }.pickerStyle(.menu).tint(T.text)
                    TextField("Year", text: $nmEndYear).keyboardType(.numberPad).modifier(FieldStyle()).frame(width: 70)
                }
                Button {
                    guard !nmName.isEmpty else { return }
                    store.addMumItem(
                        name: nmName, amount: Double(nmAmount) ?? 0,
                        startMonth: nmStartMonth == 0 ? nil : nmStartMonth, startYear: Int(nmStartYear),
                        endMonth: nmEndMonth == 0 ? nil : nmEndMonth, endYear: Int(nmEndYear))
                    nmName = ""; nmAmount = ""; nmStartMonth = 0; nmStartYear = ""; nmEndMonth = 0; nmEndYear = ""
                } label: {
                    Text("+ Add Mum item").fontWeight(.semibold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(T.roseD).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }
    private func mumWindowLabel(_ m: JSONValue) -> String {
        guard let sM = m["startMonth"]?.int, let sY = m["startYear"]?.int else { return "always" }
        let start = "\(MO_SHORT[max(0, min(11, sM - 1))]) \(sY)"
        if let eM = m["endMonth"]?.int, let eY = m["endYear"]?.int {
            return "\(start) → \(MO_SHORT[max(0, min(11, eM - 1))]) \(eY)"
        }
        return "\(start) → ongoing"
    }

    private static let subFreqs = [1, 2, 3, 4, 6]
    private func freqLabel(_ n: Int) -> String { n <= 1 ? "every month" : "every \(n) months" }

    @ViewBuilder private func subItems(_ c: Calc) -> some View {
        card("Subscribe & Save", T.peachD) {
            if c.subItems.isEmpty { Text("No items yet.").font(.footnote).foregroundStyle(T.muted) }
            ForEach(Array(c.subItems.enumerated()), id: \.offset) { _, s in
                let id = c.idStr(s["id"])
                let ev = s.i("everyN", 1)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.s("name")).font(.footnote)
                        // Tap the cadence to change delivery frequency (#4 — was web-only).
                        Menu {
                            ForEach(Self.subFreqs, id: \.self) { n in
                                Button(freqLabel(n)) { store.updateSubItem(id, everyN: n) }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(freqLabel(ev))
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                            }.font(.caption2).foregroundStyle(T.blueD)
                        }
                    }
                    Spacer()
                    Text(yen(s.d("price"))).font(.footnote).fontWeight(.semibold)
                    Button { store.removeSubItem(id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.roseD)
                }
                .padding(.vertical, 4).overlay(Divider().overlay(T.border), alignment: .bottom)
            }
            HStack(spacing: 8) {
                TextField("Item name", text: $nsName).modifier(FieldStyle())
                HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("0", text: $nsPrice).keyboardType(.numberPad) }.modifier(FieldStyle()).frame(width: 80)
                Menu {
                    ForEach(Self.subFreqs, id: \.self) { n in Button(freqLabel(n)) { nsEveryN = n } }
                } label: {
                    HStack(spacing: 3) {
                        Text(nsEveryN <= 1 ? "1mo" : "\(nsEveryN)mo")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }.font(.caption2).foregroundStyle(T.sub)
                     .padding(.horizontal, 8).padding(.vertical, 11)
                     .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                Button {
                    if !nsName.isEmpty { store.addSubItem(name: nsName, price: Double(nsPrice) ?? 0, everyN: nsEveryN); nsName = ""; nsPrice = ""; nsEveryN = 1 }
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
    /// Default break for new shifts. Clamped on write so a typo can't produce NaN hours.
    private var defaultBreakBinding: Binding<Double> {
        Binding(get: { store.blob.settings["defaultBreak"]?.double ?? DS.defaultBreak },
                set: { store.setSetting("defaultBreak", .number($0.isFinite ? min(480, max(0, $0)) : DS.defaultBreak)) })
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
