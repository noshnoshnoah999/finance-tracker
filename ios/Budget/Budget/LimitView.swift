// LimitView.swift — Budget (iOS/Mac)
// The ¥1,030,000 annual-limit tracker — used/remaining, a plain-language monthly
// target (¥ AND hours), a monthly earnings breakdown, and a shift simulator that
// tells you whether the shifts you're planning fit your pace (with optional
// Claude advice via the limit-advisor edge function).

import SwiftUI

struct LimitView: View {
    @EnvironmentObject var store: BudgetStore

    // freq: "weekly" repeats the shift for every matching weekday in the month (the default —
    // Noah's normal work pattern repeats every week); "once" counts it a single time.
    struct SimShift: Identifiable { let id = UUID(); var day: String; var start: Date; var end: Date; var breakMin: Int; var freq: String = "weekly" }
    @State private var shifts: [SimShift] = []
    @State private var advice: BudgetStore.LimitAdvice?
    @State private var adviceLoading = false
    @State private var adviceErr = ""
    // Which month the simulator plans for (nil = default to the current month).
    @State private var planMK: String? = nil

    // Follow-up chat with Claude — persisted locally (UserDefaults) for 1 day only, per-device,
    // no Supabase sync. This is a scratchpad for thinking out loud, not a financial record.
    @State private var chatMsgs: [LimitChatMessage] = LimitChatStore.load()
    @State private var chatInput = ""
    @State private var chatLoading = false
    @State private var chatErr = ""
    // The exact context dict used for the last verdict — reused for chat follow-ups so Claude
    // answers against the same numbers.
    @State private var limitCtx: [String: JSONValue]? = nil

    private let dayOptions = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // The current calendar month's key, clamped into the MONTHS array.
    private var currentMK: String {
        let cMN = store.calc.currentMonthNumber
        return MONTHS[max(0, min(MONTHS.count - 1, cMN - 1))].key
    }
    // The month actually being planned (chosen month, or current month by default).
    private var effectivePlanMK: String {
        if let p = planMK, MONTHS.contains(where: { $0.key == p }) { return p }
        return currentMK
    }
    // Months offered in the picker: current month through December.
    private var planMonths: [MonthMeta] {
        let start = max(0, store.calc.currentMonthNumber - 1)
        return Array(MONTHS[start...])
    }
    private var planLabel: String { monthMeta(effectivePlanMK)?.label ?? "" }

    var body: some View {
        let c = store.calc
        let earned = c.earnedSoFar
        let limit = c.annualLimit
        let remaining = c.roomLeft
        let pct = limit > 0 ? min(1, earned / limit) : 0
        let nFM = max(0, 12 - c.currentMonthNumber)
        let safe = nFM > 0 ? floor(remaining / Double(nFM)) : 0
        let hoursPerMonth = c.hourlyWage > 0 ? safe / c.hourlyWage : 0

        // Simulator — "weekly" shifts repeat for every matching weekday in the month being planned.
        let plannedH = shifts.reduce(0.0) { $0 + shiftHours($1) * Double(occurrences($1)) }
        let plannedPay = (plannedH * c.hourlyWage).rounded()
        let diff = safe - plannedPay
        let projYear = (earned + plannedPay * Double(nFM)).rounded()
        let overYear = projYear > limit
        let verdict = shifts.isEmpty ? "none" : (plannedPay <= safe ? "yes" : (overYear ? "over" : "caution"))
        let vColor: Color = verdict == "yes" ? T.greenD : verdict == "caution" ? T.peachD : verdict == "over" ? T.roseD : T.muted

        // Bank-style insights
        let pctUsed = limit > 0 ? min(1, earned / limit) : 0
        let pctTxt = limit > 0 ? Int((earned / limit * 100).rounded()) : 0
        let elapsed = max(1, c.currentMonthNumber)
        let avgMonth = (earned / Double(elapsed)).rounded()
        let projYearEnd = (avgMonth * 12).rounded()
        let projOver = projYearEnd > limit
        let evenPace = limit * Double(elapsed) / 12
        let paceDelta = (evenPace - earned).rounded()
        let ci = c.currentMonthNumber - 1
        let curVal = (ci >= 0 && ci < MONTHS.count) ? c.taxable(MONTHS[ci].key) : 0
        let curName = (ci >= 0 && ci < MONTHS.count) ? MONTHS[ci].label : ""
        let lastVal = (ci - 1 >= 0 && ci - 1 < MONTHS.count) ? c.taxable(MONTHS[ci - 1].key) : 0
        let momPct: Int? = lastVal > 0 ? Int(((curVal - lastVal) / lastVal * 100).rounded()) : nil
        let statusTxt = remaining < 0 ? "Over limit" : remaining < 150000 ? "Getting close" : "On track"
        let ringColor: Color = earned >= limit ? Color(red: 1, green: 0.54, blue: 0.54) : (pctUsed > 0.85 ? Color(red: 1, green: 0.81, blue: 0.48) : .white)
        let monthlyShare = limit / 12

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Bank-style hero with progress ring
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.22), lineWidth: 12)
                        Circle().trim(from: 0, to: pctUsed).stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(pctTxt)%").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                            Text("of limit").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        }
                    }.frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("REMAINING TO EARN").font(.caption2).foregroundStyle(.white.opacity(0.7))
                        Text(yen(remaining)).font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                        Text("\(yen(earned)) used of \(yen(limit))").font(.caption2).foregroundStyle(.white.opacity(0.75))
                        Text("● \(statusTxt)").font(.caption).fontWeight(.bold).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 4).background(Color.white.opacity(0.18)).clipShape(Capsule()).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [T.blueD, T.lavD], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                // Insights grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    limCell("Projected year-end", yen(projYearEnd), projOver ? T.roseD : T.greenD, projOver ? "over by \(yen(projYearEnd - limit))" : "\(yen(limit - projYearEnd)) under limit", T.sub)
                    limCell("Average / month", yen(avgMonth), T.text, "over \(elapsed) month\(elapsed == 1 ? "" : "s")", T.sub)
                    limCell("\(curName) so far", yen(curVal), T.text, momPct == nil ? "vs last month —" : "\(momPct! > 0 ? "↑" : "↓") \(abs(momPct!))% vs last", momPct == nil ? T.sub : (momPct! > 0 ? T.peachD : T.greenD))
                    limCell("Safe / month left", yen(safe), remaining < 100000 ? T.roseD : T.greenD, "≈ \(Int(hoursPerMonth))h · \(nFM) left", T.sub)
                }

                // Earning pace
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Earning pace").font(.subheadline).fontWeight(.bold)
                        Spacer()
                        Text(paceDelta >= 0 ? "\(yen(paceDelta)) under pace" : "\(yen(-paceDelta)) ahead").font(.caption).fontWeight(.bold).foregroundStyle(paceDelta >= 0 ? T.greenD : T.peachD)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(T.cardAlt)
                            Capsule().fill(LinearGradient(colors: paceDelta >= 0 ? [T.green, T.blueD] : [T.peach, T.roseD], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * pctUsed)
                            Rectangle().fill(T.text.opacity(0.55)).frame(width: 2).offset(x: geo.size.width * (Double(elapsed) / 12))
                        }
                    }.frame(height: 12)
                    Text(paceDelta >= 0 ? "You're under the even-pace line (mark) — room to work more if you want." : "You're ahead of the even-pace line (mark) — ease off to stay safe.").font(.caption2).foregroundStyle(T.sub)
                }
                .card()

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
                    Text("Add the shifts you're thinking of working, pick the month, and I'll tell you if you can.")
                        .font(.caption).foregroundStyle(T.sub)
                    HStack(spacing: 8) {
                        Text("Planning for").font(.caption).foregroundStyle(T.sub)
                        Menu {
                            ForEach(planMonths, id: \.key) { m in
                                Button(m.key == currentMK ? "\(m.label) (this month)" : m.label) { planMK = m.key }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(planLabel).font(.caption).fontWeight(.semibold)
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }.foregroundStyle(T.text)
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Spacer()
                    }

                    if shifts.isEmpty {
                        Text("No shifts yet — add one below.").font(.footnote).foregroundStyle(T.muted)
                    }
                    ForEach($shifts) { $shift in
                        VStack(alignment: .leading, spacing: 6) {
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
                            HStack(spacing: 6) {
                                Menu {
                                    Button("Every week in \(planLabel)") { shift.freq = "weekly" }
                                    Button("Just this once") { shift.freq = "once" }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(shift.freq == "once" ? "Just this once" : "Every week in \(planLabel)").font(.caption2)
                                        Image(systemName: "chevron.down").font(.system(size: 9))
                                    }.foregroundStyle(T.sub)
                                    .padding(.vertical, 5).padding(.horizontal, 8)
                                    .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                if shift.freq != "once" {
                                    Text("× \(occurrences(shift)) in \(planLabel)").font(.caption2).foregroundStyle(T.muted)
                                }
                                Spacer()
                            }
                        }
                        .padding(.bottom, 6)
                    }
                    Button { shifts.append(SimShift(day: "Mon", start: at(9, 0), end: at(16, 0), breakMin: Int(c.defaultBreak), freq: "weekly")) } label: {
                        Text("+ Add a shift").font(.footnote).fontWeight(.semibold).foregroundStyle(T.sub)
                            .frame(maxWidth: .infinity).padding(10)
                            .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                    Text("Breaks are only deducted for shifts longer than 3 hours (defaults to \(Int(c.defaultBreak)) min — change it in Settings); a shift of 3 hours or under keeps its full time. \"Every week\" repeats the shift for every matching weekday in the chosen month.")
                        .font(.caption2).foregroundStyle(T.muted)

                    if !shifts.isEmpty {
                        VStack(spacing: 8) {
                            HStack { Text(planLabel).foregroundStyle(T.sub); Spacer(); Text("\(fmt1(plannedH))h · \(yen(plannedPay))").fontWeight(.bold) }
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
                        if let a = advice, a.headline.isEmpty, a.reasoning.isEmpty, a.suggestions.isEmpty {
                            Text("Claude's advice came back empty — try again in a moment. If this keeps happening, the advice service may be down.")
                                .font(.caption).foregroundStyle(T.roseD).padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(T.roseBg).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if let a = advice, !(a.headline.isEmpty && a.reasoning.isEmpty && a.suggestions.isEmpty) {
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

                        // Follow-up chat — appears once the first verdict has come back.
                        if let a = advice, !(a.headline.isEmpty && a.reasoning.isEmpty) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Ask a follow-up").font(.caption).fontWeight(.bold).foregroundStyle(T.sub)
                                    Spacer()
                                    if !chatMsgs.isEmpty {
                                        Button("Clear chat") { clearChat() }
                                            .font(.caption2).foregroundStyle(T.muted)
                                    }
                                }
                                if !chatMsgs.isEmpty {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(chatMsgs) { m in
                                                Text(m.content)
                                                    .font(.footnote)
                                                    .foregroundStyle(m.role == "user" ? .white : T.text)
                                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                                    .background(m.role == "user" ? T.blueD : T.cardAlt)
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                    .frame(maxWidth: .infinity, alignment: m.role == "user" ? .trailing : .leading)
                                            }
                                            if chatLoading {
                                                Text("Claude is thinking…").font(.footnote).foregroundStyle(T.muted)
                                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                                    .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 320)
                                }
                                HStack(spacing: 8) {
                                    TextField("e.g. what if I drop the Saturday shift?", text: $chatInput)
                                        .font(.footnote)
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .disabled(chatLoading)
                                        .onSubmit { sendChat() }
                                    Button { sendChat() } label: {
                                        Text("Send").font(.footnote).fontWeight(.bold).foregroundStyle(.white)
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(T.blueD).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }.buttonStyle(.plain).disabled(chatLoading || chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                if !chatErr.isEmpty {
                                    Text(chatErr).font(.caption2).foregroundStyle(T.roseD).padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(T.roseBg).clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .card()

                // Monthly earnings — colour-coded vs even share
                let amounts = MONTHS.map { c.taxable($0.key) }
                let maxW = max(amounts.max() ?? 1, 1)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(T.blueD).frame(width: 3, height: 18); Text("Monthly earnings").font(.headline) }
                        Spacer()
                        Text("even share \(yen(monthlyShare.rounded()))").font(.caption2).foregroundStyle(T.sub)
                    }
                    Text("Each bar's full width is this month's highest earning (\(yen(maxW))) — the tick mark shows where the even share (\(yen(monthlyShare.rounded()))/month) falls. Orange means that month earned more than the even share.")
                        .font(.caption2).foregroundStyle(T.muted)
                    ForEach(Array(MONTHS.enumerated()), id: \.offset) { i, mo in
                        let w = amounts[i]
                        let isFut = i >= c.currentMonthNumber
                        let isCur = i == c.currentMonthNumber - 1
                        let heavy = w > monthlyShare
                        let sharePct = min(1, monthlyShare / maxW)
                        HStack(spacing: 10) {
                            Text(mo.short).font(.caption).fontWeight(isCur ? .bold : .regular).foregroundStyle(isCur ? T.blueD : T.sub).frame(width: 34, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(T.cardAlt)
                                    if w > 0 { Capsule().fill(heavy ? T.peachD : T.blueD).frame(width: w / maxW * geo.size.width) }
                                    Rectangle().fill(T.text.opacity(0.55)).frame(width: 2, height: 12)
                                        .offset(x: sharePct * geo.size.width - 1, y: -2)
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
        .keyboardDoneBar()
    }

    // MARK: helpers
    private func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }
    // Raw duration before any break.
    private func rawHours(_ s: SimShift) -> Double { max(0, s.end.timeIntervalSince(s.start) / 3600) }
    // Breaks only apply once a shift runs longer than 3 hours — 3h or under gets no break deducted.
    private func shiftHours(_ s: SimShift) -> Double {
        let r = rawHours(s)
        let brk = r > 3 ? Double(s.breakMin) / 60 : 0
        return max(0, r - brk)
    }
    private func occurrences(_ s: SimShift) -> Int {
        guard s.freq != "once" else { return 1 }
        let dowMap: [String: Int] = ["Sun": 0, "Mon": 1, "Tue": 2, "Wed": 3, "Thu": 4, "Fri": 5, "Sat": 6]
        return store.calc.weekdayCount(effectivePlanMK, dowMap[s.day] ?? 1)
    }
    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }

    // Estimated pay for upcoming unlogged months (arrears convention, same as Wage tab) — passed
    // to Claude so it can reason about "what if" questions for months not yet logged.
    private func buildEstimateLines() -> String {
        let c = store.calc
        let start = max(0, c.currentMonthNumber - 1)
        let futureMonths = Array(MONTHS[start...])
        return futureMonths.compactMap { mo -> String? in
            let est = c.estimatedPay(mo.key)
            guard est.total > 0 else { return nil }
            return "- \(mo.label): ~\(yen(est.total)) (\(fmt1(est.hours))h)"
        }.joined(separator: "\n")
    }

    private func runAdvisor(earned: Double, limit: Double, remaining: Double, nFM: Int, safe: Double, hoursPerMonth: Double) {
        let c = store.calc
        let plannedH = shifts.reduce(0.0) { $0 + shiftHours($1) * Double(occurrences($1)) }
        let plannedPay = (plannedH * c.hourlyWage).rounded()
        let projYear = (earned + plannedPay * Double(nFM)).rounded()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let lines = shifts.map { s in
            "- \(s.day) \(f.string(from: s.start))-\(f.string(from: s.end))\(rawHours(s) > 3 ? " (\(s.breakMin)m break)" : "")\(s.freq == "once" ? " (this occurrence only)" : " (every week)") = \(fmt1(shiftHours(s)))h/occurrence × \(occurrences(s)) in \(planLabel)"
        }.joined(separator: "\n")
        let ctx: [String: JSONValue] = [
            "annualLimit": .number(limit), "earnedSoFar": .number(earned), "roomLeft": .number(remaining),
            "monthsLeft": .number(Double(nFM)), "hourlyWage": .number(c.hourlyWage),
            "safePerMonthYen": .number(safe), "safePerMonthHours": .number(Double(Int(hoursPerMonth.rounded()))),
            "plannedHours": .string(fmt1(plannedH)), "plannedPay": .number(plannedPay),
            "projectedYearEnd": .number(projYear), "shiftLines": .string(lines),
            "estimateLines": .string(buildEstimateLines()),
        ]
        limitCtx = ctx
        // A fresh verdict means a fresh shift plan — clear any old chat thread so follow-up
        // questions aren't answered against stale numbers.
        chatMsgs = []; LimitChatStore.clear(); chatErr = ""
        adviceErr = ""; advice = nil; adviceLoading = true
        Task {
            do { let a = try await store.limitAdvice(ctx); await MainActor.run { advice = a; adviceLoading = false } }
            catch { await MainActor.run { adviceErr = "Couldn't get advice: \(error.localizedDescription)"; adviceLoading = false } }
        }
    }

    private func sendChat() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatLoading, let ctx = limitCtx else { return }
        let history = chatMsgs.map { (role: $0.role, content: $0.content) }
        chatMsgs.append(LimitChatMessage(role: "user", content: text))
        chatInput = ""; chatErr = ""; chatLoading = true
        Task {
            do {
                let reply = try await store.limitChatReply(ctx: ctx, history: history, message: text)
                await MainActor.run {
                    chatMsgs.append(LimitChatMessage(role: "assistant", content: reply))
                    LimitChatStore.save(chatMsgs)
                    chatLoading = false
                }
            } catch {
                await MainActor.run { chatErr = "Couldn't send: \(error.localizedDescription)"; chatLoading = false }
            }
        }
    }

    private func clearChat() {
        chatMsgs = []; LimitChatStore.clear(); chatErr = ""
    }

    private func limCell(_ label: String, _ value: String, _ valueColor: Color, _ sub: String, _ subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(T.sub)
            Text(value).font(.headline).fontWeight(.bold).foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.caption2).fontWeight(.semibold).foregroundStyle(subColor).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(T.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

// MARK: - Limit-page chat persistence
// Follow-up chat with Claude is a local scratchpad, not a financial record: stored in
// UserDefaults, kept for 1 day only, per-device (no Supabase sync, no server storage).

struct LimitChatMessage: Identifiable, Codable {
    var id = UUID()
    var role: String    // "user" | "assistant"
    var content: String
}

private struct LimitChatSnapshot: Codable {
    var savedAt: Date
    var messages: [LimitChatMessage]
}

enum LimitChatStore {
    private static let key = "limitChat_v1"
    private static let ttl: TimeInterval = 24 * 60 * 60 // 1 day

    static func load() -> [LimitChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(LimitChatSnapshot.self, from: data) else { return [] }
        if Date().timeIntervalSince(snap.savedAt) > ttl {
            UserDefaults.standard.removeObject(forKey: key)
            return []
        }
        return snap.messages
    }

    static func save(_ messages: [LimitChatMessage]) {
        guard !messages.isEmpty else { clear(); return }
        let snap = LimitChatSnapshot(savedAt: Date(), messages: messages)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
