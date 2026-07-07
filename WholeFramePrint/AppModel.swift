//
//  AppModel.swift
//  WholeFramePrint
//
//  Observable state for the whole app: the loaded image, the print
//  configuration and the derived layout.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class AppModel: ObservableObject {
    @Published var nsImage: NSImage?
    @Published var cgImage: CGImage?
    @Published var imagePixels: CGSize = .zero
    @Published var imageDPI: Double = 300
    @Published var fileName: String = ""

    @Published var config = PrintConfig() {
        didSet { recompute() }
    }

    @Published private(set) var layout = LayoutResult()
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published private(set) var printers: [PrinterDevice] = []
    @Published var selectedPrinterName: String?

    var hasImage: Bool { cgImage != nil }
    var hasPrinters: Bool { PrinterService.systemCanPrint || !printers.isEmpty }

    init() {
        refreshPrinters()
    }

    // MARK: - Image loading

    func loadImage(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            errorMessage = L10n.imageReadError
            return
        }

        var dpi = 300.0
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            if let d = props[kCGImagePropertyDPIWidth] as? Double, d > 1 { dpi = d }
        }

        cgImage = cg
        nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        imagePixels = CGSize(width: cg.width, height: cg.height)
        imageDPI = dpi
        fileName = url.lastPathComponent
        errorMessage = nil

        // Seed a sensible default target width from the native size.
        let nativeWidthMM = imagePixels.width / dpi * MM_PER_INCH
        config.targetWidthMM = max(100, (nativeWidthMM).rounded())

        // Match orientation to the image.
        config.orientation = imagePixels.width >= imagePixels.height ? .landscape : .portrait
        autoSuggestGrid()
        recompute()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    // MARK: - Layout

    func recompute() {
        guard hasImage else { layout = LayoutResult(); return }
        layout = LayoutEngine.compute(config: config,
                                      imagePixels: imagePixels,
                                      imageDPI: imageDPI)
    }

    func autoSuggestGrid() {
        guard hasImage else { return }
        let target = max(2, config.cols * config.rows)
        let g = LayoutEngine.suggestGrid(imagePixels: imagePixels,
                                         paper: config.paper,
                                         orientation: config.orientation,
                                         targetSheets: target)
        config.cols = g.cols
        config.rows = g.rows
    }

    // MARK: - Printers

    func refreshPrinters() {
        printers = PrinterService.discover()
        if let selected = selectedPrinterName,
           printers.contains(where: { $0.name == selected }) {
            return
        }
        selectedPrinterName = printers.first(where: \.isDefault)?.name ?? printers.first?.name
    }

    func openAddPrinter() {
        if PrinterService.openAddPrinterSettings() {
            successMessage = L10n.addPrinterOpenedSettings
        } else {
            errorMessage = L10n.addPrinterSettingsFailed
        }
    }

    // MARK: - Output

    func printLayout() {
        guard hasImage else { return }
        refreshPrinters()
        let printer = selectedPrinterName
            ?? printers.first(where: \.isDefault)?.name
            ?? printers.first?.name
            ?? PrinterService.defaultPrinterName()

        let ok = PrintService.run(
            pages: layout.pages,
            image: cgImage,
            config: config,
            printerName: printer
        )
        if ok {
            successMessage = L10n.printJobSent(layout.sheetCount)
            errorMessage = nil
        } else {
            errorMessage = L10n.printCancelled
        }
        refreshPrinters()
    }

    func exportCombinedPDF() {
        guard hasImage,
              let data = PageRenderer.makePDF(pages: layout.pages, image: cgImage, config: config) else {
            errorMessage = L10n.pdfGenerateError
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = exportBaseName
        panel.nameFieldStringValue = base + L10n.pdfSuffix
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                errorMessage = L10n.saveFailed(error.localizedDescription)
            }
        }
    }

    func exportSeparateSheets(format: SheetFileFormat) {
        guard hasImage, !layout.pages.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export")
        panel.message = L10n.exportFolderMessage(format: format, count: layout.pages.count)

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }

        do {
            let count = try SheetExporter.exportSeparate(
                pages: layout.pages,
                image: cgImage,
                config: config,
                format: format,
                to: directory,
                baseName: exportBaseName,
                dpi: max(72, layout.effectiveDPI)
            )
            errorMessage = nil
            _ = count
        } catch {
            errorMessage = L10n.saveFailed(error.localizedDescription)
        }
    }

    private var exportBaseName: String {
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? L10n.tiledPrintDefaultName : base
    }
}
