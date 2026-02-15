//  SpiralListView.swift
//  3D Cylindrical Spiral List — SwiftUI + Metal
//
//  Displays 100 cells arranged on a virtual cylinder with
//  depth-based blur (Metal shader), perspective, spring-physics
//  scroll, and pinch-to-expand interaction.

import SwiftUI

// MARK: - Data Model

struct SpiralItem: Identifiable, Equatable {
    let id: Int
    let name: String
    let subtitle: String
    let imageID: Int
    let gradientColors: [Color]
}

// MARK: - SpiralListView

struct SpiralListView: View {

    // ── Scroll State ──────────────────────────
    @State private var scrollOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var dragStartOffset: CGFloat = 0

    // ── Pinch State ───────────────────────────
    @State private var cylinderRadius: CGFloat = 130
    @State private var verticalSpacing: CGFloat = 62
    @State private var baseRadius: CGFloat = 130
    @State private var baseSpacing: CGFloat = 62

    // ── Layout Constants ──────────────────────
    private let tightness: CGFloat = 130
    private let cellWidth: CGFloat = 270
    private let cellHeight: CGFloat = 58
    private let maxBlur: CGFloat = 5.0
    private let renderBuffer: CGFloat = 300

    let items: [SpiralItem]

    // MARK: - Init

    init() {
        let names: [(String, String)] = [
            ("Twin Flame", "KAYTRANADA"),
            ("Summer In NY", "Sofi Tukker"),
            ("Diamonds", "Polish Ambassador"),
            ("Run Away", "Alison Wonderland"),
            ("Can I Get There", "Big Wild"),
            ("Feeling", "Opus Whathen"),
            ("Be Like You", "Whethan"),
            ("Outta Here", "RL Grime"),
            ("Better Not", "Louis the Child"),
            ("All of Me", "Big Gigantic"),
            ("Anything", "Alison Wonderland"),
            ("Chase You", "Flight Facilities"),
            ("Home Bound", "Dena Lisa"),
            ("Delish", "Flight Mode"),
            ("Solar System", "Sub Focus"),
            ("Midnight City", "M83"),
            ("Innerbloom", "RUFUS DU SOL"),
            ("On My Mind", "Diplo"),
            ("Shelter", "Porter Robinson"),
            ("Lean On", "Major Lazer"),
        ]

        let palettes: [[Color]] = [
            [Color(red: 0.35, green: 0.35, blue: 0.50),
             Color(red: 0.55, green: 0.55, blue: 0.70)],
            [Color(red: 0.85, green: 0.75, blue: 0.20),
             Color(red: 0.95, green: 0.85, blue: 0.35)],
            [Color(red: 0.30, green: 0.55, blue: 0.45),
             Color(red: 0.45, green: 0.70, blue: 0.60)],
            [Color(red: 0.75, green: 0.25, blue: 0.30),
             Color(red: 0.90, green: 0.40, blue: 0.45)],
            [Color(red: 0.50, green: 0.30, blue: 0.70),
             Color(red: 0.65, green: 0.45, blue: 0.85)],
            [Color(red: 0.20, green: 0.45, blue: 0.75),
             Color(red: 0.35, green: 0.60, blue: 0.90)],
            [Color(red: 0.70, green: 0.50, blue: 0.30),
             Color(red: 0.85, green: 0.65, blue: 0.45)],
            [Color(red: 0.40, green: 0.65, blue: 0.35),
             Color(red: 0.55, green: 0.80, blue: 0.50)],
            [Color(red: 0.60, green: 0.35, blue: 0.55),
             Color(red: 0.75, green: 0.50, blue: 0.70)],
            [Color(red: 0.25, green: 0.40, blue: 0.55),
             Color(red: 0.40, green: 0.55, blue: 0.70)],
        ]

        var result: [SpiralItem] = []
        for i in 0..<100 {
            let idx = i % names.count
            result.append(SpiralItem(
                id: i,
                name: names[idx].0,
                subtitle: names[idx].1,
                imageID: (i * 13 + 10) % 200 + 1,
                gradientColors: palettes[i % palettes.count]
            ))
        }
        self.items = result
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2

            ZStack {
                Color.black.ignoresSafeArea()

                ForEach(items) { item in
                    spiralCell(
                        item: item,
                        centerY: centerY,
                        screenHeight: geo.size.height
                    )
                }
            }
            .gesture(scrollGesture(screenHeight: geo.size.height))
            .simultaneousGesture(pinchGesture)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Spiral Cell

    @ViewBuilder
    private func spiralCell(
        item: SpiralItem,
        centerY: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        let cellY = CGFloat(item.id) * verticalSpacing + scrollOffset
        let screenY = centerY + cellY

        // Only render cells within the visible window + buffer
        if screenY > -renderBuffer && screenY < screenHeight + renderBuffer {
            let angle = cellY / tightness
            let x = cylinderRadius * sin(angle)
            let z = cylinderRadius * cos(angle)
            let normalizedZ = (z + cylinderRadius) / (2 * cylinderRadius)

            let scale = 0.7 + 0.3 * normalizedZ
            let depthOpacity = Double(0.35 + 0.65 * normalizedZ)
            let blurAmount = (1.0 - normalizedZ) * maxBlur

            cellContent(item: item)
                .frame(width: cellWidth, height: cellHeight)
                .layerEffect(
                    ShaderLibrary.spiralDepthEffect(
                        .float2(Float(cellWidth), Float(cellHeight)),
                        .float(Float(normalizedZ)),
                        .float(Float(blurAmount))
                    ),
                    maxSampleOffset: CGSize(width: 8, height: 8)
                )
                .scaleEffect(scale)
                .opacity(depthOpacity)
                .rotation3DEffect(
                    .radians(-Double(angle)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.4
                )
                .offset(x: x, y: cellY)
                .zIndex(Double(normalizedZ * 100))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Cell Content

    private func cellContent(item: SpiralItem) -> some View {
        HStack(spacing: 10) {
            AsyncImage(
                url: URL(string: "https://picsum.photos/id/\(item.imageID)/80/80")
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.15))
                default:
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.08))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Scroll Gesture (DragGesture + Inertia)

    private func scrollGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartOffset = scrollOffset
                }
                scrollOffset = dragStartOffset + value.translation.height
            }
            .onEnded { value in
                isDragging = false

                // Project the final position based on flick velocity
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let targetOffset = scrollOffset + velocity

                // Clamp to scroll bounds with some rubber-band margin
                let maxOffset: CGFloat = screenHeight * 0.4
                let minOffset = -(CGFloat(items.count - 1) * verticalSpacing) + screenHeight * 0.3
                let clamped = min(maxOffset, max(minOffset, targetOffset))

                withAnimation(.spring(response: 0.6, dampingFraction: 0.92)) {
                    scrollOffset = clamped
                }
            }
    }

    // MARK: - Pinch Gesture (Magnify)

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let scale = value.magnification
                cylinderRadius = spiralClamp(
                    baseRadius * scale, min: 40, max: 300
                )
                verticalSpacing = spiralClamp(
                    baseSpacing * scale, min: 28, max: 130
                )
            }
            .onEnded { _ in
                baseRadius = cylinderRadius
                baseSpacing = verticalSpacing
            }
    }
}

// MARK: - Utility

private func spiralClamp(
    _ value: CGFloat,
    min minVal: CGFloat,
    max maxVal: CGFloat
) -> CGFloat {
    Swift.min(Swift.max(value, minVal), maxVal)
}

// MARK: - Preview

#Preview {
    SpiralListView()
}
