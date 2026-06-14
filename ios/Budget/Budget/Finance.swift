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
    var showSkin: Bool { se["showSkin"]?.bool != false }
    var showGenSav: Bool { se["showGenSav"]?.bool != false }
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
    func shifts(_ mk: String) -> [String: JSONValue] {
        let base = se["shifts"]?.object ?? [:]
        let ov = month(mk)["shiftOverrides"]?.object ?? [:]
        var r: [String: JSONValue] = [:]
        for (k, v) in base {
            if let o = ov[k]?.object {
                var merged = v.object ?? [:]
                for (kk, vv) in o { merged[kk] = vv }
                r[k] = .object(merged)
            } else { r[k] = v }
        }
        return r
    }

    // MARK: Paid leave hours in a month
    func plHours(_ mk: String) -> Double {
        let (y, m) = ym(mk)
        let cd = month(mk)["customDays"] ?? .object([:])
        let sh = shifts(mk)
        var h = 0.0
        for d in 1...daysInMonth(y, m) where dayState(dstr(y, m, d), y, m, d, cd) == "pl" {
            if let s = sh[String(jsDay(y, m, d))] { h += shiftHours(s) }
        }
        return h
    }

    // MARK: Wage / transport / taxable
    func transportRate(_ mk: String) -> Double { mk <= "2026-03" ? se.d("trBefore", DS.trBefore) : se.d("trAfter", DS.trAfter) }

    func wage(_ mk: String) -> Double {
        let d = month(mk)
        return d.d("hours") > 0 ? (d.d("hours") * hourlyWage).rounded() : d.d("wageOverride")
    }
    func transport(_ mk: String) -> Double { month(mk).d("days") * transportRate(mk) }

    func prevMK(_ mk: String) -> String? {
        guard let i = MONTHS.firstIndex(where: { $0.key == mk }), i > 0 else { return nil }
        return MONTHS[i - 1].key
    }
    /// Taxable income for a month = this month's wage + last month's paid leave (paid in arrears).
    func taxable(_ mk: String) -> Double {
        var pl = 0.0
        if month(mk).d("hours") > 0, let p = prevMK(mk) { pl = plHours(p) }
        return wage(mk) + (pl * hourlyWage).rounded()
    }
    /// Paid-leave yen credited into this month's paycheck (for display).
    func paidLeaveYen(_ mk: String) -> Double {
        guard month(mk).d("hours") > 0, let p = prevMK(mk) else { return 0 }
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

    // MARK: Food
    func food(_ mk: String) -> Double {
        let d = month(mk)
        if let ov = d["foodOverride"]?.double, d["foodOverride"] != .null { return ov }
        return (monthMeta(mk)?.is5wk ?? false) ? se.d("food5wk", DS.food5wk) : se.d("food4wk", DS.food4wk)
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

    // MARK: Fixed expenses
    func fixedAmount(_ f: JSONValue, _ mk: String) -> Double {
        if f.b("sub") { return subTotal(mk) }
        if f.b("variable") { return month(mk)["fixedAmounts"]?[idStr(f["id"])]?.double ?? 0 }
        return f.d("amount")
    }

    // MARK: Month roll-ups (mirror the Home/Budget computeds)
    var monthlyPay: (String) -> Double { { self.taxable($0) + self.transport($0) } }

    func dadFree(_ mk: String) -> Double {
        let free = se["dadFreeSpend"]?.object ?? [:]
        return month(mk).arr("dadItems")
            .filter { free[idStr($0["id"])]?.bool == true }
            .reduce(0) { $0 + ($1.d("gbp") * gbpToJpy).rounded() }
    }
    func skin(_ mk: String) -> Double { showSkin ? month(mk).d("skinTreatment") : 0 }
    func genSav(_ mk: String) -> Double { showGenSav ? month(mk).d("generalSavings") : 0 }

    /// Total budgeted spending for a month, excluding skipped fixed lines (mirror cmSpending).
    func spending(_ mk: String) -> Double {
        let d = month(mk)
        let skipped = d["skippedFixed"]?.object ?? [:]
        var s = 0.0
        for f in fixed where skipped[idStr(f["id"])]?.bool != true { s += fixedAmount(f, mk) }
        s += commute(mk) + food(mk) + skin(mk) + genSav(mk)
        for o in d.arr("oneOffs") where o["mumPays"]?.bool != true { s += o.d("amount") }
        return s
    }
    func income(_ mk: String) -> Double { monthlyPay(mk) + dadFree(mk) }
    func freeToSpend(_ mk: String) -> Double { income(mk) - spending(mk) }

    /// Bills (ids) shown on the Home progress, excluding skipped and zero skin/savings.
    func homeBillIds(_ mk: String) -> [String] {
        let d = month(mk)
        let skipped = d["skippedFixed"]?.object ?? [:]
        var ids = fixed.filter { skipped[idStr($0["id"])]?.bool != true }.map { idStr($0["id"]) }
        ids += ["suica", "food"]
        if showSkin && skin(mk) > 0 { ids.append("skinTreatment") }
        if showGenSav && genSav(mk) > 0 { ids.append("generalSavings") }
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
        return u
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
}

/// Format a yen amount like the web app (¥ + thousands separators, rounded).
func yen(_ n: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return "¥" + (f.string(from: NSNumber(value: n.rounded())) ?? "0")
}
