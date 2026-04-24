//
//  SplashView.swift
//  BarsysAppSwiftUI
//
//  1:1 port of BarsysApp/Controllers/Splash/SplashViewController.swift.
//
//  UIKit layout (User.storyboard + LaunchScreen.storyboard):
//    - SDAnimatedImageView with `transparent.gif` (1080×1080)
//    - height = view.height × 0.25   (view = full screen, NOT safe area)
//    - width  = view.width
//    - leading/trailing pinned to safeArea
//    - centerX, centerY to safeArea
//    - contentMode = .scaleAspectFit
//    - backgroundColor = primaryBackgroundColor
//    - 2.5s splash duration then navigate
//

import SwiftUI
import UIKit
import ImageIO

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            // UIKit constraint: height = view.height × 0.25
            // view.height is the FULL screen (852 on iPhone 15 Pro),
            // not the safe-area-inset height. Reconstruct it.
            let fullHeight = geo.size.height
                           + geo.safeAreaInsets.top
                           + geo.safeAreaInsets.bottom

            ZStack {
                Color("primaryBackgroundColor")
                    .ignoresSafeArea()

                SplashAnimatedGIFView(dataAssetName: "splashGif",
                                      fallbackImageName: "splashAppIcon")
                    .frame(width: geo.size.width,
                           height: fullHeight * 0.25)
                    .clipped()
                    // The GIF artwork is dark on a transparent background,
                    // so it blends into the dark background. Invert only
                    // in dark mode so light mode keeps the original GIF.
                    .colorInvert(isActive: colorScheme == .dark)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Barsys")
        .accessibilityAddTraits(.isImage)
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(isActive: Bool) -> some View {
        if isActive {
            self.colorInvert()
        } else {
            self
        }
    }
}

// MARK: - SplashAnimatedGIFView
//
// UIViewRepresentable that renders an animated GIF using ImageIO.
// Loads from the asset catalog via `NSDataAsset` — the GIF lives
// in Assets.xcassets/Splash/splashGif.dataset/transparent.gif.
//
// Uses a container UIView with the UIImageView pinned via auto-layout
// so the image is ALWAYS constrained to the SwiftUI-proposed frame
// (prevents the 1080×1080 intrinsic content size from overflowing).
private struct SplashAnimatedGIFView: UIViewRepresentable {
    let dataAssetName: String
    let fallbackImageName: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.backgroundColor = .clear

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        loadAnimatedImage(into: imageView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    // Accept whatever size SwiftUI proposes — never use the GIF's
    // 1080×1080 intrinsic content size.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UIView,
                      context: Context) -> CGSize? {
        guard let w = proposal.width, let h = proposal.height else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - GIF Loading

    private func loadAnimatedImage(into imageView: UIImageView) {
        // Try asset-catalog dataset first.
        if let asset = NSDataAsset(name: dataAssetName) {
            let data = asset.data as CFData
            if let source = CGImageSourceCreateWithData(data, nil),
               decodeGIF(source: source, into: imageView) {
                return
            }
        }

        // Fallback: loose bundle resource.
        if let url = Bundle.main.url(forResource: "transparent",
                                     withExtension: "gif"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           decodeGIF(source: source, into: imageView) {
            return
        }

        // Last resort: static splash icon.
        imageView.image = UIImage(named: fallbackImageName)
    }

    @discardableResult
    private func decodeGIF(source: CGImageSource,
                           into imageView: UIImageView) -> Bool {
        let frameCount = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var totalDuration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil)
            else { continue }
            frames.append(UIImage(cgImage: cgImage))
            totalDuration += Self.frameDelay(at: index, source: source)
        }

        guard !frames.isEmpty else { return false }

        imageView.animationImages = frames
        imageView.animationDuration = totalDuration
        imageView.animationRepeatCount = 0 // infinite loop
        imageView.image = frames.first
        imageView.startAnimating()
        return true
    }

    private static func frameDelay(at index: Int,
                                   source: CGImageSource) -> TimeInterval {
        let defaultDelay: TimeInterval = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary]
                as? [CFString: Any]
        else {
            return defaultDelay
        }
        if let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime]
            as? TimeInterval, unclamped > 0 {
            return unclamped
        }
        if let clamped = gifProperties[kCGImagePropertyGIFDelayTime]
            as? TimeInterval, clamped > 0 {
            return clamped
        }
        return defaultDelay
    }
}
