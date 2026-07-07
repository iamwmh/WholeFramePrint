//
//  PreviewView.swift
//  WholeFramePrint
//
//  Faithful on-screen preview of the tiled layout. Each cell mirrors exactly
//  what one physical sheet will print, arranged in the assembly grid.
//

import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let layout = model.layout
            if layout.isEmpty {
                EmptyState()
            } else {
                content(in: geo.size, layout: layout)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func content(in available: CGSize, layout: LayoutResult) -> some View {
        let gap: CGFloat = 10
        let cols = CGFloat(layout.cols)
        let rows = CGFloat(layout.rows)
        let pageW = layout.pageSizePt.width
        let pageH = layout.pageSizePt.height
        let gridW = cols * pageW + (cols - 1) * gap
        let gridH = rows * pageH + (rows - 1) * gap
        let pad: CGFloat = 32
        let scale = max(0.02, min((available.width - pad) / gridW,
                                  (available.height - pad) / gridH))

        return VStack(spacing: gap * scale) {
            ForEach(0..<layout.rows, id: \.self) { r in
                HStack(spacing: gap * scale) {
                    ForEach(0..<layout.cols, id: \.self) { c in
                        if let page = pageAt(layout, r, c) {
                            SheetCell(page: page,
                                      image: model.nsImage,
                                      config: model.config,
                                      scale: scale)
                        }
                    }
                }
            }
        }
        .frame(width: available.width, height: available.height)
    }

    private func pageAt(_ layout: LayoutResult, _ r: Int, _ c: Int) -> PagePlan? {
        layout.pages.first { $0.row == r && $0.col == c }
    }
}

private struct SheetCell: View {
    let page: PagePlan
    let image: NSImage?
    let config: PrintConfig
    let scale: CGFloat

    var body: some View {
        let s = scale
        let pw = page.pageSizePt.width * s
        let ph = page.pageSizePt.height * s
        let clip = page.contentClipPt
        let img = page.imageRectPt

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .frame(width: pw, height: ph)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)

            // Image clipped to the sheet's content area.
            if let image {
                Color.clear
                    .frame(width: clip.width * s, height: clip.height * s)
                    .overlay(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: img.width * s, height: img.height * s)
                            .offset(x: (img.minX - clip.minX) * s,
                                    y: (img.minY - clip.minY) * s)
                    }
                    .clipped()
                    .offset(x: clip.minX * s, y: clip.minY * s)
            }

            // Content boundary guide.
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(.blue.opacity(0.4))
                .frame(width: clip.width * s, height: clip.height * s)
                .offset(x: clip.minX * s, y: clip.minY * s)

            if config.showCropMarks {
                CropMarks(rect: CGRect(x: clip.minX * s, y: clip.minY * s,
                                       width: clip.width * s, height: clip.height * s))
            }

            if config.showLabels {
                Text(page.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
                    .padding(3)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: clip.minX * s + 4, y: clip.minY * s + 4)
            }
        }
        .frame(width: pw, height: ph)
    }
}

private struct CropMarks: View {
    let rect: CGRect
    var body: some View {
        Path { p in
            let len: CGFloat = 12, gap: CGFloat = 3
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
                (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
                (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
                (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
            ]
            for (pt, hx, vy) in corners {
                p.move(to: CGPoint(x: pt.x + hx * gap, y: pt.y))
                p.addLine(to: CGPoint(x: pt.x + hx * (gap + len), y: pt.y))
                p.move(to: CGPoint(x: pt.x, y: pt.y + vy * gap))
                p.addLine(to: CGPoint(x: pt.x, y: pt.y + vy * (gap + len)))
            }
        }
        .stroke(Color.black.opacity(0.7), lineWidth: 0.8)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Drop or open an image to begin tiled printing")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Calligraphy, painting, photography and other large artworks")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
