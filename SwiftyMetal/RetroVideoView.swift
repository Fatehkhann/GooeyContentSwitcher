//  RetroVideoView.swift
//  Retro Black & White Pixelated TV — SwiftUI + Metal
//
//  Plays a looping video through a Metal shader that applies
//  pixelation, grayscale, animated static noise, and CRT scanlines.
//  Frames are extracted via AVPlayerItemVideoOutput → CGImage so
//  the shader operates on native SwiftUI Image content.

import SwiftUI
import AVFoundation
import CoreImage

// MARK: - Frame Extractor (reference type to avoid @State issues)

final class FrameExtractor {
    var player: AVPlayer?
    var videoOutput: AVPlayerItemVideoOutput?
    var loopObserver: NSObjectProtocol?
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var debugInfo = "Not started"
    var timerCallCount = 0
    var extractedFrames = 0

    func setup() {
        guard let url = Bundle.main.url(forResource: "lion", withExtension: "mp4") else {
            debugInfo = "lion.mp4 not found"
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
        player = p

        // Manual loop
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }

        p.play()
        debugInfo = "Player started, waiting for frames..."
    }

    func readFrame() -> CGImage? {
        timerCallCount += 1

        guard let output = videoOutput else {
            debugInfo = "No output (\(timerCallCount) ticks)"
            return nil
        }

        let time = output.itemTime(forHostTime: CACurrentMediaTime())

        guard time.isValid, time.isNumeric else {
            let status = player?.currentItem?.status.rawValue ?? -1
            let rate = player?.rate ?? 0
            debugInfo = "Time invalid | status=\(status) rate=\(rate) (\(timerCallCount) ticks)"
            return nil
        }

        guard output.hasNewPixelBuffer(forItemTime: time) else {
            let secs = CMTimeGetSeconds(time)
            debugInfo = "No new buffer @ \(String(format: "%.2f", secs))s (\(timerCallCount) ticks, \(extractedFrames) frames)"
            return nil
        }

        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            debugInfo = "copyPixelBuffer nil (\(timerCallCount) ticks)"
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            debugInfo = "CIContext failed (\(timerCallCount) ticks)"
            return nil
        }

        extractedFrames += 1
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        debugInfo = "OK \(w)x\(h) | \(extractedFrames) frames (\(timerCallCount) ticks)"
        return cgImage
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
}

// MARK: - RetroVideoView

struct RetroVideoView: View {

    @State private var extractor = FrameExtractor()
    @State private var currentFrame: CGImage?
    @State private var pixelStrength: Float = 6.0
    @State private var startDate = Date()
    @State private var debugText = "..."

    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let elapsed = Float(timeline.date.timeIntervalSince(startDate))

                ZStack {
                    Color.black.ignoresSafeArea()

                    if let currentFrame {
                        Image(decorative: currentFrame, scale: 1.0)
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
                    }

                    // Debug + controls overlay
                    VStack {
                        Text(debugText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(8)
                            .background(.black.opacity(0.7))
                            .padding(.top, 60)

                        Spacer()

                        VStack(spacing: 12) {
                            Text("Pixel Strength: \(Int(pixelStrength))")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)

                            Slider(value: $pixelStrength, in: 1...20, step: 1)
                                .tint(.white)
                                .padding(.horizontal, 12)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .onAppear { extractor.setup() }
        .onDisappear { extractor.tearDown() }
        .onReceive(timer) { _ in
            if let frame = extractor.readFrame() {
                currentFrame = frame
            }
            debugText = extractor.debugInfo
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview

#Preview {
    RetroVideoView()
}
