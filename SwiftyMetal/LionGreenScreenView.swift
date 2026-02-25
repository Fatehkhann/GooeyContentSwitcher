//  LionGreenScreenView.swift
//  SwiftyMetal
//
//  Plays a looping video and uses the Vision framework to remove
//  the background. The retro TV CRT shader is applied to the original
//  frame, then a clean Vision mask clips the result so only the lion
//  subject shows — the white background stays pristine.

import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// MARK: - Processed Frame

struct ProcessedFrame {
    let original: CGImage
    let mask: CGImage?
}

// MARK: - Green Screen Processor

final class GreenScreenProcessor {
    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput?
    var loopObserver: NSObjectProtocol?
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func setup() {
        guard let url = Bundle.main.url(forResource: "eagle", withExtension: "mp4") else {
            return
        }

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        videoOutput = output

        let item = AVPlayerItem(url: url)
        item.add(output)

        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        player = p

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }

        p.play()
    }

    func readFrame() -> ProcessedFrame? {
        guard let output = videoOutput else { return nil }

        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard time.isValid, time.isNumeric else { return nil }
        guard output.hasNewPixelBuffer(forItemTime: time) else { return nil }
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return nil }

        let foreground = CIImage(cvPixelBuffer: buffer)
        let extent = foreground.extent

        guard let originalCG = ciContext.createCGImage(foreground, from: extent) else {
            return nil
        }

        guard let maskBuffer = generateMask(from: buffer) else {
            return ProcessedFrame(original: originalCG, mask: nil)
        }

        let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            .applyingFilter("CIBicubicScaleTransform", parameters: [
                "inputScale": extent.width / CGFloat(CVPixelBufferGetWidth(maskBuffer)),
                "inputAspectRatio": (extent.height / CGFloat(CVPixelBufferGetHeight(maskBuffer)))
                    / (extent.width / CGFloat(CVPixelBufferGetWidth(maskBuffer)))
            ])

        // Convert grayscale luminance → alpha channel so SwiftUI .mask() works.
        // RGB = white, Alpha = mask luminance (white=opaque, black=transparent).
        let alphaFromLuma = maskCI.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
        ])

        guard let maskCG = ciContext.createCGImage(alphaFromLuma, from: extent,
                                                    format: .BGRA8,
                                                    colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            return ProcessedFrame(original: originalCG, mask: nil)
        }

        return ProcessedFrame(original: originalCG, mask: maskCG)
    }

    func tearDown() {
        player?.pause()
        player = nil
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        loopObserver = nil
        videoOutput = nil
    }

    // MARK: - Helpers

    private func generateMask(from buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }

        do {
            return try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
        } catch {
            return nil
        }
    }
}

// MARK: - LionGreenScreenView

struct LionGreenScreenView: View {

    @State private var processor = GreenScreenProcessor()
    @State private var currentFrame: ProcessedFrame?
    @State private var startDate = Date()

    private let pixelStrength: Float = 1.0
    private let timer = Timer.publish(every: 1.0 / 15.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let elapsed = Float(timeline.date.timeIntervalSince(startDate))

                ZStack {
                    Color.white.ignoresSafeArea()

                    if let frame = currentFrame {
                        Image(decorative: frame.original, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .layerEffect(
                                ShaderLibrary.retroTV(
                                    .float2(Float(geo.size.width), Float(geo.size.height)),
                                    .float(elapsed),
                                    .float(pixelStrength)
                                ),
                                maxSampleOffset: CGSize(
                                    width: CGFloat(pixelStrength) + 2,
                                    height: CGFloat(pixelStrength) + 2
                                )
                            )
                            .colorEffect(
                                ShaderLibrary.bwThreshold(.float(0.5))
                            )
                            .mask {
                                if let maskCG = frame.mask {
                                    Image(decorative: maskCG, scale: 1.0)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                } else {
                                    Color.white
                                }
                            }
                    }

                    VStack {
                        Spacer()
                        Text("Where every swipe lands you somewhere new")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.gray)
                            .padding()
                        
                        Button {
                            // Action
                        } label: {
                            Text("Get Started")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black, lineWidth: 1.5)
                                )
                        }
                        .frame(width: geo.size.width / 1.6)
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .onAppear { processor.setup() }
        .onDisappear { processor.tearDown() }
        .onReceive(timer) { _ in
            if let frame = processor.readFrame() {
                currentFrame = frame
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LionGreenScreenView()
}
