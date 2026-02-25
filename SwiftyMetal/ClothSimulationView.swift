import SwiftUI
import MetalKit

struct ClothSimulationView: UIViewRepresentable {
    let renderer: ClothRenderer

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        mtkView.preferredFramesPerSecond = 60
        mtkView.delegate = renderer
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        // Add tap gesture for wave interaction
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mtkView.addGestureRecognizer(tapGesture)

        // Add pan gesture for continuous wave
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    class Coordinator: NSObject {
        let renderer: ClothRenderer

        init(renderer: ClothRenderer) {
            self.renderer = renderer
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            let nx = Float(location.x / view.bounds.width)
            let ny = Float(location.y / view.bounds.height)
            renderer.applyForceAt(normalizedX: nx, normalizedY: ny, strength: 3.0)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            let nx = Float(location.x / view.bounds.width)
            let ny = Float(location.y / view.bounds.height)
            renderer.applyForceAt(normalizedX: nx, normalizedY: ny, strength: 1.5)
        }
    }
}
