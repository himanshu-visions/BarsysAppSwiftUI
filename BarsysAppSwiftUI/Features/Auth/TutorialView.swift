//
//  TutorialView.swift
//  BarsysAppSwiftUI
//
//  1:1 port of `BarsysApp/Controllers/Tutorial/TutorialViewController.swift`
//  + `ControlCenter.storyboard` scene `XYQ-8f-7GQ`.
//
//  UIKit reference:
//   • Modal presentation: `modalPresentationStyle = .overFullScreen`
//   • Background: black (storyboard root view)
//   • Video view (`XGh-V7-FXt`): pinned to safeArea (top: 88pt
//     status-bar-inset, bottom: 0), 20pt corner radius.
//     - VideoPlayerManager with `.resizeAspect` fill, `shouldRepeat: true`.
//     - Auto-plays in `viewWillAppear`; auto-pauses in `viewWillDisappear`.
//   • Play / pause button (`7sX-Xb-XWl`): full-screen overlay 375×661,
//     uses `play_thumb` image when paused, hidden when playing.
//   • Mute / unmute button (`94J-Vh-Rii`): bottom-right 35×44,
//     trailing 20pt, bottom 16pt, uses `mute` / `unmute` image.
//     Default state: MUTED (`isMuted = true`), `player.isMuted = true`.
//   • Close button (`0dn-hj-C21`): top-right 30×30, trailing 20pt,
//     top 20pt, uses `crossIcon`.
//   • Bounce effect on mute + play/pause + close.
//   • Haptic: light on play/pause + close, selection on mute toggle.
//
//  Default video: `VideoURLConstants.barsys360VideoUrl`. Override via
//  the `videoURL` initializer parameter (Control Center "Tutorial" menu
//  passes the device-specific URL for the connected device — Coaster /
//  Shaker → barsysCoasterUrl, Barsys 360 → barsys360VideoUrl).
//

import SwiftUI
import AVKit

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    /// Dismiss callback fired when the user closes the tutorial. Always
    /// provided — `TutorialView` is only shown modally from the
    /// device-pairing flow (1:1 with UIKit, which never auto-presents
    /// a tutorial after login).
    private let onDismiss: () -> Void

    /// Video URL — defaults to the Barsys 360 instruction video.
    /// Caller can override per-device (Coaster / Shaker).
    private let videoURL: URL?

    @StateObject private var playerHolder = PlayerHolder()
    @State private var isMuted: Bool = true                 // UIKit `isMuted = true` default

    /// Mirrors `playerHolder.isPlaying` for view-binding ease. Updates
    /// flow ONE-WAY from PlayerHolder → this @State so the play_thumb
    /// overlay reflects whatever the AVPlayer is actually doing
    /// (including the auto-pause/resume on app backgrounding).
    private var isPlaying: Bool { playerHolder.isPlaying }

    /// Modal-presentation init — used by Control Center → Tutorial menu
    /// item and the Explore screen device-paired tutorial card. The
    /// caller passes a device-specific URL and a dismiss closure that
    /// hides the cover. 1:1 with UIKit
    /// `tutorialVc.videoURL = URL(string: ...)` in
    /// `ControlCenterViewController` L195-197.
    init(videoURL: URL?, onDismiss: @escaping () -> Void) {
        self.videoURL = videoURL ?? URL(string: VideoURLConstants.barsys360VideoUrl)
        self.onDismiss = onDismiss
    }

    var body: some View {
        // UIKit storyboard root view: solid black backgroundColor
        // (white=0.0, alpha=1) — sits behind the video so any letterbox
        // bars from `resizeAspect` read as black, matching the cinematic
        // tutorial framing.
        ZStack {
            Color.black.ignoresSafeArea()

            // Video view container — UIKit `XGh-V7-FXt` (pinned to
            // safeArea top + bottom + leading + trailing). Inside it
            // sits an AVPlayer with `.resizeAspect` (preserve aspect,
            // letterbox if needed) and `shouldRepeat: true`.
            ZStack {
                if let player = playerHolder.player {
                    VideoPlayerView(player: player, fillMode: .resizeAspect)
                        .ignoresSafeArea(edges: [.bottom, .horizontal])
                } else {
                    Color.black
                }

                // Full-screen play / pause overlay button — UIKit
                // `7sX-Xb-XWl` (frame 375×661, fills the video view).
                // 1:1 with TutorialViewController.updatePlayPauseIcon()
                // L62-65: `imageName = isPlaying == true ? nil : UIImage.playThumb`
                //   • Playing  → image is NIL (button has no visible
                //               glyph; the whole video is a play/pause
                //               tap target)
                //   • Paused   → 24×24 `play_thumb` icon centered (the
                //               storyboard image declares natural size
                //               24×24 — `<image name="play_thumb"
                //               width="24" height="24"/>` L1744)
                Button {
                    HapticService.light()
                    togglePlay()
                } label: {
                    ZStack {
                        // Transparent tap target spans the whole video
                        // — without it the button has no hit area when
                        // the play icon is hidden.
                        Color.black.opacity(0.001)
                        if !isPlaying {
                            // Storyboard `play_thumb width="24" height="24"`.
                            // Render at natural 24×24, white tint to match
                            // UIKit `tintColor white="1" alpha="1"` on btn.
                            Image("play_thumb")
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .foregroundStyle(Theme.Color.softWhiteText)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .accessibilityHint("Toggle video playback")
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Top-right close button — UIKit `0dn-hj-C21`, 30×30,
            // trailing 20pt, top 20pt, `crossIcon`, white tint.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        HapticService.light()
                        playerHolder.cleanup()
                        finishTutorial()
                    } label: {
                        Image("crossIcon")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .foregroundStyle(Theme.Color.softWhiteText)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                    .accessibilityLabel("Close tutorial")
                }
                Spacer()

                // Bottom-right mute / unmute button — UIKit
                // `94J-Vh-Rii`, 35×44, trailing 20pt, bottom 16pt,
                // images `mute` / `unmute`, white tint.
                HStack {
                    Spacer()
                    Button {
                        HapticService.selection()
                        toggleMute()
                    } label: {
                        Image(isMuted ? "mute" : "unmute")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 35, height: 44)
                            .foregroundStyle(Theme.Color.softWhiteText)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    .accessibilityHint("Toggle audio")
                }
            }
        }
        .statusBarHidden(false)
        // 1:1 with UIKit `viewWillAppear`:
        //   playerView?.play()
        //   updatePlayPauseIcon()
        //   if isMuted { player?.isMuted = true; btnMute.setImage(.mute) }
        .onAppear {
            playerHolder.load(url: videoURL, repeatPlayback: true)
            playerHolder.player?.isMuted = isMuted
            playerHolder.play()
        }
        // 1:1 with UIKit `viewWillDisappear`:
        //   playerView?.pause(); updatePlayPauseIcon()
        .onDisappear {
            playerHolder.pause()
        }
    }

    // MARK: - Actions (1:1 with UIKit IBActions)

    /// 1:1 with UIKit `muteUnmuteAction(_:)`:
    ///   if isMuted { player.isMuted = false; btnMute.setImage(.unmute) }
    ///   else       { player.isMuted = true;  btnMute.setImage(.mute) }
    ///   isMuted.toggle()
    private func toggleMute() {
        isMuted.toggle()
        playerHolder.player?.isMuted = isMuted
    }

    /// 1:1 with UIKit `didPressPlayPauseButton(_:)`:
    ///   playerView?.togglePlayPause()
    ///   updatePlayPauseIcon()
    private func togglePlay() {
        if playerHolder.isPlaying {
            playerHolder.pause()
        } else {
            playerHolder.play()
        }
    }

    /// Dismisses the modal tutorial cover. 1:1 with UIKit `dismiss(animated:)`
    /// in `TutorialViewController.dismissAction(_:)` — the post-login
    /// onboarding tutorial that UIKit never had stays absent here too.
    private func finishTutorial() {
        onDismiss()
    }
}

// MARK: - VideoPlayerView (UIViewRepresentable for resizeAspect control)
//
// SwiftUI's `VideoPlayer` always uses `.resizeAspect` but renders system
// transport controls overlaid on the video. UIKit `VideoPlayerManager`
// hides those controls — it just shows the raw frame and overlays the
// app's own play / mute / close buttons. We mirror that by hosting an
// `AVPlayerLayer` directly via `UIViewRepresentable`, with the fill mode
// passed in (`.resizeAspect` for the tutorial — letterbox to preserve
// aspect, exactly like UIKit `playerView?.setupPlayer(... fillMode: .resizeAspect)`).
struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let fillMode: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fillMode
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = fillMode
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - PlayerHolder
//
// 1:1 port of UIKit `VideoPlayerManager` (Helpers/VideoManager/VideoManager.swift).
//
// Mirrors:
//   • setupPlayer(with:on:fillMode:shouldRepeat:) — same dedup-by-URL
//     behaviour to avoid resetting playback if the same video is
//     reloaded.
//   • togglePlayPause / play / pause — explicit `isPlaying` state.
//   • playerDidFinishPlaying — loop on `.AVPlayerItemDidPlayToEndTime`.
//   • cleanup — pauses, removes observers, releases player.
//   • addAppLifecycleObservers — tracks `wasPlayingBeforeBackground`
//     on `UIApplication.willResignActiveNotification`; resumes on
//     `didBecomeActiveNotification` ONLY if the user had it playing
//     before the app backgrounded. Without this, the SwiftUI port
//     would let the video play silently in the background while the
//     user is on the home screen — UIKit explicitly suspends it.
final class PlayerHolder: ObservableObject {
    @Published var player: AVPlayer?
    @Published private(set) var isPlaying: Bool = false

    private var loopObserver: NSObjectProtocol?
    private var willResignObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?

    /// 1:1 with UIKit `wasPlayingBeforeBackground` — captured on
    /// resign-active so the resume only fires if the user had the
    /// video playing.
    private var wasPlayingBeforeBackground = false

    init() {
        addAppLifecycleObservers()
    }

    func load(url: URL?, repeatPlayback: Bool = true) {
        guard let url else { return }
        // 1:1 with VideoPlayerManager L32 dedup — re-loading the same
        // URL skips a reset to avoid restarting playback.
        if let existing = player,
           let currentURL = (existing.currentItem?.asset as? AVURLAsset)?.url,
           currentURL == url {
            return
        }
        cleanup(removeLifecycle: false)
        let p = AVPlayer(url: url)
        self.player = p
        if repeatPlayback {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                self?.player?.play()
                self?.isPlaying = true
            }
        }
    }

    /// 1:1 with UIKit `play()` — sets `isPlaying = true` after issuing
    /// the AVPlayer command.
    func play() {
        player?.play()
        isPlaying = true
    }

    /// 1:1 with UIKit `pause()` — sets `isPlaying = false`.
    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// 1:1 with UIKit `cleanup()` — full teardown for view dismiss.
    func cleanup() {
        cleanup(removeLifecycle: true)
    }

    private func cleanup(removeLifecycle: Bool) {
        player?.pause()
        isPlaying = false
        if let token = loopObserver {
            NotificationCenter.default.removeObserver(token)
            loopObserver = nil
        }
        if removeLifecycle {
            removeAppLifecycleObservers()
        }
        player = nil
    }

    // MARK: - App lifecycle (UIKit VideoPlayerManager L107-134)

    private func addAppLifecycleObservers() {
        willResignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.wasPlayingBeforeBackground = self.isPlaying
            self.pause()
        }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.wasPlayingBeforeBackground {
                self.play()
            }
        }
    }

    private func removeAppLifecycleObservers() {
        if let token = willResignObserver {
            NotificationCenter.default.removeObserver(token)
            willResignObserver = nil
        }
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            didBecomeActiveObserver = nil
        }
    }

    deinit { cleanup(removeLifecycle: true) }
}
