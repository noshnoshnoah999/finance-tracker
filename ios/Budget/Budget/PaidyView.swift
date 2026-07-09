// PaidyView.swift — Budget (iOS/Mac)
// Tracks Apple Paidy installment plans (mirror of the web app's Paidy tab).
// Reads/writes settings.paidyPlans on the shared blob so iOS ⇄ web ⇄ cloud stay in sync.
// The Fixed Expenses "Paidy" line is DERIVED from these plans (see Calc.paidyMonthly),
// so there is a single source of truth for the monthly Paidy cost — no double-counting.

import SwiftUI

struct PaidyView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var editingId: String? = nil

    // Add-plan form state
    @State private var nName = ""
    @State private var nFinanced = ""
    @State private var nInstall = ""
    @State private var nMonthly = ""
    @State private var nPaid = ""
    @State private var nStartMonth = 0   // 0 = unset
    @State private var nStartYear = ""
    @State private var nDay = "27"

    var body: some View {
        let c = store.calc
        let plans = c.paidyPlans
        let states = plans.map { c.paidyCalc($0) }
        let totBal = states.reduce(0) { $0 + $1.remainingBal }
        let totMo = states.filter { !$0.done }.reduce(0) { $0 + $1.monthly }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Summary header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total remaining Paidy debt").font(.caption).foregroundStyle(T.sub)
                    Text(yen(totBal)).font(.system(size: 30, weight: .bold)).foregroundStyle(T.text)
                    HStack { Text("Combined monthly").foregroundStyle(T.sub); Spacer(); Text(yen(totMo)).fontWeight(.bold).foregroundStyle(T.text) }.font(.footnote)
                    HStack { Text("Next payment").foregroundStyle(T.sub); Spacer(); Text(c.paidyNextPayLabel()).fontWeight(.bold).foregroundStyle(T.text) }.font(.footnote)
                }
                .card()

                // Per-plan cards
                ForEach(Array(plans.enumerated()), id: \.offset) { idx, p in
                    planCard(c, p, states[idx])
                }

                // Add-plan form
                addPlanForm(c)
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .navigationTitle("Paidy")
        .refreshable { await store.refresh() }
        .keyboardDoneBar()
    }

    // MARK: Plan card
    @ViewBuilder private func planCard(_ c: Calc, _ p: JSONValue, _ s: Calc.PaidyState) -> some View {
        let id = c.idStr(p["id"])
        let editing = editingId == id
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.s("name")).font(.headline).foregroundStyle(T.text)
                if s.done { Text("PAID OFF").font(.caption2).fontWeight(.semibold).foregroundStyle(T.greenD) }
                Spacer()
                Button(editing ? "Done" : "Edit") { editingId = editing ? nil : id }
                    .font(.caption).fontWeight(.semibold).foregroundStyle(editing ? .white : T.sub)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(editing ? T.greenD : T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                Button { store.removePaidyPlan(id) } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.plain).foregroundStyle(T.roseD)
            }
            ProgressBar(fraction: s.installments > 0 ? Double(s.paid) / Double(s.installments) : 0, color: s.done ? T.greenD : T.accent)
            HStack(spacing: 6) {
                Text("\(s.paid) / \(s.installments) payments · \(s.pct)%").foregroundStyle(T.sub)
                Text(s.isAuto ? "auto" : "manual").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(s.isAuto ? T.greenD : T.peachD)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(s.isAuto ? T.greenBg : T.peachBg).clipShape(Capsule())
                Spacer()
                Text("\(s.remainingInst) left").foregroundStyle(T.sub)
            }.font(.caption)
            infoRow("Monthly", yen(s.monthly))
            infoRow("Remaining balance", yen(s.remainingBal))
            infoRow("Financed total", yen(s.financed))
            infoRow("Projected payoff", s.payoffLabel)

            if editing { editFields(c, p, id) }
        }
        .card()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(T.sub); Spacer(); Text(value).fontWeight(.semibold).foregroundStyle(T.text) }
            .font(.footnote).padding(.vertical, 2)
    }

    // MARK: Inline edit fields
    @ViewBuilder private func editFields(_ c: Calc, _ p: JSONValue, _ id: String) -> some View {
        Divider().overlay(T.border).padding(.vertical, 4)
        VStack(spacing: 8) {
            TextField("Name", text: Binding(
                get: { p.s("name") },
                set: { store.updatePaidyPlan(id, name: $0) })).modifier(FieldStyle())
            HStack(spacing: 8) {
                labeledField("Financed ¥") {
                    TextField("0", text: numBinding(p, "financedAmount") { store.updatePaidyPlan(id, financedAmount: $0) }).keyboardType(.numberPad)
                }
                labeledField("Monthly ¥") {
                    TextField("0", text: numBinding(p, "monthlyPayment") { store.updatePaidyPlan(id, monthlyPayment: $0) }).keyboardType(.numberPad)
                }
            }
            HStack(spacing: 8) {
                labeledField("Installments") {
                    TextField("0", text: intBinding(p, "installments") { store.updatePaidyPlan(id, installments: $0) }).keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(p["paidCountOverride"] == nil || p["paidCountOverride"] == .null ? "Payments made (auto)" : "Payments made (manual)")
                            .font(.caption2).foregroundStyle(T.sub)
                        Spacer()
                        if let ov = p["paidCountOverride"], ov != .null {
                            Button("↻ auto") { store.updatePaidyPlan(id, paidCountOverride: .some(nil)) }
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(T.greenD).buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub).opacity(0); TextField("auto", text: intOptBinding(p, "paidCountOverride") { store.updatePaidyPlan(id, paidCountOverride: .some($0)) }).keyboardType(.numberPad) }.modifier(FieldStyle())
                }
            }
            Text("“Payments made” = a count (how many times you’ve paid), not ¥. Blank = auto-calc.")
                .font(.caption2).foregroundStyle(T.muted).frame(maxWidth: .infinity, alignment: .leading)
            Text("Start of plan").font(.caption).fontWeight(.semibold).foregroundStyle(T.sub).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { p.i("startMonth", 0) },
                    set: { store.updatePaidyPlan(id, startMonth: .some($0 == 0 ? nil : $0)) })) {
                        Text("Month").tag(0)
                        ForEach(1...12, id: \.self) { Text(MO_SHORT[$0 - 1]).tag($0) }
                    }.pickerStyle(.menu).tint(T.text).frame(maxWidth: .infinity, alignment: .leading)
                TextField("Year", text: intOptBinding(p, "startYear") { store.updatePaidyPlan(id, startYear: .some($0)) }).keyboardType(.numberPad).modifier(FieldStyle()).frame(width: 80)
            }
            HStack(spacing: 8) {
                Text("Payment day of month").font(.caption).foregroundStyle(T.sub)
                Spacer()
                TextField("27", text: intBinding(p, "paymentDay") { store.updatePaidyPlan(id, paymentDay: $0) }).keyboardType(.numberPad).multilineTextAlignment(.center).modifier(FieldStyle()).frame(width: 64)
            }
        }
    }

    // MARK: Add-plan form
    @ViewBuilder private func addPlanForm(_ c: Calc) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a Paidy plan").font(.subheadline).fontWeight(.semibold).foregroundStyle(T.text)
            TextField("Name (e.g. iPad Pro)", text: $nName).modifier(FieldStyle())
            HStack(spacing: 8) {
                TextField("Financed ¥", text: $nFinanced).keyboardType(.numberPad).modifier(FieldStyle())
                TextField("Monthly ¥", text: $nMonthly).keyboardType(.numberPad).modifier(FieldStyle())
            }
            HStack(spacing: 8) {
                TextField("Installments", text: $nInstall).keyboardType(.numberPad).modifier(FieldStyle())
                TextField("Paid so far", text: $nPaid).keyboardType(.numberPad).modifier(FieldStyle())
            }
            Text("“Payments made” = how many times you’ve paid (a count, not ¥). Blank = auto-calc.")
                .font(.caption2).foregroundStyle(T.muted).frame(maxWidth: .infinity, alignment: .leading)
            Text("Start of plan").font(.caption).fontWeight(.semibold).foregroundStyle(T.sub).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Picker("", selection: $nStartMonth) {
                    Text("Month").tag(0)
                    ForEach(1...12, id: \.self) { Text(MO_SHORT[$0 - 1]).tag($0) }
                }.pickerStyle(.menu).tint(T.text).frame(maxWidth: .infinity, alignment: .leading)
                TextField("Year", text: $nStartYear).keyboardType(.numberPad).modifier(FieldStyle()).frame(width: 80)
            }
            HStack(spacing: 8) {
                Text("Payment day of month").font(.caption).foregroundStyle(T.sub)
                Spacer()
                TextField("27", text: $nDay).keyboardType(.numberPad).multilineTextAlignment(.center).modifier(FieldStyle()).frame(width: 64)
            }
            Button {
                let install = Int(nInstall) ?? 0
                let monthly = Double(nMonthly) ?? 0
                guard !nName.isEmpty, monthly > 0 || install > 0 else { return }
                let financed = Double(nFinanced) ?? (monthly * Double(install))
                store.addPaidyPlan(
                    name: nName, financedAmount: financed, installments: install, monthlyPayment: monthly,
                    startMonth: nStartMonth == 0 ? nil : nStartMonth,
                    startYear: Int(nStartYear),
                    paymentDay: Int(nDay) ?? 27,
                    paidCountOverride: nPaid.isEmpty ? nil : Int(nPaid))
                nName = ""; nFinanced = ""; nInstall = ""; nMonthly = ""; nPaid = ""
                nStartMonth = 0; nStartYear = ""; nDay = "27"
            } label: {
                Text("+ Add plan").fontWeight(.semibold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(T.accent).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
        }
        .card()
    }

    // MARK: Small helpers
    @ViewBuilder private func labeledField<Content: View>(_ label: String, @ViewBuilder _ field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(T.sub)
            HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub).opacity(label.contains("¥") ? 1 : 0); field() }.modifier(FieldStyle())
        }
    }

    private func numBinding(_ p: JSONValue, _ key: String, _ set: @escaping (Double) -> Void) -> Binding<String> {
        Binding(get: { let v = p.d(key); return v == 0 ? "" : String(Int(v)) },
                set: { set(Double($0) ?? 0) })
    }
    private func intBinding(_ p: JSONValue, _ key: String, _ set: @escaping (Int) -> Void) -> Binding<String> {
        Binding(get: { let v = p.i(key); return v == 0 ? "" : String(v) },
                set: { set(Int($0) ?? 0) })
    }
    private func intOptBinding(_ p: JSONValue, _ key: String, _ set: @escaping (Int) -> Void) -> Binding<String> {
        Binding(get: { if let v = p[key]?.int { return String(v) }; return "" },
                set: { if let n = Int($0) { set(n) } })
    }
}
