// GoalsView.swift — Budget (iOS/Mac)
// Phase 2: savings goals with item lists, progress, and saved/monthly editing.

import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var addingItemTo: String?
    @State private var itemName = ""
    @State private var itemPrice = ""
    @State private var itemURL = ""
    @State private var newName = ""
    @State private var newTarget = ""
    @State private var newMonthly = ""

    var body: some View {
        let c = store.calc
        let goals = store.blob.settings["goals"]?.array ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if goals.isEmpty {
                    VStack(spacing: 8) {
                        Text("No goals yet").font(.headline).foregroundStyle(T.text)
                        Text("Add something you're saving toward below").font(.footnote).foregroundStyle(T.sub)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30).card()
                }
                ForEach(Array(goals.enumerated()), id: \.offset) { _, g in goalCard(c, g) }
                addGoalCard()
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    @ViewBuilder private func goalCard(_ c: Calc, _ g: JSONValue) -> some View {
        let id = c.idStr(g["id"])
        let items = g["items"]?.array ?? []
        let itemsTotal = items.reduce(0.0) { $0 + $1.d("price") }
        let target = items.isEmpty ? g.d("target") : itemsTotal
        let saved = g.d("saved")
        let monthly = g.d("monthly")
        let pct = target > 0 ? min(1, saved / target) : 0
        let left = max(0, target - saved)
        let done = saved >= target && target > 0

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.s("name")).font(.title3).fontWeight(.bold).foregroundStyle(T.text)
                    Text("Target: \(yen(target))").font(.caption).foregroundStyle(T.sub)
                }
                Spacer()
                Text("\(Int(pct * 100))%").font(.headline).foregroundStyle(done ? T.greenD : T.blueD)
                Button { store.removeGoal(id) } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(T.roseD)
            }
            ProgressBar(fraction: pct, color: done ? T.greenD : T.blueD)

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ITEMS").font(.caption2).foregroundStyle(T.sub).padding(.bottom, 4)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        HStack {
                            Text(it.s("name")).font(.footnote).foregroundStyle(T.text)
                            Spacer()
                            Text(yen(it.d("price"))).font(.footnote).fontWeight(.semibold)
                            if let u = it["url"]?.string, let url = URL(string: u) {
                                Link(destination: url) { Image(systemName: "link").font(.caption2) }
                            }
                            Button { store.removeGoalItem(id, c.idStr(it["id"])) } label: { Image(systemName: "xmark").font(.caption2) }
                                .buttonStyle(.plain).foregroundStyle(T.roseD)
                        }
                        .padding(.vertical, 6).overlay(Divider().overlay(T.border), alignment: .bottom)
                    }
                }
            }

            // Add item
            if addingItemTo == id {
                VStack(spacing: 8) {
                    TextField("Item name (e.g. Bed frame)", text: $itemName).modifier(FieldStyle())
                    HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("40000", text: $itemPrice).keyboardType(.numberPad) }.modifier(FieldStyle())
                    TextField("Link (optional)", text: $itemURL).modifier(FieldStyle())
                    HStack(spacing: 8) {
                        Button("Add item") {
                            if !itemName.isEmpty { store.addGoalItem(id, name: itemName, price: Double(itemPrice) ?? 0, url: itemURL); resetItem() }
                        }.fontWeight(.bold).foregroundStyle(.white).frame(maxWidth: .infinity).padding(10).background(T.greenD).clipShape(RoundedRectangle(cornerRadius: 10)).buttonStyle(.plain)
                        Button("Cancel") { resetItem() }.foregroundStyle(T.sub).frame(maxWidth: .infinity).padding(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(T.border)).buttonStyle(.plain)
                    }
                }
                .padding(12).background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button { addingItemTo = id; resetItemFields() } label: {
                    Text("+ Add item with price & link").font(.caption).foregroundStyle(T.sub)
                        .frame(maxWidth: .infinity).padding(9)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.border, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }.buttonStyle(.plain)
            }

            // Saved / monthly
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SAVED SO FAR").font(.caption2).foregroundStyle(T.sub)
                    HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("0", value: goalBinding(id, "saved"), format: .number).keyboardType(.numberPad) }.modifier(FieldStyle())
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SAVING / MONTH").font(.caption2).foregroundStyle(T.sub)
                    HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("0", value: goalBinding(id, "monthly"), format: .number).keyboardType(.numberPad) }.modifier(FieldStyle())
                }.frame(maxWidth: .infinity)
            }

            if done {
                Text("Goal reached!").fontWeight(.bold).foregroundStyle(.white).frame(maxWidth: .infinity).padding(12).background(T.greenD).clipShape(RoundedRectangle(cornerRadius: 12))
            } else if target > 0 {
                VStack(spacing: 6) {
                    HStack { Text("Still needed").foregroundStyle(T.sub); Spacer(); Text(yen(left)).fontWeight(.bold).foregroundStyle(T.blueD) }
                    if monthly > 0 { HStack { Text("At \(yen(monthly))/mo").foregroundStyle(T.sub); Spacer(); Text("\(Int(ceil(left / monthly))) months to go").fontWeight(.semibold) } }
                }.font(.footnote).padding(12).background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .card()
    }

    @ViewBuilder private func addGoalCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(T.greenD).frame(width: 3, height: 18); Text("Add a goal").font(.headline) }
            TextField("Goal name (e.g. Bed setup)", text: $newName).modifier(FieldStyle())
            HStack(spacing: 10) {
                HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("Target", text: $newTarget).keyboardType(.numberPad) }.modifier(FieldStyle())
                HStack(spacing: 6) { Text("¥").foregroundStyle(T.sub); TextField("Monthly", text: $newMonthly).keyboardType(.numberPad) }.modifier(FieldStyle())
            }
            Button("Add Goal") {
                if !newName.isEmpty {
                    store.addGoal(name: newName, target: Double(newTarget) ?? 0, monthly: Double(newMonthly) ?? 0)
                    newName = ""; newTarget = ""; newMonthly = ""
                }
            }.fontWeight(.bold).foregroundStyle(.white).frame(maxWidth: .infinity).padding(14).background(T.greenD).clipShape(RoundedRectangle(cornerRadius: 12)).buttonStyle(.plain)
        }
        .card()
    }

    private func goalBinding(_ id: String, _ field: String) -> Binding<Double> {
        Binding(
            get: {
                let goals = store.blob.settings["goals"]?.array ?? []
                let c = store.calc
                return goals.first { c.idStr($0["id"]) == id }?[field]?.double ?? 0
            },
            set: { store.setGoalNumber(id, field, $0) }
        )
    }
    private func resetItem() { addingItemTo = nil; resetItemFields() }
    private func resetItemFields() { itemName = ""; itemPrice = ""; itemURL = "" }
}
