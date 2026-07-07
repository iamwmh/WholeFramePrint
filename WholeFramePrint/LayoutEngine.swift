//
//  LayoutEngine.swift
//  WholeFramePrint
//
//  Pure geometry: turns a PrintConfig + image size into a set of PagePlans.
//  No AppKit / drawing here so the maths is easy to reason about and test.
//

import Foundation
import CoreGraphics

enum LayoutEngine {

    /// Entry point. `imagePixels` is the pixel size of the source image,
    /// `imageDPI` its native resolution (used to derive real-world size).
    static func compute(config: PrintConfig,
                        imagePixels: CGSize,
                        imageDPI: Double) -> LayoutResult {
        guard imagePixels.width > 0, imagePixels.height > 0 else { return LayoutResult() }
        switch config.mode {
        case .actualSize:
            return config.centerInAssembly
                ? actualSizeCentered(config, imagePixels: imagePixels, dpi: max(1, imageDPI))
                : actualSizeLegacy(config, imagePixels: imagePixels, dpi: max(1, imageDPI))
        case .fitSheets:
            return fitSheets(config, imagePixels: imagePixels, dpi: max(1, imageDPI))
        }
    }

    // MARK: - Shared page builder (centered assembly, per-edge margins)

    /// Build page plans for an image placed at `(leftM, topM)` on a canvas of
    /// `cols × rows` sheets. When `centerInAssembly` is true, `outerMarginMM`
    /// is applied only on the assembly perimeter; inner sheets are full bleed.
    private static func buildPages(cols: Int,
                                   rows: Int,
                                   pw: Double,
                                   ph: Double,
                                   artW: Double,
                                   artH: Double,
                                   leftM: Double,
                                   topM: Double,
                                   overlapMM: Double,
                                   outerMarginMM: Double,
                                   centerInAssembly: Bool) -> [PagePlan] {
        let pageSizePt = CGSize(width: mmToPt(pw), height: mmToPt(ph))
        let outer = max(0, outerMarginMM)
        let overlap = max(0, overlapMM)
        let stepX = pw - overlap
        let stepY = ph - overlap

        var pages: [PagePlan] = []
        for r in 0..<rows {
            for col in 0..<cols {
                let originX = Double(col) * stepX
                let originY = Double(r) * stepY

                let imageRect = CGRect(x: mmToPt(leftM - originX),
                                       y: mmToPt(topM - originY),
                                       width: mmToPt(artW),
                                       height: mmToPt(artH))

                let mLeft: Double
                let mRight: Double
                let mTop: Double
                let mBottom: Double
                if centerInAssembly {
                    mLeft = col == 0 ? outer : 0
                    mRight = col == cols - 1 ? outer : 0
                    mTop = r == 0 ? outer : 0
                    mBottom = r == rows - 1 ? outer : 0
                } else {
                    mLeft = outer
                    mRight = outer
                    mTop = outer
                    mBottom = outer
                }

                let clip = CGRect(x: mmToPt(mLeft),
                                  y: mmToPt(mTop),
                                  width: mmToPt(max(1, pw - mLeft - mRight)),
                                  height: mmToPt(max(1, ph - mTop - mBottom)))

                pages.append(PagePlan(row: r, col: col,
                                      pageSizePt: pageSizePt,
                                      imageRectPt: imageRect,
                                      contentClipPt: clip))
            }
        }
        return pages
    }

    private static func canvasSizeMM(cols: Int, rows: Int,
                                     pw: Double, ph: Double,
                                     overlap: Double) -> CGSize {
        let canvasW = Double(cols) * pw - Double(max(0, cols - 1)) * overlap
        let canvasH = Double(rows) * ph - Double(max(0, rows - 1)) * overlap
        return CGSize(width: canvasW, height: canvasH)
    }

    // MARK: - Mode 1a: actual size, centered in assembly

    private static func actualSizeCentered(_ c: PrintConfig,
                                           imagePixels: CGSize,
                                           dpi: Double) -> LayoutResult {
        let aspect = Double(imagePixels.width / imagePixels.height)
        let pageMM = c.paper.sizeMM(c.orientation)
        let pw = Double(pageMM.width)
        let ph = Double(pageMM.height)

        let artW = max(1, c.targetWidthMM)
        let artH = artW / aspect

        let overlap = max(0, min(c.overlapMM, min(pw, ph) - 1))
        let stepX = max(1, pw - overlap)
        let stepY = max(1, ph - overlap)

        let cols = max(1, Int(ceil((artW - overlap) / stepX - 1e-6)))
        let rows = max(1, Int(ceil((artH - overlap) / stepY - 1e-6)))

        let canvas = canvasSizeMM(cols: cols, rows: rows, pw: pw, ph: ph, overlap: overlap)
        let leftM = max(0, (canvas.width - artW) / 2)
        let topM = max(0, (canvas.height - artH) / 2)

        let pages = buildPages(cols: cols, rows: rows, pw: pw, ph: ph,
                               artW: artW, artH: artH,
                               leftM: leftM, topM: topM,
                               overlapMM: overlap,
                               outerMarginMM: c.printerMarginMM,
                               centerInAssembly: true)

        var result = LayoutResult()
        result.pages = pages
        result.cols = cols
        result.rows = rows
        result.pageSizePt = pages.first?.pageSizePt ?? .zero
        result.artworkSizeMM = CGSize(width: artW, height: artH)
        result.canvasSizeMM = canvas
        let nativeWidthMM = Double(imagePixels.width) / dpi * MM_PER_INCH
        result.scalePercent = nativeWidthMM > 0 ? artW / nativeWidthMM * 100 : 100
        result.effectiveDPI = Double(imagePixels.width) / (artW / MM_PER_INCH)
        result.overlapMM = overlap
        result.marginsMM = EdgeInsetsMM(top: topM, left: leftM,
                                        bottom: canvas.height - topM - artH,
                                        right: canvas.width - leftM - artW)
        return result
    }

    // MARK: - Mode 1b: actual size, legacy (uniform margin on every sheet)

    private static func actualSizeLegacy(_ c: PrintConfig,
                                         imagePixels: CGSize,
                                         dpi: Double) -> LayoutResult {
        let aspect = Double(imagePixels.width / imagePixels.height)
        let pageMM = c.paper.sizeMM(c.orientation)
        let pw = Double(pageMM.width)
        let ph = Double(pageMM.height)

        let artW = max(1, c.targetWidthMM)
        let artH = artW / aspect

        let margin = max(0, min(c.printerMarginMM, min(pw, ph) / 2 - 1))
        let usableW = max(1, pw - 2 * margin)
        let usableH = max(1, ph - 2 * margin)

        let overlap = max(0, min(c.overlapMM, min(usableW, usableH) - 1))
        let stepX = max(1, usableW - overlap)
        let stepY = max(1, usableH - overlap)

        let cols = max(1, Int(ceil((artW - overlap) / stepX - 1e-6)))
        let rows = max(1, Int(ceil((artH - overlap) / stepY - 1e-6)))

        let pageSizePt = CGSize(width: mmToPt(pw), height: mmToPt(ph))
        let marginPt = mmToPt(margin)

        var pages: [PagePlan] = []
        for r in 0..<rows {
            for col in 0..<cols {
                let offX = Double(col) * stepX
                let offY = Double(r) * stepY
                let imageRect = CGRect(x: marginPt - mmToPt(offX),
                                       y: marginPt - mmToPt(offY),
                                       width: mmToPt(artW),
                                       height: mmToPt(artH))
                let clipW = min(usableW, artW - offX)
                let clipH = min(usableH, artH - offY)
                let clip = CGRect(x: marginPt, y: marginPt,
                                  width: mmToPt(max(0, clipW)),
                                  height: mmToPt(max(0, clipH)))
                pages.append(PagePlan(row: r, col: col,
                                      pageSizePt: pageSizePt,
                                      imageRectPt: imageRect,
                                      contentClipPt: clip))
            }
        }

        var result = LayoutResult()
        result.pages = pages
        result.cols = cols
        result.rows = rows
        result.pageSizePt = pageSizePt
        result.artworkSizeMM = CGSize(width: artW, height: artH)
        result.canvasSizeMM = CGSize(width: pw * Double(cols),
                                     height: ph * Double(rows))
        let nativeWidthMM = Double(imagePixels.width) / dpi * MM_PER_INCH
        result.scalePercent = nativeWidthMM > 0 ? artW / nativeWidthMM * 100 : 100
        result.effectiveDPI = Double(imagePixels.width) / (artW / MM_PER_INCH)
        result.overlapMM = overlap
        return result
    }

    // MARK: - Mode 2: fit onto a grid with golden-ratio margins

    private static func fitSheets(_ c: PrintConfig,
                                  imagePixels: CGSize,
                                  dpi: Double) -> LayoutResult {
        let aspect = Double(imagePixels.width / imagePixels.height)
        let pageMM = c.paper.sizeMM(c.orientation)
        let pw = Double(pageMM.width)
        let ph = Double(pageMM.height)
        let cols = max(1, c.cols)
        let rows = max(1, c.rows)

        let canvasW = pw * Double(cols)
        let canvasH = ph * Double(rows)

        let unit = max(0, min(c.marginFraction, 0.45)) * min(canvasW, canvasH)
        let side0 = unit
        let top0 = unit
        let bottom0 = c.goldenBottomHeavy ? unit * PHI : unit

        let innerW = max(1, canvasW - 2 * side0)
        let innerH = max(1, canvasH - top0 - bottom0)

        var imgW = innerW
        var imgH = innerW / aspect
        if imgH > innerH {
            imgH = innerH
            imgW = innerH * aspect
        }

        let slackX = max(0, canvasW - imgW)
        let leftM = slackX / 2
        let rightM = slackX / 2

        let slackY = max(0, canvasH - imgH)
        let topM: Double
        let bottomM: Double
        if c.goldenBottomHeavy {
            topM = slackY / (1 + PHI)
            bottomM = slackY * PHI / (1 + PHI)
        } else {
            topM = slackY / 2
            bottomM = slackY / 2
        }

        let outerMargin = c.bleedTrim ? 0 : max(0, c.printerMarginMM)
        let pages = buildPages(cols: cols, rows: rows, pw: pw, ph: ph,
                               artW: imgW, artH: imgH,
                               leftM: leftM, topM: topM,
                               overlapMM: 0,
                               outerMarginMM: outerMargin,
                               centerInAssembly: c.centerInAssembly)

        var result = LayoutResult()
        result.pages = pages
        result.cols = cols
        result.rows = rows
        result.pageSizePt = pages.first?.pageSizePt ?? .zero
        result.artworkSizeMM = CGSize(width: imgW, height: imgH)
        result.canvasSizeMM = CGSize(width: canvasW, height: canvasH)
        let nativeWidthMM = Double(imagePixels.width) / dpi * MM_PER_INCH
        result.scalePercent = nativeWidthMM > 0 ? imgW / nativeWidthMM * 100 : 100
        result.effectiveDPI = Double(imagePixels.width) / (imgW / MM_PER_INCH)
        result.marginsMM = EdgeInsetsMM(top: topM, left: leftM, bottom: bottomM, right: rightM)
        return result
    }

    /// Suggest a grid (cols × rows) for `fitSheets` that best matches the image
    /// aspect for a target number of sheets.
    static func suggestGrid(imagePixels: CGSize,
                            paper: PaperSize,
                            orientation: PageOrientation,
                            targetSheets: Int) -> (cols: Int, rows: Int) {
        guard imagePixels.width > 0, imagePixels.height > 0, targetSheets >= 1 else {
            return (1, 1)
        }
        let page = paper.sizeMM(orientation)
        let pw = Double(page.width)
        let ph = Double(page.height)
        let imgAspect = Double(imagePixels.width / imagePixels.height)
        var best = (cols: 1, rows: 1)
        var bestScore = Double.greatestFiniteMagnitude
        for cols in 1...targetSheets {
            for rows in 1...targetSheets where cols * rows >= targetSheets && cols * rows <= targetSheets + 2 {
                let canvasAspect = (pw * Double(cols)) / (ph * Double(rows))
                let score = abs(log(canvasAspect) - log(imgAspect))
                if score < bestScore {
                    bestScore = score
                    best = (cols, rows)
                }
            }
        }
        return best
    }
}
