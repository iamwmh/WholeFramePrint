//
//  Models.swift
//  WholeFramePrint
//
//  Core value types: paper sizes, units, print configuration and the
//  per-sheet layout plan produced by the layout engine.
//

import Foundation
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Unit conversion helpers

let MM_PER_INCH = 25.4
let PT_PER_INCH = 72.0
/// Golden ratio φ.
let PHI = 1.618_033_988_749_895

@inline(__always) func mmToPt(_ mm: Double) -> Double { mm / MM_PER_INCH * PT_PER_INCH }
@inline(__always) func ptToMM(_ pt: Double) -> Double { pt / PT_PER_INCH * MM_PER_INCH }

enum LengthUnit: String, CaseIterable, Identifiable {
    case mm, cm, inch
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .mm: return "mm"
        case .cm: return "cm"
        case .inch: return "in"
        }
    }
    /// Convert a value expressed in this unit into millimetres.
    func toMM(_ value: Double) -> Double {
        switch self {
        case .mm: return value
        case .cm: return value * 10
        case .inch: return value * MM_PER_INCH
        }
    }
    /// Convert a millimetre value into this unit.
    func fromMM(_ mm: Double) -> Double {
        switch self {
        case .mm: return mm
        case .cm: return mm / 10
        case .inch: return mm / MM_PER_INCH
        }
    }
}

// MARK: - Paper

struct PaperSize: Identifiable, Hashable {
    let name: String
    /// Portrait short side (mm).
    let widthMM: Double
    /// Portrait long side (mm).
    let heightMM: Double
    var id: String { name }

    static let all: [PaperSize] = [
        .init(name: "A5", widthMM: 148, heightMM: 210),
        .init(name: "A4", widthMM: 210, heightMM: 297),
        .init(name: "A3", widthMM: 297, heightMM: 420),
        .init(name: "A2", widthMM: 420, heightMM: 594),
        .init(name: "A1", widthMM: 594, heightMM: 841),
        .init(name: "Letter", widthMM: 215.9, heightMM: 279.4),
        .init(name: "Legal", widthMM: 215.9, heightMM: 355.6),
        .init(name: "Tabloid", widthMM: 279.4, heightMM: 431.8),
    ]

    /// Size in millimetres taking orientation into account.
    func sizeMM(_ orientation: PageOrientation) -> CGSize {
        switch orientation {
        case .portrait: return CGSize(width: widthMM, height: heightMM)
        case .landscape: return CGSize(width: heightMM, height: widthMM)
        }
    }
}

enum PageOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape
    var id: String { rawValue }
}

enum PrintMode: String, CaseIterable, Identifiable {
    /// 100 % actual-size tiling across as many sheets as needed.
    case actualSize
    /// Fit the whole picture onto a chosen grid of sheets with golden-ratio margins.
    case fitSheets
    var id: String { rawValue }
}

// MARK: - Margins

struct EdgeInsetsMM: Equatable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double
}

// MARK: - Configuration driving the layout engine

struct PrintConfig {
    var mode: PrintMode = .actualSize
    var paper: PaperSize = PaperSize.all[1]   // A4
    var orientation: PageOrientation = .portrait
    var unit: LengthUnit = .cm

    // --- Actual-size mode ---
    /// Desired physical width of the whole artwork (mm).
    var targetWidthMM: Double = 600
    /// Overlap between neighbouring sheets for gluing (mm).
    var overlapMM: Double = 10
    /// Non-printable safe margin on assembly outer edges only (mm).
    /// Inner sheets print edge-to-edge when `centerInAssembly` is enabled.
    var printerMarginMM: Double = 5
    /// Center the image in the sheet grid; margins apply only on the assembly perimeter.
    var centerInAssembly: Bool = true

    // --- Fit-to-sheets mode ---
    var cols: Int = 2
    var rows: Int = 2
    /// Base margin as a fraction of the canvas short side (0…0.45).
    var marginFraction: Double = 0.191   // ≈ (1 − 1/φ) / 2  → picture spans ~0.618 of canvas
    /// If true the bottom margin is φ× the top margin (traditional mounting).
    var goldenBottomHeavy: Bool = true
    /// If true assume borderless / trim-and-butt printing (content fills each sheet).
    var bleedTrim: Bool = true

    // Overlays
    var showCropMarks: Bool = true
    var showLabels: Bool = true
}

// MARK: - Layout output

/// Everything needed to draw one physical sheet.
struct PagePlan: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let pageSizePt: CGSize
    /// Placement of the *entire* image in this page's coordinate space
    /// (top-left origin, y-down). May extend beyond the page bounds.
    let imageRectPt: CGRect
    /// Region of the page the image is clipped to (content / printable area).
    let contentClipPt: CGRect
    var label: String { L10n.pageLabel(row: row, col: col) }
}

struct LayoutResult {
    var pages: [PagePlan] = []
    var cols: Int = 0
    var rows: Int = 0
    var pageSizePt: CGSize = .zero

    /// Visible artwork size after layout (mm).
    var artworkSizeMM: CGSize = .zero
    /// Full assembled paper size (mm).
    var canvasSizeMM: CGSize = .zero
    var scalePercent: Double = 100
    var effectiveDPI: Double = 0

    /// Outer margins around the artwork (fit mode only).
    var marginsMM: EdgeInsetsMM?
    /// Overlap between sheets (actual-size mode only).
    var overlapMM: Double?

    var sheetCount: Int { pages.count }
    var isEmpty: Bool { pages.isEmpty }
}

// MARK: - Export

enum SheetFileFormat: String, CaseIterable, Identifiable {
    case pdf, jpeg, png, tiff
    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: return .pdf
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        }
    }
}
