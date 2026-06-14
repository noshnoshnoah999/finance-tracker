// Models.swift — Budget (iOS/Mac)
// The web app (app.html) OWNS and actively evolves the Supabase `finance_data` blob.
// To stay forward-compatible and never drop a field the web side writes, we keep the
// whole blob as a lossless JSONValue tree and read it through typed accessors. Native
// edits mutate the tree in place, so unknown keys round-trip untouched.

import Foundation

// MARK: - Lossless JSON tree

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // Bool MUST be tried before Double — Foundation backs JSON booleans with
        // NSNumber, and decode(Double) on a JSON `true` would wrongly yield 1.0.
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: Read accessors (lenient, like the JS `||` fallbacks)
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var int: Int? { double.map { Int($0.rounded()) } }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return nil
        }
    }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    func d(_ key: String, _ def: Double = 0) -> Double { self[key]?.double ?? def }
    func i(_ key: String, _ def: Int = 0) -> Int { self[key]?.int ?? def }
    func s(_ key: String, _ def: String = "") -> String { self[key]?.string ?? def }
    func b(_ key: String, _ def: Bool = false) -> Bool { self[key]?.bool ?? def }
    func arr(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }

    subscript(_ key: String) -> JSONValue? {
        get { if case .object(let o) = self { return o[key] }; return nil }
        set {
            var o = object ?? [:]
            o[key] = newValue
            self = .object(o)
        }
    }
    subscript(_ index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    // Convenience constructors for writing back.
    static func of(_ v: Double) -> JSONValue { .number(v) }
    static func of(_ v: Int) -> JSONValue { .number(Double(v)) }
    static func of(_ v: String) -> JSONValue { .string(v) }
    static func of(_ v: Bool) -> JSONValue { .bool(v) }
}

// MARK: - The blob row

/// One row of `finance_data`: { settings: {...}, data: { "2026-01": {...}, ... }, theme: "latte" }
struct FinanceBlob: Codable, Equatable {
    var settings: JSONValue
    var data: JSONValue
    var theme: String?

    static let empty = FinanceBlob(settings: .object([:]), data: .object([:]), theme: "latte")

    /// Month keys present in `data`, chronological (they're "YYYY-MM" so string sort works).
    var monthKeys: [String] { (data.object?.keys).map { $0.sorted() } ?? [] }
}

// MARK: - The 12 months of 2026 (mirrors MONTHS in app.html)

struct MonthMeta: Identifiable {
    let key: String      // "2026-06"
    let label: String    // "June"
    let short: String    // "Jun"
    let is5wk: Bool
    var id: String { key }
}

let MONTHS: [MonthMeta] = [
    .init(key: "2026-01", label: "January",   short: "Jan", is5wk: false),
    .init(key: "2026-02", label: "February",  short: "Feb", is5wk: false),
    .init(key: "2026-03", label: "March",     short: "Mar", is5wk: true),
    .init(key: "2026-04", label: "April",     short: "Apr", is5wk: false),
    .init(key: "2026-05", label: "May",       short: "May", is5wk: false),
    .init(key: "2026-06", label: "June",      short: "Jun", is5wk: true),
    .init(key: "2026-07", label: "July",      short: "Jul", is5wk: false),
    .init(key: "2026-08", label: "August",    short: "Aug", is5wk: true),
    .init(key: "2026-09", label: "September", short: "Sep", is5wk: false),
    .init(key: "2026-10", label: "October",   short: "Oct", is5wk: false),
    .init(key: "2026-11", label: "November",  short: "Nov", is5wk: true),
    .init(key: "2026-12", label: "December",  short: "Dec", is5wk: false),
]

func monthMeta(_ key: String) -> MonthMeta? { MONTHS.first { $0.key == key } }

/// Default settings fallbacks (mirror DS in app.html) — used when a field is absent.
enum DS {
    static let hourlyWage = 1400.0
    static let annualLimit = 1_030_000.0
    static let commuteOneWay = 178.0
    static let trBefore = 1040.0
    static let trAfter = 1100.0
    static let food4wk = 20000.0
    static let food5wk = 25000.0
    static let gbpToJpy = 215.0
    static let usdToJpy = 155.0
    static let workDays = [0, 1, 2]   // Sun, Mon, Tue
}

/// Paid-leave dates (mirror PAID_LEAVE in app.html).
let PAID_LEAVE: Set<String> = ["2026-05-24", "2026-05-25", "2026-05-31", "2026-06-01", "2026-06-07"]
