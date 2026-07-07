//
//  L10n.swift
//  WholeFramePrint
//
//  Centralized localized strings for programmatic use (errors, labels, formats).
//  UI strings in SwiftUI views use English keys directly; this file covers
//  everything that cannot rely on automatic Text() extraction.
//

import Foundation

enum L10n {
    // MARK: - Errors

    static let imageReadError = String(localized: "Unable to read this image file.")
    static let pdfGenerateError = String(localized: "Failed to generate PDF.")
    static let exportCreateError = String(localized: "Could not create export file.")
    static let exportWriteError = String(localized: "Failed to write export file.")
    static let exportNoPagesError = String(localized: "No pages to export.")
    static func saveFailed(_ detail: String) -> String {
        String(localized: "Save failed: \(detail)")
    }

    static func exportFolderMessage(format: SheetFileFormat, count: Int) -> String {
        String(localized: "Choose a folder to save \(count) \(format.exportLabel) files.")
    }

    static func sheetFileFormat(_ format: SheetFileFormat) -> String {
        switch format {
        case .pdf: String(localized: "PDF")
        case .jpeg: String(localized: "JPEG")
        case .png: String(localized: "PNG")
        case .tiff: String(localized: "TIFF")
        }
    }

    // MARK: - PDF default name

    static let tiledPrintDefaultName = String(localized: "Tiled Print")
    static let pdfSuffix = String(localized: "_tiled.pdf")

    // MARK: - Enums

    static func lengthUnit(_ unit: LengthUnit) -> String {
        switch unit {
        case .mm: String(localized: "Millimeters")
        case .cm: String(localized: "Centimeters")
        case .inch: String(localized: "Inches")
        }
    }

    static func orientation(_ o: PageOrientation) -> String {
        switch o {
        case .portrait: String(localized: "Portrait")
        case .landscape: String(localized: "Landscape")
        }
    }

    static func printModeLabel(_ mode: PrintMode) -> String {
        switch mode {
        case .actualSize: String(localized: "Actual Size (100%)")
        case .fitSheets: String(localized: "Fit to Sheets · Smart Scale")
        }
    }

    static func printModeSubtitle(_ mode: PrintMode) -> String {
        switch mode {
        case .actualSize: String(localized: "Split the image at true physical size across multiple sheets")
        case .fitSheets: String(localized: "Scale and lay out on a chosen number of sheets with golden-ratio margins")
        }
    }

    // MARK: - Formatted values

    static func pageLabel(row: Int, col: Int) -> String {
        String(localized: "R\(row + 1)·C\(col + 1)")
    }

    static func paperPickerLabel(name: String, width: String, height: String) -> String {
        String(localized: "\(name) (\(width)×\(height) mm)")
    }

    static func heightAuto(value: String, unit: String) -> String {
        String(localized: "Height auto: \(value) \(unit)")
    }

    static func columnsCount(_ n: Int) -> String {
        String(localized: "Columns: \(n)")
    }

    static func rowsCount(_ n: Int) -> String {
        String(localized: "Rows: \(n)")
    }

    static func marginRatio(_ percent: Int) -> String {
        String(localized: "Margin ratio: \(percent)%")
    }

    static func imageCoverage(_ percent: Int) -> String {
        String(localized: "Image covers ~\(percent)% · golden ratio 0.618")
    }

    static func sheetCount(_ count: Int, cols: Int, rows: Int) -> String {
        String(localized: "\(count) sheets (\(cols)×\(rows))")
    }

    static func sizeCm(width: String, height: String) -> String {
        "\(width) × \(height) cm"
    }

    static func scalePercent(_ n: Int) -> String {
        "\(n)%"
    }

    static func dpiValue(_ n: Int) -> String {
        "\(n) dpi"
    }

    static func marginsValue(top: String, bottom: String, left: String, right: String) -> String {
        "\(top)/\(bottom)/\(left)/\(right) mm"
    }

    static func overlapValue(_ mm: String) -> String {
        "\(mm) mm"
    }

    // MARK: - Printer

    static let noPrintersFound = String(localized: "No printers are installed. Add a printer in System Settings, then click Refresh.")
    static let addPrinterOpenedSettings = String(localized: "Printer settings opened. Add your printer, then click Refresh.")
    static let addPrinterSettingsFailed = String(localized: "Could not open printer settings.")
    static let printCancelled = String(localized: "Printing was cancelled.")
    static func printJobSent(_ count: Int) -> String {
        String(localized: "Sent \(count) sheets to the printer.")
    }
    static func printSheets(_ count: Int) -> String {
        String(localized: "Print \(count) sheets…")
    }

    static let printerKindLaser = String(localized: "Laser")
    static let printerKindInkjet = String(localized: "Inkjet")
    static let printerKindLine = String(localized: "Line printer")
    static let printerKindSerial = String(localized: "Serial")
    static let printerKindUnknown = String(localized: "Printer")
}

extension SheetFileFormat {
    var exportLabel: String { L10n.sheetFileFormat(self) }

    var separateExportMenuTitle: String {
        switch self {
        case .pdf: String(localized: "Separate PDFs…")
        case .jpeg: String(localized: "Separate JPEGs…")
        case .png: String(localized: "Separate PNGs…")
        case .tiff: String(localized: "Separate TIFFs…")
        }
    }
}
