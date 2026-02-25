import MetalKit
import simd

// MARK: - GPU-mirrored structs (must match ClothShaders.metal exactly)

// Metal float3 = 16 bytes (padded), Swift SIMD3<Float> = 16 bytes — no manual padding needed.
// Metal float4x4 = 64 bytes, aligned to 16 — Swift auto-pads preceding fields.

struct ClothUniforms {
    var gridSize: SIMD2<Float>       // 8 bytes,  offset 0
    var restLength: Float            // 4 bytes,  offset 8
    var damping: Float               // 4 bytes,  offset 12
    var dt: Float                    // 4 bytes,  offset 16
    var vertexForce: Float           // 4 bytes,  offset 20
    var simSpeed: Float              // 4 bytes,  offset 24
    var enableSim: Int32             // 4 bytes,  offset 28
    var enableVertexShader: Int32    // 4 bytes,  offset 32
    var time: Float                  // 4 bytes,  offset 36
    // Swift auto-pads 8 bytes here to align float4x4 to 16
    var mvpMatrix: float4x4          // 64 bytes, offset 48
    var modelMatrix: float4x4        // 64 bytes, offset 112
    var lightPosition: SIMD3<Float>  // 16 bytes, offset 176
    var cameraPosition: SIMD3<Float> // 16 bytes, offset 192
    // Total: 208 bytes
}

struct ClothNode {
    var position: SIMD3<Float>       // 16 bytes, offset 0
    var oldPosition: SIMD3<Float>    // 16 bytes, offset 16
    var restPosition: SIMD3<Float>   // 16 bytes, offset 32
    var mass: Float                  // 4 bytes,  offset 48
    var pinned: Int32                // 4 bytes,  offset 52
    var uv: SIMD2<Float>             // 8 bytes,  offset 56
    // Total: 64 bytes
}

// MARK: - Renderer

final class ClothRenderer: NSObject, MTKViewDelegate {

    // Grid dimensions
    let cols: Int = 40
    let rows: Int = 60

    // Metal objects
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var simulationPipeline: MTLComputePipelineState!
    private var constraintPipeline: MTLComputePipelineState!
    private var renderPipeline: MTLRenderPipelineState!
    private var nodeBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    private var receiptTexture: MTLTexture?
    private var samplerState: MTLSamplerState!
    private var depthStencilState: MTLDepthStencilState!
    private var indexCount: Int = 0
    private var startTime: CFAbsoluteTime

    // Simulation parameters (driven by SwiftUI)
    var vertexForce: Float = 0.0
    var damping: Float = 0.85
    var simSpeed: Float = 1.0
    var enableSim: Bool = true
    var enableVertexShader: Bool = true

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }

        self.device = device
        self.commandQueue = queue
        self.startTime = CFAbsoluteTimeGetCurrent()

        super.init()

        guard setupPipelines(),
              setupBuffers(),
              setupSampler() else { return nil }

        setupDepthStencil()
        createFallbackTexture()
    }

    // MARK: - Setup

    private func setupPipelines() -> Bool {
        guard let library = device.makeDefaultLibrary() else {
            print("[ClothRenderer] No default Metal library found")
            return false
        }

        // Compute pipelines
        guard let simFunc = library.makeFunction(name: "clothSimulation"),
              let conFunc = library.makeFunction(name: "clothConstraints") else {
            print("[ClothRenderer] Compute functions not found")
            return false
        }

        do {
            simulationPipeline = try device.makeComputePipelineState(function: simFunc)
            constraintPipeline = try device.makeComputePipelineState(function: conFunc)
        } catch {
            print("[ClothRenderer] Compute pipeline error: \(error)")
            return false
        }

        // Render pipeline
        guard let vertFunc = library.makeFunction(name: "clothVertex"),
              let fragFunc = library.makeFunction(name: "clothFragment") else {
            print("[ClothRenderer] Render functions not found")
            return false
        }

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vertFunc
        rpd.fragmentFunction = fragFunc
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        rpd.colorAttachments[0].isBlendingEnabled = true
        rpd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        rpd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        rpd.depthAttachmentPixelFormat = .depth32Float

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: rpd)
        } catch {
            print("[ClothRenderer] Render pipeline error: \(error)")
            return false
        }

        return true
    }

    private func setupBuffers() -> Bool {
        var nodes = [ClothNode]()
        let spacing: Float = 0.05
        let startX: Float = -Float(cols - 1) * spacing * 0.5
        let startY: Float = Float(rows - 1) * spacing * 0.5

        for row in 0..<rows {
            for col in 0..<cols {
                let x = startX + Float(col) * spacing
                let y = startY - Float(row) * spacing
                let z: Float = 0.0

                // Pin entire top row (sticky top)
                let isPinned: Int32 = (row == 0) ? 1 : 0

                let u = Float(col) / Float(cols - 1)
                let v = Float(row) / Float(rows - 1)

                let node = ClothNode(
                    position: SIMD3<Float>(x, y, z),
                    oldPosition: SIMD3<Float>(x, y, z),
                    restPosition: SIMD3<Float>(x, y, z),
                    mass: 1.0,
                    pinned: isPinned,
                    uv: SIMD2<Float>(u, v)
                )
                nodes.append(node)
            }
        }

        nodeBuffer = device.makeBuffer(bytes: nodes, length: MemoryLayout<ClothNode>.stride * nodes.count, options: .storageModeShared)

        // Triangle indices
        var indices = [UInt32]()
        for row in 0..<(rows - 1) {
            for col in 0..<(cols - 1) {
                let tl = UInt32(row * cols + col)
                let tr = UInt32(row * cols + col + 1)
                let bl = UInt32((row + 1) * cols + col)
                let br = UInt32((row + 1) * cols + col + 1)

                indices.append(contentsOf: [tl, bl, tr])
                indices.append(contentsOf: [tr, bl, br])
            }
        }
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count, options: .storageModeShared)

        uniformBuffer = device.makeBuffer(length: 512, options: .storageModeShared) // generous size

        return nodeBuffer != nil && indexBuffer != nil && uniformBuffer != nil
    }

    private func setupSampler() -> Bool {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: desc)
        return samplerState != nil
    }

    private func setupDepthStencil() {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .less
        desc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: desc)
    }

    // MARK: - Texture

    private func createFallbackTexture() {
        // Create a simple white 4x4 texture as fallback
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return }

        var pixels = [UInt8](repeating: 255, count: 4 * 4 * 4) // all white, full alpha
        tex.replace(
            region: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: 4, height: 4, depth: 1)),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: 4 * 4
        )
        receiptTexture = tex
    }

    func setReceiptTexture(_ texture: MTLTexture?) {
        if let texture {
            self.receiptTexture = texture
        }
    }

    // MARK: - Tap Interaction

    func applyForceAt(normalizedX: Float, normalizedY: Float, strength: Float = 2.0) {
        // Convert normalized screen coords (0...1) to grid coords
        let gridX = Int(normalizedX * Float(cols - 1))
        let gridY = Int(normalizedY * Float(rows - 1))
        let radius = 5 // affect nearby nodes too

        let nodePtr = nodeBuffer.contents().bindMemory(to: ClothNode.self, capacity: cols * rows)

        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = gridX + dx
                let ny = gridY + dy
                guard nx >= 0, nx < cols, ny >= 0, ny < rows else { continue }

                let idx = ny * cols + nx
                guard nodePtr[idx].pinned == 0 else { continue }

                let dist = sqrt(Float(dx * dx + dy * dy))
                let falloff = max(0, 1.0 - dist / Float(radius))
                let impulse = SIMD3<Float>(0, 0, strength * falloff)

                // Push the node forward (away from camera) by modifying oldPosition
                nodePtr[idx].oldPosition -= impulse * (1.0 / 60.0)
            }
        }
    }

    // MARK: - Matrix Helpers

    private func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let yScale = 1.0 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near

        return float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, -(far + near) / zRange, -1),
            SIMD4<Float>(0, 0, -2.0 * far * near / zRange, 0)
        ))
    }

    private func lookAtMatrix(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        return float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        ))
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let elapsed = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)

        let eye = SIMD3<Float>(0, 0.0, 4.5)
        let center = SIMD3<Float>(0, -0.3, 0)
        let up = SIMD3<Float>(0, 1, 0)

        let model = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
        let viewMat = lookAtMatrix(eye: eye, center: center, up: up)
        let proj = perspectiveMatrix(fovY: Float.pi / 4, aspect: aspect, near: 0.1, far: 100)
        let mvp = proj * viewMat * model

        var uniforms = ClothUniforms(
            gridSize: SIMD2<Float>(Float(cols), Float(rows)),
            restLength: 0.05,
            damping: damping,
            dt: 1.0 / 120.0,
            vertexForce: vertexForce,
            simSpeed: simSpeed,
            enableSim: enableSim ? 1 : 0,
            enableVertexShader: enableVertexShader ? 1 : 0,
            time: elapsed,
            mvpMatrix: mvp,
            modelMatrix: model,
            lightPosition: SIMD3<Float>(2, 5, 3),
            cameraPosition: eye
        )

        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<ClothUniforms>.size)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // --- Compute pass: simulation ---
        if enableSim {
            let totalNodes = cols * rows
            let threadGroupSize = min(simulationPipeline.maxTotalThreadsPerThreadgroup, 256)
            let threadsPerGrid = MTLSize(width: totalNodes, height: 1, depth: 1)
            let threadsPerGroup = MTLSize(width: threadGroupSize, height: 1, depth: 1)

            // Verlet integration
            if let enc = commandBuffer.makeComputeCommandEncoder() {
                enc.setComputePipelineState(simulationPipeline)
                enc.setBuffer(nodeBuffer, offset: 0, index: 0)
                enc.setBuffer(uniformBuffer, offset: 0, index: 1)
                enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                enc.endEncoding()
            }

            // Constraint solver — more iterations = stiffer paper-like behavior
            for _ in 0..<30 {
                if let enc = commandBuffer.makeComputeCommandEncoder() {
                    enc.setComputePipelineState(constraintPipeline)
                    enc.setBuffer(nodeBuffer, offset: 0, index: 0)
                    enc.setBuffer(uniformBuffer, offset: 0, index: 1)
                    enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                    enc.endEncoding()
                }
            }
        }

        // --- Render pass ---
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            commandBuffer.commit()
            return
        }

        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(renderPipeline)
            enc.setDepthStencilState(depthStencilState)
            enc.setCullMode(.none) // double-sided cloth

            enc.setVertexBuffer(nodeBuffer, offset: 0, index: 0)
            enc.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

            if let tex = receiptTexture {
                enc.setFragmentTexture(tex, index: 0)
            }
            enc.setFragmentSamplerState(samplerState, index: 0)

            enc.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )

            enc.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
