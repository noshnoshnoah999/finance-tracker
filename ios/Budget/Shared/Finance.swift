// Finance.swift — Budget (iOS/Mac)
// Swift port of the money math in app.html (gW, gTr, gTx, gPD, gCm, gPLHours, …) so the
// native app shows the SAME numbers as the web app over the same Supabase blob.

import Foundation

struct Calc {
    let se: JSONValue            // settings object
    let data: JSONValue         // months object ("2026-06" -> {...})

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    // MARK: Settings accessors
    var hourlyWage: Double { se.d("hourlyWage", DS.hourlyWage) }
    var annualLimit: Double { se.d("annualLimit", DS.annualLimit) }
    var commuteOneWay: Double { se.d("commuteOneWay", DS.commuteOneWay) }
    var rt: Double { commuteOneWay * 2 }
    var gbpToJpy: Double { se.d("gbpToJpy", DS.gbpToJpy) }
    var usdToJpy: Double { se.d("usdToJpy", DS.usdToJpy) }
    var workDays: [Int] { se["workDays"]?.array?.compactMap { $0.int } ?? DS.workDays }
    /// Break in minutes for newly created shifts. Clamped to 0–480 and falling back to 60
    /// if the stored value is missing or garbage, so a bad setting can never produce NaN
    /// hours — shiftHours subtracts breakMin/60 and one NaN would poison every downstream
    /// pay figure. Mirrors dfBrk() in app.html.
    var defaultBreak: Double {
        guard let v = se["defaultBreak"]?.double, v.isFinite else { return DS.defaultBreak }
        return min(480, max(0, v))
    }
    var showSkin: Bool { se["showSkin"]?.bool != false }
    var showGenSav: Bool { se["showGenSav"]?.bool != false }
    var genSavAmount: Double { se.d("genSavAmount") }
    var fixed: [JSONValue] { se.arr("fixed") }
    var subItems: [JSONValue] { se.arr("subItems") }

    func month(_ mk: String) -> JSONValue { data[mk] ?? .object([:]) }

    // MARK: Date helpers
    private func ym(_ mk: String) -> (Int, Int) {
        let p = mk.split(separator: "-")
        return (Int(p[0]) ?? 2026, Int(p.count > 1 ? p[1] : "1") ?? 1)
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
    }
    /// JS getDay(): 0 = Sunday … 6 = Saturday.
    private func jsDay(_ y: Int, _ m: Int, _ d: Int) -> Int {
        cal.component(.weekday, from: date(y, m, d)) - 1
    }
    private func daysInMonth(_ y: Int, _ m: Int) -> Int {
        cal.range(of: .day, in: .month, for: date(y, m, 1))?.count ?? 30
    }
    private func dstr(_ y: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Stringified id (fixed/sub item ids are JSON numbers; map keys are their string form).
    func idStr(_ v: JSONValue?) -> String {
        guard let v else { return "" }
        if case .number(let n) = v { return n == n.rounded() ? String(Int(n)) : String(n) }
        if case .string(let s) = v { return s }
        return ""
    }

    // MARK: Payday (15th, pulled back off weekends)
    func payday(_ mk: String) -> Int {
        let (y, m) = ym(mk)
        switch jsDay(y, m, 15) {
        case 6: return 14   // Saturday
        case 0: return 13   // Sunday
        default: return 15
        }
    }

    /// Is this calendar day one of the scheduled work weekdays?
    func isScheduled(_ y: Int, _ m: Int, _ d: Int) -> Bool { workDays.contains(jsDay(y, m, d)) }
    /// Public wrapper for jsDay — lets callers outside Calc (e.g. BudgetStore's one-off-shift
    /// prompt) look up that weekday's shift without duplicating the JS-getDay() math.
    func weekday(_ y: Int, _ m: Int, _ d: Int) -> Int { jsDay(y, m, d) }
    /// Number of days in the month (exposed for the calendar grid).
    func daysIn(_ mk: String) -> Int { let (y, m) = ym(mk); return daysInMonth(y, m) }
    /// JS weekday (0=Sun) of the 1st of the month — for calendar leading blanks.
    func firstWeekday(_ mk: String) -> Int { let (y, m) = ym(mk); return jsDay(y, m, 1) }
    /// How many times a given weekday (0=Sun...6=Sat) occurs in this month — mirrors web's cDIM,
    /// used to project a weekly-recurring shift's total hours/pay across the whole month.
    func weekdayCount(_ mk: String, _ dow: Int) -> Int {
        let (y, m) = ym(mk)
        let dim = daysInMonth(y, m)
        var n = 0
        for d in 1...dim { if jsDay(y, m, d) == dow { n += 1 } }
        return n
    }

    // MARK: Day state (work / hol / pl / off / none)
    func dayState(_ ds: String, _ y: Int, _ m: Int, _ d: Int, _ customDays: JSONValue) -> String {
        if let ov = customDays[ds]?.string { return ov }
        if PAID_LEAVE.contains(ds) { return "pl" }
        if workDays.contains(jsDay(y, m, d)) { return "work" }
        return "none"
    }

    // MARK: Shifts
    func shiftHours(_ sh: JSONValue?) -> Double {
        guard let sh, let start = sh["start"]?.string, let end = sh["end"]?.string else { return 0 }
        let s = hm(start), e = hm(end)
        return (Double(e.0) + Double(e.1) / 60) - (Double(s.0) + Double(s.1) / 60) - sh.d("breakMin") / 60
    }
    private func hm(_ t: String) -> (Int, Int) {
        let p = t.split(separator: ":")
        return (Int(p.first ?? "0") ?? 0, Int(p.count > 1 ? p[1] : "0") ?? 0)
    }
    /// Base shifts merged with the month's per-day overrides.
    /// Mirrors gShifts in app.html: this is the UNION of the base schedule and the
    /// month's overrides, not just a walk of the base. The union matters because
    /// BudgetStore.freezeDOW writes an override for a weekday it is about to delete from
    /// the base schedule — past months must keep that shift's hours even though the day
    /// no longer appears in Settings.
    func shifts(_ mk: String) -> [String: JSONValue] {
        let base = se["shifts"]?.object ?? [:]
        let ov = month(mk)["shiftOverrides"]?.object ?? [:]
        var r: [String: JSONValue] = [:]
        for k in Set(base.keys).union(ov.keys) {
            let b = base[k], o = ov[k]?.object
            if let b, let o {
                var merged = b.object ?? [:]
                for (kk, vv) in o { merged[kk] = vv }
                r[k] = .object(merged)
            } else if let b {
                r[k] = b
            } else if let o, o["start"]?.string != nil, o["end"]?.string != nil {
                r[k] = .object(o)   // override for a weekday removed from the base schedule
            }
        }
        return r
    }

    /// Flat hours credited for each Paid Leave day, regardless of that day's scheduled shift length.
    static let plHoursPerDay: Double = 7

    // MARK: Paid leave hours in a month
    func plHours(_ mk: String) -> Double {
        let (y, m) = ym(mk)
        let cd = month(mk)["customDays"] ?? .object([:])
        var h = 0.0
        for d in 1...daysInMonth(y, m) where dayState(dstr(y, m, d), y, m, d, cd) == "pl" {
            h += Calc.plHoursPerDay
        }
        return h
    }

    // MARK: Wage / transport / taxable
    func transportRate(_ mk: String) -> Double { mk <= "2026-03" ? se.d("trBefore", DS.trBefore) : se.d("trAfter", DS.trAfter) }

    func wage(_ mk: String) -> Double {
        let d = month(mk)
        // Override = the TOTAL received (incl. transport); base = total − transport.
        if d.d("wageOverride") > 0 { return max(0, d.d("wageOverride") - d.d("transportOverride")) }
        return d.d("hours") > 0 ? (d.d("hours") * hourlyWage).rounded() : 0
    }
    func transport(_ mk: String) -> Double {
        let d = month(mk)
        if d.d("wageOverride") > 0 { return d.d("transportOverride") }   // the portion you entered, not added on top
        // Transport is paid alongside wage for the PREVIOUS calendar month's work (same
        // arrears convention as paidLeaveYen) — count work-days from prevMK(mk), not mk itself.
        let refMK = prevMK(mk) ?? mk
        return Double(workDaysInMonth(refMK)) * transportRate(mk)   // derive from the calendar (source of truth)
    }

    func prevMK(_ mk: String) -> String? {
        guard let i = MONTHS.firstIndex(where: { $0.key == mk }), i > 0 else { return nil }
        return MONTHS[i - 1].key
    }
    /// Taxable income for a month = this month's wage + last month's paid leave (paid in arrears).
    func taxable(_ mk: String) -> Double {
        // A manual override is the full pay (already includes paid leave) — don't add it on top.
        if month(mk).d("wageOverride") > 0 { return wage(mk) }
        // Paid leave is paid in the NEXT month, so show it regardless of this month's hours.
        var pl = 0.0
        if let p = prevMK(mk) { pl = plHours(p) }
        return wage(mk) + (pl * hourlyWage).rounded()
    }
    /// Paid-leave yen credited into this month's paycheck (for display).
    func paidLeaveYen(_ mk: String) -> Double {
        if month(mk).d("wageOverride") > 0 { return 0 }
        guard let p = prevMK(mk) else { return 0 }
        return (plHours(p) * hourlyWage).rounded()
    }

    // MARK: SUICA / commute
    func suicaDays(_ mk: String) -> Int {
        let (y, mo) = ym(mk)
        let pd1 = payday(mk)
        let nextMK = mo == 12 ? "\(y + 1)-01" : String(format: "%04d-%02d", y, mo + 1)
        let (y2, mo2) = ym(nextMK)
        let pd2 = payday(nextMK)
        var allCD: [String: JSONValue] = [:]
        if let a = month(mk)["customDays"]?.object { for (k, v) in a { allCD[k] = v } }
        if let a = month(nextMK)["customDays"]?.object { for (k, v) in a { allCD[k] = v } }
        let cd = JSONValue.object(allCD)
        var n = 0
        var cur = date(y, mo, pd1)
        let end = date(y2, mo2, pd2 - 1)
        while cur <= end {
            let c = cal.dateComponents([.year, .month, .day], from: cur)
            let yy = c.year!, mm = c.month!, dd = c.day!
            if dayState(dstr(yy, mm, dd), yy, mm, dd, cd) == "work" { n += 1 }
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? end.addingTimeInterval(1)
        }
        return n
    }
    func commute(_ mk: String) -> Double {
        let d = month(mk)
        if let ov = d["suicaOverride"]?.double, d["suicaOverride"] != .null { return ov }
        return Double(suicaDays(mk)) * rt
    }
    /// Work days within the calendar month (for the "SUICA needed" figure on the Budget tab).
    func workDaysInMonth(_ mk: String) -> Int {
        let (y, m) = ym(mk)
        let cd = month(mk)["customDays"] ?? .object([:])
        var n = 0
        for d in 1...daysInMonth(y, m) where dayState(dstr(y, m, d), y, m, d, cd) == "work" { n += 1 }
        return n
    }

    // MARK: Estimated Pay (future/unlogged months)
    struct EstPay { var hours: Double = 0; var wage: Double = 0; var days: Int = 0; var transport: Double = 0; var total: Double = 0; var noShiftDays: Int = 0 }

    /// Estimated hours for a month, computed live from the calendar (customDays) + set schedule (shifts).
    /// "work" days use that weekday's actual shift length (shiftHours already subtracts the break);
    /// "pl" days use the flat plHoursPerDay, same convention as plHours(). A "work" day with an
    /// exact-date entry in oneOffShifts (a one-off shift on a day not in the weekly schedule) uses
    /// THAT date's own start/end/break instead of the weekday lookup — mirrors gEstHours in app.html.
    /// Only once both miss does the day contribute 0h and get counted in noShiftDays.
    private func estHours(_ mk: String, _ shifts: [String: JSONValue]) -> (hours: Double, noShiftDays: Int) {
        let (y, m) = ym(mk)
        let cd = month(mk)["customDays"] ?? .object([:])
        let oneOff = month(mk)["oneOffShifts"]?.object ?? [:]
        var h = 0.0, noShift = 0
        for d in 1...daysInMonth(y, m) {
            let ds = dstr(y, m, d)
            let st = dayState(ds, y, m, d, cd)
            if st == "work" {
                let dow = jsDay(y, m, d)
                if let sh = oneOff[ds] ?? shifts[String(dow)] { h += shiftHours(sh) } else { noShift += 1 }
            } else if st == "pl" {
                h += Calc.plHoursPerDay
            }
        }
        return (h, noShift)
    }

    /// Estimated Pay for a future/unlogged month: mirrors the arrears convention used elsewhere
    /// (wage+transport shown for month mk are actually earned working prevMK). Live-computed from
    /// shifts/workDays/customDays/oneOffShifts every call, so flipping a calendar day re-syncs automatically.
    func estimatedPay(_ mk: String) -> EstPay {
        guard let pmk = prevMK(mk) else { return EstPay() }
        let sh = shifts(pmk)
        let (hours, noShift) = estHours(pmk, sh)
        let wageEst = (hours * hourlyWage).rounded()
        let cd = month(pmk)["customDays"] ?? .object([:])
        let (y, m) = ym(pmk)
        var days = 0
        for d in 1...daysInMonth(y, m) where dayState(dstr(y, m, d), y, m, d, cd) == "work" { days += 1 }
        let transportEst = Double(days) * transportRate(mk)
        return EstPay(hours: hours, wage: wageEst, days: days, transport: transportEst, total: wageEst + transportEst, noShiftDays: noShift)
    }

    // MARK: Food
    func food(_ mk: String) -> Double {
        let d = month(mk)
        if let ov = d["foodOverride"]?.double, d["foodOverride"] != .null { return ov }
        return (monthMeta(mk)?.is5wk ?? false) ? se.d("food5wk", DS.food5wk) : se.d("food4wk", DS.food4wk)
    }

    // MARK: Send to Mum — sum of the month's *checked* mum items (food + mumItems),
    // matching the web `bdMTDisplay`.
    func sendToMum(_ mk: String) -> Double {
        let checked = Set((month(mk)["mumChecked"]?.array ?? []).map { idStr($0) })
        var total = 0.0
        if checked.contains("food") { total += food(mk) }
        for it in se.arr("mumItems") where checked.contains(idStr(it["id"])) && mumActive(it, mk) {
            total += it.d("amount")
        }
        return total
    }

    // MARK: Subscriptions
    private func mIdx(_ mk: String) -> Int { MONTHS.firstIndex { $0.key == mk } ?? -1 }
    func subScheduled(_ it: JSONValue, _ mk: String) -> Bool {
        let ev = max(1, it.i("everyN", 1))
        if ev <= 1 { return true }
        let a = mIdx(mk), b = mIdx(it.s("startMK", MONTHS[0].key))
        return a >= 0 && b >= 0 && a >= b && ((a - b) % ev == 0)
    }
    func subIncluded(_ it: JSONValue, _ mk: String) -> Bool {
        if let o = month(mk)["subInc"]?[idStr(it["id"])]?.bool { return o }
        return subScheduled(it, mk)
    }
    /// What you (not Dad) pay in Subscribe & Save this month.
    func subTotal(_ mk: String) -> Double {
        subItems.filter { subIncluded($0, mk) && $0.s("payer", "me") != "dad" }
            .reduce(0) { $0 + $1.d("price") }
    }
    /// What Dad pays in Subscribe & Save this month (¥) — items tagged payer "dad" that are ticked/included.
    func subTotalDad(_ mk: String) -> Double {
        subItems.filter { subIncluded($0, mk) && $0.s("payer", "me") == "dad" }
            .reduce(0) { $0 + $1.d("price") }
    }

    // MARK: Fixed expenses
    func fixedAmount(_ f: JSONValue, _ mk: String) -> Double {
        if f.b("sub") { return subTotal(mk) }
        if f.b("paidyDerived") { return paidyMonthly(mk) }   // ¥ derived from active Paidy plans (mirror web paidyMonthlyForMonth)
        if f.b("variable") { return month(mk)["fixedAmounts"]?[idStr(f["id"])]?.double ?? 0 }
        return f.d("amount")
    }

    // MARK: Paidy installment plans (mirror app.html paidyPlans / paidyCalc / paidyMonthlyForMonth)
    var paidyPlans: [JSONValue] { se.arr("paidyPlans") }

    /// Combined monthly Paidy cost active in month `mk` ("YYYY-MM").
    /// A plan counts if `mk` is within [start, start + installments - 1].
    func paidyMonthly(_ mk: String) -> Double {
        let (y, mo) = ym(mk)
        let mkIdx = y * 12 + (mo - 1)
        var s = 0.0
        for p in paidyPlans {
            let inst = p.i("installments")
            let startIdx = p.i("startYear", y) * 12 + (p.i("startMonth", 1) - 1)
            let endIdx = startIdx + max(0, inst - 1)
            if mkIdx >= startIdx && mkIdx <= endIdx { s += p.d("monthlyPayment") }
        }
        return s
    }

    /// Live computed state for one Paidy plan as of `now`.
    struct PaidyState {
        let paid: Int, installments: Int, remainingInst: Int
        let monthly: Double, remainingBal: Double, financed: Double
        let done: Bool, pct: Int, payoffLabel: String
        let isAuto: Bool   // true when paid count is derived from the schedule (no manual override)
    }

    func paidyCalc(_ p: JSONValue, _ now: Date = Date()) -> PaidyState {
        let inst = p.i("installments")
        let mp = p.d("monthlyPayment")
        let financed = p["financedAmount"]?.double ?? (mp * Double(inst))
        let startMonth = p.i("startMonth", 1), startYear = p.i("startYear", cal.component(.year, from: now))
        let paymentDay = p.i("paymentDay", 1)
        var paid: Int
        var isAuto = false
        if let ov = p["paidCountOverride"], ov != .null, let n = ov.int {
            paid = n
        } else {
            isAuto = true
            let startIdx = startYear * 12 + (startMonth - 1)
            let nowIdx = cal.component(.year, from: now) * 12 + (cal.component(.month, from: now) - 1)
            let dayBump = cal.component(.day, from: now) >= paymentDay ? 1 : 0
            paid = max(0, nowIdx - startIdx + dayBump)
        }
        paid = max(0, min(inst, paid))
        let remainingInst = max(0, inst - paid)
        let remainingBal = max(0, financed - Double(paid) * mp)
        let done = remainingInst <= 0
        let startIdx = startYear * 12 + (startMonth - 1)
        let payoffIdx = startIdx + max(0, inst - 1)
        let payoffLabel = "\(MO_SHORT[((payoffIdx % 12) + 12) % 12]) \(payoffIdx / 12)"
        let pct = inst > 0 ? Int((Double(paid) / Double(inst) * 100).rounded()) : 0
        return PaidyState(paid: paid, installments: inst, remainingInst: remainingInst,
                          monthly: mp, remainingBal: remainingBal, financed: financed,
                          done: done, pct: pct, payoffLabel: payoffLabel, isAuto: isAuto)
    }

    /// Next Paidy payment date label. Uses the most common payment day (default 27).
    func paidyNextPayLabel(_ now: Date = Date(), day: Int? = nil) -> String {
        let d = day ?? paidyPlans.first.map { $0.i("paymentDay", 27) } ?? 27
        var y = cal.component(.year, from: now)
        var m = cal.component(.month, from: now)   // 1-based
        if cal.component(.day, from: now) > d {
            m += 1
            if m > 12 { m = 1; y += 1 }
        }
        return "\(MO_SHORT[m - 1]) \(d), \(y)"
    }

    /// Whether a mum item is active in month `mk` (blank start = always; blank end = ongoing).
    func mumActive(_ it: JSONValue, _ mk: String) -> Bool {
        let (y, mo) = ym(mk)
        let mkIdx = y * 12 + (mo - 1)
        let sM = it["startMonth"]?.int, sY = it["startYear"]?.int
        let eM = it["endMonth"]?.int, eY = it["endYear"]?.int
        let start = (sM != nil && sY != nil) ? (sY! * 12 + (sM! - 1)) : Int.min
        let end = (eM != nil && eY != nil) ? (eY! * 12 + (eM! - 1)) : Int.max
        return mkIdx >= start && mkIdx <= end
    }

    // MARK: Month roll-ups (mirror the Home/Budget computeds)
    var monthlyPay: (String) -> Double { { self.taxable($0) + self.transport($0) } }

    /// monthlyPay, but for a month with no hours/override logged yet, the wage portion is
    /// projected from the set schedule + calendar (estimatedPay) instead of ¥0 — used by
    /// income()/freeToSpend() so Free to Spend reflects a realistic budget for future months.
    /// Reverts to the real monthlyPay the instant hours or an override are entered (mirrors
    /// the Wage tab's Estimated Pay card behavior exactly).
    func projectedMonthlyPay(_ mk: String) -> Double {
        let d = month(mk)
        if wage(mk) == 0 && d.d("wageOverride") <= 0 {
            let est = estimatedPay(mk)
            if est.wage > 0 { return est.wage + transport(mk) }
        }
        return monthlyPay(mk)
    }

    func skin(_ mk: String) -> Double { showSkin ? month(mk).d("skinTreatment") : 0 }
    func genSav(_ mk: String) -> Double {
        guard showGenSav, month(mk)["saveGen"]?.bool == true else { return 0 }
        let ov = month(mk).d("genSavAmt")
        return ov > 0 ? ov : genSavAmount
    }
    // Effective "amount saved" for the Savings tab: a manual entry always wins;
    // otherwise it defaults to that month's General Savings figure. Intentionally
    // NOT additive — typing your own number replaces the auto amount, not stacks on it.
    func savingsTotal(_ mk: String) -> Double {
        // Budget "not saving" toggle wins: an opted-out month contributes ¥0 regardless
        // of any manual amount left in "savings". Keeps Budget & Savings tabs in sync.
        guard showGenSav, month(mk)["saveGen"]?.bool == true else { return 0 }
        let manual = month(mk).d("savings")
        return manual > 0 ? manual : genSav(mk)
    }
    /// True when the month is opted out of General Savings on the Budget tab.
    func savingsOptedOut(_ mk: String) -> Bool {
        return !(showGenSav && month(mk)["saveGen"]?.bool == true)
    }
    // Silver investment (¥) for a month — a budget outflow; syncs to the Silver page as USD.
    // saveSilver mirrors saveGen's toggle, but defaults ON (undefined != false) for
    // back-compat with entries made before the toggle existed — matches web's silverM().
    var showSilver: Bool { se["showSilver"]?.bool != false }
    func silverInvest(_ mk: String) -> Double {
        guard showSilver, month(mk)["saveSilver"]?.bool != false, month(mk).d("silverInvest") > 0 else { return 0 }
        return month(mk).d("silverInvest")
    }
    func silverUsd(_ mk: String) -> Double {
        let inv = silverInvest(mk)
        return inv > 0 ? (inv / (se.d("usdToJpy", DS.usdToJpy))).rounded() : month(mk).d("silverUsd")
    }

    /// Total budgeted spending for a month, excluding skipped fixed lines (mirror cmSpending).
    func spending(_ mk: String) -> Double {
        let d = month(mk)
        let skipped = d["skippedFixed"]?.object ?? [:]
        var s = 0.0
        for f in fixed where skipped[idStr(f["id"])]?.bool != true { s += fixedAmount(f, mk) }
        s += commute(mk) + food(mk) + skin(mk) + genSav(mk) + silverInvest(mk)
        for o in d.arr("oneOffs") where o["mumPays"]?.bool != true { s += o.d("amount") }
        return s
    }

    /// Extra money (gifts, Dad's pocket money, etc.) — non-pay income, NOT taxable.
    func extraIncome(_ mk: String) -> Double { month(mk).arr("extraIncome").reduce(0) { $0 + $1.d("amount") } }

    /// Bills that don't appear as card transactions (fixed + skin + savings + one-offs).
    func nonCardBills(_ mk: String) -> Double {
        let d = month(mk)
        let skipped = d["skippedFixed"]?.object ?? [:]
        var s = 0.0
        for f in fixed where skipped[idStr(f["id"])]?.bool != true { s += fixedAmount(f, mk) }
        s += skin(mk) + genSav(mk) + silverInvest(mk)
        for o in d.arr("oneOffs") where o["mumPays"]?.bool != true { s += o.d("amount") }
        return s
    }
    /// Single source of truth for "money out" — used by Home and Passbook so they agree.
    /// Real months: non-card bills + actual card spending. Estimated: full budget.
    func monthOut(_ mk: String) -> Double {
        let tx = month(mk).arr("txns")
        if !tx.isEmpty {
            let card = tx.filter { $0.s("direction") == "out" }.reduce(0) { $0 + $1.d("amount") }
            return nonCardBills(mk) + card
        }
        return spending(mk)
    }

    func income(_ mk: String) -> Double { projectedMonthlyPay(mk) + extraIncome(mk) }
    func freeToSpend(_ mk: String) -> Double { income(mk) - monthOut(mk) }

    /// Bills (ids) shown on the Home progress, excluding skipped and zero skin/savings.
    func homeBillIds(_ mk: String) -> [String] {
        let d = month(mk)
        let skipped = d["skippedFixed"]?.object ?? [:]
        var ids = fixed.filter { skipped[idStr($0["id"])]?.bool != true }.map { idStr($0["id"]) }
        ids += ["suica", "food"]
        if showSkin && skin(mk) > 0 { ids.append("skinTreatment") }
        if showGenSav && genSav(mk) > 0 { ids.append("generalSavings") }
        if showSilver && silverInvest(mk) > 0 { ids.append("silverInvest") }
        return ids
    }
    func paidCount(_ mk: String) -> Int {
        let pf = month(mk)["paidFixed"]?.object ?? [:]
        return homeBillIds(mk).filter { pf[$0]?.bool == true }.count
    }
    func leftToPay(_ mk: String) -> Double {
        let d = month(mk)
        let pf = d["paidFixed"]?.object ?? [:]
        let sf = d["skippedFixed"]?.object ?? [:]
        var u = 0.0
        for f in fixed {
            let id = idStr(f["id"])
            if sf[id]?.bool != true && pf[id]?.bool != true { u += fixedAmount(f, mk) }
        }
        if pf["suica"]?.bool != true { u += commute(mk) }
        if pf["food"]?.bool != true { u += food(mk) }
        if pf["skinTreatment"]?.bool != true { u += skin(mk) }
        if pf["generalSavings"]?.bool != true { u += genSav(mk) }
        if pf["silverInvest"]?.bool != true { u += silverInvest(mk) }
        return u
    }
    /// Total one-off expenses you pay (excludes Mum-pays) — mirrors web bdOY.
    func oneOffTotal(_ mk: String) -> Double {
        var s = 0.0
        for o in month(mk).arr("oneOffs") where o["mumPays"]?.bool != true { s += o.d("amount") }
        return s
    }
    /// One-off left to pay: your items not yet ticked as paid — mirrors web one-off left pill.
    func oneOffLeft(_ mk: String) -> Double {
        let poo = month(mk)["paidOneOffs"]?.object ?? [:]
        var s = 0.0
        for o in month(mk).arr("oneOffs") where o["mumPays"]?.bool != true {
            if poo[idStr(o["id"])]?.bool != true { s += o.d("amount") }
        }
        return s
    }

    // MARK: Annual limit
    /// Current month number 1…12 for 2026 (0 before, 12 after) — mirrors cMN.
    var currentMonthNumber: Int {
        let now = Date()
        let y = cal.component(.year, from: now)
        if y == 2026 { return cal.component(.month, from: now) }
        return y > 2026 ? 12 : 0
    }
    /// Total earned across elapsed months (index < cMN).
    var earnedSoFar: Double {
        let n = currentMonthNumber
        return MONTHS.enumerated().filter { $0.offset < n }.reduce(0) { $0 + taxable($1.element.key) }
    }
    var roomLeft: Double { annualLimit - earnedSoFar }

    // MARK: Transactions (Passbook)
    func txns(_ mk: String) -> [JSONValue] { month(mk).arr("txns") }
    var totalTxns: Int { MONTHS.reduce(0) { $0 + txns($1.key).count } }
    func hasRealTxns(_ mk: String) -> Bool { !txns(mk).isEmpty }
    func outReal(_ mk: String) -> Double { txns(mk).filter { $0.s("direction") == "out" }.reduce(0) { $0 + $1.d("amount") } }
    /// Spending for the month: real imported transactions if present, else the budgeted estimate.
    func passbookOut(_ mk: String) -> Double { hasRealTxns(mk) ? outReal(mk) : spending(mk) }

    struct CatTotal: Identifiable { let cat: String; let total: Double; let count: Int; var id: String { cat } }
    func cats(_ mk: String) -> [CatTotal] {
        var m: [String: (Double, Int)] = [:]
        for t in txns(mk) where t.s("direction") == "out" {
            let k = t.s("category", "other"); let cur = m[k] ?? (0, 0)
            m[k] = (cur.0 + t.d("amount"), cur.1 + 1)
        }
        return m.map { CatTotal(cat: $0.key, total: $0.value.0, count: $0.value.1) }.sorted { $0.total > $1.total }
    }

    struct BudgetLine: Identifiable { let name: String; let amount: Double; let cat: String; var id: String { name } }
    func budgetLines(_ mk: String) -> [BudgetLine] {
        let d = month(mk); var out: [BudgetLine] = []
        for f in fixed {
            let amt = fixedAmount(f, mk)
            if amt > 0 { out.append(.init(name: f.s("name"), amount: amt, cat: f.b("sub") ? "subscriptions" : "bills")) }
        }
        let su = commute(mk); if su > 0 { out.append(.init(name: "SUICA / commute", amount: su, cat: "transport")) }
        let fd = food(mk); if fd > 0 { out.append(.init(name: "Food budget", amount: fd, cat: "food")) }
        if showSkin && skin(mk) > 0 { out.append(.init(name: "Skin treatment", amount: skin(mk), cat: "shopping")) }
        if showGenSav && genSav(mk) > 0 { out.append(.init(name: "General savings", amount: genSav(mk), cat: "savings")) }
        for o in d.arr("oneOffs") where o["mumPays"]?.bool != true { out.append(.init(name: o.s("name"), amount: o.d("amount"), cat: "other")) }
        return out
    }

    private var elapsedKeys: [String] { MONTHS.enumerated().filter { $0.offset < currentMonthNumber }.map { $0.element.key } }
    var passbookYearIn: Double { elapsedKeys.reduce(0) { $0 + monthlyPay($1) + extraIncome($1) } }
    var passbookYearOut: Double { elapsedKeys.reduce(0) { $0 + passbookOut($1) } }
}

/// Emoji + label for an imported-transaction category.
let TX_CATS: [String: (emoji: String, label: String)] = [
    "income": ("💰", "Income"), "food": ("🍜", "Food"), "transport": ("🚇", "Transport"),
    "subscriptions": ("🔁", "Subscriptions"), "shopping": ("🛍️", "Shopping"), "bills": ("📄", "Bills"),
    "savings": ("🏦", "Savings"), "investment": ("📈", "Investment"), "fees": ("⚠️", "Fees"),
    "transfer": ("↔︎", "Transfer"), "cash": ("💴", "Cash"), "other": ("•", "Other"),
]
func txCat(_ k: String) -> (emoji: String, label: String) { TX_CATS[k] ?? ("•", "Other") }

/// De-dup key for an imported transaction (mirrors the web txKey).
func txKey(_ t: JSONValue) -> String {
    "\(t.s("date"))|\(t.s("description").trimmingCharacters(in: .whitespaces))|\(t.d("amount"))|\(t.s("direction"))|\(t.s("ref"))"
}

/// Current month "YYYY-MM" clamped to a valid 2026 month (the app is 2026-only).
func currentMonthKeyClamped() -> String {
    let cal = Calendar.current
    let mk = String(format: "%04d-%02d", cal.component(.year, from: Date()), cal.component(.month, from: Date()))
    if monthMeta(mk) != nil { return mk }
    return mk < "2026-01" ? "2026-01" : "2026-12"
}

/// Format a USD amount ($ + 2 decimals).
func usd(_ n: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return "$" + (f.string(from: NSNumber(value: n)) ?? "0.00")
}

/// Format a yen amount like the web app (¥ + thousands separators, rounded).
func yen(_ n: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return "¥" + (f.string(from: NSNumber(value: n.rounded())) ?? "0")
}
