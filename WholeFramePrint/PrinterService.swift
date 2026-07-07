//
//  PrinterService.swift
//  WholeFramePrint
//
//  Discover installed printers, open system printer setup, and run tiled jobs.
//

import AppKit
import Foundation

struct PrinterDevice: Identifiable, Hashable {
    let name: String
    let isDefault: Bool
    let kind: String
    var id: String { name }
}

enum PrinterService {

    /// All printers registered with the system print subsystem.
    static func discover() -> [PrinterDevice] {
        let defaultName = defaultPrinterName() ?? ""
        var seen = Set<String>()
        var devices: [PrinterDevice] = []

        for name in NSPrinter.printerNames {
            let n = String(describing: name)
            guard seen.insert(n).inserted else { continue }
            devices.append(PrinterDevice(
                name: n,
                isDefault: !defaultName.isEmpty && n == defaultName,
                kind: ""
            ))
        }

        // Always include the system default printer even if it is missing from printerNames.
        if !defaultName.isEmpty, seen.insert(defaultName).inserted {
            devices.append(PrinterDevice(name: defaultName, isDefault: true, kind: ""))
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Whether the system reports any usable printer (default or installed list).
    static var systemCanPrint: Bool {
        if let name = defaultPrinterName(), !name.isEmpty { return true }
        return !NSPrinter.printerNames.isEmpty
    }

    static func defaultPrinterName() -> String? {
        let name = NSPrintInfo.shared.printer.name
        return name.isEmpty ? nil : name
    }

    /// Opens macOS printer settings so the user can add or configure printers.
    @discardableResult
    static func openAddPrinterSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.printfax",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Print.prefPane"))
    }
}

// MARK: - Print operation

enum PrintService {

    /// Show the system print panel and spool the tiled layout.
    /// Returns `true` when the user confirms printing (does not wait for the physical job to finish).
    @MainActor
    @discardableResult
    static func run(pages: [PagePlan],
                    image: CGImage?,
                    config: PrintConfig,
                    printerName: String?) -> Bool {
        guard !pages.isEmpty else { return false }

        let view = PaginatedPrintView()
        view.pages = pages
        view.image = image
        view.config = config
        view.sizeToPages()

        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = pages[0].pageSizePt
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.orientation = pages[0].pageSizePt.width > pages[0].pageSizePt.height ? .landscape : .portrait
        info.jobDisposition = .spool

        // Use the system default printer, or the user's in-app selection if valid.
        if let printerName, !printerName.isEmpty, let printer = NSPrinter(name: printerName) {
            info.printer = printer
        } else if let defaultName = PrinterService.defaultPrinterName(),
                  let printer = NSPrinter(name: defaultName) {
            info.printer = printer
        }
        // Otherwise NSPrintInfo.shared (copied above) keeps the system default.

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        // Print panel lists every printer installed in macOS; user can switch there too.

        return op.run()
    }
}
