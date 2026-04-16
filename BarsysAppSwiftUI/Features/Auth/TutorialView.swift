//
//  TutorialView.swift
//  BarsysAppSwiftUI
//
//  Ports BarsysApp/Controllers/Tutorial/TutorialViewController.swift.
//  The real screen is a fullscreen tutorial video (resizeAspect, looping)
//  with mute/unmute and play/pause buttons. SwiftUI's AVKit `VideoPlayer`
//  gives us the same behaviour with native controls; we still expose
//  custom mute and continue buttons to match the UIKit overlay.
//

import SwiftUI
import AVKit

struct TutorialView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter

    @StateObject private var playerHolder = PlayerHolder()
    @State private var isMuted = true
    @State private var isPlaying = true

    /// Same default URL as VideoURLConstants.barsys360VideoUrl in the UIKit project.
    private let videoURL = URL(string: "https://barsys.com/tutorial/barsys360.mp4")

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.l) {
                // Video area (resizeAspect)
                Group {
                    if let player = playerHolder.player {
                        VideoPlayer(player: player)
                    } else {
                        ZStack {
                            Color.black
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Theme.Color.brand)
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: Theme.Spacing.s) {
                        IconButton(systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                            toggleMute()
                        }
                        IconButton(systemImage: isPlaying ? "pause.fill" : "play.fill") {
                            togglePlay()
                        }
                    }
                    .padding(Theme.Spacing.s)
                }
                .pagePadding()
                .padding(.top, Theme.Spacing.l)

                Text(Constants.tutorialsTextBarsys360)
                    .font(Theme.Font.medium(15))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .pagePadding()

                Spacer()

                VStack(spacing: Theme.Spacing.s) {
                    PrimaryButton(title: "Get started") {
                        env.preferences.hasSeenTutorial = true
                        router.didFinishTutorial()
                    }
                    Button("Skip") {
                        env.preferences.hasSeenTutorial = true
                        router.didFinishTutorial()
                    }
                    .foregroundStyle(Theme.Color.textSecondary)
                    .font(Theme.Font.medium(13))
                }
                .pagePadding()
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .onAppear {
            playerHolder.load(url: videoURL)
            playerHolder.player?.isMuted = isMuted
            if isPlaying { playerHolder.player?.play() }
        }
        .onDisappear {
            playerHolder.player?.pause()
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        playerHolder.player?.isMuted = isMuted
    }

    private func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            playerHolder.player?.play()
        } else {
            playerHolder.player?.pause()
        }
    }
}

/// Simple wrapper that owns an `AVPlayer` lifecycle and loops the video.
final class PlayerHolder: ObservableObject {
    @Published var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?

    func load(url: URL?) {
        guard let url else { return }
        let p = AVPlayer(url: url)
        self.player = p
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }
    }

    deinit {
        if let token = loopObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
