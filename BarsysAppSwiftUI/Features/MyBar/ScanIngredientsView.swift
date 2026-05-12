//
//  ScanIngredientsView.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit `ScanIngredientsViewController` and its
//  `+Camera` extension. Reference files:
//    • Controllers/MyBar/ScanIngredientsViewController.swift
//    • Controllers/MyBar/ScanIngredientsViewController+Camera.swift
//    • Helpers/UploadImage/UploadIngredientsImage.swift
//    • Helpers/CustomViews/UIViewClass+GlassEffects.swift
//    • StoryBoards/Base.lproj/Device.storyboard scene `Lia-fw-G3l`
//
//  This screen is pushed from `MyBarView` when the user taps:
//    • Empty state → "Take A Photo"               (storyboard btn `Avz-rE-CtO`)
//    • Data state  → "Add ingredient" → "Camera"  (storyboard btn `jrL-ey-GS1`)
//
//  -------------------------------------------------------------------
//  RUNTIME FLOW (ports UIKit ScanIngredientsViewController.viewDidLoad
//  + viewWillAppear + capturePhoto + proceedForMyBar + popup)
//  -------------------------------------------------------------------
//
//  • viewDidLoad → setupView() → setupCaptureButton() → setupRetakeSubmitButtons()
//  • viewWillAppear → if !isImageCaptured → startCamera()
//  • Tap capture → capturePhoto() → AVCapturePhotoCaptureDelegate
//      → photoOutput(_:didFinishProcessingPhoto:error:) →
//        capturedImage = image · stopCamera() · showCapturedImage()
//        → swap viewCaptureImage out (hidden) and
//          viewRetakeSubmitContainer in (visible)
//  • Tap retake → restartCameraProcess() → drop captured image,
//        flush session, startCamera() again
//  • Tap submit → proceedForMyBar(capturedImage:) →
//        ConnectionMonitor → showGlassLoader("Adding Ingredients") →
//        UploadIngredientsImage().uploadImageAndGetIngredientsResponseForMyBar →
//        filter base/mixer (drop garnish/additional) → addingredientPopUpShow
//  • Popup Proceed → MyBarApiService.addIngredientToMyBar → on success,
//        onIngredientScannedForMyBar?(arrayOfSelections) and pop the VC
//  • Popup Reupload → restartCameraProcess()
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Camera controller
//
// Owns a single `AVCaptureSession` for the scan screen and exposes the
// state SwiftUI needs (`capturedImage`, `isCapturing`, `permissionState`).
// Mirrors the imperative state machine in
// `ScanIngredientsViewController` (`captureSession`, `photoOutput`,
// `capturedImage`, `isImageCaptured`, `isCapturing`,
// `sessionQueue`) inside an `ObservableObject` so the view can react
// to capture / reset transitions.

@MainActor
final class ScanCameraController: NSObject, ObservableObject {

    // MARK: Permission states

    enum PermissionState: Equatable {
        case unknown          // not yet checked
        case authorized
        case denied           // explicit deny / restricted / notDetermined-then-rejected
        case unavailable      // device has no usable camera (simulator, hardware fault)
    }

    // MARK: Public state

    /// Live AVCaptureSession — handed to `ScanCameraPreview` so the
    /// preview layer renders directly off it.
    let session = AVCaptureSession()

    /// The image captured by the most recent shutter tap. SwiftUI
    /// observes this to swap from "live preview" → "captured image"
    /// state, matching UIKit `viewCaptureImage.isHidden = isImageCaptured`
    /// / `viewRetakeSubmitContainer.isHidden = !isImageCaptured`
    /// (ScanIngredientsViewController.swift L186-193).
    @Published private(set) var capturedImage: UIImage?

    /// Drives the disabled state of the shutter — guards against
    /// double-tap that UIKit's `isCapturing` flag also covers
    /// (ScanIngredientsViewController.swift L40 + L146-150).
    @Published private(set) var isCapturing: Bool = false

    /// Camera permission state. SwiftUI consults this to decide
    /// whether to show the live preview or push a denied alert.
    @Published var permissionState: PermissionState = .unknown

    /// `true` after `AVCaptureSession.startRunning()` returns — the
    /// view uses this to drop the "Starting camera…" loader as soon
    /// as the preview layer can actually pump frames. Mirrors the
    /// underlying `session.isRunning` state on the main actor so
    /// SwiftUI can observe it.
    @Published private(set) var isSessionRunning: Bool = false

    // MARK: Private state

    private var photoOutput: AVCapturePhotoOutput?
    private let sessionQueue = DispatchQueue(label: "scan.ingredients.session.queue")
    /// Once we've added input + output to the session we don't need
    /// to re-add them every time the screen reappears — UIKit avoids
    /// this with the same `captureSession == nil` guard at the top of
    /// `startCamera()` (ScanIngredientsViewController+Camera.swift L18).
    private var didConfigure = false

    /// The single `UIView` that backs the live camera preview, owned
    /// by THIS controller — not by `ScanCameraPreview`'s
    /// `UIViewRepresentable` lifecycle.
    ///
    /// Why ownership lives here: when SwiftUI swaps `portraitLayout`
    /// (`VStack`) for `landscapeLayout` (`HStack` with a nested
    /// `VStack`), the view tree shape around the camera changes
    /// completely. SwiftUI then calls `dismantleUIView` on the old
    /// `PreviewView` and `makeUIView` for a new one — and the new
    /// `AVCaptureVideoPreviewLayer` has zero frames buffered, so it
    /// renders solid black until the session pumps a fresh frame
    /// into it. THAT is the "right half goes black on rotation"
    /// glitch.
    ///
    /// Pinning the `UIView` (and therefore its
    /// `AVCaptureVideoPreviewLayer`) to the controller means the
    /// SAME layer is just reparented from old superview → new
    /// superview on rotation. UIKit's `addSubview` automatically
    /// removes from the previous superview, and the layer keeps its
    /// last frame painted across the move — no black flash.
    let previewView: ScanCameraPreview.PreviewView = {
        let v = ScanCameraPreview.PreviewView()
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }()

    override init() {
        super.init()
        // Wire the session into the controller-owned preview layer
        // ONCE up front, so the preview is ready to display as soon
        // as the session starts running — no waiting for SwiftUI's
        // first `makeUIView` callback to attach it.
        previewView.previewLayer.session = session
    }

    // MARK: - Lifecycle

    /// 1:1 with UIKit `viewWillAppear` recipe:
    ///   if !isImageCaptured { sessionQueue.async { startCamera() } }
    /// First-call path also requests AVCaptureDevice authorization.
    func start() {
        // Already running — nothing to do.
        if session.isRunning {
            if !isSessionRunning { isSessionRunning = true }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let granted = await Self.ensureAuthorization()
            await MainActor.run {
                self.permissionState = granted ? .authorized : .denied
            }
            guard granted else { return }
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.configureSessionIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.isSessionRunning = running
                }
            }
        }
    }

    /// 1:1 with UIKit `stopCamera()`. Called from `viewWillDisappear`.
    func stop() {
        sessionQueue.async { [weak self, session] in
            if session.isRunning {
                session.stopRunning()
            }
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }

    /// 1:1 with UIKit `restartCameraProcess()` — drop the captured
    /// image, flush state and restart the live preview.
    func reset() {
        capturedImage = nil
        isCapturing = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isSessionRunning = running
            }
        }
    }

    /// 1:1 with UIKit `capturePhoto()` — guarded by `isCapturing`,
    /// then `photoOutput.capturePhoto(with:delegate:)`. Result is
    /// delivered via `AVCapturePhotoCaptureDelegate` below.
    func capture() {
        guard !isCapturing else { return }
        guard let output = photoOutput else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()

        // QA fix ("after capture in landscape, the image comes out
        // portrait"): the PHOTO OUTPUT has its own
        // `AVCaptureConnection`, separate from the preview layer's
        // connection that `ScanCameraPreview.PreviewView` keeps in
        // sync. Without setting the photo connection's rotation here,
        // captured frames are encoded against whatever orientation
        // the connection defaulted to (typically portrait) and the
        // resulting JPEG carries portrait EXIF — so a landscape shot
        // displays sideways / portrait-shaped on the review screen.
        //
        // Read the interface orientation on the main actor (this
        // function already runs on @MainActor since the class is
        // @MainActor), then hop to `sessionQueue` to mutate the
        // connection in the same serial queue used for all other
        // session config.
        let interfaceOrientation = currentInterfaceOrientation()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let connection = output.connection(with: .video) {
                Self.applyOrientation(interfaceOrientation, to: connection)
            }
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Resolve the active `UIInterfaceOrientation`, preferring the
    /// preview view's own window scene (most accurate during multi-
    /// scene / split-view) and falling back to the first connected
    /// window scene. Mirrors `PreviewView.applyVideoOrientationFromInterface`'s
    /// resolution order so the photo output and the preview layer
    /// always agree on which way is "up".
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let scene = previewView.window?.windowScene {
            return scene.interfaceOrientation
        }
        return UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
    }

    /// Stamp the given interface orientation onto an
    /// `AVCaptureConnection`. Uses iOS 17's
    /// `videoRotationAngle` API when available, falls back to the
    /// (now-deprecated) `videoOrientation` enum for iOS 16.
    /// Numeric angle mapping mirrors
    /// `PreviewView.applyVideoOrientationFromInterface` exactly so
    /// preview and capture stay in lockstep.
    private static func applyOrientation(
        _ interfaceOrientation: UIInterfaceOrientation,
        to connection: AVCaptureConnection
    ) {
        if #available(iOS 17.0, *) {
            let angle: CGFloat
            switch interfaceOrientation {
            case .portrait:           angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeLeft:      angle = 180
            case .landscapeRight:     angle = 0
            case .unknown:            angle = 90
            @unknown default:         angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            let avOrientation: AVCaptureVideoOrientation
            switch interfaceOrientation {
            case .portrait:           avOrientation = .portrait
            case .portraitUpsideDown: avOrientation = .portraitUpsideDown
            case .landscapeLeft:      avOrientation = .landscapeLeft
            case .landscapeRight:     avOrientation = .landscapeRight
            case .unknown:            avOrientation = .portrait
            @unknown default:         avOrientation = .portrait
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = avOrientation
            }
        }
    }

    // MARK: - Internal

    /// 1:1 with UIKit `startCamera()` body — runs ONCE on the first
    /// `start()` call. Adds the back wide-angle camera as an input
    /// and an `AVCapturePhotoOutput` for the shutter.
    private func configureSessionIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                // Surface the same "Camera Disabled" alert as UIKit
                // `showCameraErrorAlert` (ScanIngredientsViewController
                // +Camera.swift L75-88) — we reuse the `.denied` case
                // since the resulting UI prompt is identical (cancel +
                // Go-to-Settings).
                self?.permissionState = .unavailable
            }
            return
        }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.photoOutput = output
        }
        session.commitConfiguration()
    }

    /// Bridges `AVCaptureDevice.authorizationStatus` to a single
    /// async-await call. Mirrors UIKit's
    /// `MediaPermissions.requestCamera` recipe used by the
    /// SwiftUI port elsewhere.
    private static func ensureAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                AVCaptureDevice.requestAccess(for: .video) { c.resume(returning: $0) }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
//
// 1:1 with UIKit `photoOutput(_:didFinishProcessingPhoto:error:)` at
// ScanIngredientsViewController+Camera.swift L153-183. On success:
//   • capturedImage = image
//   • stopCamera() (we just leave session running until the user
//     submits/retakes — UIKit stops, we don't strictly need to since
//     `ScanCameraPreview` is hidden when an image is captured anyway,
//     but stopping saves battery + thermal so we mirror it).
//   • showCapturedImage()  ← in SwiftUI this is just a state flip.

extension ScanCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            print("ScanIngredients: capture error \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isCapturing = false
            }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.isCapturing = false
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCapturing = false
            self.capturedImage = image
        }
        // Stop the session on the session queue so the preview layer
        // immediately freezes — matches UIKit `stopCamera()` after
        // the photo lands (ScanIngredientsViewController+Camera.swift
        // L180).
        sessionQueue.async { [weak self, session] in
            if session.isRunning {
                session.stopRunning()
            }
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
}

// MARK: - Live camera preview
//
// Wraps `AVCaptureVideoPreviewLayer` in a `UIView` whose backing layer
// IS that preview layer. Avoids the auto-resize headaches of inserting
// the layer as a sublayer (which UIKit had to fight via
// `viewDidLayoutSubviews`).

struct ScanCameraPreview: UIViewRepresentable {
    /// The controller owns the `PreviewView` — see
    /// `ScanCameraController.previewView` for the rationale (TL;DR:
    /// keeps the `AVCaptureVideoPreviewLayer` alive across SwiftUI
    /// view tree rebuilds so rotation doesn't flash black).
    let controller: ScanCameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = controller.previewView
        // Defensive: if the view was attached to a previous
        // superview (e.g. during a rotation, SwiftUI tears down the
        // old representable BEFORE building the new one), make sure
        // it's detached so UIKit doesn't reject the imminent
        // `addSubview` call. UIKit's own `addSubview` does this
        // implicitly, but doing it here keeps the state predictable
        // when SwiftUI sequences makeUIView calls in the order it
        // chooses.
        view.removeFromSuperview()
        view.startObservingOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Session is wired up at controller-init time; no need to
        // re-attach here. We do, however, refresh the connection's
        // video rotation so the live feed reflects whatever
        // orientation the window settled on after the last layout
        // pass.
        uiView.applyVideoOrientationFromInterface()
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        // Intentionally NOT calling `stopObservingOrientation()` —
        // the controller owns the view and survives this dismantle.
        // Calling it here would tear down the rotation observer for
        // the next layout swap, leaving the live feed stuck at the
        // pre-rotation orientation.
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var orientationObserver: NSObjectProtocol?

        // 1:1 with UIKit `viewDidLayoutSubviews` updating the preview
        // layer frame to match `viewCameraFrame.bounds`
        // (ScanIngredientsViewController.swift L138). In SwiftUI the
        // backing layer IS the preview layer, so the layer frame
        // tracks the view bounds automatically — but we still hook
        // `layoutSubviews` to refresh the connection's video
        // orientation when the frame changes (e.g. portrait ↔
        // landscape rotation).
        override func layoutSubviews() {
            super.layoutSubviews()
            applyVideoOrientationFromInterface()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyVideoOrientationFromInterface()
        }

        func startObservingOrientation() {
            guard orientationObserver == nil else { return }
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applyVideoOrientationFromInterface()
            }
        }

        func stopObservingOrientation() {
            if let token = orientationObserver {
                NotificationCenter.default.removeObserver(token)
                orientationObserver = nil
            }
        }

        /// Rotate the live video to match the current interface
        /// orientation. UIKit handles this implicitly via the
        /// view-controller's auto-rotate behaviour; in SwiftUI we
        /// have to drive it from the window scene each layout pass.
        ///
        /// Without this call the live preview stays locked to
        /// `.portrait` even when the phone is in landscape, which is
        /// what made the camera feed appear cropped / tiny in
        /// landscape on iPhone.
        func applyVideoOrientationFromInterface() {
            guard let connection = previewLayer.connection else { return }
            let interfaceOrientation: UIInterfaceOrientation = {
                if let scene = window?.windowScene {
                    return scene.interfaceOrientation
                }
                return UIApplication.shared
                    .connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.interfaceOrientation ?? .portrait
            }()

            // iOS 17 deprecated `videoOrientation` in favour of a
            // numeric `videoRotationAngle`. Use the new API when
            // available, fall back to the old one for iOS 16.
            if #available(iOS 17.0, *) {
                let angle: CGFloat
                switch interfaceOrientation {
                case .portrait:           angle = 90
                case .portraitUpsideDown: angle = 270
                case .landscapeLeft:      angle = 180
                case .landscapeRight:     angle = 0
                case .unknown:            angle = 90
                @unknown default:         angle = 90
                }
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            } else {
                let avOrientation: AVCaptureVideoOrientation
                switch interfaceOrientation {
                case .portrait:           avOrientation = .portrait
                case .portraitUpsideDown: avOrientation = .portraitUpsideDown
                case .landscapeLeft:      avOrientation = .landscapeLeft
                case .landscapeRight:     avOrientation = .landscapeRight
                case .unknown:            avOrientation = .portrait
                @unknown default:         avOrientation = .portrait
                }
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = avOrientation
                }
            }
        }
    }
}

// MARK: - ScanIngredientsView
//
// 1:1 with UIKit `ScanIngredientsViewController`. Renders the live
// preview inside `viewCameraFrame`, swaps to the captured image when
// the shutter fires, and presents the same multi-ingredient popup
// after `proceedForMyBar(capturedImage:)`.

struct ScanIngredientsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    @Environment(\.dismiss) private var dismiss
    /// `compact` vertical size class on iPhone signals "landscape /
    /// short" — we use it to (a) shorten the multi-ingredient popup
    /// list height so the card fits the ~390pt landscape viewport,
    /// and (b) stop the title's description from wrapping into a
    /// multi-line block in the right column.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @StateObject private var camera = ScanCameraController()

    // Popup state — 1:1 with `MyBarView.detectedIngredients` /
    // `showIngredientsFoundPopup`. Same layout, same Reupload /
    // Proceed actions; differs only in that Reupload here restarts
    // the live camera (UIKit `restartCameraProcess()`) instead of
    // re-opening the system photo picker.
    @State private var detectedIngredients: [DetectedMyBarIngredient] = []
    @State private var showIngredientsFoundPopup = false
    @State private var showCameraDeniedAlert = false

    /// Pre-resolved landscape flag — read from `UIDevice` /
    /// `UIWindowScene` synchronously so the very first render is
    /// already in the correct orientation. Without this, the screen
    /// briefly composes the portrait layout (because the
    /// `verticalSizeClass` env value lags one render pass) and then
    /// snaps to landscape, which is exactly the "right half goes
    /// black on rotation" behaviour the user reported.
    @State private var deviceLandscape: Bool = ScanIngredientsView.resolveLandscapeNow()

    // MARK: - Derived helpers

    private var deviceIconName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }
    private var deviceKindName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    private var hasCapturedImage: Bool { camera.capturedImage != nil }
    private var selectedCount: Int {
        detectedIngredients.filter { $0.isSelected && !$0.isExisting }.count
    }
    private var hasNewIngredients: Bool {
        detectedIngredients.contains { !$0.isExisting }
    }

    // MARK: - Body
    //
    // Layout switch is driven by `@Environment(\.verticalSizeClass)`,
    // NOT a `GeometryReader`. Why:
    //   • `verticalSizeClass` is propagated through SwiftUI's trait
    //     collection. iOS updates it once per rotation, after the
    //     window has settled at the new size. The body re-renders
    //     exactly once, with the final layout — no intermediate
    //     "in-flight" sizes during the animation.
    //   • A previous `GeometryReader { proxy in … }` wrapper (with
    //     an explicit `.frame(width: proxy.size.width, height:
    //     proxy.size.height)` on the inner ZStack) caused the screen
    //     to look "stuck" on rotation: the proxy reports a stream of
    //     intermediate sizes during the rotation animation, the
    //     explicit frame fights the system's adaptive layout, and
    //     the result was that the camera preview occasionally froze
    //     in the pre-rotation orientation until the user navigated
    //     away and back.
    //   • iPad is forced to portrait layout regardless of size class
    //     so the screen never collapses into the iPhone-landscape
    //     side-by-side variant on iPad split view.

    // Two signals, OR'd together:
    //   • `verticalSizeClass == .compact` — authoritative once
    //     SwiftUI's trait collection has propagated (typically the
    //     SECOND render pass after rotation / first appear).
    //   • `deviceLandscape` — resolved synchronously from
    //     `UIWindowScene.interfaceOrientation` / `UIDevice.current
    //     .orientation`, so the FIRST render pass is already correct.
    //
    // OR'ing them means the layout flips to landscape the moment
    // either source agrees.
    //
    // iPad: previously excluded from the landscape variant entirely
    // (so split-view never collapsed to the iPhone side-by-side
    // layout) — but QA reported the camera reads as small / narrow
    // on iPad landscape because the portrait layout's 3:4 aspect-
    // fit camera shrinks to the viewport's short side. Now iPad
    // landscape ALSO uses the side-by-side layout — it has the
    // horizontal space for it and the camera column gets the
    // majority of the viewport width. iPad portrait still uses the
    // tall portrait layout (deviceLandscape false → portraitLayout).
    private var isPhoneLandscape: Bool {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if isIPad {
            // iPad: size classes are regular/regular in BOTH
            // orientations, so the only reliable landscape signal
            // is the explicit device orientation flag.
            return deviceLandscape
        }
        return verticalSizeClass == .compact || deviceLandscape
    }

    /// Synchronous landscape probe used to seed `deviceLandscape`
    /// at first render. Walks `UIWindowScene.interfaceOrientation`
    /// first (most reliable: respects supported orientations / app
    /// state), and falls back to `UIDevice.current.orientation`
    /// when the scene's value is unknown (true in the brief window
    /// between view init and the window being attached).
    ///
    /// iPad is no longer short-circuited to `false` — the side-by-
    /// side layout now applies on iPad landscape too (see
    /// `isPhoneLandscape` above), so the seed needs the real
    /// orientation on iPad as well.
    private static func resolveLandscapeNow() -> Bool {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let interface = scene?.interfaceOrientation ?? .unknown
        if interface != .unknown { return interface.isLandscape }
        let device = UIDevice.current.orientation
        if device.isLandscape { return true }
        if device.isPortrait { return false }
        return false
    }

    /// Re-probe orientation from a notification / appear callback
    /// and write the result to the `@State` flag. Cheap — only
    /// commits to state when the value actually changed, so
    /// SwiftUI doesn't trigger a redundant body pass.
    private func refreshDeviceLandscape() {
        let current = ScanIngredientsView.resolveLandscapeNow()
        if current != deviceLandscape {
            deviceLandscape = current
        }
    }

    var body: some View {
        ZStack {
            Color("primaryBackgroundColor").ignoresSafeArea()

            // Wrapping the conditional in a `Group` + explicit
            // `.transaction { $0.animation = nil }` collapses
            // SwiftUI's implicit cross-fade between
            // `portraitLayout` and `landscapeLayout`. Without
            // suppression, on rotation SwiftUI tries to animate
            // both branches simultaneously — the dismantled
            // portrait branch fades out at its old (portrait)
            // frame on top of the freshly-built landscape branch,
            // and during that fade the camera-frame side of the
            // screen is a near-black placeholder square. That fade
            // window IS the black-half-screen the user sees mid-
            // rotation. Cutting the animation flips the layout in
            // a single layout pass instead.
            Group {
                if isPhoneLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        // Always fill whatever the parent proposes — during the
        // rotation animation the view's frame can briefly retain
        // its pre-rotation size while the window is already at
        // post-rotation dimensions. Without this `.frame`, the
        // gap between the (small) view and the (larger) window
        // shows the window's black backing, which the user reads
        // as "half the screen turned black".
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .chooseOptionsStyleNavBar()
        .interactivePopGestureEnabled()
        .onAppear {
            // Begin generating orientation notifications so the
            // preview-layer rotation observer in `PreviewView` fires
            // when the user rotates the device. Other screens in the
            // app may have already enabled this; calling the API a
            // second time is a no-op.
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            // Re-probe in case the scene attached after the @State
            // seed ran (init runs before the window is wired up on
            // some iOS versions).
            refreshDeviceLandscape()
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        // Rotation: update the synchronous landscape flag the moment
        // the device reports a new orientation, so the layout flips
        // BEFORE SwiftUI propagates the new `verticalSizeClass`.
        // Without this, the layout is gated on the env update which
        // can lag a frame and leaves the camera view recreated mid-
        // rotation — that flash is the "black half-screen" the user
        // saw.
        .onReceive(NotificationCenter.default.publisher(
            for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshDeviceLandscape()
        }
        // Belt-and-braces: when SwiftUI's authoritative
        // `verticalSizeClass` finally lands, mirror it into the
        // synchronous flag. Keeps the two signals in agreement so
        // the layout doesn't oscillate.
        .onChange(of: verticalSizeClass) { _ in
            refreshDeviceLandscape()
        }
        .onChange(of: camera.permissionState) { state in
            // UIKit: `showCameraErrorAlert()` is invoked from inside
            // `startCamera()` when the AV input fails to acquire.
            if state == .denied || state == .unavailable {
                showCameraDeniedAlert = true
            }
        }
        .alert(Constants.cameraDisabledForApp,
               isPresented: $showCameraDeniedAlert,
               actions: {
            Button(ConstantButtonsTitle.cancelButtonTitle, role: .cancel) {
                dismiss()
            }
            Button(ConstantButtonsTitle.goToSettingsTitle) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }, message: {
            Text(Constants.cameraRequiredAuthorizationForScanIngredients)
        })
        .overlay {
            if showIngredientsFoundPopup {
                ingredientsFoundPopup
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showIngredientsFoundPopup)
    }

    // MARK: - Portrait layout (1:1 with the original UIKit storyboard)
    //
    // Title at top → camera frame (3:4 portrait aspect) → spacer →
    // controls. Same dimensions as the iPhone storyboard scene.

    @ViewBuilder
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            titleAndSubtitle
                .padding(.top, 8)

            cameraOrCapturedImageView
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .padding(.top, 24)

            Spacer(minLength: 16)

            bottomControlsContainer
                .padding(.bottom, 50)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Landscape layout (iPhone-only — iPad portrait still wins)
    //
    // Two columns, per the user-confirmed layout:
    //   • LEFT  — Title + description, vertically centered, left-
    //             aligned text. Capped at ~38% of screen width so the
    //             right (camera) column always gets the majority of
    //             the viewport.
    //   • RIGHT — Camera preview filling the available vertical
    //             space at a 4:3 landscape aspect, with the
    //             retake/submit (or shutter) button row directly
    //             below it. The button row is 45pt for the two-button
    //             state and 80pt for the shutter state, mirroring the
    //             portrait layout. The camera frame uses
    //             `aspectRatio(.fit)` so it scales down on smaller
    //             iPhones automatically.
    //
    // Previous version had the columns reversed (camera on the left,
    // controls on the right). This one matches the user's request:
    // content on the left, camera + capture on the right.

    @ViewBuilder
    private var landscapeLayout: some View {
        // Per-idiom sizing for the side-by-side landscape layout.
        //
        // iPhone:
        //   • Left column 200pt, HStack spacing 12pt, outer
        //     horizontal padding 8pt — tightened across multiple
        //     QA passes to hand the camera ~554pt of width on
        //     iPhone 14 Pro landscape (≈ +27% vs the original
        //     280 / 24 / 20 baseline). Title may wrap to 2 lines
        //     on the narrowest iPhones; acceptable for the camera
        //     real estate.
        //
        // iPad:
        //   • Left column 280pt — wide enough for the iPad-bumped
        //     26pt title to stay on a single line and the 17pt
        //     description to read at ~3 lines, narrow enough that
        //     the camera column still gets the OVERWHELMING
        //     majority of the wide iPad-landscape viewport (QA:
        //     "increase width of take photo of ingredients view
        //     on my bar — observe and fix for landscape, increase
        //     its width on iPad").
        //   • HStack spacing 24pt + outer horizontal padding 24pt
        //     — generous breathing room appropriate for the iPad
        //     canvas.
        //
        // Resulting camera widths (approximate, after safe area):
        //   iPad Mini    landscape (1133pt usable w):
        //       1133 − 280 − 24 − 48 = 781pt
        //   iPad 10.9"   landscape (1180pt usable w):
        //       1180 − 280 − 24 − 48 = 828pt
        //   iPad Pro 11" landscape (1194pt usable w):
        //       1194 − 280 − 24 − 48 = 842pt
        //   iPad Pro 13" landscape (1366pt usable w):
        //       1366 − 280 − 24 − 48 = 1014pt
        //
        // Hard-coding the widths avoids the "stuck on rotation"
        // pathology that came from computing widths via a
        // `GeometryReader` proxy whose size lags one re-layout pass
        // behind the actual rotation.
        //
        // Layout shared across idioms:
        //   • Right column uses `.frame(maxWidth: .infinity)` so
        //     it soaks up whatever horizontal space remains.
        //   • Camera frame fills the full right column
        //     (maxHeight: .infinity) — no longer shares vertical
        //     space with a controls row, so the live preview is as
        //     tall as the viewport allows.
        //   • Controls (shutter / retake+submit) are rendered as a
        //     bottom-anchored `.overlay` ON TOP of the camera so
        //     the user can see the framing AND the capture button
        //     at the same time without the camera being pushed up.

        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let leftColumnWidth: CGFloat = isIPad ? 280 : 200
        let hStackSpacing: CGFloat   = isIPad ? 24  : 12
        let horizontalPadding: CGFloat = isIPad ? 24 : 8

        HStack(alignment: .center, spacing: hStackSpacing) {

            // LEFT — title + description, left-aligned, vertically
            // centered.
            titleAndSubtitleLandscape
                .frame(width: leftColumnWidth)
                .frame(maxHeight: .infinity)

            // RIGHT — camera fills the column, controls overlay on top.
            cameraOrCapturedImageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    bottomControlsContainer
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Landscape title block (left-aligned)
    //
    // Same content as `titleAndSubtitle` but left-aligned for the
    // landscape side panel — the centered version reads as awkward
    // when sitting next to a tall camera preview.
    @ViewBuilder
    private var titleAndSubtitleLandscape: some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let titleSize: CGFloat = isIPad ? 26 : 20
        let descSize: CGFloat = isIPad ? 17 : 14
        VStack(alignment: .leading, spacing: 10) {
            Text("Take a Photo of Ingredient(s)")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(Color("appBlackColor"))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !hasCapturedImage {
                Text("Snap a clear photo of the bottle or ingredient and Barbot AI will add it to your 'My Bar' visible on the next screen.")
                    .font(.system(size: descSize))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toolbar (matches MyBarView's nav bar exactly)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                DevicePrincipalIcon(assetName: deviceIconName,
                                    accessibilityLabel: deviceKindName)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationRightGlassButtons(
                onFavorites: { router.push(.favorites) },
                onProfile: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        router.showSideMenu = true
                    }
                }
            )
        }
    }

    // MARK: - Title & subtitle
    //
    // 1:1 with UIKit `lblTakeAPhotoTitle.text` (system 20pt bold,
    // appBlackColor) and `lblDescription.text` (14pt, mutedGrayColor).
    // The MyBar branch always sets:
    //   • title: "Take a Photo of Ingredient(s)"
    //   • description: "Snap a clear photo of the bottle or ingredient
    //     and Barbot AI will add it to your 'My Bar' visible on the
    //     next screen."
    // (ScanIngredientsViewController.swift L72-78). The description
    // hides once an image is captured (UIKit L189-190).

    @ViewBuilder
    private var titleAndSubtitle: some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let titleSize: CGFloat = isIPad ? 26 : 20
        let descSize: CGFloat = isIPad ? 17 : 14
        VStack(spacing: 8) {
            Text("Take a Photo of Ingredient(s)")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(Color("appBlackColor"))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if !hasCapturedImage {
                Text("Snap a clear photo of the bottle or ingredient and Barbot AI will add it to your 'My Bar' visible on the next screen.")
                    .font(.system(size: descSize))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Camera / captured image view
    //
    // Storyboard `viewCameraFrame` is a 16pt-cornered container
    // (BarsysCornerRadius.medium = 12, but storyboard uses 16; we
    // mirror the storyboard) sized to fill whatever bounds the
    // parent layout proposes. The `.resizeAspectFill` setting on the
    // underlying `AVCaptureVideoPreviewLayer` then crops the camera
    // feed to fill that rectangle, so the camera always looks "full
    // bleed" inside its container — portrait OR landscape.
    //
    // The aspect ratio (`3:4` portrait / `4:3` landscape / fixed
    // size) is now applied by `portraitLayout(in:)` /
    // `landscapeLayout(in:)`, NOT here. Putting the aspect on the
    // child made the live preview shrink to ~290pt wide on iPhone
    // landscape because the screen height (~390pt) became the
    // limiting axis for a portrait aspect — that was the user-
    // reported "camera comes very small in landscape" bug.

    @ViewBuilder
    private var cameraOrCapturedImageView: some View {
        ZStack {
            // Placeholder fill below the camera / image so the
            // viewport is never a stark black square while the
            // session is warming up. Previously this used
            // `UIColor(white: 0.08)` in dark mode — close enough to
            // pure black that a half-screen of placeholder during
            // rotation looked exactly like a hung view ("right side
            // is black"). The new tone (~0.20 / ~0.92) keeps the
            // viewfinder clearly visible as a UI surface, so even
            // when a rotation flushes the preview layer the gap
            // reads as "loading", not "broken".
            Color(UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.20, alpha: 1.0)
                    : UIColor(white: 0.92, alpha: 1.0)
            })

            if let image = camera.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityLabel("Captured photo")
            } else if camera.permissionState == .authorized {
                // The `ScanCameraPreview` representable is a thin
                // wrapper around `camera.previewView` — the actual
                // `UIView` (and its `AVCaptureVideoPreviewLayer`)
                // is owned by the controller, so it survives
                // SwiftUI rebuilding this view tree on rotation.
                // The `.id` is belt-and-braces: even with
                // controller-owned UIKit state, asking SwiftUI to
                // treat this representable as the same view across
                // structural changes lets it reuse the existing
                // bridge instead of tearing it down and recreating
                // it.
                ScanCameraPreview(controller: camera)
                    .id("scan-ingredients-preview")
                    .accessibilityLabel("Camera preview")
            }

            // Loader: only while we're authorized but the session
            // hasn't reported running yet. Hides the moment the
            // first frame can flow, and stays hidden after the user
            // captures a photo (placeholder is replaced by the
            // captured image at that point).
            if camera.permissionState == .authorized
                && camera.capturedImage == nil
                && !camera.isSessionRunning {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)
                    .tint(Color("appBlackColor"))
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
    }

    // MARK: - Bottom controls
    //
    // Two states, controlled by `hasCapturedImage`:
    //   • Capturing: large 70×70 circular shutter button (storyboard
    //     `btnCapture` inside `viewCaptureImage` 80×80 ring).
    //   • Captured: side-by-side Retake (secondary) + Submit (primary)
    //     buttons, 168.67×45 each, 8pt spacing — same pair as the
    //     storyboard's `viewRetakeSubmitContainer` and the MyBar
    //     bottom bar (which uses `MyBarPrimaryButton` /
    //     `MyBarSecondaryButton`).

    @ViewBuilder
    private var bottomControlsContainer: some View {
        if hasCapturedImage {
            HStack(spacing: 8) {
                ScanSecondaryButton(title: ConstantButtonsTitle.retakeButtonTitle) {
                    HapticService.light()
                    camera.reset()
                }
                ScanPrimaryButton(title: ConstantButtonsTitle.submitButtonTitle) {
                    HapticService.light()
                    submitCapturedImage()
                }
            }
        } else {
            HStack {
                Spacer()
                shutterButton
                Spacer()
            }
        }
    }

    /// Circular shutter button — ports `viewCaptureImage` (80×80
    /// outer ring) + `btnCapture` (inset hit target). UIKit applies
    /// `roundCorners = frame.height/2` so it's a perfect circle.
    @ViewBuilder
    private var shutterButton: some View {
        Button {
            HapticService.light()
            camera.capture()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 4)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.isCapturing || camera.permissionState != .authorized)
        .opacity(camera.permissionState == .authorized ? 1.0 : 0.5)
        .accessibilityLabel("Capture photo")
        .accessibilityHint("Takes a photo")
    }

    // MARK: - Submit / Reupload actions

    /// 1:1 with UIKit `proceedForMyBar(capturedImage:)`
    /// (ScanIngredientsViewController.swift L214-299).
    ///
    /// Error-path UX: every failure branch (jpeg encode, no
    /// connection, server response missing usable ingredients,
    /// upload throws) calls `failAndRetake(message:)` instead of
    /// just `env.alerts.show(...)`. That helper shows the alert AND
    /// resets the camera back to live preview so the user lands on
    /// the retake state automatically — they don't have to tap
    /// "Retake" by hand after every error. Per the user request:
    /// "when error comes in my bar it should automatically move to
    /// retake option when error comes".
    private func submitCapturedImage() {
        guard let image = camera.capturedImage else { return }
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            failAndRetake(message: Constants.ingredientUpdateError)
            return
        }
        env.loading.show(Constants.addingIngredientLoaderText)
        Task { @MainActor in
            // UIKit L216-222: pre-flight connectivity check.
            guard await ConnectionMonitor.shared.isConnected else {
                env.loading.hide()
                failAndRetake(
                    title: Constants.internetConnectionMessage,
                    message: ""
                )
                return
            }
            do {
                let detected = try await env.api.uploadIngredientImageForMyBar(data)
                env.loading.hide()
                let (toShow, errorMessage) = processImageScanResults(detected)
                if let errorMessage, toShow.isEmpty {
                    failAndRetake(message: errorMessage)
                    return
                }
                if toShow.isEmpty {
                    failAndRetake(message: Constants.ingredientCannotBeUsedHere)
                    return
                }
                detectedIngredients = toShow
                showIngredientsFoundPopup = true
            } catch {
                env.loading.hide()
                let message = Self.isCancellationError(error)
                    ? Constants.requestCancelledMessage
                    : Constants.ingredientUpdateError
                failAndRetake(message: message)
            }
        }
    }

    /// `true` when the thrown error represents a user-initiated cancel
    /// (Task cancellation or `URLSession` `URLError.cancelled` -999).
    /// Used by the submit catch path so a cancelled upload surfaces
    /// "Your request has been cancelled." instead of the generic
    /// `ingredientUpdateError` message.
    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Show the failure alert AND drop the captured image so the UI
    /// flips back to the live camera preview (the retake state).
    /// Used by every error branch in `submitCapturedImage` so the
    /// user can re-shoot with one tap (the alert "OK") instead of
    /// having to dismiss the alert AND tap "Retake" separately.
    ///
    /// `camera.reset()` clears `capturedImage` and restarts the
    /// session — `bottomControlsContainer` reads `hasCapturedImage`
    /// and re-renders to the shutter-button state automatically.
    private func failAndRetake(title: String? = nil, message: String) {
        camera.reset()
        if let title {
            env.alerts.show(title: title,
                            message: message,
                            primary: Constants.okButtonTitle)
        } else {
            env.alerts.show(message: message)
        }
    }

    /// 1:1 with `MyBarView.processImageScanResults` — kept private to
    /// this file so the screen can be audited end-to-end without
    /// chasing helpers across files.
    private func processImageScanResults(
        _ detected: [MyBarIngredientFromImage]
    ) -> (ingredients: [DetectedMyBarIngredient], errorMessage: String?) {
        guard !detected.isEmpty else {
            return ([], Constants.ingredientCannotBeUsedHere)
        }
        // UIKit L244-247: NOT IN ('garnish','additionals','additional').
        let baseAndMixer = detected.filter {
            let p = ($0.category?.primary ?? "").lowercased()
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        if baseAndMixer.isEmpty {
            return ([], Constants.ingredientCannotBeUsedHere)
        }
        let first = baseAndMixer[0]
        let primary = first.category?.primary ?? ""
        let secondary = first.category?.secondary ?? ""
        if primary.isEmpty || secondary.isEmpty {
            return ([], Constants.ingredientCannotBeUsedHere)
        }

        let existingNames = Set(env.storage.myBarIngredients().map { $0.name.lowercased() })
        var result: [DetectedMyBarIngredient] = []
        for item in baseAndMixer {
            let name = item.name ?? ""
            guard !name.isEmpty else { continue }
            let category = IngredientCategory(
                primary: item.category?.primary,
                secondary: item.category?.secondary,
                flavourTags: nil
            )
            let ingredient = Ingredient(
                name: name,
                unit: Constants.mlText.lowercased(),
                notes: "",
                category: category,
                quantity: 0,
                perishable: item.perishable,
                substitutes: item.substitutes,
                ingredientOptional: false
            )
            let isExisting = existingNames.contains(name.lowercased())
            result.append(DetectedMyBarIngredient(
                ingredient: ingredient,
                isExisting: isExisting,
                isSelected: !isExisting
            ))
        }
        return (result, nil)
    }

    /// 1:1 with UIKit `addingredientPopUpShow.onRightAction` at
    /// ScanIngredientsViewController.swift L306-321:
    ///
    /// ```swift
    /// self.myBarApiService.addIngredientToMyBar(...) { success, errorMessage in
    ///     DispatchQueue.main.async {
    ///         self.hideGlassLoader()
    ///         if success {
    ///             self.onIngredientScannedForMyBar?(arrayOfSelections)
    ///             self.navigationController?.popViewController(...)
    ///         } else {
    ///             topVC.showDefaultAlert(message: errorMessage ?? Constants.ingredientScanError, ...)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// PREVIOUS SwiftUI port skipped the API entirely and only
    /// mutated `env.storage.toggleMyBar` locally — same anti-pattern
    /// as the QA-flagged "ingredient comes back on refresh" delete
    /// bug fixed in `confirmDelete()`. Without the POST, the new
    /// ingredient existed only in the local cache and disappeared
    /// the next time the user pulled `loadMyBarFromServer()` (which
    /// `replaceMyBar`s wholesale).
    ///
    /// Now mirrors UIKit exactly:
    ///   1. Dismiss the popup (UIKit's
    ///      `showMultipleIngredientsPopUpForMyBar` dismisses on
    ///      right-button tap, BEFORE the API resolves)
    ///   2. Offline guard (matches `confirmDelete` and the MyBar
    ///      `proceedWithSelectedIngredients` — UIKit's
    ///      `MyBarApiService` surfaces a generic error instead, but
    ///      we keep the branded `internetConnectionMessage` for
    ///      consistency with every other API path in this file)
    ///   3. Show "Adding Ingredients" loader
    ///   4. POST `/my/bar` with the selected ingredients
    ///   5. SUCCESS → toggle each ingredient into the LocalCache
    ///      (which is `@Published`, so the MyBar screen shows the
    ///      new rows the moment we dismiss back to it — equivalent
    ///      to UIKit's `onIngredientScannedForMyBar?` callback +
    ///      `appendConfirmedIngredients`) THEN dismiss
    ///   6. FAILURE → show the same default alert UIKit shows and
    ///      STAY on the scan screen so the user can retake / reupload
    ///      from the same captured frame. Storage is NOT mutated,
    ///      so the MyBar screen behind us still shows the same data
    ///      it had before the failed add — fixes QA-reported "data
    ///      not shown on MyBar screen when add ingredient API gives
    ///      error" by guaranteeing we never optimistically write a
    ///      to-be-failed ingredient into LocalCache.
    private func proceedWithSelectedIngredients() {
        let selections = detectedIngredients.filter { $0.isSelected && !$0.isExisting }
        guard !selections.isEmpty else { return }
        HapticService.success()
        showIngredientsFoundPopup = false

        let payload: [MyBarAddIngredient] = selections.map { detected in
            MyBarAddIngredient(
                name: detected.ingredient.name,
                category: detected.ingredient.category,
                // UIKit `MyBarApiService.addIngredientToMyBar`
                // L111 falls back to `?? 0.0` when confidence is
                // missing — we don't surface confidence through
                // `DetectedMyBarIngredient`, so default to the
                // same 0.0. Backend tolerates this.
                confidence: 0.0,
                perishable: detected.ingredient.perishable ?? false,
                substitutes: detected.ingredient.substitutes ?? []
            )
        }

        Task { @MainActor in
            guard await ConnectionMonitor.shared.isConnected else {
                env.alerts.show(message: Constants.internetConnectionMessage)
                return
            }
            env.loading.show(Constants.savingIngredientsMessage)
            do {
                try await env.api.addMyBarIngredients(payload)
                env.loading.hide()
                // UIKit L313-315 success branch: append to local
                // arrays via the parent callback, then pop. SwiftUI
                // mirror: write directly to the shared `@Published`
                // LocalCache so MyBar shows the new rows on dismiss.
                for detected in selections {
                    env.storage.toggleMyBar(detected.ingredient)
                }
                detectedIngredients = []
                dismiss()
            } catch {
                env.loading.hide()
                // UIKit L316-318 failure branch: alert only, no pop,
                // no local mutation.
                //
                // SwiftUI extension (matches the same UX pattern
                // `submitCapturedImage` already uses for every
                // upload-side failure): route through
                // `failAndRetake(message:)` so the camera is reset
                // back to the live-preview (retake) state in the
                // same body pass that surfaces the alert. Per the
                // user request: "when error comes on submit, camera
                // and labels should be resettled to take photo
                // mode". `camera.reset()` clears `capturedImage`,
                // which flips `hasCapturedImage` to false — that in
                // turn:
                //   • swaps the bottom controls from
                //     Retake/Submit back to the shutter button
                //     (`bottomControlsContainer`)
                //   • re-shows the description label in
                //     `titleAndSubtitleLandscape` (gated by
                //     `if !hasCapturedImage`)
                //   • brings back the live preview behind the
                //     shutter (`cameraOrCapturedImageView` reads
                //     `camera.capturedImage`)
                // — all in a single re-render, so the user lands on
                // a fresh take-photo state the moment they dismiss
                // the alert.
                let message = error.localizedDescription.isEmpty
                    ? Constants.ingredientScanError
                    : error.localizedDescription
                failAndRetake(message: message)
            }
        }
    }

    private func closeIngredientsFoundPopup() {
        showIngredientsFoundPopup = false
        detectedIngredients = []
    }

    // MARK: - Ingredient(s) found popup
    //
    // Mirrors `MyBarView.ingredientsFoundPopup` exactly (same
    // dimensions, same iPad bumps, same close X). The only difference
    // is the Reupload action: here it triggers `camera.reset()` to
    // restart the live preview, mirroring UIKit
    // `addingredientPopUpShow.onCompleteAlertPopup` →
    // `restartCameraProcess()` (ScanIngredientsViewController.swift
    // L304).

    @ViewBuilder
    private var ingredientsFoundPopup: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            ingredientsFoundCard
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var ingredientsFoundCard: some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        // iPhone in landscape (verticalSizeClass == .compact) has a
        // very short viewport (~390pt). The popup chrome alone
        // (close X + title + subtitle + buttons) is ~200pt, so the
        // standard 250pt list height pushes the card off-screen.
        // Cap the list at 140pt in landscape so the popup always
        // fits inside the safe area without scrolling the whole
        // card.
        let isCompactHeight = verticalSizeClass == .compact && !isIPad
        let titleSize: CGFloat = isIPad ? 24 : 18
        let subtitleSize: CGFloat = isIPad ? 18 : 14
        let errorSize: CGFloat = isIPad ? 16 : 12
        let listMaxHeight: CGFloat = isIPad ? 360 : (isCompactHeight ? 140 : 250)

        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    HapticService.light()
                    closeIngredientsFoundPopup()
                } label: {
                    Image("crossIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isIPad ? 18 : 14, height: isIPad ? 18 : 14)
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(width: isIPad ? 50 : 44, height: isIPad ? 50 : 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text("Ingredient(s) found")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(Color("appBlackColor"))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Select ingredients to proceed")
                .font(.system(size: subtitleSize))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach($detectedIngredients) { $detected in
                        detectedIngredientRow($detected)
                    }
                }
            }
            .frame(maxHeight: listMaxHeight)

            if selectedCount == 0 && hasNewIngredients {
                Text(Constants.pleaseAddAtleastOneIngredient)
                    .font(.system(size: errorSize))
                    .foregroundStyle(Color("errorLabelColor"))
                    .padding(.top, 8)
            }

            HStack(spacing: 8) {
                ScanSecondaryButton(title: ConstantButtonsTitle.reUploadButtonTitle) {
                    closeIngredientsFoundPopup()
                    // UIKit L304 — reupload restarts the live camera.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        camera.reset()
                    }
                }
                ScanPrimaryButton(title: ConstantButtonsTitle.proceedButtonTitle) {
                    proceedWithSelectedIngredients()
                }
                .opacity(selectedCount > 0 ? 1.0 : 0.5)
                .disabled(selectedCount == 0)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 6)
        .background(
            ZStack {
                if #available(iOS 26.0, *) {
                    BarsysGlassPanelBackground(whiteTintAlpha: 0.20)
                        .clipShape(RoundedRectangle(cornerRadius: 12,
                                                    style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 0.95)
                                : UIColor.white.withAlphaComponent(0.95)
                        }))
                }
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private func detectedIngredientRow(_ detected: Binding<DetectedMyBarIngredient>) -> some View {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let checkboxCircle: CGFloat = isIPad ? 28 : 22
        let checkboxFrame: CGFloat = isIPad ? 38 : 30
        let checkmarkSize: CGFloat = isIPad ? 14 : 11
        let nameSize: CGFloat = isIPad ? 18 : 14
        let sublabelSize: CGFloat = isIPad ? 14 : 11
        let d = detected.wrappedValue
        return HStack(spacing: 12) {
            Button {
                guard !d.isExisting else { return }
                HapticService.light()
                detected.wrappedValue.isSelected.toggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(
                            d.isExisting
                                ? Color.gray.opacity(0.5)
                                : Color("craftButtonBorderColor"),
                            lineWidth: 1
                        )
                        .frame(width: checkboxCircle, height: checkboxCircle)
                    if d.isSelected && !d.isExisting {
                        Circle()
                            .fill(Color("segmentSelectionColor"))
                            .frame(width: checkboxCircle, height: checkboxCircle)
                        Image(systemName: "checkmark")
                            .font(.system(size: checkmarkSize, weight: .bold))
                            .foregroundStyle(Theme.Color.softWhiteText)
                    }
                }
                .frame(width: checkboxFrame, height: checkboxFrame)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.isSelected ? "Selected" : "Not selected")

            VStack(alignment: .leading, spacing: 2) {
                Text(d.ingredient.name)
                    .font(.system(size: nameSize))
                    .foregroundStyle(
                        d.isExisting
                            ? Color.gray
                            : Color("veryDarkGrayColor")
                    )
                if d.isExisting {
                    Text(Constants.alreadyAddedInMyBarText)
                        .font(.system(size: sublabelSize))
                        .foregroundStyle(Color.gray)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !d.isExisting else { return }
            HapticService.light()
            detected.wrappedValue.isSelected.toggle()
        }
    }
}

// MARK: - Local primary / secondary button styles
//
// Drop-in clones of `MyBarPrimaryButton` / `MyBarSecondaryButton` from
// MyBarScreens.swift so this file is self-contained — those types are
// `private` to MyBarScreens. Keeping them duplicated here avoids
// promoting MyBar internals to file-private just to share two button
// shells, and tests at the navigation boundary stay simple.

private struct ScanPrimaryButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(primaryFill)
                .clipShape(primaryShape)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var primaryFill: some View {
        if #available(iOS 26.0, *) {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.980, green: 0.878, blue: 0.800),
                        Color(red: 0.949, green: 0.761, blue: 0.631)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [Color("brandGradientTop"), Color("brandGradientBottom")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            Color("brandTanColor")
        }
    }

    private var primaryShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ScanSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(secondaryFill)
                .overlay(secondaryBorder)
                .clipShape(secondaryShape)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var secondaryFill: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(SwiftUI.Color.white.opacity(0.85))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SwiftUI.Color.white)
        }
    }

    @ViewBuilder
    private var secondaryBorder: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            SwiftUI.Color.white.opacity(0.95),
                            SwiftUI.Color(white: 0.85).opacity(0.9),
                            SwiftUI.Color.white.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
        }
    }

    private var secondaryShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
