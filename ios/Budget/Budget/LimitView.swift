// LimitView.swift — Budget (iOS/Mac)
// Phase 2: the ¥1,030,000 annual-limit tracker — used/remaining/safe-per-month,
// status banner, and a monthly earnings breakdown. (Read-only analysis.)

import SwiftUI

struct LimitView: View {
    @EnvironmentObject var store: BudgetStore

    var body: some View {
        let c = store.calc
        let earned = c.earnedSoFar
        let limit = c.annualLimit
        let remaining = c.roomLeft
        let pct = limit > 0 ? min(1, earned / limit) : 0
        let nFM = max(0, 12 - c.currentMonthNumber)
        let safe = nFM > 0 ? floor(remaining / Double(nFM)) : 0
        let hoursPerMonth = c.hourlyWage > 0 ? safe / c.hourlyWage : 0

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
                        tile("Remaining", yen(remaining), remaining < 100000 ? T.roseD : T.greenD)
                        tile("Safe/month (\(nFM) left)", yen(safe), remaining < 100000 ? T.roseD : T.greenD)
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

                Text("Tip: detailed shift planning (\"what to work\") stays on the web app for now.")
                    .font(.caption2).foregroundStyle(T.muted).padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(T.sub)
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
