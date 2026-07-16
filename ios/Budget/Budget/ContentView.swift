// ContentView.swift — Budget (iOS/Mac)
// Phase 1: tab shell + a working Home dashboard reading the live shared blob.

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var store: BudgetStore
    // Regular width (iPad / Mac) can show a 6th tab cleanly; compact width (iPhone)
    // would collapse the 6th into iOS's white system "More" overflow — so on iPhone we
    // keep 5 tabs and Paidy stays inside the custom MoreView (its "Paidy" row).
    @Environment(\.horizontalSizeClass) private var hSize
    private var showPaidyTab: Bool { hSize == .regular }

    var body: some View {
        // More is ALWAYS tag 5 (whether or not the Paidy tab at tag 4 is shown), so the
        // deep-link indices (Limit → tab 5) stay consistent across devices.
        TabView(selection: $store.selectedTab) {
            HomeView().tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            WageView().tabItem { Label("Wage", systemImage: "yensign.circle") }.tag(1)
            BudgetTabView().tabItem { Label("Budget", systemImage: "list.bullet.rectangle") }.tag(2)
            SavingsView().tabItem { Label("Savings", systemImage: "banknote") }.tag(3)
            if showPaidyTab {
                NavigationStack { PaidyView() }.tabItem { Label("Paidy", systemImage: "creditcard") }.tag(4)
            }
            MoreView().tabItem { Label("More", systemImage: "ellipsis") }.tag(5)
        }
        // Numeric keypads (.numberPad / .decimalPad) have no built-in Return/Done key.
        // A TabView-level keyboard toolbar does NOT reliably reach screens that live in
        // their own NavigationStack (Budget, Paidy, and the More screens), which is why
        // many fields had no Done button. Instead, .keyboardDoneBar() is applied directly
        // to each screen that owns numeric fields (Wage, Savings, Budget, Paidy, Limit,
        // Goals, Settings) — guaranteed to be the nearest toolbar, so no duplicates.
        // Safety: on iPhone there is no tab 4 (Paidy), so never leave selection stranded there.
        .onChange(of: showPaidyTab) { _, shown in if !shown && store.selectedTab == 4 { store.selectedTab = 5; store.openPaidy = true } }
        .onAppear { if !showPaidyTab && store.selectedTab == 4 { store.selectedTab = 5 } }
    }
}

/// Resigns whatever text field currently has focus, anywhere in the app.
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Makes the numeric keyboard dismissable. `ToolbarItemGroup(placement:.keyboard)` is
/// unreliable — it often renders NOTHING inside nested NavigationStacks — so we do NOT
/// depend on it. Instead we use two mechanisms that always work on a ScrollView:
///   1. `.scrollDismissesKeyboard(.immediately)` — scroll/swipe the page closes the keypad.
///   2. a full-area tap gesture — tapping empty space closes it.
/// The `.toolbar` Done button is kept as a bonus for when it does render.
extension View {
    func keyboardDoneBar() -> some View {
        self
            .scrollDismissesKeyboard(.immediately)
            // Tap on empty space closes the keypad. `.simultaneousGesture` so it never
            // swallows taps meant for buttons/fields underneath.
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }.fontWeight(.semibold)
                }
            }
    }
}

// MARK: - More (custom, themed — replaces iOS's white system overflow tab)

struct MoreView: View {
    @EnvironmentObject var store: BudgetStore
    // On iPhone (compact) Paidy is not a top-level tab, so surface it here. On iPad/Mac
    // (regular) it's already a tab, so hide the redundant row.
    @Environment(\.horizontalSizeClass) private var hSize
    var body: some View {
        NavigationStack {
            ZStack {
                T.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        moreLink("Limit", "gauge.with.dots.needle.bottom.50percent") { LimitView() }
                        if hSize != .regular {
                            moreLink("Paidy", "creditcard") { PaidyView() }
                        }
                        moreLink("Goals", "target") { GoalsView() }
                        moreLink("Settings", "gearshape") { SettingsView() }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("More")
            // Deep link: a Home card ("Limit →") switches to this tab and sets openLimit,
            // which pushes the Limit screen automatically.
            .navigationDestination(isPresented: $store.openLimit) { LimitView() }
            .navigationDestination(isPresented: $store.openPaidy) { PaidyView() }
        }
    }

    @ViewBuilder private func moreLink<D: View>(_ title: String, _ icon: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(T.peachD).frame(width: 28)
                Text(title).font(.headline).foregroundStyle(T.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(T.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: BudgetStore
    @Environment(\.horizontalSizeClass) private var hSize
    /// Route to Paidy: a top-level tab on iPad/Mac, else the More tab with a deep-link push.
    private func goToPaidy() {
        if hSize == .regular { store.selectedTab = 4 }
        else { store.selectedTab = 5; store.openPaidy = true }
    }

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
                    paidySummary(c, now)
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
        let plY = c.paidLeaveYen(payMK)
        let wageRaw = c.wage(payMK), tr = c.transport(payMK)
        // No hours/override logged yet for the pay month → project wage from schedule + calendar
        // (same estimate the Wage tab uses) instead of showing ¥0. Reverts automatically once
        // real KOT hours or a wage override are entered.
        let monthD = c.month(payMK)
        let est: Calc.EstPay? = (wageRaw == 0 && monthD.d("wageOverride") <= 0) ? c.estimatedPay(payMK) : nil
        let wage = (est?.wage ?? 0) > 0 ? est!.wage : wageRaw
        let isEst = (est?.wage ?? 0) > 0
        let total = wage + tr + plY
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
                    payRow(isEst ? "Wage (est.)" : "Wage", wage)
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
        .contentShape(Rectangle())
        .onTapGesture { store.selectedTab = 1 }
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
        let extra = c.extraIncome(cmk)
        let spend = c.monthOut(cmk)
        let free = pay + dad + extra - spend
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
                if extra > 0 { lineRow("Extra money", "+" + yen(extra)) }
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
        .contentShape(Rectangle())
        .onTapGesture { store.selectedTab = 2 }
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
        .contentShape(Rectangle())
        .onTapGesture { store.selectedTab = 5; store.openLimit = true }
    }

    // MARK: Paidy summary (total remaining, combined monthly, next payment)
    @ViewBuilder private func paidySummary(_ c: Calc, _ now: Date) -> some View {
        let plans = c.paidyPlans
        if !plans.isEmpty {
            let states = plans.map { c.paidyCalc($0, now) }
            let totBal = states.reduce(0) { $0 + $1.remainingBal }
            let totMo = states.filter { !$0.done }.reduce(0) { $0 + $1.monthly }
            let totInst = states.reduce(0) { $0 + $1.installments }
            let totPaid = states.reduce(0) { $0 + $1.paid }
            let frac = totInst > 0 ? Double(totPaid) / Double(totInst) : 0
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PAIDY").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                    Spacer()
                    Text("\(yen(totMo))/mo · next \(c.paidyNextPayLabel(now))").font(.caption2).fontWeight(.semibold).foregroundStyle(T.muted)
                }
                (Text(yen(totBal)).font(.system(size: 26, weight: .bold)).foregroundStyle(T.roseD)
                 + Text("  remaining").font(.caption).foregroundStyle(T.sub))
                ProgressBar(fraction: frac, color: T.accent)
                Text("\(totPaid)/\(totInst) payments · \(Int((frac * 100).rounded()))%").font(.caption).foregroundStyle(T.sub)
            }
            .card()
            .contentShape(Rectangle())
            .onTapGesture { goToPaidy() }
        }
    }

    // MARK: Saved + Silver
    @ViewBuilder private func savedAndSilver(_ c: Calc) -> some View {
        let totalSaved = MONTHS.reduce(0.0) { $0 + c.savingsTotal($1.key) }
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
