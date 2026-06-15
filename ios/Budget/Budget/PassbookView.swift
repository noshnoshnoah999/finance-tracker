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

    // MARK: Year overview
    @ViewBuilder private func yearOverview(_ c: Calc) -> some View {
        let inT = c.passbookYearIn, outT = c.passbookYearOut
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("2026 SO FAR").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub)
                Spacer()
                Text("\(c.totalTxns) transaction\(c.totalTxns == 1 ? "" : "s") imported").font(.caption2).foregroundStyle(T.muted)
            }
            HStack {
                miniStat("In", yen(inT), T.greenD)
                miniStat("Out", yen(outT), T.roseD)
                miniStat("Net", yen(inT - outT), inT - outT >= 0 ? T.greenD : T.roseD)
            }
        }
        .card()
    }
    private func miniStat(_ l: String, _ v: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.uppercased()).font(.caption2).foregroundStyle(T.sub)
            Text(v).font(.headline).fontWeight(.bold).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        let net = inT - outT
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
            HStack {
                Text(net >= 0 ? "Left over" : "Overspent").fontWeight(.semibold).foregroundStyle(.white)
                Spacer()
                Text(yen(abs(net))).font(.title3).fontWeight(.bold).foregroundStyle(.white)
            }
            .padding(14).background(net >= 0 ? T.greenD : T.roseD).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .card()

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
                ForEach(cats) { x in
                    let e = txCat(x.cat)
                    VStack(spacing: 4) {
                        HStack {
                            Text("\(e.emoji) \(e.label)").font(.footnote)
                            Text("×\(x.count)").font(.caption2).foregroundStyle(T.muted)
                            Spacer()
                            Text(yen(x.total)).font(.footnote).fontWeight(.bold)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(T.cardAlt)
                                Capsule().fill(T.roseD).frame(width: (outT > 0 ? x.total / outT : 0) * geo.size.width)
                            }
                        }.frame(height: 6)
                    }
                }
                Text("TRANSACTIONS").font(.caption2).fontWeight(.semibold).foregroundStyle(T.sub).padding(.top, 4)
                ForEach(Array(c.txns(pbm).sorted { $0.s("date") < $1.s("date") }.enumerated()), id: \.offset) { _, t in
                    let e = txCat(t.s("category"))
                    HStack(spacing: 8) {
                        Text(e.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.s("description")).font(.caption).fontWeight(.semibold).lineLimit(1)
                            Text(t.s("date")).font(.system(size: 10)).foregroundStyle(T.muted)
                        }
                        Spacer()
                        Text("\(t.s("direction") == "in" ? "+" : "−")\(yen(t.d("amount")))")
                            .font(.caption).fontWeight(.bold).foregroundStyle(t.s("direction") == "in" ? T.greenD : T.text)
                    }
                    .padding(.vertical, 5).overlay(Divider().overlay(T.border), alignment: .bottom)
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
}
