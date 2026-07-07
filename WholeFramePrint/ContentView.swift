//
//  ContentView.swift
//  WholeFramePrint
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 380)
        } detail: {
            VStack(spacing: 0) {
                PreviewView(model: model)
                    .overlay(alignment: .center) {
                        if dropTargeted {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                    }
                if model.hasImage {
                    InfoBar(model: model)
                }
            }
            .navigationTitle("Whole-Frame Tiled Print")
            .toolbar { toolbarContent }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .onAppear { model.refreshPrinters() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPrinters()
        }
        .alert("Notice", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Notice", isPresented: Binding(
            get: { model.successMessage != nil },
            set: { if !$0 { model.successMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.successMessage ?? "")
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.openPanel()
            } label: {
                Label("Open Image", systemImage: "photo.badge.plus")
            }
            Menu {
                Button {
                    model.exportCombinedPDF()
                } label: {
                    Label("Combined PDF…", systemImage: "doc.richtext")
                }
                Divider()
                ForEach(SheetFileFormat.allCases) { format in
                    Button {
                        model.exportSeparateSheets(format: format)
                    } label: {
                        Text(format.separateExportMenuTitle)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .disabled(!model.hasImage)

            Button {
                model.printLayout()
            } label: {
                Label("Print", systemImage: "printer")
            }
            .disabled(!model.hasImage)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { model.loadImage(from: url) }
        }
        return true
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Artwork") {
                if model.hasImage {
                    HStack {
                        Image(systemName: "photo")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.fileName).lineLimit(1).font(.callout)
                            Text("\(Int(model.imagePixels.width)) × \(Int(model.imagePixels.height)) px · \(Int(model.imageDPI)) dpi")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    model.openPanel()
                } label: {
                    Label(model.hasImage ? "Change Image…" : "Choose Image…", systemImage: "folder")
                }
            }

            Section("Print Mode") {
                Picker("Mode", selection: $model.config.mode) {
                    ForEach(PrintMode.allCases) {
                        Text(L10n.printModeLabel($0)).tag($0)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(L10n.printModeSubtitle(model.config.mode))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Paper") {
                Picker("Paper Size", selection: $model.config.paper) {
                    ForEach(PaperSize.all) { p in
                        Text(L10n.paperPickerLabel(name: p.name,
                                                   width: fmt(p.widthMM),
                                                   height: fmt(p.heightMM))).tag(p)
                    }
                }
                Picker("Orientation", selection: $model.config.orientation) {
                    ForEach(PageOrientation.allCases) {
                        Text(L10n.orientation($0)).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Units", selection: $model.config.unit) {
                    ForEach(LengthUnit.allCases) {
                        Text(L10n.lengthUnit($0)).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Assembly") {
                Toggle("Center image in assembly", isOn: $model.config.centerInAssembly)
                Text(String(localized: "Center image in assembly help"))
                    .font(.caption).foregroundStyle(.secondary)
                if model.config.centerInAssembly {
                    LabeledNumberField(title: String(localized: "Outer assembly margin"),
                                       value: $model.config.printerMarginMM,
                                       suffix: "mm")
                }
            }

            if model.config.mode == .actualSize {
                actualSizeSection
            } else {
                fitSection
            }

            Section("Marks") {
                Toggle("Crop marks (preview only)", isOn: $model.config.showCropMarks)
                Toggle("Page labels (preview only)", isOn: $model.config.showLabels)
            }

            PrinterSection(model: model)
        }
        .formStyle(.grouped)
    }

    private var actualSizeSection: some View {
        Section("Actual Size Settings") {
            LabeledNumberField(title: String(localized: "Artwork Width"),
                               value: unitBinding(\.targetWidthMM),
                               suffix: model.config.unit.symbol)
            if model.hasImage {
                let h = model.config.targetWidthMM / max(0.0001, model.imagePixels.width / model.imagePixels.height)
                Text(L10n.heightAuto(value: fmt(model.config.unit.fromMM(h)),
                                     unit: model.config.unit.symbol))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledNumberField(title: String(localized: "Tile overlap"),
                               value: $model.config.overlapMM,
                               suffix: "mm")
            if !model.config.centerInAssembly {
                LabeledNumberField(title: String(localized: "Margins per sheet"),
                                   value: $model.config.printerMarginMM,
                                   suffix: "mm")
            }
        }
    }

    private var fitSection: some View {
        Section("Sheet Layout") {
            Stepper(value: $model.config.cols, in: 1...12) {
                Text(L10n.columnsCount(model.config.cols))
            }
            Stepper(value: $model.config.rows, in: 1...12) {
                Text(L10n.rowsCount(model.config.rows))
            }
            Button {
                model.autoSuggestGrid()
            } label: {
                Label("Auto-fit to aspect ratio", systemImage: "wand.and.stars")
            }

            VStack(alignment: .leading) {
                Text(L10n.marginRatio(Int(model.config.marginFraction * 100)))
                Slider(value: $model.config.marginFraction, in: 0...0.4)
                Text(L10n.imageCoverage(Int((1 - marginSpan()) * 100)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Golden-ratio margins (wider bottom)", isOn: $model.config.goldenBottomHeavy)
            Toggle("Full bleed (trim to assemble)", isOn: $model.config.bleedTrim)
            if !model.config.centerInAssembly && !model.config.bleedTrim {
                LabeledNumberField(title: String(localized: "Printer safe margin"),
                                   value: $model.config.printerMarginMM,
                                   suffix: "mm")
            }
        }
    }

    private func marginSpan() -> Double {
        model.config.marginFraction * 2
    }

    private func unitBinding(_ keyPath: WritableKeyPath<PrintConfig, Double>) -> Binding<Double> {
        Binding(
            get: { model.config.unit.fromMM(model.config[keyPath: keyPath]) },
            set: { model.config[keyPath: keyPath] = model.config.unit.toMM($0) }
        )
    }

    private func fmt(_ v: Double) -> String {
        String(format: v == v.rounded() ? "%.0f" : "%.1f", v)
    }
}

private struct PrinterSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section("Printer") {
            if let defaultName = PrinterService.defaultPrinterName() {
                LabeledContent(String(localized: "System default")) {
                    Text(defaultName).lineLimit(1)
                }
            }

            if model.hasPrinters {
                Picker("Printer", selection: Binding(
                    get: { model.selectedPrinterName ?? model.printers.first?.name ?? "" },
                    set: { model.selectedPrinterName = $0 }
                )) {
                    ForEach(model.printers) { printer in
                        Text(printerLabel(printer)).tag(printer.name)
                    }
                }
            } else {
                Text("Use system print dialog")
                    .foregroundStyle(.secondary)
            }

            Text(String(localized: "Printer uses system help"))
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Button {
                    model.refreshPrinters()
                } label: {
                    Label("Refresh printers", systemImage: "arrow.clockwise")
                }
                Button {
                    model.openAddPrinter()
                } label: {
                    Label("Add printer…", systemImage: "plus.circle")
                }
            }

            if model.hasImage {
                Button {
                    model.printLayout()
                } label: {
                    Label {
                        Text(L10n.printSheets(model.layout.sheetCount))
                    } icon: {
                        Image(systemName: "printer.fill")
                    }
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
        }
    }

    private func printerLabel(_ printer: PrinterDevice) -> String {
        let suffix: String
        if printer.isDefault {
            suffix = printer.kind.isEmpty
                ? String(localized: "Default")
                : "\(printer.kind) · \(String(localized: "Default"))"
        } else {
            suffix = printer.kind
        }
        if suffix.isEmpty { return printer.name }
        return "\(printer.name) (\(suffix))"
    }
}

private struct LabeledNumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
                .multilineTextAlignment(.trailing)
            Text(suffix).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
        }
    }
}

// MARK: - Info bar

private struct InfoBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let l = model.layout
        HStack(spacing: 20) {
            stat(String(localized: "Sheets"),
                 L10n.sheetCount(l.sheetCount, cols: l.cols, rows: l.rows))
            Divider().frame(height: 26)
            stat(String(localized: "Assembly size"),
                 L10n.sizeCm(width: cm(l.canvasSizeMM.width), height: cm(l.canvasSizeMM.height)))
            Divider().frame(height: 26)
            stat(String(localized: "Image size"),
                 L10n.sizeCm(width: cm(l.artworkSizeMM.width), height: cm(l.artworkSizeMM.height)))
            Divider().frame(height: 26)
            stat(String(localized: "Scale"), L10n.scalePercent(Int(l.scalePercent)))
            Divider().frame(height: 26)
            stat(String(localized: "Effective resolution"),
                 dpiText(l.effectiveDPI),
                 warn: l.effectiveDPI < 150)
            if let m = l.marginsMM {
                Divider().frame(height: 26)
                stat(String(localized: "Margins T/B/L/R"),
                     L10n.marginsValue(top: mm(m.top), bottom: mm(m.bottom),
                                       left: mm(m.left), right: mm(m.right)))
            }
            if let o = l.overlapMM {
                Divider().frame(height: 26)
                stat(String(localized: "Overlap"), L10n.overlapValue(mm(o)))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func stat(_ label: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
                .foregroundStyle(warn ? Color.orange : Color.primary)
        }
    }

    private func cm(_ mm: Double) -> String { String(format: "%.1f", mm / 10) }
    private func mm(_ v: Double) -> String { String(format: "%.0f", v) }
    private func dpiText(_ v: Double) -> String {
        v.isFinite ? L10n.dpiValue(Int(v)) : "—"
    }
}

#Preview {
    ContentView()
}
