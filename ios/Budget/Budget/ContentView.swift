// ContentView.swift — Budget (iOS/Mac)
// Phase 1: tab shell + a working Home dashboard reading the live shared blob.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BudgetStore

    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }
            WageView().tabItem { Label("Wage", systemImage: "yensign.circle") }
            PlaceholderView(title: "Budget").tabItem { Label("Budget", systemImage: "list.bullet.rectangle") }
            PlaceholderView(title: "Passbook").tabItem { Label("Passbook", systemImage: "building.columns") }
            PlaceholderView(title: "Limit").tabItem { Label("Limit", systemImage: "gauge.with.dots.needle.bottom.50percent") }
            PlaceholderView(title: "Savings").tabItem { Label("Savings", systemImage: "banknote") }
            PlaceholderView(title: "Goals").tabItem { Label("Goals", systemImage: "target") }
            PlaceholderView(title: "Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: BudgetStore

    var body: some View {
        let c = store.calc
        let now = Date()

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                greeting(now)

                if !store.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    nextPaycheck(c, now)
                    leftToSpend(c, now)
                    roomToEarn(c)
                    savedAndSilver(c)
                }
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
    }

    // MARK: Greeting
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; return f
    }()
    @ViewBuilder private func greeting(_ now: Date) -> some View {
        let hr = Calendar.current.component(.hour, from: now)
        let g = hr < 12 ? "Good morning" : hr < 18 ? "Good afternoon" : "Good evening"
        VStack(alignment: .leading, spacing: 3) {
            Text(g.uppercased()).font(.caption).fontWeight(.semibold).foregroundStyle(T.sub).tracking(0.6)
            Text(Self.dateFmt.string(from: now)).font(.system(size: 22, weight: .bold)).foregroundStyle(T.text)
        }
        .padding(.bottom, 2)
    }

    // MARK: Next paycheck (the genuinely next payday)
    @ViewBuilder private func nextPaycheck(_ c: Calc, _ now: Date) -> some View {
        let cal = Calendar.current
        let y = cal.component(.year, from: now), mo = cal.component(.month, from: now), day = cal.component(.day, from: now)
        let curMK = clampMK(String(format: "%04d-%02d", y, mo))
        let curPD = c.payday(curMK)
        let miCur = MONTHS.firstIndex { $0.key == curMK } ?? 0
        let isLast = day > curPD && miCur == MONTHS.count - 1
        let payMK = (day <= curPD) ? curMK : (miCur < MONTHS.count - 1 ? MONTHS[miCur + 1].key : curMK)
        let payPD = c.payday(payMK)
        let payLabel = monthMeta(payMK)?.label ?? ""
        let total = c.monthlyPay(payMK) + 0   // monthlyPay = taxable + transport
        let plY = c.paidLeaveYen(payMK)
        let wage = c.wage(payMK), tr = c.transport(payMK)
        // days until payday
        let payComps = payMK.split(separator: "-")
        let pdate = cal.date(from: DateComponents(year: Int(payComps[0]), month: Int(payComps[1]), day: payPD)) ?? now
        let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: pdate)).day ?? 0)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT PAYCHECK · \(payLabel.uppercased())").font(.caption2).fontWeight(.semibold).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("Wages →").font(.caption2).fontWeight(.semibold).foregroundStyle(.white.opacity(0.65))
            }
            Text(yen(total)).font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            Text(isLast ? "Paid on the \(payPD)th ✓ · next payday in January"
                        : days == 0 ? "Payday is today 🎉" : "in \(days) day\(days == 1 ? "" : "s") · the \(payPD)th")
                .font(.footnote).foregroundStyle(.white.opacity(0.82))
            if total > 0 {
                VStack(spacing: 7) {
                    payRow("Wage", wage)
                    payRow("Transport", tr)
                    if plY > 0 { payRow("Paid leave", plY) }
                }.padding(.top, 6)
            } else {
                Text("Log your hours to see this →").font(.footnote).fontWeight(.semibold).foregroundStyle(.white.opacity(0.92)).padding(.top, 6)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.greenD)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private func payRow(_ label: String, _ v: Double) -> some View {
        HStack { Text(label).foregroundStyle(.white.opacity(0.9)); Spacer(); Text(yen(v)).fontWeight(.bold).foregroundStyle(.white) }
            .font(.footnote)
    }

    // MARK: Left to spend (current month, independent of any month browsing)
    @ViewBuilder private func leftToSpend(_ c: Calc, _ now: Date) -> some View {
        let cal = Calendar.current
        let cmk = clampMK(String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now)))
        let pay = c.monthlyPay(cmk)
        let dad = c.dadFree(cmk)
        let spend = c.spending(cmk)
        let free = pay + dad - spend
        let label = monthMeta(cmk)?.label ?? ""
        let billCount = c.homeBillIds(cmk).count
        let paid = c.paidCount(cmk)
        let leftPay = c.leftToPay(cmk)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LEFT TO SPEND · \(label.uppercased())").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                Spacer()
                Text("Budget →").font(.caption2).fontWeight(.semibold).foregroundStyle(T.muted)
            }
            Text(yen(free)).font(.system(size: 30, weight: .bold)).foregroundStyle(free < 0 ? T.roseD : T.text)
            VStack(spacing: 6) {
                lineRow("Income", yen(pay))
                if dad > 0 { lineRow("From Dad", "+" + yen(dad)) }
                lineRow("Bills & spending", "−" + yen(spend))
            }
            Divider().overlay(T.border)
            HStack {
                Text("Bills paid").font(.caption).foregroundStyle(T.sub)
                Spacer()
                Text(leftPay > 0 ? "\(paid) of \(billCount) · \(yen(leftPay)) left" : "\(paid) of \(billCount) · all done ✓")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(leftPay > 0 ? T.lavD : T.greenD)
            }
            ProgressBar(fraction: billCount > 0 ? Double(paid) / Double(billCount) : 0, color: leftPay > 0 ? T.lavD : T.greenD)
        }
        .card()
    }

    // MARK: Room left to earn
    @ViewBuilder private func roomToEarn(_ c: Calc) -> some View {
        let earned = c.earnedSoFar
        let room = c.roomLeft
        let pct = c.annualLimit > 0 ? min(1, earned / c.annualLimit) : 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROOM LEFT TO EARN").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                Spacer()
                Text("Limit →").font(.caption2).fontWeight(.semibold).foregroundStyle(T.muted)
            }
            Text(yen(room)).font(.system(size: 26, weight: .bold)).foregroundStyle(room < 100000 ? T.roseD : T.text)
            ProgressBar(fraction: pct, color: room < 100000 ? T.roseD : T.blueD)
            HStack {
                Text("\(yen(earned)) earned").font(.caption).foregroundStyle(T.sub)
                Spacer()
                Text("\(Int((earned / max(1, c.annualLimit)) * 100))% of limit used").font(.caption).foregroundStyle(T.sub)
            }
        }
        .card()
    }

    // MARK: Saved + Silver
    @ViewBuilder private func savedAndSilver(_ c: Calc) -> some View {
        let totalSaved = MONTHS.reduce(0.0) { $0 + c.month($1.key).d("savings") }
        let slvOz = MONTHS.reduce(0.0) { $0 + c.month($1.key).d("silverOz") }
        let slvUsd = MONTHS.reduce(0.0) { $0 + c.month($1.key).d("silverUsd") }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SAVED").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                Text(yen(totalSaved)).font(.system(size: 21, weight: .bold)).foregroundStyle(T.blueD)
            }.card(padding: 16)
            VStack(alignment: .leading, spacing: 5) {
                Text("SILVER").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                Text(String(format: "%.2f oz", slvOz)).font(.system(size: 21, weight: .bold)).foregroundStyle(T.peachD)
                Text(String(format: "$%.0f in", slvUsd)).font(.caption2).foregroundStyle(T.sub)
            }.card(padding: 16)
        }
    }

    // MARK: helpers
    private func lineRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(T.sub); Spacer(); Text(value).fontWeight(.semibold).foregroundStyle(T.text) }
            .font(.footnote)
    }
    /// Clamp a YYYY-MM to a valid 2026 month (the app is 2026-only).
    private func clampMK(_ mk: String) -> String {
        if monthMeta(mk) != nil { return mk }
        return mk < "2026-01" ? "2026-01" : "2026-12"
    }
}

// MARK: - Reusable bits

struct ProgressBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(T.cardAlt)
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

struct PlaceholderView: View {
    let title: String
    var body: some View {
        ZStack {
            T.background.ignoresSafeArea()
            VStack(spacing: 10) {
                Text(title).font(.title2.bold()).foregroundStyle(T.text)
                Text("Coming in the native build").font(.subheadline).foregroundStyle(T.sub)
            }
        }
    }
}
