//  HomeView.swift
//  SwiftyMetal
//
//  Navigation hub listing all UI demos with full-screen presentation.

import SwiftUI

// MARK: - Demo Item

enum Demo: String, CaseIterable, Identifiable {
    case gooeyCards = "Gooey Card Carousel"
    case spiralList = "3D Spiral List"
    case retroTV = "Retro TV"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .gooeyCards:
            "Fluid Metal shader distortion with spring physics"
        case .spiralList:
            "Cylindrical scroll with depth blur and pinch-to-expand"
        case .retroTV:
            "Pixelated B&W CRT effect on looping video"
        }
    }

    var icon: String {
        switch self {
        case .gooeyCards: "rectangle.stack"
        case .spiralList: "circle.hexagongrid"
        case .retroTV: "tv"
        }
    }
}

// MARK: - HomeView

struct HomeView: View {

    @State private var selectedDemo: Demo?

    var body: some View {
        NavigationStack {
            List(Demo.allCases) { demo in
                Button {
                    selectedDemo = demo
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: demo.icon)
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(demo.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(demo.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("SwiftyMetal")
            .fullScreenCover(item: $selectedDemo) { demo in
                DemoContainer(demo: demo) {
                    selectedDemo = nil
                }
            }
        }
    }
}

// MARK: - Full-Screen Container

private struct DemoContainer: View {

    let demo: Demo
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch demo {
            case .gooeyCards:
                SwiftyMetal()
            case .spiralList:
                SpiralListView()
            case .retroTV:
                RetroVideoView()
            }

            closeButton
        }
        .ignoresSafeArea()
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.top, 54)
        .padding(.leading, 16)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
}
