import UIKit
import MetalKit

struct ReceiptTextureRenderer {

    @MainActor
    static func renderReceiptTexture(device: MTLDevice, width: Int = 512, height: Int = 768) -> MTLTexture? {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let cg = ctx.cgContext

            // Off-white receipt paper background
            UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0).setFill()
            cg.fill(rect)

            let black = UIColor.black
            let gray = UIColor(white: 0.45, alpha: 1.0)
            let lightGray = UIColor(white: 0.7, alpha: 1.0)

            func drawCentered(_ text: String, at y: CGFloat, font: UIFont, color: UIColor = black) {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
                let textRect = CGRect(x: 24, y: y, width: size.width - 48, height: 50)
                (text as NSString).draw(in: textRect, withAttributes: attrs)
            }

            func drawRow(_ left: String, _ right: String, at y: CGFloat, font: UIFont, color: UIColor = black) {
                let leftAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let rightStyle = NSMutableParagraphStyle()
                rightStyle.alignment = .right
                let rightAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: rightStyle]
                (left as NSString).draw(in: CGRect(x: 32, y: y, width: size.width / 2 - 32, height: 28), withAttributes: leftAttrs)
                (right as NSString).draw(in: CGRect(x: size.width / 2, y: y, width: size.width / 2 - 32, height: 28), withAttributes: rightAttrs)
            }

            func drawSolidLine(at y: CGFloat) {
                cg.setStrokeColor(UIColor(white: 0.75, alpha: 1.0).cgColor)
                cg.setLineWidth(1.5)
                cg.move(to: CGPoint(x: 28, y: y))
                cg.addLine(to: CGPoint(x: size.width - 28, y: y))
                cg.strokePath()
            }

            func drawDottedLine(at y: CGFloat) {
                cg.setStrokeColor(UIColor(white: 0.75, alpha: 1.0).cgColor)
                cg.setLineWidth(1)
                cg.setLineDash(phase: 0, lengths: [4, 3])
                cg.move(to: CGPoint(x: 28, y: y))
                cg.addLine(to: CGPoint(x: size.width - 28, y: y))
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
            }

            let titleFont = UIFont.monospacedSystemFont(ofSize: 28, weight: .black)
            let subtitleFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let bodyFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
            let boldBody = UIFont.monospacedSystemFont(ofSize: 18, weight: .bold)
            let smallFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            var y: CGFloat = 28

            // @angularpk at very top
            drawCentered("@angularpk", at: y, font: UIFont.monospacedSystemFont(ofSize: 32, weight: .medium), color: gray)
            y += 38

            // Shop name
            drawCentered("THE ANGULARPK SHOP", at: y, font: titleFont)
            y += 38
            drawCentered("42 Mesh Lane, WebGL City", at: y, font: subtitleFont, color: gray)
            y += 22
            drawCentered("Tel: (555) 042-1337", at: y, font: subtitleFont, color: gray)
            y += 30

            drawSolidLine(at: y)
            y += 20

            // Date & Order
            let dateAttrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: black]
            ("Date: 2026-02-24  14:17" as NSString).draw(in: CGRect(x: 32, y: y, width: 300, height: 22), withAttributes: dateAttrs)
            y += 22
            ("Order: #00382" as NSString).draw(in: CGRect(x: 32, y: y, width: 300, height: 22), withAttributes: dateAttrs)
            y += 30

            drawDottedLine(at: y)
            y += 20

            // Line items
            let items: [(String, String)] = [
                ("Vertex Shader", "$4.20"),
                ("Fragment Shader", "$3.50"),
                ("Normal Map", "$2.80"),
                ("UV Unwrap", "$1.50"),
                ("Cloth Simulation", "$6.00"),
            ]
            for (label, price) in items {
                drawRow(label, price, at: y, font: bodyFont)
                y += 28
            }

            y += 10
            drawDottedLine(at: y)
            y += 20

            // Subtotal & Tax
            drawRow("Subtotal", "$18.00", at: y, font: bodyFont)
            y += 28
            drawRow("Tax (8%)", "$1.44", at: y, font: bodyFont)
            y += 34

            drawSolidLine(at: y)
            y += 20

            // Total
            drawRow("TOTAL", "$19.44", at: y, font: boldBody)
            y += 34

            drawDottedLine(at: y)
            y += 30

            // Footer
            drawCentered("Thank you for visiting!", at: y, font: subtitleFont, color: gray)
            y += 24
            drawCentered("github.com/angularpk", at: y, font: smallFont, color: lightGray)
        }

        guard let cgImage = image.cgImage else { return nil }

        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(cgImage: cgImage, options: [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.shared.rawValue)
        ])
    }
}
