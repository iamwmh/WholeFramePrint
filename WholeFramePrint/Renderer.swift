//
//  Renderer.swift
//  WholeFramePrint
//
//  Draws PagePlans into a Core Graphics context, exports a multi-page PDF and
//  drives the AppKit print pipeline. All rects in PagePlan use a top-left,
//  y-down origin; the CG context here is native y-up, so rects are flipped.
//

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum PageRenderer {

    /// Flip a top-left/y-down rect into the y-up space of a page of height `h`.
    private static func flip(_ r: CGRect, pageHeight h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// Render a single page. The context origin (0,0) must be the page's
    /// bottom-left corner and the context must be y-up.
    /// Set `overlays` to false for print/export (clean output); preview uses overlays.
    static func draw(_ page: PagePlan,
                     image: CGImage?,
                     config: PrintConfig,
                     overlays: Bool,
                     in ctx: CGContext) {
        let h = page.pageSizePt.height
        let pageRect = CGRect(origin: .zero, size: page.pageSizePt)

        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(pageRect)

        if let image {
            let clip = flip(page.contentClipPt, pageHeight: h)
            ctx.saveGState()
            ctx.clip(to: clip)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: flip(page.imageRectPt, pageHeight: h))
            ctx.restoreGState()
        }

        if overlays {
            let content = flip(page.contentClipPt, pageHeight: h)
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(0.5)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(content.insetBy(dx: 0.25, dy: 0.25))
            ctx.setLineDash(phase: 0, lengths: [])

            if config.showCropMarks {
                drawCropMarks(content, in: ctx)
            }
            if config.showLabels {
                drawLabel(page.label, page: page, in: ctx)
            }
        }
        ctx.restoreGState()
    }

    private static func drawCropMarks(_ rect: CGRect, in ctx: CGContext) {
        let len: CGFloat = 14
        let gap: CGFloat = 3
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(0.6)
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        ]
        for (p, hDir, vDir) in corners {
            ctx.move(to: CGPoint(x: p.x + hDir.dx * gap, y: p.y + hDir.dy * gap))
            ctx.addLine(to: CGPoint(x: p.x + hDir.dx * (gap + len), y: p.y + hDir.dy * (gap + len)))
            ctx.move(to: CGPoint(x: p.x + vDir.dx * gap, y: p.y + vDir.dy * gap))
            ctx.addLine(to: CGPoint(x: p.x + vDir.dx * (gap + len), y: p.y + vDir.dy * (gap + len)))
        }
        ctx.strokePath()
    }

    private static func drawLabel(_ text: String, page: PagePlan, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.55),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let content = flip(page.contentClipPt, pageHeight: page.pageSizePt.height)
        let origin = CGPoint(x: content.minX + 6, y: content.minY + 6)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        str.draw(at: origin)
        _ = size
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - PDF export

    static func makePDF(pages: [PagePlan],
                        image: CGImage?,
                        config: PrintConfig) -> Data? {
        guard !pages.isEmpty else { return nil }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pages[0].pageSizePt)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        for page in pages {
            var box = CGRect(origin: .zero, size: page.pageSizePt)
            ctx.beginPage(mediaBox: &box)
            draw(page, image: image, config: config, overlays: false, in: ctx)
            ctx.endPage()
        }
        ctx.closePDF()
        return data as Data
    }

    static func makeSinglePagePDF(_ page: PagePlan,
                                  image: CGImage?,
                                  config: PrintConfig) -> Data? {
        makePDF(pages: [page], image: image, config: config)
    }

    // MARK: - Raster export (one file per sheet at paper size)

    /// Render one sheet to a bitmap at the given DPI (defaults to 300).
    static func renderRaster(_ page: PagePlan,
                             image: CGImage?,
                             config: PrintConfig,
                             dpi: Double = 300) -> CGImage? {
        let inchesW = page.pageSizePt.width / PT_PER_INCH
        let inchesH = page.pageSizePt.height / PT_PER_INCH
        let width = max(1, Int((inchesW * dpi).rounded()))
        let height = max(1, Int((inchesH * dpi).rounded()))

        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        ctx.scaleBy(x: CGFloat(width) / page.pageSizePt.width,
                    y: CGFloat(height) / page.pageSizePt.height)
        draw(page, image: image, config: config, overlays: false, in: ctx)
        return ctx.makeImage()
    }

    static func writeImage(_ cgImage: CGImage,
                           to url: URL,
                           format: SheetFileFormat,
                           jpegQuality: CGFloat = 0.92) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ExportError.cannotCreateDestination
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.writeFailed
        }
    }
}

enum ExportError: LocalizedError {
    case cannotCreateDestination
    case writeFailed
    case noPages

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestination: L10n.exportCreateError
        case .writeFailed: L10n.exportWriteError
        case .noPages: L10n.exportNoPagesError
        }
    }
}

enum SheetExporter {
    /// Export each page as a separate file into `directory`.
    /// Files are named `{baseName}_R{row}C{col}.{ext}`.
    @discardableResult
    static func exportSeparate(pages: [PagePlan],
                               image: CGImage?,
                               config: PrintConfig,
                               format: SheetFileFormat,
                               to directory: URL,
                               baseName: String,
                               dpi: Double = 300) throws -> Int {
        guard !pages.isEmpty else { throw ExportError.noPages }

        for page in pages {
            let name = "\(baseName)_R\(page.row + 1)C\(page.col + 1).\(format.fileExtension)"
            let url = directory.appendingPathComponent(name)

            switch format {
            case .pdf:
                guard let data = PageRenderer.makeSinglePagePDF(page, image: image, config: config) else {
                    throw ExportError.writeFailed
                }
                try data.write(to: url)
            case .jpeg, .png, .tiff:
                guard let raster = PageRenderer.renderRaster(page, image: image, config: config, dpi: dpi) else {
                    throw ExportError.writeFailed
                }
                try PageRenderer.writeImage(raster, to: url, format: format)
            }
        }
        return pages.count
    }
}

// MARK: - Paginated view used for printing

final class PaginatedPrintView: NSView {
    var pages: [PagePlan] = []
    var image: CGImage?
    var config = PrintConfig()

    private var pageHeight: CGFloat { pages.first?.pageSizePt.height ?? 792 }
    private var pageWidth: CGFloat { pages.first?.pageSizePt.width ?? 612 }

    override var isFlipped: Bool { false }

    func sizeToPages() {
        let count = max(1, pages.count)
        setFrameSize(NSSize(width: pageWidth, height: pageHeight * CGFloat(count)))
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(1, pages.count))
        return true
    }

    override func rectForPage(_ number: Int) -> NSRect {
        // Page 1 sits at the top of the (y-up) view.
        let index = number - 1
        let y = CGFloat(pages.count - 1 - index) * pageHeight
        return NSRect(x: 0, y: y, width: pageWidth, height: pageHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for (index, page) in pages.enumerated() {
            let y = CGFloat(pages.count - 1 - index) * pageHeight
            let frame = CGRect(x: 0, y: y, width: pageWidth, height: pageHeight)
            guard frame.intersects(dirtyRect) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: y)
            PageRenderer.draw(page, image: image, config: config, overlays: false, in: ctx)
            ctx.restoreGState()
        }
    }
}