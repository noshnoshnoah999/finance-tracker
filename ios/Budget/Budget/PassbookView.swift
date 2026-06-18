// PassbookView.swift — Budget (iOS/Mac)
// Phase 2: bank-statement view per month (income from pay, real or budgeted spending),
// transaction list + category bars, AI spending insights, and passbook upload (up to 5).

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct PassbookView: View {
    @EnvironmentObject var store: BudgetStore
    @State private var pbm = currentMonthKeyClamped()
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        let c = store.calc
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                yearOverview(c)
                monthChips(c)
                statement(c)
                insights(c)
                importCard(c)
            }
            .padding(20)
        }
        .background(T.background.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var files: [(data: Data, type: String)] = []
                for item in items.prefix(5) {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        files.append(downscale(data, "image/jpeg"))
                    }
                }
                photoItems = []
                if !files.isEmpty { await store.analyzePassbooks(files) }
            }
        }
    }

    /// Shrink an image to <= 1536px on the long edge (Claude caps at 8000px; full-page
    /// screenshots exceed it). PDFs pass through untouched.
    private func downscale(_ data: Data, _ type: String) -> (data: Data, type: String) {
        guard type != "application/pdf", let img = UIImage(data: data) else { return (data, type) }
        let maxDim: CGFloat = 1536
        let w = img.size.width, h = img.size.height
        let scale = min(1, maxDim / max(w, h))
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let out = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        return (out.jpegData(compressionQuality: 0.85) ?? data, "image/jpeg")
    }

    // MARK: Year hero (bank-style gradient)
    @ViewBuilder private func yearOverview(_ c: Calc) -> some View {
        let inT = c.passbookYearIn, outT = c.passbookYearOut
        let net = inT - outT
        let inPct = inT > 0 ? Int((outT / inT * 100).rounded()) : 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("2026 SO FAR").font(.caption2).fontWeight(.semibold).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(c.totalTxns) txn\(c.totalTxns == 1 ? "" : "s")").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            Text("Net kept this year").font(.caption2).foregroundStyle(.white.opacity(0.75))
            Text(yen(net)).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            HStack(spacing: 10) {
                heroTile("In", yen(inT))
                heroTile("Out", yen(outT))
            }
            if inT > 0 { Text("You spent \(inPct)% of what came in.").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [T.greenD, T.blueD], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private func heroTile(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(l.uppercased()).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(v).font(.headline).fontWeight(.bold).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 12)
        .background(Color.white.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Month chips
    @ViewBuilder private func monthChips(_ c: Calc) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MONTHS) { mo in
                    Button { pbm = mo.key } label: {
                        HStack(spacing: 4) {
                            Text(mo.short)
                            if c.hasRealTxns(mo.key) { Circle().fill(pbm == mo.key ? Color.white : T.peachD).frame(width: 5, height: 5) }
                        }
                        .font(.caption).fontWeight(pbm == mo.key ? .semibold : .regular)
                        .padding(.vertical, 7).padding(.horizontal, 14)
                        .background(pbm == mo.key ? T.accent : T.card)
                        .foregroundStyle(pbm == mo.key ? .white : T.sub)
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Statement
    @ViewBuilder private func statement(_ c: Calc) -> some View {
        let real = c.hasRealTxns(pbm)
        let inT = c.monthlyPay(pbm)
        let outT = c.passbookOut(pbm)
        let fixedB = real ? c.fixedBills(pbm) : 0   // real months: card txns miss fixed bills
        let net = inT - outT - fixedB
        let label = monthMeta(pbm)?.label ?? ""

        // Summary
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(label).font(.title3).fontWeight(.bold)
                Spacer()
                Text(real ? "● Real" : "Estimated").font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(real ? T.greenBg : T.cardAlt).foregroundStyle(real ? T.greenD : T.muted)
                    .clipShape(Capsule())
            }
            HStack(spacing: 10) {
                bigStat("Money in", yen(inT), T.greenD, T.greenBg)
                bigStat("Money out", yen(outT), T.roseD, T.roseBg)
            }
            if fixedB > 0 {
                HStack(spacing: 6) {
                    Text("Fixed bills").foregroundStyle(T.sub)
                    Text("(rent, subs, savings…)").font(.caption2).foregroundStyle(T.muted)
                    Spacer()
                    Text("−\(yen(fixedB))").fontWeight(.bold).foregroundStyle(T.text)
                }.font(.footnote)
            }
            HStack {
                Text((net >= 0 ? "Left over" : "Overspent") + (fixedB > 0 ? " after bills" : "")).fontWeight(.semibold).foregroundStyle(.white)
                Spacer()
                Text(yen(abs(net))).font(.title3).fontWeight(.bold).foregroundStyle(.white)
            }
            .padding(14).background(net >= 0 ? T.greenD : T.roseD).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .card()

        // Month insights
        if real { monthInsights(c) }

        // Money In
        VStack(alignment: .leading, spacing: 8) {
            header("Money In", T.greenD)
            if inT > 0 {
                line("Wage", yen(c.wage(pbm)))
                if c.paidLeaveYen(pbm) > 0 { line("Paid leave", yen(c.paidLeaveYen(pbm)), T.blueD) }
                line("Transport", yen(c.transport(pbm)))
                Divider().overlay(T.border)
                line("Monthly pay", yen(inT), T.greenD, bold: true)
            } else {
                Text("No pay logged for \(label) yet — add hours in the Wage tab.").font(.footnote).foregroundStyle(T.muted)
            }
        }
        .card()

        // Money Out
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header("Money Out", T.roseD)
                Spacer()
                Text(real ? "\(c.txns(pbm).count) txns" : "from budget").font(.caption2).foregroundStyle(T.muted)
            }
            if real {
                let cats = c.cats(pbm)
                let fracs = cats.map { outT > 0 ? $0.total / outT : 0 }
                HStack(spacing: 16) {
                    donut(fracs, outT)
                    VStack(spacing: 7) {
                        ForEach(Array(cats.enumerated()), id: \.offset) { i, x in
                            let e = txCat(x.cat)
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3).fill(catColor(i)).frame(width: 9, height: 9)
                                Text("\(e.emoji) \(e.label)").font(.caption).lineLimit(1)
                                Text("×\(x.count)").font(.system(size: 10)).foregroundStyle(T.muted)
                                Spacer()
                                Text(yen(x.total)).font(.caption).fontWeight(.bold)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
                Text("TRANSACTIONS").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub).padding(.top, 4)
                let groups = Dictionary(grouping: c.txns(pbm)) { $0.s("date") }
                ForEach(groups.keys.sorted(by: >), id: \.self) { date in
                    let items = groups[date] ?? []
                    let dayOut = items.filter { $0.s("direction") != "in" }.reduce(0.0) { $0 + $1.d("amount") }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(date).font(.caption2).fontWeight(.bold).foregroundStyle(T.sub)
                            Spacer()
                            if dayOut > 0 { Text("−\(yen(dayOut))").font(.caption2).foregroundStyle(T.muted) }
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                                let e = txCat(t.s("category"))
                                HStack(spacing: 9) {
                                    Text(e.emoji)
                                    Text(t.s("description")).font(.caption).fontWeight(.semibold).lineLimit(1)
                                    Spacer()
                                    Text("\(t.s("direction") == "in" ? "+" : "−")\(yen(t.d("amount")))")
                                        .font(.caption).fontWeight(.bold).foregroundStyle(t.s("direction") == "in" ? T.greenD : T.text)
                                }
                                .padding(.vertical, 9).padding(.horizontal, 12)
                                .overlay(alignment: .top) { if i > 0 { Divider().overlay(T.border) } }
                            }
                        }
                        .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.bottom, 6)
                }
            } else {
                let lines = c.budgetLines(pbm)
                if lines.isEmpty {
                    Text("Nothing budgeted for \(label).").font(.footnote).foregroundStyle(T.muted)
                } else {
                    ForEach(lines) { x in
                        let e = txCat(x.cat)
                        line("\(e.emoji) \(x.name)", yen(x.amount))
                    }
                    Divider().overlay(T.border)
                    line("Estimated total", yen(outT), T.roseD, bold: true)
                }
                Text("Budgeted spending. Upload \(label)'s passbook below to see actual spending.")
                    .font(.caption2).foregroundStyle(T.muted)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.cardAlt).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .card()
    }

    // MARK: Insights
    @ViewBuilder private func insights(_ c: Calc) -> some View {
        let ins = store.blob.settings["spendInsights"]
        VStack(alignment: .leading, spacing: 10) {
            HStack { header("Spending Insights", T.lavD); Spacer(); Text("🧠") }
            Text("AI feedback & recommendations across everything you've imported.").font(.caption2).foregroundStyle(T.sub)
            Button {
                Task { await store.analyzeSpending() }
            } label: {
                Text(store.spendLoading ? "Analysing…" : c.totalTxns == 0 ? "Import a passbook first" : (ins != nil ? "Re-analyse my spending" : "Analyse my spending"))
                    .fontWeight(.bold).foregroundStyle(c.totalTxns == 0 ? T.muted : .white)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(c.totalTxns == 0 ? T.cardAlt : T.lavD)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(.plain).disabled(store.spendLoading || c.totalTxns == 0)
            if !store.spendErr.isEmpty { errBox(store.spendErr) }
            if let R = ins { insightBody(R) }
        }
        .card()
    }
    @ViewBuilder private func insightBody(_ R: JSONValue) -> some View {
        if let xs = R["insights"]?.array, !xs.isEmpty {
            sec("What I noticed"); ForEach(Array(xs.enumerated()), id: \.offset) { _, x in bullet("•", x.string ?? "") }
        }
        if let xs = R["suggestions"]?.array, !xs.isEmpty {
            sec("Recommendations"); ForEach(Array(xs.enumerated()), id: \.offset) { _, x in bullet("→", x.string ?? "", T.greenD) }
        }
        if let xs = R["recurring"]?.array, !xs.isEmpty {
            sec("Recurring & subscriptions")
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in
                HStack { Text(x.s("description")).font(.footnote).fontWeight(.semibold); Spacer(); Text(yen(x.d("amount"))).font(.footnote).fontWeight(.bold).foregroundStyle(T.peachD) }
            }
        }
        if let xs = R["anomalies"]?.array, !xs.isEmpty {
            sec("Heads up")
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(x.s("description")).font(.footnote).fontWeight(.semibold).foregroundStyle(T.roseD); Spacer(); Text(yen(x.d("amount"))).font(.footnote).fontWeight(.bold).foregroundStyle(T.roseD) }
                    Text(x.s("reason")).font(.caption2).foregroundStyle(T.sub)
                }.padding(10).background(T.roseBg).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Import
    @ViewBuilder private func importCard(_ c: Calc) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { header("Import a passbook", T.peachD); Spacer(); Text("🏦") }
            Text("Upload up to 5 photos or PDFs of your bank passbook (通帳). Claude reads every transaction and files them into the right month.").font(.caption2).foregroundStyle(T.sub)
            if store.pbLoading {
                Text("Reading your passbook… ~15-40s").fontWeight(.semibold).foregroundStyle(T.sub)
                    .frame(maxWidth: .infinity).padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.border, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
            } else {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Label("Photos", systemImage: "photo").fontWeight(.semibold).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13).background(T.peachD).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button { importing = true } label: {
                        Label("Files / PDF", systemImage: "doc").fontWeight(.semibold).foregroundStyle(T.sub)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.border, lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
            }
            Button { Task { await store.importBankEmails() } } label: {
                Label("Import Sony Bank emails", systemImage: "envelope").fontWeight(.semibold).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).background(T.greenD).clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(store.pbLoading)
            Text("Pulls Sony Bank WALLET transaction emails from Gmail automatically.").font(.caption2).foregroundStyle(T.muted)
            if !store.pbErr.isEmpty { errBox(store.pbErr) }
            if !store.pbMsg.isEmpty && store.pbErr.isEmpty {
                Text(store.pbMsg).font(.caption).fontWeight(.semibold).foregroundStyle(T.greenD)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(T.greenBg).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .card()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        var files: [(data: Data, type: String)] = []
        for u in urls.prefix(5) {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: u) else { continue }
            let ext = u.pathExtension.lowercased()
            let type = ext == "pdf" ? "application/pdf" : ext == "png" ? "image/png" : "image/jpeg"
            files.append(downscale(d, type))
        }
        Task { await store.analyzePassbooks(files) }
    }

    // MARK: bits
    private func header(_ t: String, _ color: Color) -> some View {
        HStack(spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 18); Text(t).font(.headline) }
    }
    private func bigStat(_ l: String, _ v: String, _ color: Color, _ bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.uppercased()).font(.caption2).foregroundStyle(T.sub)
            Text(v).font(.title3).fontWeight(.bold).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(bg).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func line(_ l: String, _ v: String, _ color: Color = T.text, bold: Bool = false) -> some View {
        HStack { Text(l).foregroundStyle(bold ? color : T.sub); Spacer(); Text(v).fontWeight(bold ? .bold : .semibold).foregroundStyle(color) }.font(.footnote)
    }
    private func sec(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2).fontWeight(.bold).foregroundStyle(T.sub).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
    private func bullet(_ mark: String, _ text: String, _ color: Color = T.text) -> some View {
        HStack(alignment: .top, spacing: 8) { Text(mark).foregroundStyle(color); Text(text) }.font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func errBox(_ t: String) -> some View {
        Text(t).font(.caption).fontWeight(.semibold).foregroundStyle(T.roseD)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(T.roseBg).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Insights grid (bank-style)
    @ViewBuilder private func monthInsights(_ c: Calc) -> some View {
        let outTxs = c.txns(pbm).filter { $0.s("direction") != "in" }
        let outT = c.passbookOut(pbm)
        let biggest = outTxs.max { $0.d("amount") < $1.d("amount") }
        let nDays = Set(outTxs.map { $0.s("date") }).count
        let dailyAvg = nDays > 0 ? Int((outT / Double(nDays)).rounded()) : 0
        let top = c.cats(pbm).first
        let pm = prevMK(pbm)
        let prevOut = pm != nil ? c.passbookOut(pm!) : 0
        let momPct: Int? = prevOut > 0 ? Int(((outT - prevOut) / prevOut * 100).rounded()) : nil
        let tc = top != nil ? txCat(top!.cat) : (emoji: "", label: "")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            insightCell("Daily average", yen(Double(dailyAvg)), "over \(nDays) active day\(nDays == 1 ? "" : "s")", T.text)
            insightCell("Biggest purchase", biggest != nil ? yen(biggest!.d("amount")) : "—", biggest?.s("description") ?? "", T.text)
            insightCell("Top category", top != nil ? "\(tc.emoji) \(tc.label)" : "—", top != nil ? yen(top!.total) : "", T.text)
            insightCell("vs last month", momPct == nil ? "—" : "\(momPct! > 0 ? "↑" : "↓") \(abs(momPct!))%", prevOut > 0 ? "spent \(yen(prevOut)) before" : "no prior month", momPct == nil ? T.text : (momPct! > 0 ? T.roseD : T.greenD))
        }
    }
    private func insightCell(_ label: String, _ value: String, _ sub: String, _ col: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(T.sub)
            Text(value).font(.headline).fontWeight(.bold).foregroundStyle(col).lineLimit(1).minimumScaleFactor(0.7)
            if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(T.sub).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(T.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Donut ring for the category breakdown
    @ViewBuilder private func donut(_ fracs: [Double], _ total: Double) -> some View {
        ZStack {
            Circle().stroke(T.cardAlt, lineWidth: 14)
            ForEach(Array(fracs.enumerated()), id: \.offset) { i, f in
                let start = fracs.prefix(i).reduce(0, +)
                Circle().trim(from: min(start, 1), to: min(start + f, 1))
                    .stroke(catColor(i), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("spent").font(.system(size: 9)).foregroundStyle(T.sub)
                Text(yen(total)).font(.caption).fontWeight(.bold).foregroundStyle(T.text).minimumScaleFactor(0.6).lineLimit(1)
            }
        }
        .frame(width: 104, height: 104)
    }
    private func catColor(_ i: Int) -> Color {
        let pal: [Color] = [T.roseD, T.peachD, T.blueD, T.lavD, T.greenD, T.rose, T.peach, T.blue]
        return pal[i % pal.count]
    }
    private func prevMK(_ mk: String) -> String? {
        guard let i = MONTHS.firstIndex(where: { $0.key == mk }), i > 0 else { return nil }
        return MONTHS[i - 1].key
    }
}
