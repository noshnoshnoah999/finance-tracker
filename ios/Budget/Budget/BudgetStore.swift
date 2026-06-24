// BudgetStore.swift — Budget (iOS/Mac)
// Loads/saves the shared Supabase `finance_data` blob so iOS ⇄ web ⇄ cloud stay in sync.
// Same project + anon key + user_key as app.html, so both clients edit one blob.

import Foundation
import SwiftUI

@MainActor
final class BudgetStore: ObservableObject {
    @Published var blob: FinanceBlob = .empty
    @Published var syncState: String = "Local"
    @Published var loaded = false

    // Passbook AI UI state
    @Published var pbLoading = false
    @Published var pbMsg = ""
    @Published var pbErr = ""
    @Published var spendLoading = false
    @Published var spendErr = ""

    /// True from a local edit until its debounced push lands — guards against an older
    /// cloud copy stomping an un-pushed edit (same rule as NudgeStore).
    private var hasPendingPush = false
    private var pushTask: Task<Void, Never>?

    // Same Supabase project + anon key as the web app (anon key is public-tier).
    private let baseURL = "https://ipjwpkqcuztahumijici.supabase.co"
    private let anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlwandwa3FjdXp0YWh1bWlqaWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMTg0NjAsImV4cCI6MjA5MjU5NDQ2MH0.aCrIwHvNLkCtA_RXPdzIybRp2EMCrBeIVS5ABCtjl48"
    private let userKey = "f7e2a914-3b8c-4d5e-9a1f-6c2d7b0e8f3a"
    private let table = "finance_data"

    /// Vends the calculation engine over the current blob.
    var calc: Calc { Calc(se: blob.settings, data: blob.data) }
    var theme: String { blob.theme ?? "latte" }

    private var cacheURL: URL {
        AppPaths.file("budget_cache.json")
    }

    init() { loadCache() }

    // MARK: - Load
    private func loadCache() {
        if let d = try? Data(contentsOf: cacheURL),
           let b = try? JSONDecoder().decode(FinanceBlob.self, from: d) {
            blob = b
            loaded = true
        }
    }

    struct Row: Codable { var data: FinanceBlob }

    func refresh() async {
        guard let u = URL(string: "\(baseURL)/rest/v1/\(table)?user_key=eq.\(userKey)&select=data") else { return }
        var req = URLRequest(url: u)
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let rows = try JSONDecoder().decode([Row].self, from: data)
            if let b = rows.first?.data {
                if hasPendingPush || b == blob {
                    setSync("Synced")
                } else {
                    backupSnapshot("cloud")
                    blob = b
                    cache(b)
                    setSync("Synced")
                }
                loaded = true
            }
        } catch {
            setSync("Offline")
        }
    }

    /// Publish syncState only when it actually changes (avoid re-render churn / focus loss).
    private func setSync(_ s: String) { if syncState != s { syncState = s } }

    private func cache(_ b: FinanceBlob) {
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: cacheURL) }
    }

    // MARK: - Save (debounced upsert)
    struct Payload: Codable { var user_key: String; var data: FinanceBlob; var updated_at: String }

    func persist() {
        cache(blob)
        setSync("Syncing…")
        hasPendingPush = true
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            await self?.push()
        }
    }

    /// Immediate awaited push — for background work (notification actions) where iOS
    /// would suspend the app before the 700ms debounce fires.
    func persistNow() async {
        pushTask?.cancel()
        cache(blob)
        hasPendingPush = true
        await push()
    }

    private func push() async {
        defer { hasPendingPush = false }
        guard let u = URL(string: "\(baseURL)/rest/v1/\(table)") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        let payload = Payload(user_key: userKey, data: blob, updated_at: ISO8601DateFormatter().string(from: Date()))
        req.httpBody = try? JSONEncoder().encode(payload)
        do { _ = try await URLSession.shared.data(for: req); setSync("Synced") }
        catch { setSync("Offline") }
    }

    // MARK: - Mutations (lossless: mutate the JSON tree, never re-typed structs)
    /// Set settings.<key> = value and persist.
    func setSetting(_ key: String, _ value: JSONValue) {
        blob.settings[key] = value
        persist()
    }
    /// Edit one field of one weekday's shift (settings.shifts."1".start, etc.).
    func setShift(_ day: String, _ field: String, _ value: JSONValue) {
        var shifts = blob.settings["shifts"]?.object ?? [:]
        var sh = shifts[day]?.object ?? [:]
        sh[field] = value
        shifts[day] = .object(sh)
        blob.settings["shifts"] = .object(shifts)
        persist()
    }

    // Live GBP→JPY rate (Settings).
    @Published var fxLoading = false
    func fetchRate() async {
        fxLoading = true
        defer { fxLoading = false }
        guard let u = URL(string: "https://open.er-api.com/v6/latest/GBP") else { return }
        if let (d, _) = try? await URLSession.shared.data(from: u),
           let j = try? JSONDecoder().decode(JSONValue.self, from: d),
           let jpy = j["rates"]?["JPY"]?.double {
            setSetting("gbpToJpy", .number((jpy * 10).rounded() / 10))
        }
    }
    /// Set data.<monthKey>.<field> = value and persist.
    func setMonth(_ mk: String, _ field: String, _ value: JSONValue) {
        var m = blob.data[mk] ?? .object([:])
        m[field] = value
        blob.data[mk] = m
        persist()
    }

    /// Flip a boolean inside a month map field (paidFixed / skippedFixed / paidOneOffs / subInc).
    func toggleBoolMap(_ mk: String, _ field: String, _ key: String) {
        var m = blob.data[mk] ?? .object([:])
        var map = m[field]?.object ?? [:]
        map[key] = .bool(!(map[key]?.bool ?? false))
        m[field] = .object(map)
        blob.data[mk] = m
        persist()
    }
    /// Set a number inside a month map field (fixedAmounts).
    func setNumberMap(_ mk: String, _ field: String, _ key: String, _ v: Double) {
        var m = blob.data[mk] ?? .object([:])
        var map = m[field]?.object ?? [:]
        map[key] = .number(v)
        m[field] = .object(map)
        blob.data[mk] = m
        persist()
    }
    /// Toggle membership of an id in a month array field (mumChecked).
    func toggleArrayMember(_ mk: String, _ field: String, _ id: String) {
        var m = blob.data[mk] ?? .object([:])
        var arr = m[field]?.array ?? []
        if let idx = arr.firstIndex(where: { $0.string == id }) { arr.remove(at: idx) } else { arr.append(.string(id)) }
        m[field] = .array(arr)
        blob.data[mk] = m
        persist()
    }
    /// Set a month-level override that can be null (suicaOverride / foodOverride). Pass nil to clear.
    func setMonthNullable(_ mk: String, _ field: String, _ v: Double?) {
        var m = blob.data[mk] ?? .object([:])
        m[field] = v == nil ? .null : .number(v!)
        blob.data[mk] = m
        persist()
    }

    // MARK: One-offs
    func addOneOff(_ mk: String, name: String, amount: Double) {
        var m = blob.data[mk] ?? .object([:])
        var arr = m["oneOffs"]?.array ?? []
        let id = "o" + String(UUID().uuidString.prefix(12))
        arr.append(.object(["id": .string(id), "name": .string(name), "amount": .number(amount), "mumPays": .bool(false)]))
        m["oneOffs"] = .array(arr)
        blob.data[mk] = m
        persist()
    }
    func removeOneOff(_ mk: String, _ id: String) {
        let c = calc
        var m = blob.data[mk] ?? .object([:])
        var arr = m["oneOffs"]?.array ?? []
        arr.removeAll { c.idStr($0["id"]) == id }
        m["oneOffs"] = .array(arr)
        blob.data[mk] = m
        persist()
    }
    // MARK: Dad's contributions (per-month £ items; "free" flags are global)
    func addDadItem(_ mk: String, note: String, gbp: Double) {
        var m = blob.data[mk] ?? .object([:])
        var arr = m["dadItems"]?.array ?? []
        let id = "d" + String(UUID().uuidString.prefix(12))
        arr.append(.object(["id": .string(id), "note": .string(note.isEmpty ? "Dad" : note), "gbp": .number(gbp)]))
        m["dadItems"] = .array(arr); blob.data[mk] = m; persist()
    }
    func removeDadItem(_ mk: String, _ id: String) {
        let c = calc
        var m = blob.data[mk] ?? .object([:])
        var arr = m["dadItems"]?.array ?? []
        arr.removeAll { c.idStr($0["id"]) == id }
        m["dadItems"] = .array(arr); blob.data[mk] = m; persist()
    }
    func updateDadItem(_ mk: String, _ id: String, note: String? = nil, gbp: Double? = nil) {
        let c = calc
        var m = blob.data[mk] ?? .object([:])
        let arr = (m["dadItems"]?.array ?? []).map { o -> JSONValue in
            guard c.idStr(o["id"]) == id else { return o }
            var oo = o.object ?? [:]
            if let note { oo["note"] = .string(note) }
            if let gbp { oo["gbp"] = .number(gbp) }
            return .object(oo)
        }
        m["dadItems"] = .array(arr); blob.data[mk] = m; persist()
    }
    func toggleDadFree(_ id: String) {
        var fs = blob.settings["dadFreeSpend"]?.object ?? [:]
        fs[id] = .bool(!(fs[id]?.bool ?? false))
        blob.settings["dadFreeSpend"] = .object(fs); persist()
    }
    func toggleOneOffMum(_ mk: String, _ id: String) {
        let c = calc
        var m = blob.data[mk] ?? .object([:])
        let arr = (m["oneOffs"]?.array ?? []).map { o -> JSONValue in
            guard c.idStr(o["id"]) == id else { return o }
            var oo = o.object ?? [:]
            oo["mumPays"] = .bool(!(o["mumPays"]?.bool ?? false))
            return .object(oo)
        }
        m["oneOffs"] = .array(arr)
        blob.data[mk] = m
        persist()
    }

    // MARK: Goals (settings.goals array)
    private func updateGoal(_ id: String, _ f: ([String: JSONValue]) -> [String: JSONValue]) {
        let c = calc
        let goals = (blob.settings["goals"]?.array ?? []).map { g -> JSONValue in
            c.idStr(g["id"]) == id ? .object(f(g.object ?? [:])) : g
        }
        blob.settings["goals"] = .array(goals)
        persist()
    }
    func addGoal(name: String, target: Double, monthly: Double) {
        var goals = blob.settings["goals"]?.array ?? []
        let id = "g" + String(UUID().uuidString.prefix(12))
        goals.append(.object(["id": .string(id), "name": .string(name), "target": .number(target),
                              "saved": .number(0), "monthly": .number(monthly), "items": .array([])]))
        blob.settings["goals"] = .array(goals)
        persist()
    }
    func removeGoal(_ id: String) {
        let c = calc
        var goals = blob.settings["goals"]?.array ?? []
        goals.removeAll { c.idStr($0["id"]) == id }
        blob.settings["goals"] = .array(goals)
        persist()
    }
    func setGoalNumber(_ id: String, _ field: String, _ v: Double) {
        updateGoal(id) { var o = $0; o[field] = .number(v); return o }
    }
    func addGoalItem(_ goalId: String, name: String, price: Double, url: String) {
        updateGoal(goalId) { o in
            var oo = o
            var items = oo["items"]?.array ?? []
            let iid = "i" + String(UUID().uuidString.prefix(12))
            var item: [String: JSONValue] = ["id": .string(iid), "name": .string(name), "price": .number(price)]
            if !url.isEmpty { item["url"] = .string(url) }
            items.append(.object(item))
            oo["items"] = .array(items)
            return oo
        }
    }
    func removeGoalItem(_ goalId: String, _ itemId: String) {
        let c = calc
        updateGoal(goalId) { o in
            var oo = o
            var items = oo["items"]?.array ?? []
            items.removeAll { c.idStr($0["id"]) == itemId }
            oo["items"] = .array(items)
            return oo
        }
    }

    // MARK: Calendar day cycling (mirrors the web toggleDay)
    func toggleDay(_ mk: String, _ ds: String, _ y: Int, _ mo: Int, _ d: Int) {
        let c = calc
        let isPL = PAID_LEAVE.contains(ds)
        var m = blob.data[mk] ?? .object([:])
        var cd = m["customDays"]?.object ?? [:]
        let state = c.dayState(ds, y, mo, d, .object(cd))
        let isSched = c.isScheduled(y, mo, d)
        var next: String?
        if state == "work" && isSched { next = "hol" }
        else if state == "work" && !isSched { next = isPL ? "hol" : nil }
        else if state == "hol" { next = "pl" }
        else if state == "pl" { next = "off" }
        else if state == "off" { next = isPL ? "work" : nil }
        else if state == "none" { next = "work" }
        if let n = next { cd[ds] = .string(n) } else { cd[ds] = nil }
        m["customDays"] = .object(cd)
        // Keep the stored work-day count in sync with the calendar (drives transport).
        var wd = 0
        for dd in 1...c.daysIn(mk) {
            let dsi = String(format: "%04d-%02d-%02d", y, mo, dd)
            if c.dayState(dsi, y, mo, dd, .object(cd)) == "work" { wd += 1 }
        }
        m["days"] = .number(Double(wd))
        blob.data[mk] = m
        persist()
    }

    // MARK: - Settings arrays (fixed expenses, Subscribe & Save items)
    func addFixed(name: String, amount: Double, variable: Bool) {
        var arr = blob.settings["fixed"]?.array ?? []
        let id = "f" + String(UUID().uuidString.prefix(12))
        var o: [String: JSONValue] = ["id": .string(id), "name": .string(name), "amount": .number(amount)]
        if variable { o["variable"] = .bool(true) }
        arr.append(.object(o))
        blob.settings["fixed"] = .array(arr)
        persist()
    }
    func removeFixed(_ id: String) {
        let c = calc
        var arr = blob.settings["fixed"]?.array ?? []
        arr.removeAll { c.idStr($0["id"]) == id }
        blob.settings["fixed"] = .array(arr)
        persist()
    }
    func updateFixed(_ id: String, name: String? = nil, amount: Double? = nil, variable: Bool? = nil) {
        let c = calc
        let arr = (blob.settings["fixed"]?.array ?? []).map { f -> JSONValue in
            guard c.idStr(f["id"]) == id else { return f }
            var o = f.object ?? [:]
            if let name { o["name"] = .string(name) }
            if let amount { o["amount"] = .number(amount) }
            if let variable { o["variable"] = .bool(variable) }
            return .object(o)
        }
        blob.settings["fixed"] = .array(arr)
        persist()
    }
    func addSubItem(name: String, price: Double, everyN: Int) {
        var arr = blob.settings["subItems"]?.array ?? []
        let id = "s" + String(UUID().uuidString.prefix(12))
        arr.append(.object(["id": .string(id), "name": .string(name), "price": .number(price),
                            "everyN": .number(Double(everyN)), "startMK": .string(currentMonthKeyClamped()), "payer": .string("me")]))
        blob.settings["subItems"] = .array(arr)
        persist()
    }
    func removeSubItem(_ id: String) {
        let c = calc
        var arr = blob.settings["subItems"]?.array ?? []
        arr.removeAll { c.idStr($0["id"]) == id }
        blob.settings["subItems"] = .array(arr)
        persist()
    }
    /// Edit a Subscribe & Save item's name / price / delivery frequency / payer.
    /// Only non-nil arguments are changed (mirrors the web `uSub`).
    func updateSubItem(_ id: String, name: String? = nil, price: Double? = nil, everyN: Int? = nil, payer: String? = nil) {
        let c = calc
        var arr = blob.settings["subItems"]?.array ?? []
        arr = arr.map { item in
            guard c.idStr(item["id"]) == id, var obj = item.object else { return item }
            if let name = name { obj["name"] = .string(name) }
            if let price = price { obj["price"] = .number(price) }
            if let everyN = everyN { obj["everyN"] = .number(Double(everyN)) }
            if let payer = payer { obj["payer"] = .string(payer) }
            return .object(obj)
        }
        blob.settings["subItems"] = .array(arr)
        persist()
    }
    /// Per-month include override for a S&S item (the budget-tab tick). Writes the
    /// explicit boolean into that month's `subInc` map, same as the web `tSubInc`.
    func setSubInc(_ mk: String, _ id: String, _ included: Bool) {
        var m = blob.data[mk] ?? .object([:])
        var map = m["subInc"]?.object ?? [:]
        map[id] = .bool(included)
        m["subInc"] = .object(map)
        blob.data[mk] = m
        persist()
    }

    // MARK: - Passbook AI (upload → analyse → bucket into months; same edge function as the web)
    func budgetContextString() -> String {
        let c = calc
        let fixed = c.fixed.map { "\($0.s("name")) ¥\(Int($0.d("amount")))" }.joined(separator: ", ")
        let subs = c.subItems.map { "\($0.s("name")) ¥\(Int($0.d("price")))" }.joined(separator: ", ")
        let mum = c.se.arr("mumItems").map { "\($0.s("name")) ¥\(Int($0.d("amount")))" }.joined(separator: ", ")
        return "Fixed expenses: \(fixed)\nSubscribe & Save: \(subs)\nMum repayments: \(mum)\nHourly wage ¥\(Int(c.hourlyWage)), monthly silver investing in USD."
    }
    private func callAnalyze(_ body: [String: JSONValue]) async throws -> JSONValue {
        guard let u = URL(string: "\(baseURL)/functions/v1/analyze-passbook") else { throw URLError(.badURL) }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 150
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(JSONValue.self, from: data)
        if let e = resp["error"]?.string { throw NSError(domain: "fn", code: 1, userInfo: [NSLocalizedDescriptionKey: e]) }
        return resp["data"] ?? .object([:])
    }

    // Limit page — Claude shift advisor (limit-advisor edge function).
    struct LimitAdvice { var verdict: String; var headline: String; var reasoning: String; var suggestions: [String] }
    func limitAdvice(_ ctx: [String: JSONValue]) async throws -> LimitAdvice {
        guard let u = URL(string: "\(baseURL)/functions/v1/limit-advisor") else { throw URLError(.badURL) }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(JSONValue.object(ctx))
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(JSONValue.self, from: data)
        if let e = resp["error"]?.string { throw NSError(domain: "fn", code: 1, userInfo: [NSLocalizedDescriptionKey: e]) }
        let d = resp["data"] ?? .object([:])
        return LimitAdvice(
            verdict: d["verdict"]?.string ?? "yes",
            headline: d["headline"]?.string ?? "",
            reasoning: d["reasoning"]?.string ?? "",
            suggestions: (d["suggestions"]?.array ?? []).compactMap { $0.string }
        )
    }
    /// Import up to 5 passbook files: analyse each, bucket transactions into their months
    /// (de-duped), and stash the latest AI insights.
    func analyzePassbooks(_ files: [(data: Data, type: String)]) async {
        let picked = Array(files.prefix(5))
        guard !picked.isEmpty else { return }
        pbErr = ""; pbMsg = ""; pbLoading = true
        var combined: [JSONValue] = []
        var errs: [String] = []
        var last: JSONValue? = nil
        for (i, f) in picked.enumerated() {
            do {
                let d = try await callAnalyze(["fileBase64": .string(f.data.base64EncodedString()),
                                               "mediaType": .string(f.type),
                                               "budgetContext": .string(budgetContextString())])
                last = d
                if let txs = d["transactions"]?.array { combined.append(contentsOf: txs) }
            } catch { errs.append("file \(i + 1): \(error.localizedDescription)") }
        }
        // Bucket into months (2026 only), de-dup vs stored AND within the batch.
        var added = 0; var months = Set<String>()
        var byM: [String: [JSONValue]] = [:]
        for t in combined {
            let mk = String((t["date"]?.string ?? "").prefix(7))
            guard monthMeta(mk) != nil else { continue }
            byM[mk, default: []].append(t)
        }
        for (mk, txs) in byM {
            guard var m = blob.data[mk]?.object else { continue }   // only known 2026 months
            var existing = m["txns"]?.array ?? []
            var seen = Set(existing.map { txKey($0) })
            for t in txs where !seen.contains(txKey(t)) { seen.insert(txKey(t)); existing.append(t); added += 1; months.insert(mk) }
            m["txns"] = .array(existing)
            blob.data[mk] = .object(m)
        }
        if let last { stashInsights(last) }
        if added > 0 { persist() }
        let ok = picked.count - errs.count
        if ok == 0 { pbErr = errs.first ?? "Couldn't read the passbook." }
        else {
            var msg = added > 0 ? "Imported \(added) transaction\(added == 1 ? "" : "s") across \(months.count) month\(months.count == 1 ? "" : "s")" : "No new transactions (already imported)"
            if picked.count > 1 { msg += " · \(ok) of \(picked.count) read" }
            pbMsg = msg + "."
        }
        pbLoading = false
    }

    /// Pull Sony Bank WALLET transaction emails (Gmail label) via the import-bank-emails
    /// edge function and merge them into months (same dedup as the passbook importer).
    func importBankEmails() async {
        pbErr = ""; pbMsg = ""; pbLoading = true
        do {
            guard let u = URL(string: "\(baseURL)/functions/v1/import-bank-emails") else { throw URLError(.badURL) }
            var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 60
            req.setValue(anon, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(JSONValue.object(["sinceDays": .number(120)]))
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(JSONValue.self, from: data)
            if let e = resp["error"]?.string { throw NSError(domain: "fn", code: 1, userInfo: [NSLocalizedDescriptionKey: e]) }
            let combined = resp["transactions"]?.array ?? []
            var added = 0; var months = Set<String>(); var byM: [String: [JSONValue]] = [:]
            for t in combined {
                let mk = String((t["date"]?.string ?? "").prefix(7))
                guard monthMeta(mk) != nil else { continue }
                byM[mk, default: []].append(t)
            }
            for (mk, txs) in byM {
                guard var m = blob.data[mk]?.object else { continue }
                var existing = m["txns"]?.array ?? []
                var seen = Set(existing.map { txKey($0) })
                for t in txs where !seen.contains(txKey(t)) { seen.insert(txKey(t)); existing.append(t); added += 1; months.insert(mk) }
                m["txns"] = .array(existing)
                blob.data[mk] = .object(m)
            }
            if added > 0 { persist() }
            pbMsg = added > 0
                ? "Imported \(added) bank transaction\(added == 1 ? "" : "s") across \(months.count) month\(months.count == 1 ? "" : "s"). (\(combined.count) scanned)"
                : "No new bank transactions (\(combined.count) scanned, already imported)."
        } catch { pbErr = "Bank email import failed: \(error.localizedDescription)" }
        pbLoading = false
    }
    /// On-demand cross-month insights over all stored transactions (edge-function Mode B).
    func analyzeSpending() async {
        var all: [JSONValue] = []
        for mo in MONTHS { all.append(contentsOf: calc.txns(mo.key)) }
        guard !all.isEmpty else { spendErr = "Import a passbook first — then I can analyse your spending."; return }
        spendErr = ""; spendLoading = true
        do {
            let d = try await callAnalyze(["transactions": .array(all), "budgetContext": .string(budgetContextString())])
            stashInsights(d)
            persist()
        } catch { spendErr = error.localizedDescription }
        spendLoading = false
    }
    private func stashInsights(_ d: JSONValue) {
        var ins: [String: JSONValue] = [:]
        for k in ["categories", "recurring", "anomalies", "budget_matches", "suggestions", "insights", "summary"] {
            ins[k] = d[k] ?? (k == "summary" ? .object([:]) : .array([]))
        }
        ins["at"] = .number(Date().timeIntervalSince1970)
        blob.settings["spendInsights"] = .object(ins)
    }

    // MARK: - Backups (rotating local snapshots, keep 60, throttle 10 min)
    private lazy var backupDir: URL = {
        let d = AppPaths.file("backups")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    var lastBackup: (date: Date, count: Int)? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]),
              !files.isEmpty else { return nil }
        let dates = files.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let newest = dates.max() else { return nil }
        return (newest, files.count)
    }

    func backupSnapshot(_ reason: String = "auto", force: Bool = false) {
        guard !(blob.data.object?.isEmpty ?? true) else { return }
        if !force, let last = lastBackup?.date, Date().timeIntervalSince(last) < 600 { return }
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDir.appendingPathComponent("budget_\(reason)_\(ts).json")
        guard let d = try? JSONEncoder().encode(blob) else { return }
        try? d.write(to: url)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            for old in sorted.dropFirst(60) { try? FileManager.default.removeItem(at: old) }
        }
    }
}
