//  GooeyContentSwitcher.swift
//  Fluid Content Switcher — SwiftUI + Metal
//
//  Implements draggable cards with real-time Metal shader distortion,
//  spring physics, and interactive parameter controls.

import SwiftUI

// MARK: - Card Model

struct CardItem: Identifiable, Equatable {
    let id = UUID()
    let imageURL: URL
    let gradient: [Color]     // fallback background while loading
}

// MARK: - Main View

struct GooeyContentSwitcher: View {

    // ── Shader Uniforms (user-controllable) ────
    @State private var angularity: CGFloat = 0.35
    @State private var amplitude: CGFloat  = 0.55
    @State private var viscosity: CGFloat  = 0.45

    // ── Drag State ─────────────────────────────
    @State private var dragOffset: CGSize      = .zero
    @State private var touchLocation: CGPoint  = .zero
    @State private var velocity: CGSize        = .zero
    @State private var isDragging: Bool        = false
    @State private var activeCardIndex: Int    = 0

    // ── Spring Animation ───────────────────────
    @State private var springOffset: CGSize    = .zero

    // ── UI State ─────────────────────────────
    @State private var showControls: Bool      = false

    // ── Sample Cards (Lorem Picsum high-res images) ──
    let cards: [CardItem] = [
        CardItem(imageURL: URL(string: "https://picsum.photos/id/29/800/1600")!,
                 gradient: [Color(red: 0.15, green: 0.05, blue: 0.35),
                            Color(red: 0.4, green: 0.1, blue: 0.7)]),
        CardItem(imageURL: URL(string: "https://picsum.photos/id/37/800/1600")!,
                 gradient: [Color(red: 0.95, green: 0.85, blue: 0.3),
                            Color(red: 1.0, green: 0.6, blue: 0.2)]),
        CardItem(imageURL: URL(string: "https://picsum.photos/id/47/800/1600")!,
                 gradient: [Color(red: 0.1, green: 0.55, blue: 0.3),
                            Color(red: 0.2, green: 0.8, blue: 0.5)]),
        CardItem(imageURL: URL(string: "https://picsum.photos/id/65/800/1600")!,
                 gradient: [Color(red: 0.85, green: 0.15, blue: 0.1),
                            Color(red: 1.0, green: 0.45, blue: 0.15)]),
    ]

    var body: some View {
        ZStack {
            // ── Background ────────────────────
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                // ── Card Carousel with Shader ─
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    cardStack(time: elapsed)
                }
                .frame(maxHeight: .infinity)

                Spacer(minLength: 16)

                // ── Page Indicators + Toggle ──
                HStack {
                    // Pill indicators for card position
                    HStack(spacing: 6) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, _ in
                            Capsule()
                                .fill(index == activeCardIndex ? Color.white : Color.white.opacity(0.25))
                                .frame(width: index == activeCardIndex ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35), value: activeCardIndex)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showControls.toggle()
                        }
                    } label: {
                        Image(systemName: showControls ? "slider.horizontal.3" : "slider.horizontal.3")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                // ── Control Panel ─────────────
                if showControls {
                    controlPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Card Stack (with Metal shader)

    private func cardStack(time: Double) -> some View {
        GeometryReader { geo in
            let size = geo.size
            // 1:2 aspect ratio (400×800), fit within available space
            let cardHeight = min(size.height * 0.92, size.width * 2)
            let cardWidth  = cardHeight / 2

            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let isActive = index == activeCardIndex
                    let depth    = abs(index - activeCardIndex)

                    cardView(card: card, size: CGSize(width: cardWidth, height: cardHeight))
                        .frame(width: cardWidth, height: cardHeight)
                        // ── Apply Metal Shader ────────
                        .layerEffect(
                            ShaderLibrary.gooeyDistortion(
                                .float2(Float(cardWidth), Float(cardHeight)),
                                .float2(
                                    Float(isActive ? touchLocation.x : cardWidth / 2),
                                    Float(isActive ? touchLocation.y : cardHeight / 2)
                                ),
                                .float2(
                                    Float(isActive ? velocity.width : 0),
                                    Float(isActive ? velocity.height : 0)
                                ),
                                .float(Float(time)),
                                .float(Float(angularity)),
                                .float(Float(isActive ? amplitude : 0)),
                                .float(Float(viscosity)),
                                .float(Float(isActive && isDragging ? 1.0 : 0.0))
                            ),
                            maxSampleOffset: CGSize(width: 120, height: 120)
                        )
                        // ── Position & Z-ordering ─────
                        .offset(
                            x: isActive ? springOffset.width : CGFloat(index - activeCardIndex) * 24,
                            y: isActive ? springOffset.height : CGFloat(depth) * -12
                        )
                        .scaleEffect(isActive ? 1.0 : max(0.85, 1.0 - CGFloat(depth) * 0.08))
                        .opacity(isActive ? 1.0 : max(0.0, 1.0 - Double(depth) * 0.35))
                        .zIndex(isActive ? 10 : Double(10 - depth))
                        .rotation3DEffect(
                            .degrees(isActive ? Double(springOffset.width) * 0.04 : 0),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        // ── Gesture ───────────────────
                        .gesture(isActive ? dragGesture(cardSize: CGSize(width: cardWidth, height: cardHeight)) : nil)
                        .animation(
                            .interpolatingSpring(
                                stiffness: mix(120, 50, viscosity),
                                damping: mix(12, 25, viscosity)
                            ),
                            value: springOffset
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Individual Card

    private func cardView(card: CardItem, size: CGSize) -> some View {
        AsyncImage(url: card.imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            case .failure:
                fallbackGradient(card: card)
            default:
                fallbackGradient(card: card)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: mix(12, 40, angularity), style: .continuous))
    }

    private func fallbackGradient(card: CardItem) -> some View {
        RoundedRectangle(cornerRadius: mix(12, 40, angularity), style: .continuous)
            .fill(
                LinearGradient(
                    colors: card.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Drag Gesture

    private func dragGesture(cardSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation

                // Touch location relative to the card
                touchLocation = CGPoint(
                    x: clamp(value.location.x, min: 0, max: cardSize.width),
                    y: clamp(value.location.y, min: 0, max: cardSize.height)
                )

                // Approximate velocity from predicted end
                velocity = CGSize(
                    width: value.predictedEndTranslation.width - value.translation.width,
                    height: value.predictedEndTranslation.height - value.translation.height
                )

                // Spring offset tracks the drag (damped by viscosity)
                let dampFactor = mix(1.0, 0.4, viscosity)
                springOffset = CGSize(
                    width: value.translation.width * dampFactor,
                    height: value.translation.height * dampFactor * 0.4
                )
            }
            .onEnded { value in
                isDragging = false
                velocity = .zero

                // Determine if we should switch cards
                let threshold: CGFloat = 80
                if value.translation.width < -threshold && activeCardIndex < cards.count - 1 {
                    activeCardIndex += 1
                } else if value.translation.width > threshold && activeCardIndex > 0 {
                    activeCardIndex -= 1
                }

                // Spring back
                withAnimation(.interpolatingSpring(
                    stiffness: mix(200, 80, viscosity),
                    damping: mix(15, 28, viscosity)
                )) {
                    springOffset = .zero
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 14) {
            parameterSlider(label: "ANGULARITY", value: $angularity)
            parameterSlider(label: "HEIGHT",     value: $amplitude)
            parameterSlider(label: "VISCOSITY",  value: $viscosity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func parameterSlider(label: String, value: Binding<CGFloat>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.2)
                .frame(width: 80, alignment: .leading)

            Slider(value: value, in: 0...1)
                .tint(.blue)

            Text(String(format: "%.0f", value.wrappedValue * 100))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - Utility Functions

/// Linear interpolation
private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// Overload for Double
private func mix(_ a: Double, _ b: Double, _ t: CGFloat) -> Double {
    a + (b - a) * Double(t)
}

/// Clamp a value to a range
private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, minVal), maxVal)
}

// MARK: - Preview

#Preview {
    GooeyContentSwitcher()
}
