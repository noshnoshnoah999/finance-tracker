// LimitView.swift — Budget (iOS/Mac)
// The ¥1,030,000 annual-limit tracker — used/remaining, a plain-language monthly
// target (¥ AND hours), a monthly earnings breakdown, and a shift simulator that
// tells you whether the shifts you're planning fit your pace (with optional
// Claude advice via the limit-advisor edge function).

import SwiftUI

struct LimitView: View {
    @EnvironmentObject var store: BudgetStore

    struct SimShift: Identifiable { let id = UUID(); var day: String; var start: Date; var end: Date; var breakMin: Int }
    @State private var shifts: [SimShift] = []
    @State private var advice: BudgetStore.LimitAdvice?
    @State private var adviceLoading = false
    @State private var adviceErr = ""

    private let dayOptions = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let c = store.calc
        let earned = c.earnedSoFar
        let limit = c.annualLimit
        let remaining = c.roomLeft
        let pct = limit > 0 ? min(1, earned / limit) : 0
        let nFM = max(0, 12 - c.currentMonthNumber)
        let safe = nFM > 0 ? floor(remaining / Double(nFM)) : 0
        let hoursPerMonth = c.hourlyWage > 0 ? safe / c.hourlyWage : 0

        // Simulator
        let plannedH = shifts.reduce(0.0) { $0 + shiftHours($1) }
        let plannedPay = (plannedH * c.hourlyWage).rounded()
        let diff = safe - plannedPay
        let projYear = (earned + plannedPay * Double(nFM)).rounded()
        let overYear = projYear > limit
        let verdict = shifts.isEmpty ? "none" : (plannedPay <= safe ? "yes" : (overYear ? "over" : "caution"))
        let vColor: Color = verdict == "yes" ? T.greenD : verdict == "caution" ? T.peachD : verdict == "over" ? T.roseD : T.muted

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Overview
                VStack(alignment: .leading, spacing: 12) {
                    Text("ANNUAL LIMIT USED").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                    HStack(alignment: .firstTextBaseline) {
                        Text(yen(earned)).font(.system(size: 34, weight: .bold)).foregroundStyle(T.text)
                        Spacer()
                        Text("of \(yen(limit))").font(.footnote).foregroundStyle(T.sub)
                    }
                    ProgressBar(fraction: pct, color: remaining < 100000 ? T.roseD : T.blueD).frame(height: 12)
                    HStack(spacing: 10) {
                        tile("Remaining", yen(remaining), remaining < 100000 ? T.roseD : T.greenD, sub: nil)
                        tile("Safe/month (\(nFM) left)", yen(safe), remaining < 100000 ? T.roseD : T.greenD, sub: "≈ \(Int(hoursPerMonth)) hrs")
                    }
                }
                .card()

                // Status banner
                let overdraft = remaining < 0
                let close = remaining < 150000
                VStack(alignment: .leading, spacing: 4) {
                    Text(overdraft ? "Over your limit" : close ? "Getting close — be careful" : "You're on track")
                        .font(.headline).foregroundStyle(.white)
                    Text(overdraft ? "Exceeded by \(yen(abs(remaining)))"
                         : close ? "Only \(yen(remaining)) left across \(nFM) months"
                         : "About \(Int(hoursPerMonth)) hours/month at \(yen(c.hourlyWage))/hr")
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(overdraft ? T.roseD : close ? T.peachD : T.greenD)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                // Monthly target — plain language
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(T.blueD).frame(width: 3, height: 18); Text("Your monthly target").font(.headline) }
                    Text("To spread the rest of your \(yen(limit)) limit evenly across the \(nFM) months left, each month aim for about:")
                        .font(.footnote).foregroundStyle(T.sub)
                    HStack(spacing: 10) {
                        targetTile("Earn about", yen(safe))
                        targetTile("Work about", "\(Int(hoursPerMonth))h")
                    }
                    Text(remaining < 0 ? "You're \(yen(abs(remaining))) over the limit — ease off"
                         : "Work more some months, less others — just keep the year under \(yen(limit)).")
                        .font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(remaining < 0 ? T.roseD : T.greenD)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(remaining < 0 ? T.roseBg : T.greenBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .card()
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(T.blueD, lineWidth: 2))

                // Shift simulator
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(T.peachD).frame(width: 3, height: 18); Text("Can I work these shifts?").font(.headline) }
                    Text("Add the shifts you're thinking of working this month — I'll tell you if you can.")
                        .font(.caption).foregroundStyle(T.sub)

                    if shifts.isEmpty {
                        Text("No shifts yet — add one below.").font(.footnote).foregroundStyle(T.muted)
                    }
                    ForEach($shifts) { $shift in
                        HStack(spacing: 6) {
                            Menu {
                                ForEach(dayOptions, id: \.self) { d in Button(d) { shift.day = d } }
                            } label: {
                                Text(shift.day).font(.caption).fontWeight(.semibold).foregroundStyle(T.text)
                                    .frame(width: 42).padding(.vertical, 9)
                                    .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            DatePicker("", selection: $shift.start, displayedComponents: .hourAndMinute).labelsHidden()
                            DatePicker("", selection: $shift.end, displayedComponents: .hourAndMinute).labelsHidden()
                            Text("\(fmt1(shiftHours(shift)))h").font(.caption).foregroundStyle(T.sub).frame(width: 36, alignment: .trailing)
                            Button { shifts.removeAll { $0.id == shift.id } } label: { Image(systemName: "xmark").font(.caption2) }
                                .buttonStyle(.plain).foregroundStyle(T.roseD)
                        }
                    }
                    Button { shifts.append(SimShift(day: "Mon", start: at(9, 0), end: at(16, 0), breakMin: 60)) } label: {
                        Text("+ Add a shift").font(.footnote).fontWeight(.semibold).foregroundStyle(T.sub)
                            .frame(maxWidth: .infinity).padding(10)
                            .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                    Text("Each shift's break is taken off automatically (defaults to 60 min).")
                        .font(.caption2).foregroundStyle(T.muted)

                    if !shifts.isEmpty {
                        VStack(spacing: 8) {
                            HStack { Text("This month").foregroundStyle(T.sub); Spacer(); Text("\(fmt1(plannedH))h · \(yen(plannedPay))").fontWeight(.bold) }
                            HStack { Text("Your monthly target").foregroundStyle(T.sub); Spacer(); Text("\(Int(hoursPerMonth))h · \(yen(safe))").fontWeight(.semibold) }
                            Divider().overlay(T.border)
                            HStack { Text("If every month were like this").foregroundStyle(T.sub); Spacer(); Text("≈ \(yen(projYear))/yr").fontWeight(.semibold).foregroundStyle(overYear ? T.roseD : T.text) }
                        }
                        .font(.footnote).padding(14)
                        .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(verdict == "yes" ? "✅ Yes — go for it. \(yen(abs(diff))) under your monthly pace."
                             : verdict == "caution" ? "⚠️ Doable, but \(yen(plannedPay - safe)) above your steady pace — balance it with a lighter month."
                             : "❌ Too much — at this rate you'd reach \(yen(projYear)) (over by \(yen(projYear - limit))).")
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(14)
                            .background(vColor).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button { runAdvisor(earned: earned, limit: limit, remaining: remaining, nFM: nFM, safe: safe, hoursPerMonth: hoursPerMonth) } label: {
                            Text(adviceLoading ? "Claude is thinking…" : "🤖 Ask Claude for advice")
                                .font(.footnote).fontWeight(.bold).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(T.blueD).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }.buttonStyle(.plain).disabled(adviceLoading)

                        if !adviceErr.isEmpty {
                            Text(adviceErr).font(.caption).foregroundStyle(T.roseD).padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(T.roseBg).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if let a = advice {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(a.headline).font(.subheadline).fontWeight(.bold).foregroundStyle(T.text)
                                if !a.reasoning.isEmpty { Text(a.reasoning).font(.footnote).foregroundStyle(T.sub) }
                                ForEach(Array(a.suggestions.enumerated()), id: \.offset) { _, s in
                                    HStack(alignment: .top, spacing: 6) { Text("•").foregroundStyle(T.peachD); Text(s) }.font(.footnote).foregroundStyle(T.text)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(T.greenBg).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .card()

                // Monthly earnings
                let amounts = MONTHS.map { c.taxable($0.key) }
                let maxW = max(amounts.max() ?? 1, 1)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(T.blueD).frame(width: 3, height: 18); Text("Monthly Earnings").font(.headline) }
                    ForEach(Array(MONTHS.enumerated()), id: \.offset) { i, mo in
                        let w = amounts[i]
                        let isFut = i >= c.currentMonthNumber
                        HStack(spacing: 10) {
                            Text(mo.short).font(.caption).foregroundStyle(T.sub).frame(width: 34, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(T.cardAlt)
                                    if w > 0 { Capsule().fill(T.blueD).frame(width: w / maxW * geo.size.width) }
                                }
                            }.frame(height: 8)
                            Text(w > 0 ? yen(w) : "—").font(.caption).fontWeight(w > 0 ? .semibold : .regular)
                                .foregroundStyle(w > 0 ? T.text : T.muted).frame(width: 78, alignment: .trailing)
                        }
                        .opacity(isFut ? 0.4 : 1)
                    }
                    Divider().overlay(T.border)
                    HStack { Text("Total earned").fontWeight(.bold); Spacer(); Text(yen(earned)).fontWeight(.bold).foregroundStyle(T.blueD) }
                        .font(.subheadline)
                }
                .card()
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    // MARK: helpers
    private func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }
    private func shiftHours(_ s: SimShift) -> Double { max(0, s.end.timeIntervalSince(s.start) / 3600 - Double(s.breakMin) / 60) }
    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }

    private func runAdvisor(earned: Double, limit: Double, remaining: Double, nFM: Int, safe: Double, hoursPerMonth: Double) {
        let c = store.calc
        let plannedH = shifts.reduce(0.0) { $0 + shiftHours($1) }
        let plannedPay = (plannedH * c.hourlyWage).rounded()
        let projYear = (earned + plannedPay * Double(nFM)).rounded()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let lines = shifts.map { s in
            "- \(s.day) \(f.string(from: s.start))-\(f.string(from: s.end))\(s.breakMin > 0 ? " (\(s.breakMin)m break)" : "") = \(fmt1(shiftHours(s)))h"
        }.joined(separator: "\n")
        let ctx: [String: JSONValue] = [
            "annualLimit": .number(limit), "earnedSoFar": .number(earned), "roomLeft": .number(remaining),
            "monthsLeft": .number(Double(nFM)), "hourlyWage": .number(c.hourlyWage),
            "safePerMonthYen": .number(safe), "safePerMonthHours": .number(Double(Int(hoursPerMonth.rounded()))),
            "plannedHours": .string(fmt1(plannedH)), "plannedPay": .number(plannedPay),
            "projectedYearEnd": .number(projYear), "shiftLines": .string(lines),
        ]
        adviceErr = ""; advice = nil; adviceLoading = true
        Task {
            do { let a = try await store.limitAdvice(ctx); await MainActor.run { advice = a; adviceLoading = false } }
            catch { await MainActor.run { adviceErr = "Couldn't get advice: \(error.localizedDescription)"; adviceLoading = false } }
        }
    }

    private func tile(_ label: String, _ value: String, _ color: Color, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(T.sub)
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(color)
            if let sub { Text(sub).font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func targetTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(T.sub)
            Text(value).font(.title2).fontWeight(.bold).foregroundStyle(T.blueD)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 14)
        .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
