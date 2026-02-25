import SwiftUI
import MetalKit

struct FloatingReceiptView: View {
    @State private var renderer: ClothRenderer?
    @State private var vertexForce: Float = 0.0
    @State private var damping: Float = 0.85
    @State private var simSpeed: Float = 1.0
    @State private var enableSim = true
    @State private var enableVertexShader = true
    @State private var showControls = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Metal cloth simulation — full screen
            if let renderer {
                ClothSimulationView(renderer: renderer)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            }

            // Bottom controls
            VStack(spacing: 0) {
                if showControls {
                    controlPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Small toggle bar at bottom
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showControls.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                        Text(showControls ? "Hide" : "Controls")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 12)
            }
        }
        .task {
            setupRenderer()
        }
        .onChange(of: vertexForce) { _, val in renderer?.vertexForce = val }
        .onChange(of: damping) { _, val in renderer?.damping = val }
        .onChange(of: simSpeed) { _, val in renderer?.simSpeed = val }
        .onChange(of: enableSim) { _, val in renderer?.enableSim = val }
        .onChange(of: enableVertexShader) { _, val in renderer?.enableVertexShader = val }
        .navigationBarHidden(true)
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 10) {
            sliderRow(title: "Wind", value: $vertexForce, range: 0...5)
            sliderRow(title: "Damping", value: $damping, range: 0.7...1.0)
            sliderRow(title: "Speed", value: $simSpeed, range: 0.1...3.0)

            HStack(spacing: 16) {
                Toggle("Sim", isOn: $enableSim)
                Toggle("Vertex", isOn: $enableVertexShader)
            }
            .font(.caption2.bold())
            .toggleStyle(.switch)
            .tint(.cyan)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .foregroundStyle(.white)
    }

    private func sliderRow(title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.bold())
                .frame(width: 52, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.cyan)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36)
        }
    }

    // MARK: - Setup

    private func setupRenderer() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        guard let r = ClothRenderer(device: device) else { return }

        if let texture = ReceiptTextureRenderer.renderReceiptTexture(device: device) {
            r.setReceiptTexture(texture)
        }

        r.vertexForce = vertexForce
        r.damping = damping
        r.simSpeed = simSpeed
        r.enableSim = enableSim
        r.enableVertexShader = enableVertexShader

        self.renderer = r
    }
}
