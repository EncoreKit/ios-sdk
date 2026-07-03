//
//  ConfettiView.swift
//  Encore
//
//  Native one-shot confetti burst for the SDUI `confetti` element. SDUI JSON
//  can't express particle systems, so this wraps a CAEmitterLayer in a
//  UIViewRepresentable. It emits for a fixed duration then stops (birthRate 0)
//  so it settles without burning CPU, and never intercepts touches beneath it.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

/// SwiftUI bridge to the native confetti emitter. Non-interactive by
/// construction — the hosting UIView disables user interaction and the SwiftUI
/// wrapper disables hit testing, so it can be layered as a celebratory overlay
/// above tappable buttons without stealing their taps.
@available(iOS 17.0, *)
struct ConfettiView: UIViewRepresentable {
    /// Colors for the confetti pieces. Empty falls back to a festive palette.
    let colors: [UIColor]
    /// Total pieces-per-second, spread across the colors.
    let intensity: Int
    /// Seconds the emitter emits before it stops and settles.
    let duration: Double
    /// Fraction (0...1) of the container height for the emission line. 0 = top.
    let originY: Double
    /// Fraction (0...1) of the container width for a POINT burst, or nil for the
    /// default full-width LINE.
    let originX: Double?

    func makeUIView(context: Context) -> ConfettiEmitterUIView {
        let view = ConfettiEmitterUIView()
        view.configure(colors: colors, intensity: intensity, duration: duration, originY: originY, originX: originX)
        return view
    }

    func updateUIView(_ uiView: ConfettiEmitterUIView, context: Context) {}
}

/// UIView host that owns the `CAEmitterLayer`, sizes the emission line to its
/// width on layout, kicks off the burst once, then zeroes the birth rate after
/// `duration` for a natural one-shot settle.
@available(iOS 17.0, *)
final class ConfettiEmitterUIView: UIView {
    private let emitter = CAEmitterLayer()
    private var colors: [UIColor] = []
    private var intensity: Int = 20
    private var duration: Double = 2.5
    private var originY: Double = 0
    private var originX: Double? = nil
    private var didStart = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(emitter)
    }

    func configure(colors: [UIColor], intensity: Int, duration: Double, originY: Double, originX: Double?) {
        self.colors = colors.isEmpty ? Self.defaultPalette : colors
        self.intensity = max(1, intensity)
        self.duration = max(0.1, duration)
        self.originY = min(1, max(0, originY))
        self.originX = originX.map { min(1, max(0, $0)) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Vertical origin: at the default originY 0 the emitter sits just above
        // the top edge so pieces enter already falling.
        emitter.frame = bounds
        let y = originY <= 0 ? -8 : bounds.height * CGFloat(originY)

        if let originX {
            // POINT burst: spray from a single centered point and fan outward
            // (the widened emissionRange is applied per-cell in makeCells).
            emitter.emitterShape = .point
            emitter.emitterPosition = CGPoint(x: bounds.width * CGFloat(originX), y: y)
            emitter.emitterSize = .zero
        } else {
            // Default: rain across the full width from a line.
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: y)
            emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        }
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !didStart, bounds.width > 0 else { return }
        didStart = true

        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1
        emitter.emitterCells = makeCells()

        // One-shot: stop emitting after `duration` so existing pieces fall out
        // and the layer goes idle (no perpetual CPU/GPU work). Weak self so a
        // dismissed sheet doesn't keep the view alive.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.emitter.birthRate = 0
        }
    }

    private func makeCells() -> [CAEmitterCell] {
        // Split the requested birth rate evenly across colors, minimum 1 each.
        let perColorRate = max(1, Float(intensity) / Float(max(1, colors.count)))

        // A point burst fans out wide (~±75°) so pieces spray outward before
        // gravity pulls them down; a line rains straight down with a gentle
        // ±45° scatter.
        let emissionRange: CGFloat = originX != nil ? (.pi / 180 * 75) : (.pi / 4)

        return colors.enumerated().map { index, color in
            let cell = CAEmitterCell()
            cell.birthRate = perColorRate
            cell.lifetime = 6.0
            cell.lifetimeRange = 1.5

            // Emit downward (UIKit layer y-axis points down) with a spread for
            // horizontal scatter; gravity keeps pulling everything down.
            cell.velocity = 210
            cell.velocityRange = 80
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = emissionRange
            cell.yAcceleration = 320
            cell.xAcceleration = 0

            // Tumble as they fall.
            cell.spin = 3.5
            cell.spinRange = 4.0

            cell.scale = 0.55
            cell.scaleRange = 0.25

            // Alternate rectangles and circles for classic confetti variety.
            let shape: PieceShape = index.isMultiple(of: 2) ? .rectangle : .circle
            cell.contents = Self.pieceImage(color: color, shape: shape)?.cgImage
            return cell
        }
    }

    // MARK: - Piece rendering

    private enum PieceShape {
        case rectangle
        case circle
    }

    /// Draws a small colored piece into a UIImage so no bundled assets are
    /// required. Rectangles are slightly taller than wide for a "ribbon" look.
    private static func pieceImage(color: UIColor, shape: PieceShape) -> UIImage? {
        let size: CGSize
        switch shape {
        case .rectangle: size = CGSize(width: 8, height: 12)
        case .circle: size = CGSize(width: 9, height: 9)
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            let rect = CGRect(origin: .zero, size: size)
            switch shape {
            case .rectangle:
                ctx.fill(rect)
            case .circle:
                ctx.cgContext.fillEllipse(in: rect)
            }
        }
    }

    /// Festive default palette used when the author supplies no colors.
    static let defaultPalette: [UIColor] = [
        UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1), // red
        UIColor(red: 1.00, green: 0.18, blue: 0.33, alpha: 1), // pink
        UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1), // orange
        UIColor(red: 1.00, green: 0.80, blue: 0.00, alpha: 1), // yellow
        UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1), // green
        UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), // blue
        UIColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1)  // purple
    ]
}
#endif
