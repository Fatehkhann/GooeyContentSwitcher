//  LiquidMetalButtonView.swift
//  SwiftyMetal
//
//  A futuristic 'Liquid Metal' pill button with a shiny chrome border
//  that reflects light based on real device tilt via CoreMotion.

import CoreMotion
import SwiftUI

// MARK: - Motion Manager

@MainActor
@Observable
final class TiltMotionManager {

    var tiltX: Double = 0
    var tiltY: Double = 0

    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data, let self else { return }
            Task { @MainActor in
                // Roll → horizontal tilt, Pitch → vertical tilt
                // Clamp to −1…+1 range
                self.tiltX = max(-1, min(1, data.attitude.roll))
                self.tiltY = max(-1, min(1, data.attitude.pitch))
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

// MARK: - Showcase View

struct LiquidMetalButtonView: View {

    @State private var motionManager = TiltMotionManager()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 48) {
                headerSection
                buttonShowcase
                descriptionSection
            }
            .padding(.horizontal, 32)
        }
        .onAppear { motionManager.start() }
        .onDisappear { motionManager.stop() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Liquid Metal")
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Futuristic Button Shader")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.5))
        }
    }

    // MARK: - Button Showcase

    private var buttonShowcase: some View {
        VStack(spacing: 40) {
            LiquidMetalPillButton(
                label: "Only paper",
                tiltX: motionManager.tiltX,
                tiltY: motionManager.tiltY
            ) {}

            LiquidMetalPillButton(
                label: "Get Started",
                width: 220,
                tiltX: motionManager.tiltX,
                tiltY: motionManager.tiltY
            ) {}
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(spacing: 12) {
            Text("Metal Shader Effects")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(white: 0.6))

            Text("Tilt-responsive chrome border • Device motion reflections\nMulti-layered shadows • Press-to-scale interaction")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.4))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Liquid Metal Pill Button

struct LiquidMetalPillButton: View {

    let label: String
    var width: CGFloat = 180
    var height: CGFloat = 56
    var tiltX: Double = 0
    var tiltY: Double = 0
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = Float(timeline.date.timeIntervalSinceReferenceDate)

            let shaderArgs: [Shader.Argument] = [
                .float2(Float(width), Float(height)),
                .float(elapsed),
                .float(Float(tiltX)),
                .float(Float(tiltY))
            ]

            Button(action: action) {
                ZStack {
                    // Plain dark body
                    Capsule()
                        .fill(Color(white: 0.13))

                    // Spectrum border — no blur, no glow, strictly on the stroke
                    Capsule()
                        .strokeBorder(.white, lineWidth: 3)
                        .colorEffect(
                            ShaderLibrary.liquidMetalBorder(
                                shaderArgs[0], shaderArgs[1],
                                shaderArgs[2], shaderArgs[3]
                            )
                        )

                    // Label
                    Text(label)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(.white)
                }
                .frame(width: width, height: height)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
    }
}

// MARK: - Preview

#Preview {
    LiquidMetalButtonView()
}
