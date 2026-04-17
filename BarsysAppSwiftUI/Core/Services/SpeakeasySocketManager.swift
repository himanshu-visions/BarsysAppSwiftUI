//
//  SpeakeasySocketManager.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit `Helpers/SocketManager/SocketManager.swift` +
//  `Helpers/SocketManager/SocketDelegates.swift`.
//
//  Opens a WebSocket to `wss://bouncer.barsys.com/api/v1/ws/user/{deviceId}`
//  after a Barsys Speakeasy QR code is scanned, parses the plain-text
//  command protocol the device speaks, and publishes lifecycle events
//  to the UI via Combine so the `QRReaderView` → `ReadyToPourView`
//  transition mirrors the UIKit flow.
//
//  UIKit reference points (barsys-newapp-ios-visions):
//    • SocketManager.swift L85-92  connect(to:) — URLRequest, 10s timeout,
//      `BarsysMobile/1.0` User-Agent header.
//    • SocketManager.swift L94-95  disconnect().
//    • SocketManager.swift L121-122 sendCommand(_:) — raw string write.
//    • SocketManager.swift L17-84  didReceive(event:) — command parser.
//    • SocketManager.swift L18-25  WAITING_AREA_JOINED → isSpeakEasyCase=true.
//    • SocketManager.swift L27-31  CONTROL_GRANTED: → craft start.
//    • SocketManager.swift L36-40  "user disconnected" → auto-reconnect.
//    • SocketManager.swift L42-45  4004 close code handling.
//    • SocketManager.swift L46-64  CONTROL_DECLINED → machine offline.
//    • SocketManager.swift L78-80  PING → sendPong.
//    • SocketManager.swift L113-120 sendPong implementation.
//    • SocketDelegates.swift L19-104 connection UI routing.
//    • SocketDelegates.swift L107-132 getSocketResponse dedupe.
//

import Foundation
import Combine

// MARK: - Public events

/// Mirrors the UIKit SocketDelegates protocol methods as a single event
/// enum so a SwiftUI view can subscribe with one Combine pipeline.
enum SpeakeasySocketEvent: Equatable {
    /// UIKit `socketConnectedOrDisconnected(true, ...)` — fires when the
    /// server responds with `WAITING_AREA_JOINED`.
    case connected(deviceName: String)
    /// UIKit `socketConnectedOrDisconnected(false, ...)`.
    case disconnected(reason: String?)
    /// UIKit `getSocketResponse(result:)` for `CONTROL_GRANTED:` events.
    case controlGranted(payload: String)
    /// UIKit `CONTROL_DECLINED` — machine offline/busy.
    case controlDeclined
    /// UIKit `ERROR:MACHINE_OFFLINE`.
    case machineOffline
    /// UIKit `craftingCommandsReceivedForSpeakEasy(_:)` — pass-through for
    /// all device sensor / dispense events during a craft. Deduplicated
    /// via `previousCommand` (SocketDelegates.swift L125-128).
    case craftingResponse(String)
    /// Raw inbound string we didn't match — kept for forward compat.
    case raw(String)
    /// Connect failure — timeout, bad URL, network error.
    case connectFailed(String)
    /// Auto-reconnect is underway (user wasn't in waiting area / kicked).
    case reconnecting(deviceName: String)
}

// MARK: - Manager

/// Drop-in replacement for the no-op `SocketService` previously in
/// `Services.swift`. Uses `URLSessionWebSocketTask` (no third-party
/// dependency) to match UIKit's Starscream behaviour as closely as
/// possible without pulling a SwiftPM dependency into the port.
final class SpeakeasySocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {

    // MARK: Published state

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectedDeviceName: String = ""
    @Published private(set) var lastEvent: SpeakeasySocketEvent?

    /// UIKit `SocketManager.previousCommand` (SocketManager.swift L11) —
    /// stores the last command response received so `SocketDelegates
    /// L125-128` can de-duplicate repeated frames that the device
    /// sometimes emits back-to-back.
    private(set) var previousCommand: String?

    /// Combine publisher that fires on every inbound event.
    let events = PassthroughSubject<SpeakeasySocketEvent, Never>()

    // MARK: Config — mirrors UIKit `GlobalConstants.socketBaseUrl`

    /// UIKit: `"wss://bouncer.barsys.com/api/v1/ws/user/"` (ApiConstants.swift L78).
    static let socketBaseUrl = "wss://bouncer.barsys.com/api/v1/ws/user/"

    /// UIKit: `request.timeoutInterval = 10` (SocketManager.swift L88).
    static let connectTimeout: TimeInterval = 10

    /// UIKit: `User-Agent: "BarsysMobile/1.0"` (SocketManager.swift L89).
    static let userAgent = "BarsysMobile/1.0"

    // MARK: Internals

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var timeoutTimer: Timer?
    private var isExplicitDisconnect = false

    // MARK: Lifecycle

    override init() {
        super.init()
    }

    // MARK: API

    /// UIKit: `func connect(to deviceID: String)` (SocketManager.swift L85).
    /// Builds `socketBaseUrl + deviceID`, registers a delegate on
    /// `URLSessionWebSocketTask`, and begins listening for events.
    ///
    /// Safe to call repeatedly — the current task is cancelled before the
    /// new one is opened, mirroring `appDelegate?.socketManager = SocketManager()`
    /// in UIKit QrViewController L65.
    func connect(to deviceID: String) {
        // Clean slate — UIKit creates a fresh SocketManager instance per
        // scan. Here we reuse the object but tear down any open task.
        isExplicitDisconnect = false
        previousCommand = nil
        disconnectInternal(reason: "reconnect", notify: false)

        guard let url = URL(string: Self.socketBaseUrl + deviceID) else {
            emit(.connectFailed("Invalid socket URL for device '\(deviceID)'"))
            return
        }

        connectedDeviceName = deviceID

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.connectTimeout
        request.addValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        self.session = s

        let t = s.webSocketTask(with: request)
        self.task = t
        t.resume()
        receiveLoop()
        startTimeoutTimer()
    }

    /// UIKit: `func disconnect()` (SocketManager.swift L94-95).
    func disconnect() {
        isExplicitDisconnect = true
        disconnectInternal(reason: "user_disconnect", notify: true)
    }

    /// UIKit: `func sendCommand(_ cmd: String)` (SocketManager.swift L121-122).
    /// Used for every mobile→server command:
    ///   • `"CONTROL_REQUEST:"`   — ReadyToPourListViewController+Actions.swift L87,111
    ///   • `"CONTROL_RELEASED:"`  — DrinkCompleteViewController.swift L103,
    ///                              SocketDelegates.swift L152,176,241
    ///   • `"200,s1,q1,...,s6,q6"` craft — CraftingViewController.swift L228
    ///   • `"202"` cancel        — CraftingViewController.swift L351
    ///   • `"PONG_FROM_MOBILE"`   — auto-sent from `handleInbound` on PING
    func sendCommand(_ command: String) {
        guard let task else { return }
        task.send(.string(command)) { [weak self] error in
            if let error {
                print("[SpeakeasySocket] send error: \(error.localizedDescription)")
                self?.emit(.raw("SEND_ERROR"))
            }
        }
    }

    // MARK: Internal

    private func disconnectInternal(reason: String, notify: Bool) {
        stopTimeoutTimer()
        if let task {
            task.cancel(with: .normalClosure, reason: reason.data(using: .utf8))
        }
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if isConnected {
            isConnected = false
            // 1:1 with UIKit `AppStateManager.shared.setSpeakEasyCaseState(false)`
            // fired from `websocketDidDisconnect` (SocketManager.swift L104).
            Task { @MainActor in
                AppStateManager.shared.setSpeakEasyCaseState(false)
            }
            if notify {
                emit(.disconnected(reason: reason))
            }
        }
    }

    private func startTimeoutTimer() {
        stopTimeoutTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.connectTimeout, repeats: false) { [weak self] _ in
            guard let self, !self.isConnected else { return }
            self.emit(.connectFailed("Connection timed out after \(Int(Self.connectTimeout))s"))
            self.disconnectInternal(reason: "timeout", notify: true)
        }
    }

    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // URLSessionWebSocketTask reports *any* server-initiated
                // close (including 4004) as a `failure` here. Mirror UIKit
                // SocketManager.swift L42-45 and route it through the
                // auto-reconnect path rather than surfacing as an error.
                let desc = error.localizedDescription
                print("[SpeakeasySocket] receive failed: \(desc)")
                let nsError = error as NSError
                let errorString = "\(nsError.userInfo)\(nsError.localizedDescription)".lowercased()
                if !self.isExplicitDisconnect &&
                   (errorString.contains("4004") ||
                    errorString.contains("user disconnected")) {
                    self.attemptAutoReconnect(reason: "kicked")
                    return
                }
                self.emit(.connectFailed(desc))
                self.disconnectInternal(reason: "receive_error", notify: true)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleInbound(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleInbound(text)
                    }
                @unknown default: break
                }
                // Continue listening until the task is invalidated.
                self.receiveLoop()
            }
        }
    }

    /// UIKit `didReceive(event:)` (SocketManager.swift L17-84) parser.
    /// Uses the same substring-contains checks as UIKit so malformed /
    /// prefixed payloads are handled identically.
    private func handleInbound(_ text: String) {
        let upper = text.uppercased()
        let lower = text.lowercased()

        // UIKit L18-25: WAITING_AREA_JOINED → isSpeakEasyCase=true, connected.
        if upper.contains(SocketCommands.waitingAreaJoinedReadCommand) {
            stopTimeoutTimer()
            if !isConnected {
                isConnected = true
                // UIKit `AppStateManager.shared.setSpeakEasyCaseState(true)`
                // (SocketManager.swift L20).
                Task { @MainActor in
                    AppStateManager.shared.setSpeakEasyCaseState(true)
                }
                emit(.connected(deviceName: connectedDeviceName))
            }
            return
        }

        // UIKit L27-31: CONTROL_GRANTED: → craftStartForReadyToPourScreen.
        // Also sets isSpeakEasyCase=true again as a safety net (UIKit L29).
        if upper.contains(SocketCommands.controlGrantedCommand) {
            Task { @MainActor in
                AppStateManager.shared.setSpeakEasyCaseState(true)
            }
            emit(.controlGranted(payload: text))
            return
        }

        // UIKit L46-64: CONTROL_DECLINED — shows "machine is currently
        // offline" alert. If the payload contains "user not in waiting
        // area", UIKit silently reconnects (SocketManager.swift L47-50).
        if upper.contains(SocketCommands.controlDeclinedReadCommand) {
            if lower.contains("user not in waiting area") {
                attemptAutoReconnect(reason: "not_in_waiting_area")
                return
            }
            emit(.controlDeclined)
            return
        }

        // UIKit L66-68: ERROR:MACHINE_OFFLINE — early return, ignored.
        if upper.contains(SocketCommands.errorMachineOfflineReadCommand) {
            emit(.machineOffline)
            return
        }

        // UIKit L69-77: MACHINE_STATUS:AVAILABLE, PEERCLOSED, CANCELLED —
        // all early returns (silently ignored).
        if upper.contains(SocketCommands.machineStatusAvailableReadCommand) { return }
        if upper.contains(SocketCommands.peerClosedReadCommand) { return }
        if upper.contains(SocketCommands.cancelledReadCommand) { return }

        // UIKit L34-40: "user disconnected" → reconnect with same device.
        if lower.contains("user disconnected") {
            attemptAutoReconnect(reason: "user_disconnected")
            return
        }

        // UIKit L78-80: PING → sendPong(). Starscream handles this via
        // `sendPong()` which sends a masked PONG frame; our
        // URLSessionWebSocketTask equivalent is sendPing() with no
        // response handler, but the backend only expects the text
        // "PONG_FROM_MOBILE" per UIKit's pattern.
        if text == SocketCommands.pingCommand || upper.contains(SocketCommands.pingCommand) {
            sendPong()
            return
        }

        // UIKit L122-132 (SocketDelegates.swift): craftingCommandsReceivedForSpeakEasy
        // deduplicates against `previousCommand`. Apply the same filter
        // here so downstream subscribers see each distinct frame exactly
        // once.
        if let previousCommand, previousCommand == text {
            return
        }
        previousCommand = text
        emit(.craftingResponse(text))
    }

    /// UIKit L34-40 / L47-50: reconnect with the same device name.
    /// Used when the server signals a non-fatal drop the user shouldn't
    /// have to re-scan through.
    private func attemptAutoReconnect(reason: String) {
        guard !isExplicitDisconnect, !connectedDeviceName.isEmpty else { return }
        let deviceName = connectedDeviceName
        isConnected = false
        Task { @MainActor in
            AppStateManager.shared.setSpeakEasyCaseState(false)
        }
        emit(.reconnecting(deviceName: deviceName))
        // Small gap so the old task tears down cleanly — matches UIKit's
        // implicit ordering where `disconnect()` invalidates the socket
        // before `connect(to:)` re-opens it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isExplicitDisconnect else { return }
            self.connect(to: deviceName)
        }
    }

    /// UIKit `sendPong()` (SocketManager.swift L113-120). URLSession's
    /// WebSocket task doesn't expose a raw pong frame API — emulate by
    /// sending the text token the backend treats as a heartbeat ack.
    private func sendPong() {
        sendCommand("PONG_FROM_MOBILE")
    }

    private func emit(_ event: SpeakeasySocketEvent) {
        lastEvent = event
        events.send(event)
    }

    // MARK: URLSessionWebSocketDelegate
    //
    // URLSession calls these on the `delegateQueue` (main) we configured
    // in `connect(to:)`. These callbacks complement the `receiveLoop`
    // parser: the delegate tells us *whether* the socket opened or
    // closed, while the loop tells us *what data* arrived.

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        // Do NOT flip `isConnected = true` here. UIKit waits for the
        // server's `WAITING_AREA_JOINED` message before treating the
        // socket as "connected for the user's purpose" — the raw TCP
        // handshake completing is not enough.
        stopTimeoutTimer()
        // Restart the timeout so if WAITING_AREA_JOINED never arrives we
        // surface an error instead of spinning indefinitely.
        startTimeoutTimer()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        // UIKit SocketManager.swift L42-45 — 4004 close code is the
        // backend's "user kicked from waiting area" signal. Auto-reconnect
        // with the same device name rather than surfacing an error.
        let code = closeCode.rawValue
        if !isExplicitDisconnect && code == 4004 {
            attemptAutoReconnect(reason: "close_4004")
            return
        }
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        disconnectInternal(reason: reasonString ?? "close_\(code)", notify: true)
    }
}
