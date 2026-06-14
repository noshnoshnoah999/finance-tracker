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
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("budget_cache.json")
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
        blob.data[mk] = m
        persist()
    }

    // MARK: - Backups (rotating local snapshots, keep 60, throttle 10 min)
    private lazy var backupDir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
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
