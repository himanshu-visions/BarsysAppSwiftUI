//
//  Bridging.swift
//  BarsysAppSwiftUI
//
//  UIViewRepresentable / UIViewControllerRepresentable bridges for UIKit-only
//  capabilities that SwiftUI either doesn't support or implements differently.
//

import SwiftUI
import WebKit
import AVFoundation
import Network

// MARK: - ConnectionMonitor
//
// 1:1 port of UIKit `ConnectionMonitor.shared.isConnected` — a simple
// actor that samples `NWPathMonitor` once and returns whether the
// device currently has a usable network path (Wi-Fi / cellular /
// wired). UIKit uses this in every pre-flight network call (WebView,
// setup-stations, craft flow, etc.) and pops a
// "Please check your internet connection." alert on false.
//
// The monitor is a long-lived global — started once per process —
// so repeated checks are O(1). The stored `status` is updated on
// every path change; readers just read it.
final class ConnectionMonitor: @unchecked Sendable {
    static let shared = ConnectionMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.barsys.connectionMonitor",
                                      qos: .utility)
    private var currentStatus: NWPath.Status = .satisfied

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentStatus = path.status
        }
        monitor.start(queue: queue)
    }

    /// Mirrors UIKit `async var isConnected` — returns the last-known
    /// path status. Not strictly async in SwiftUI (the value is
    /// already resident in memory) but kept async for signature
    /// parity with UIKit callers that `await` this property.
    var isConnected: Bool {
        get async {
            // Allow `NWPathMonitor` a brief window to publish its
            // first `pathUpdateHandler` callback if the monitor was
            // just created. 50ms is well under the 1s UIKit timeout
            // the shipped app uses.
            try? await Task.sleep(nanoseconds: 50_000_000)
            return currentStatus == .satisfied
        }
    }
}

// MARK: - WebView
//
// 1:1 port of UIKit `WebViewController.swift`:
//   • Pre-flight connection check via `ConnectionMonitor.shared.isConnected`
//     — if offline, caller (`BarsysWebView`) surfaces the
//     "Please check your internet connection." alert and pops back.
//   • `WKNavigationDelegate` with URL-allowlist enforcement
//     (barsys.com, apps.apple.com, bfrands.com, bfrands.freshdesk.com).
//   • Fails-closed on any load error — reports it to the wrapper via
//     `onLoadFailed(_:)` so the host view can show an alert.
//
// This type is a LOW-level representable — the app-wide `BarsysWebView`
// (below) is the SwiftUI entry point that layers in the custom header,
// tab-bar hiding, and alert wiring.

struct WebView: UIViewRepresentable {
    let url: URL
    /// URL that was originally loaded. The allowlist lets this exact
    /// URL through even if its host isn't on the whitelist — matches
    /// UIKit L110-113 "Always allow the initial URL".
    let initialURLString: String
    /// Called on the main actor when a load fails (no internet, 404,
    /// SSL, etc.). Host view can pop the screen or show an alert.
    var onLoadFailed: ((Error) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // UIKit `audiovisualMediaTypes = .none` — prevent autoplay
        // when opening a privacy / FAQ page that embeds video.
        config.mediaTypesRequiringUserActionForPlayback = .all
        let v = WKWebView(frame: .zero, configuration: config)
        v.backgroundColor = UIColor(named: "secondaryBackgroundColor") ?? .white
        v.isOpaque = false
        v.navigationDelegate = context.coordinator
        v.load(URLRequest(url: url))
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        init(parent: WebView) {
            self.parent = parent
        }

        // 1:1 port of UIKit `decidePolicyFor navigationAction`
        // (WebViewController.swift L99-126). Lets the initial URL
        // through unconditionally, otherwise restricts to allowlisted
        // hosts (case-insensitive, suffix-match for subdomains).
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let requestURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Always allow the originally-loaded URL.
            if requestURL.absoluteString == parent.initialURLString {
                decisionHandler(.allow)
                return
            }
            // Restrict all subsequent navigation to the allowlist.
            guard let host = requestURL.host?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            let allowed = WebViewURLs.allowedHosts.contains { allowedHost in
                host == allowedHost || host.hasSuffix(".\(allowedHost)")
            }
            decisionHandler(allowed ? .allow : .cancel)
        }

        // Fail-closed: any provisional navigation error (no internet,
        // TLS failure, DNS, timeout) surfaces to the host view so it
        // can show the UIKit-style alert.
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            DispatchQueue.main.async { [parent] in
                parent.onLoadFailed?(error)
            }
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            DispatchQueue.main.async { [parent] in
                parent.onLoadFailed?(error)
            }
        }
    }
}

// MARK: - BarsysWebView (SwiftUI wrapper with UIKit-parity chrome)
//
// 1:1 port of the UIKit `WebViewController` scene in SideMenu.storyboard
// (scene ID KDb-w9-Wzm). Re-analysed against the raw storyboard XML
// — the exact numbers below are verbatim from the shipping build:
//
// **View hierarchy (SideMenu.storyboard scene `6bh-0a-0Zx`):**
//   • `view` background = `white="0.0"` — PURE BLACK (#000000)
//   • `button m9e-HR-tsb` back button:
//       – frame x=5, y=safeArea.top, width=50, height=50
//       – `tintColor white="1"` (white)
//       – `state.normal image="backWhite"`
//       – `state.normal titleColor white="1"`
//       – `imageEdgeInsets` all ≈0 (image centered, native size)
//   • `label JZC-6V-eNu` title:
//       – frame x=55, y=≈133, width=318, height=≈19
//       – `fontDescription type="boldSystem" pointSize="16"`
//       – `textColor white="1"` (white)
//       – `textAlignment natural` (left, LTR)
//       – `lineBreakMode tailTruncation`
//       – **leading = backButton.trailing (NO gap — x=55 flush)**
//       – **centerY = backButton.centerY**
//       – trailing = safeArea.trailing − 20
//   • `wkWebView Zyd-by-Vmo`:
//       – frame y=168, full width
//       – `backgroundColor name="secondaryBackgroundColor"`
//       – `top = backButton.bottom` (no gap)
//       – leading/trailing/bottom = safeArea (full)
//       – `mediaTypesRequiringUserActionForPlayback none="YES"`
//
// Visual outcome: black background showing through the status-bar
// area (safeArea.top → y=0), a 50pt area containing the back button
// + title, then the WebView below. No separator line — the flip from
// black to secondaryBackgroundColor is abrupt at y=168.
//
// Additional UIKit parity (from WebViewController.swift):
//   • L37-38: `navigationController?.isNavigationBarHidden = true`
//   • L52-53: `doYouWantToShowTheUIofBottomBar(isHiddenCustomTabBar: true)`
//             + `tabBarController?.tabBar.isHidden = true`
//   • L62-74: `ConnectionMonitor.shared.isConnected` pre-flight →
//             `showCustomAlert(title: internetConnectionMessage)` → pop
//   • L89-92: `HapticService.shared.light()` on back-tap
struct BarsysWebView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom top bar ───────────────────────────────────
            // Back button (50×50 leading:5) + title (leading = button
            // trailing, centerY aligned). No spacer between them —
            // storyboard constraint `RWh-sY-A0M`:
            //   titleLabel.leading == backButton.trailing
            HStack(alignment: .center, spacing: 0) {
                Button {
                    HapticService.light()   // UIKit L90
                    dismiss()
                } label: {
                    // UIKit: `image="backWhite"` with `tintColor="white"`.
                    // The asset is a template arrow rendered white via
                    // tintColor; `.renderingMode(.template)` +
                    // `.foregroundStyle(.white)` reproduces that.
                    // Intrinsic size ≈22pt (matches UIKit's
                    // `preferredSymbolConfiguration pointSize=22`),
                    // centered in the 50×50 hit area.
                    Image("backWhite")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text(title)
                    // UIKit: `boldSystem pointSize=16` → `.system(16, .bold)`.
                    .font(.system(size: 16, weight: .bold))
                    // UIKit: `textColor white="1"` → white.
                    .foregroundStyle(.white)
                    // UIKit: `lineBreakMode tailTruncation`, single line.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // UIKit `textAlignment natural` = left for LTR.
                    .multilineTextAlignment(.leading)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 20) // safeArea.trailing − 20 (yKn-08-Obt)
            }
            // Leading padding matches UIKit `backButton.leading = 5`.
            .padding(.leading, 5)
            .padding(.trailing, 20) // yKn-08-Obt: title.trailing = safeArea.trailing − 20
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            // UIKit view background is pure black (`white="0.0"`).
            // The header inherits that; no separate header bg colour.
            .background(Color.black)

            // ── Web content ─────────────────────────────────────────
            WebView(
                url: url,
                initialURLString: url.absoluteString,
                onLoadFailed: { _ in
                    // UIKit shows ONE alert per offline screen open;
                    // guard against duplicate alerts from multiple
                    // simultaneous failure callbacks (provisional +
                    // committed navigation errors both fire).
                    guard !showAlert else { return }
                    showAlert = true
                    env.alerts.show(
                        title: Constants.internetConnectionMessage,
                        message: "",
                        primary: Constants.okButtonTitle,
                        action: { dismiss() }
                    )
                }
            )
            // UIKit: `backgroundColor name="secondaryBackgroundColor"`.
            .background(Color("secondaryBackgroundColor"))
        }
        // UIKit root view background is pure black — bleed it through
        // the status-bar safe area so the black header appears
        // continuous from the top of the screen, not just the 50pt
        // button row.
        .background(Color.black.ignoresSafeArea(edges: .top))
        // L37-38: `isNavigationBarHidden = true`. In SwiftUI:
        // `.toolbar(.hidden)` on the navigation bar — without this, a
        // second system title bar stacks on top of our custom header.
        .toolbar(.hidden, for: .navigationBar)
        // L52-53: `tabBarController?.tabBar.isHidden = true`. SwiftUI
        // equivalent — without this the tab bar draws over the bottom
        // of the WebView, leaving a visible blank strip.
        .toolbar(.hidden, for: .tabBar)
        // L62-74: pre-flight `ConnectionMonitor.shared.isConnected`.
        // If offline, surface the alert and pop back. Runs in `.task`
        // so the WebView has been constructed (keeping SwiftUI's
        // lifecycle sane) but hasn't done real work yet.
        .task {
            guard await !ConnectionMonitor.shared.isConnected else { return }
            guard !showAlert else { return }
            showAlert = true
            env.alerts.show(
                title: Constants.internetConnectionMessage,
                message: "",
                primary: Constants.okButtonTitle,
                action: { dismiss() }
            )
        }
    }
}

// MARK: - QR Scanner
//
// 1:1 behavioural parity with UIKit `QrViewController.setupQRScanner()`
// (QrViewController.swift L95-108) + `QRScannerView` (from the
// QRScanner pod). The UIKit version:
//   • requests camera permission via `checkAuthorizationAndShowCamera()`
//     (L73-93) and routes a denied state to `showDisabledCameraAlert()`
//   • instantiates a `QRScannerView` sized to its host container (345×468)
//   • configures it with `isBlurEffectEnabled: true` + `focusImage:
//     .borderimageScanner` (the corner-frame art inside Assets.xcassets
//     /Qr Controller/borderimageScanner.imageset — already in this project)
//   • starts running once the view is attached.
//
// The SwiftUI wrapper renders the same border-image overlay on top of
// the live preview layer since the UIKit QRScanner pod is not ported
// here.

enum QRCameraAuthStatus {
    case unknown, authorized, denied, requesting
}

struct QRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onCancel: () -> Void
    var onPermissionDenied: () -> Void = {}

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onScan = onScan
        vc.onCancel = onCancel
        vc.onPermissionDenied = onPermissionDenied
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didCallOnScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // UIKit storyboard `qrViewToShow`: transparent container with a
        // 12pt corner radius. We match so the preview is clipped to the
        // SwiftUI parent's rounded frame.
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.layer.cornerRadius = 12
        checkAuthorizationAndShowCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didCallOnScan = false
        if previewLayer != nil && !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Permission flow (1:1 UIKit QrViewController L73-93)

    private func checkAuthorizationAndShowCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureCamera()
                    } else {
                        self.onPermissionDenied?()
                    }
                }
            }
        case .denied, .restricted:
            onPermissionDenied?()
        @unknown default:
            onPermissionDenied?()
        }
    }

    private func configureCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didCallOnScan else { return }
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue, !str.isEmpty else { return }
        didCallOnScan = true
        session.stopRunning()
        onScan?(str)
    }
}
