// BudgetTabView.swift — Budget (iOS/Mac)
// Phase 2: the month budget — calendar (tap days), income, fixed expenses with
// paid/skip toggles, one-offs, Send to Mum, and Free to Spend. Edits write to the
// shared blob. (Shift-time editing, SUICA date-range calc, Dad-contribution editing
// and Subscribe&Save item management are still done on the web for now.)

import SwiftUI

struct BudgetTabView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var bm: String = currentMonthKeyClamped()
    @State private var ooName = ""
    @State private var ooAmount = ""

    var body: some View {
        let c = store.calc
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                monthChips()
                calendarCard(c)
                incomeCard(c)
                fixedCard(c)
                oneOffCard(c)
                mumCard(c)
                freeCard(c)
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    // MARK: Month chips
    @ViewBuilder private func monthChips() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MONTHS) { mo in
                    Button { bm = mo.key } label: {
                        Text(mo.short).font(.caption).fontWeight(bm == mo.key ? .semibold : .regular)
                            .padding(.vertical, 7).padding(.horizontal, 14)
                            .background(bm == mo.key ? T.accent : T.card)
                            .foregroundStyle(bm == mo.key ? .white : T.sub)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Calendar
    @ViewBuilder private func calendarCard(_ c: Calc) -> some View {
        let comps = bm.split(separator: "-")
        let y = Int(comps[0]) ?? 2026, mo = Int(comps[1]) ?? 1
        let dim = c.daysIn(bm)
        let fw = c.firstWeekday(bm)               // 0=Sun
        let lead = fw == 0 ? 6 : fw - 1           // Monday-first grid
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Work Schedule", color: T.blueD)
            Text("Tap a day to change it").font(.caption2).foregroundStyle(T.muted)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(T.sub)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...dim, id: \.self) { d in
                    dayCell(c, y, mo, d)
                }
            }
            legend()
            HStack {
                Text("Work days this month").font(.footnote).foregroundStyle(T.sub)
                Spacer()
                Text("\(c.workDaysInMonth(bm)) days").font(.footnote).fontWeight(.semibold)
            }
            HStack {
                Text("SUICA needed").font(.subheadline).fontWeight(.bold)
                Spacer()
                Text(yen(Double(c.workDaysInMonth(bm)) * c.rt)).font(.subheadline).fontWeight(.bold).foregroundStyle(T.blueD)
            }
            .padding(.top, 4)
        }
        .card()
    }

    @ViewBuilder private func dayCell(_ c: Calc, _ y: Int, _ mo: Int, _ d: Int) -> some View {
        let ds = String(format: "%04d-%02d-%02d", y, mo, d)
        let cd = store.blob.data[bm]?["customDays"] ?? .object([:])
        let state = c.dayState(ds, y, mo, d, cd)
        let bg: Color = state == "work" ? T.greenD : state == "pl" ? T.blueD : state == "hol" ? T.peachD : state == "off" ? T.cardAlt : .clear
        let fg: Color = (state == "work" || state == "pl" || state == "hol") ? .white : T.muted
        let tag = state == "pl" ? "PL" : state == "hol" ? "HOL" : state == "off" ? "OFF" : nil
        Button { store.toggleDay(bm, ds, y, mo, d) } label: {
            VStack(spacing: 1) {
                Text("\(d)").font(.caption).fontWeight(state == "none" ? .regular : .bold)
                if let tag { Text(tag).font(.system(size: 7)).opacity(0.85) }
            }
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(bg).foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func legend() -> some View {
        HStack(spacing: 12) {
            ForEach([("Work", T.greenD), ("Paid leave", T.blueD), ("Holiday", T.peachD), ("Off", T.cardAlt)], id: \.0) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(item.1).frame(width: 10, height: 10)
                    Text(item.0).font(.caption2).foregroundStyle(T.sub)
                }
            }
        }
    }

    // MARK: Income
    @ViewBuilder private func incomeCard(_ c: Calc) -> some View {
        let wage = c.wage(bm), tr = c.transport(bm), pl = c.paidLeaveYen(bm), dad = c.dadFree(bm)
        let total = c.monthlyPay(bm) + dad
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Income", color: T.greenD)
            row("Wage", yen(wage))
            if pl > 0 { row("Paid leave", yen(pl), color: T.blueD) }
            row("Transport received", yen(tr))
            if dad > 0 { row("Dad (free spend)", yen(dad), color: T.greenD) }
            Divider().overlay(T.border)
            row("Total", yen(total), bold: true, color: T.greenD)
        }
        .card()
    }

    // MARK: Fixed expenses
    @ViewBuilder private func fixedCard(_ c: Calc) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Fixed Expenses", color: T.lavD)
            ForEach(Array(c.fixed.enumerated()), id: \.offset) { _, f in
                fixedRow(c, f)
            }
            builtinRow(c, id: "suica", label: "SUICA (\(c.suicaDays(bm)) days)", amount: c.commute(bm))
            builtinRow(c, id: "food", label: "Food (\(monthMeta(bm)?.is5wk == true ? "5-wk" : "4-wk"))", amount: c.food(bm))
            if c.showSkin && c.skin(bm) > 0 { builtinRow(c, id: "skinTreatment", label: "Skin treatment", amount: c.skin(bm)) }
            if c.showGenSav && c.genSav(bm) > 0 { builtinRow(c, id: "generalSavings", label: "General savings", amount: c.genSav(bm)) }
            Divider().overlay(T.border)
            row("Total fixed", yen(totalFixed(c)), bold: true, color: T.lavD)
            let left = c.leftToPay(bm)
            HStack {
                Text("Left to pay").font(.footnote).fontWeight(.semibold).foregroundStyle(left == 0 ? .white : T.lavD)
                Spacer()
                Text(left == 0 ? "All paid ✓" : yen(left)).fontWeight(.bold).foregroundStyle(left == 0 ? .white : T.lavD)
            }
            .padding(14).frame(maxWidth: .infinity)
            .background(left == 0 ? T.greenD : T.lavBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .card()
    }

    @ViewBuilder private func fixedRow(_ c: Calc, _ f: JSONValue) -> some View {
        let id = c.idStr(f["id"])
        let paid = store.blob.data[bm]?["paidFixed"]?[id]?.bool ?? false
        let skipped = store.blob.data[bm]?["skippedFixed"]?[id]?.bool ?? false
        let amount = c.fixedAmount(f, bm)
        HStack(spacing: 10) {
            if !skipped { paidCircle(paid) { store.toggleBoolMap(bm, "paidFixed", id) } }
            Text(f.s("name")).foregroundStyle(paid || skipped ? T.muted : T.text)
                .strikethrough(paid || skipped)
            Spacer()
            if f.b("variable") && !f.b("sub") {
                TextField("0", value: Binding(
                    get: { store.blob.data[bm]?["fixedAmounts"]?[id]?.double ?? 0 },
                    set: { store.setNumberMap(bm, "fixedAmounts", id, $0) }
                ), format: .number)
                .multilineTextAlignment(.trailing).frame(width: 80)
                .modifier(FieldStyle()).keyboardType(.numberPad)
            } else {
                Text(yen(amount)).fontWeight(.semibold).foregroundStyle(paid || skipped ? T.muted : T.text)
            }
            Button(skipped ? "Undo" : "Skip") { store.toggleBoolMap(bm, "skippedFixed", id) }
                .font(.caption2).foregroundStyle(skipped ? T.peachD : T.muted).buttonStyle(.plain)
        }
        .font(.footnote)
    }

    @ViewBuilder private func builtinRow(_ c: Calc, id: String, label: String, amount: Double) -> some View {
        let paid = store.blob.data[bm]?["paidFixed"]?[id]?.bool ?? false
        HStack(spacing: 10) {
            paidCircle(paid) { store.toggleBoolMap(bm, "paidFixed", id) }
            Text(label).foregroundStyle(paid ? T.muted : T.text).strikethrough(paid)
            Spacer()
            Text(yen(amount)).fontWeight(.semibold).foregroundStyle(paid ? T.muted : T.text)
        }
        .font(.footnote)
    }

    private func totalFixed(_ c: Calc) -> Double {
        let d = store.blob.data[bm] ?? .object([:])
        let skipped = d["skippedFixed"]?.object ?? [:]
        var s = 0.0
        for f in c.fixed where skipped[c.idStr(f["id"])]?.bool != true { s += c.fixedAmount(f, bm) }
        s += c.commute(bm) + c.food(bm) + c.skin(bm) + c.genSav(bm)
        return s
    }

    // MARK: One-offs
    @ViewBuilder private func oneOffCard(_ c: Calc) -> some View {
        let oneOffs = store.blob.data[bm]?["oneOffs"]?.array ?? []
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("One-off Expenses", color: T.peachD)
            if oneOffs.isEmpty { Text("None this month").font(.footnote).foregroundStyle(T.muted) }
            ForEach(Array(oneOffs.enumerated()), id: \.offset) { _, o in
                let id = c.idStr(o["id"])
                let mum = o["mumPays"]?.bool ?? false
                let paid = store.blob.data[bm]?["paidOneOffs"]?[id]?.bool ?? false
                HStack(spacing: 8) {
                    Text(o.s("name")).foregroundStyle(mum || paid ? T.muted : T.text).strikethrough(mum || paid)
                    if mum { Text("Mum").font(.system(size: 9)).padding(.horizontal, 6).padding(.vertical, 2).background(T.peachBg).foregroundStyle(T.peachD).clipShape(Capsule()) }
                    Spacer()
                    Text(yen(o.d("amount"))).fontWeight(.semibold).foregroundStyle(mum || paid ? T.muted : T.text)
                    if !mum { paidCircle(paid) { store.toggleBoolMap(bm, "paidOneOffs", id) } }
                    Button(mum ? "Me" : "Mum") { store.toggleOneOffMum(bm, id) }.font(.caption2).buttonStyle(.plain).foregroundStyle(T.sub)
                    Button { store.removeOneOff(bm, id) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain).foregroundStyle(T.roseD)
                }
                .font(.footnote)
            }
            HStack(spacing: 8) {
                TextField("Name", text: $ooName).modifier(FieldStyle())
                TextField("¥", text: $ooAmount).frame(width: 80).modifier(FieldStyle()).keyboardType(.numberPad)
                Button {
                    let amt = Double(ooAmount) ?? 0
                    if !ooName.isEmpty && amt > 0 { store.addOneOff(bm, name: ooName, amount: amt); ooName = ""; ooAmount = "" }
                } label: { Image(systemName: "plus").fontWeight(.bold).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10).background(T.peachD).clipShape(RoundedRectangle(cornerRadius: 12)) }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .card()
    }

    // MARK: Send to Mum
    @ViewBuilder private func mumCard(_ c: Calc) -> some View {
        let checked = Set((store.blob.data[bm]?["mumChecked"]?.array ?? []).compactMap { $0.string })
        var items: [(id: String, name: String, amount: Double)] = [("food", "Food Budget", c.food(bm))]
        for m in c.se.arr("mumItems") { items.append((c.idStr(m["id"]), m.s("name"), m.d("amount"))) }
        let total = items.filter { checked.contains($0.id) }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Send to Mum", color: T.roseD)
            ForEach(items, id: \.id) { it in
                HStack(spacing: 10) {
                    checkBox(checked.contains(it.id)) { store.toggleArrayMember(bm, "mumChecked", it.id) }
                    Text(it.name).foregroundStyle(checked.contains(it.id) ? T.text : T.muted)
                    Spacer()
                    Text(yen(it.amount)).fontWeight(.semibold).foregroundStyle(checked.contains(it.id) ? T.text : T.muted)
                }
                .font(.footnote)
            }
            if total > 0 {
                HStack { Text("Send to Mum").fontWeight(.bold).foregroundStyle(.white); Spacer()
                    Text(yen(total)).font(.title3).fontWeight(.bold).foregroundStyle(.white) }
                    .padding(14).frame(maxWidth: .infinity).background(T.roseD)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .card()
    }

    // MARK: Free to spend
    @ViewBuilder private func freeCard(_ c: Calc) -> some View {
        let free = c.freeToSpend(bm)
        HStack {
            Text("Free to Spend").fontWeight(.bold).foregroundStyle(.white)
            Spacer()
            Text(yen(free)).font(.title2).fontWeight(.bold).foregroundStyle(.white)
        }
        .padding(22).frame(maxWidth: .infinity)
        .background(free >= 0 ? T.greenD : T.roseD)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: bits
    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 18)
            Text(title).font(.headline).foregroundStyle(T.text)
        }
    }
    private func row(_ label: String, _ value: String, bold: Bool = false, color: Color = T.text) -> some View {
        HStack { Text(label).foregroundStyle(T.sub); Spacer(); Text(value).fontWeight(bold ? .bold : .semibold).foregroundStyle(color) }
            .font(.footnote)
    }
    private func paidCircle(_ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            ZStack {
                Circle().stroke(on ? T.greenD : T.border, lineWidth: 2).frame(width: 24, height: 24)
                if on { Circle().fill(T.greenD).frame(width: 24, height: 24); Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
            }
        }.buttonStyle(.plain)
    }
    private func checkBox(_ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).stroke(on ? T.greenD : T.border, lineWidth: 2).frame(width: 24, height: 24)
                if on { RoundedRectangle(cornerRadius: 8).fill(T.greenD).frame(width: 24, height: 24); Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
            }
        }.buttonStyle(.plain)
    }
}
