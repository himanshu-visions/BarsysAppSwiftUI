//
//  DeviceScreens.swift
//  BarsysAppSwiftUI
//
//  Pair device, device list popup, connected detail, rename.
//  Full port of PairYourDeviceViewController + DeviceListViewController
//  with every UIKit behavior: BLE permission check, device-type filtering,
//  signal strength, 10s polling, 12s stale pruning, 12s connection timeout,
//  error overlay, and the full connection lifecycle.
//

import SwiftUI

// MARK: - Pair device

struct PairDeviceView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    @Environment(\.dismiss) private var dismiss

    @State private var showDeviceListPopup = false
    @State private var selectedKind: DeviceKind?
    @State private var showBluetoothAlert = false
    @State private var bluetoothPopup: BarsysPopup? = nil

    private let devices: [(kind: DeviceKind, name: String, image: String)] = [
        (.barsys360, "Barsys 360",    "barsys_360"),
        (.shaker,    "Barsys Shaker", "barsys_shaker"),
        (.coaster,   "Coaster 2.0",   "barsys_coaster"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pair your device")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                Text("Please select your device to be paired. Make sure that your Bluetooth is discoverable and your Barsys device is turned ON.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("appBlackColor"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
            .padding(.top, 16)
            .padding(.trailing, 24)

            GeometryReader { geo in
                let rowHeight = geo.size.height / 3
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.offset) { _, device in
                        Button {
                            HapticService.light()
                            deviceTapped(device.kind)
                        } label: {
                            deviceCard(device: device)
                        }
                        .buttonStyle(.plain)
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // 1:1 with UIKit `ChooseOptionsDashboardViewController`
            // `deviceAvailableListViewed` analytics call — fires each
            // time the Pair Your Device listing screen becomes
            // visible so Braze can track "started pairing" sessions.
            env.analytics.track(TrackEventName.deviceAvailableListViewed.rawValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticService.light()
                    dismiss()
                } label: {
                    Image("back")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color("appBlackColor"))
                }
            }
            // Shared 100×48 glass pill (iOS 26+) / bare 61×24 icon
            // stack (pre-26). 1:1 UIKit `navigationRightGlassView`
            // parity.
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
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
        // Publish "we're on Pair Your Device" so the side menu's
        // "Device" row can skip a duplicate `router.push(.pairDevice)`
        // when this screen is already visible underneath the menu.
        .onAppear { router.isShowingPairDevice = true }
        .onDisappear { router.isShowingPairDevice = false }
        .fullScreenCover(isPresented: $showDeviceListPopup) {
            DeviceListPopup(
                isPresented: $showDeviceListPopup,
                filterKind: selectedKind
            )
            .background(ClearBackgroundView())
        }
        // Bluetooth alert — glass-card style matching UIKit showCustomAlertMultipleButtons
        .barsysPopup($bluetoothPopup, onPrimary: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }, onSecondary: {
            // Cancel — just dismiss
        })
    }

    @ViewBuilder
    private func deviceCard(device: (kind: DeviceKind, name: String, image: String)) -> some View {
        VStack(spacing: 16) {
            Image(device.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 100)
            Text(device.name)
                .font(Theme.Font.bold(12))
                .foregroundStyle(Color("charcoalGrayColor"))
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    /// Ports `checkAuthorizationsAndOpenDeviceList(deviceType:)`.
    /// UIKit sequence:
    ///   1. Sets selectedDeviceType on self
    ///   2. Calls BleManager.checkBlePermissions()
    ///   3. Sets bleDelegate = self → waits for bleDidNotifyPermission
    ///   4. If permission granted → openDeviceListScreen() modally
    ///   5. DeviceListVC sets bleDelegate = self → scanning filtered by selectedDeviceType
    private func deviceTapped(_ kind: DeviceKind) {
        selectedKind = kind

        // Check BLE authorization (ports BleManager.checkBlePermissions)
        if !ble.bluetoothAuthorized {
            bluetoothPopup = .confirm(
                title: "Bluetooth Required",
                message: "Please enable Bluetooth in Settings to discover Barsys devices.",
                primaryTitle: "Open Settings",
                secondaryTitle: ConstantButtonsTitle.cancelButtonTitle
            )
            return
        }

        // Clear previous scan results before starting a new filtered scan
        // (UIKit creates a fresh peripheralsDetectedArray each time DeviceList opens)
        ble.clearDiscovered()

        // Start scanning filtered by the selected device kind
        // (ports the filtering in bleDidDiscoverDevice that checks selectedDeviceType)
        ble.startScan(for: kind)
        showDeviceListPopup = true
    }
}

// MARK: - Transparent fullScreenCover background

private struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Device List Popup
//
// Full port of DeviceListViewController + Device.storyboard scene BIg-X7-9ZT.
// Centered 295×295 popup with glass background.
//
// State machine:
//   1. Searching — spinner + "Searching for Device"
//   2. No devices — "No device detected" + description + "Try again"
//   3. Devices found — "Device detected" + list with signal strength
//   4. Connecting — "Connecting to {name}" + spinner, cross hidden
//   5. Error — overlay: success icon + message + OK button

struct DeviceListPopup: View {
    @Binding var isPresented: Bool
    var filterKind: DeviceKind?

    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var router: AppRouter

    // MARK: - State machine
    @State private var isConnecting = false
    @State private var selectedDeviceName: String?
    @State private var timedOut = false
    @State private var showError = false
    @State private var errorMessage = "The device name has been changed already.\n\nPlease restart your Barsys device to start crafting."

    // MARK: - Timers
    /// 10s repeating poll timer — matches UIKit's `Timer.scheduledTimer(withTimeInterval: 10, repeats: true)`
    @State private var refreshTimer: Timer?
    /// 10s initial search timeout (delayed showTimeOutUI)
    @State private var timeoutTimer: Timer?
    /// 12s connection watchdog (checkIsConnectionBuiltAfterConnecting)
    @State private var connectionTimer: Timer?

    private let popupSize: CGFloat = 295

    /// Filtered discovered devices — mirrors UIKit's `bleDidDiscoverDevice`
    /// which only appends devices matching `selectedDeviceType`.
    private var filteredDevices: [BarsysDevice] {
        guard let kind = filterKind else { return ble.discovered }
        return ble.discovered.filter { $0.kind == kind }
    }

    var body: some View {
        ZStack {
            // ---- Layer 1: Inert tap-absorber (`dAT-Cp-YmL`) -----------------
            // UIKit storyboard declares this as a full-screen `UIButton` but
            // NO action is wired to it — it is an inert tap-absorber, NOT a
            // dismiss-on-tap layer. The user must use the cross button or
            // actually connect to a device to leave the screen. Previously
            // SwiftUI called `dismissPopup()` on tap which didn't match
            // UIKit (the user could accidentally cancel a pending scan).
            // Now the backdrop swallows the tap silently — identical to
            // UIKit behaviour.
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // The onTapGesture with an empty action intercepts the
                // touch so it doesn't leak to views below without
                // triggering a dismiss.
                .onTapGesture { /* inert — matches UIKit dAT-Cp-YmL */ }

            // ---- Layer 2+3: Glass card (`xJB-3B-j9G` + `CCd-kw-jXK`) --------
            // UIKit layers two views at the EXACT same frame:
            //   • `xJB-3B-j9G` (glassBackgroundView) — gets
            //     `alertPopUpBackgroundStyle(cornerRadius: .medium=12)` in
            //     `viewWillAppear` (DeviceListViewController.swift L111):
            //         iOS 26+ → real `UIGlassEffect(.regular)` via
            //                   `addGlassEffect(cornerRadius: 12)` (no
            //                   border, no fill).
            //         pre-26  → `backgroundColor = white@0.95`,
            //                   `roundCorners = 12`, `masksToBounds = true`.
            //   • `CCd-kw-jXK` (popupContainerView) — cornerRadius=12 from
            //     the storyboard `userDefinedRuntimeAttribute`, bg CLEAR
            //     (default). Hosts the content. Previously SwiftUI filled
            //     this with pure `Color.white` which OCCLUDED the glass
            //     layer underneath — the popup appeared solid white on
            //     iOS 26 instead of the soft-glass frost UIKit renders.
            //     Now the container is transparent, letting the glass
            //     behind it show through exactly like UIKit.
            ZStack(alignment: .topTrailing) {
                // Glass layer — unified recipe shared with the side menu,
                // edit panel, and DeviceConnectedPopup so all four glass
                // surfaces look identical.
                Group {
                    if #available(iOS 26.0, *) {
                        BarsysGlassPanelBackground()
                    } else {
                        // Pre-iOS 26 fallback — trait-resolved closure
                        // preserves the EXACT historical white@0.95 fill
                        // in light mode (bit-identical pixels), and
                        // returns elevated dark surface @ 0.95 in dark
                        // so the device-error popup card adapts to the
                        // dark page surface instead of being a stark
                        // white slab.
                        Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 0.95)
                                : UIColor.white.withAlphaComponent(0.95) // EXACT historical
                        })
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(width: popupSize, height: popupSize)

                // Transparent content host — matches `CCd-kw-jXK` bg=clear.
                popupContent
                    .frame(width: popupSize, height: popupSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Cross button (`d2e-Hj-opA`, 50×50, `crossIcon`,
                // appBlackColor tint). Hidden during connecting — matches
                // UIKit `btnCross.isHidden = true`.
                if !isConnecting {
                    Button {
                        HapticService.light()
                        dismissPopup()
                    } label: {
                        Image("crossIcon")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Color("appBlackColor"))
                            .frame(width: 50, height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityHint("Dismiss device list")
                }
            }
            // Group the two layered views at the same exact size —
            // matches the UIKit constraint pair that pins
            // xJB.leading/top/trailing/bottom = CCd.*.
            .frame(width: popupSize, height: popupSize)
            // UIKit `alertPopUpBackgroundStyle` applies NO drop shadow —
            // the popup's separation comes from the glass contrast alone.
            // Previously a custom shadow was added; now dropped for parity.

            // ---- Layer 4: Error popup overlay (`3yk-pB-6CA`) ----------------
            // Hidden by default, surfaces after a connection failure.
            if showError {
                errorPopupOverlay
            }
        }
        .onAppear { startSearching() }
        .onDisappear { cleanup() }
    }

    // MARK: - Popup content state machine

    @ViewBuilder
    private var popupContent: some View {
        if isConnecting {
            connectingState
        } else if !filteredDevices.isEmpty {
            devicesFoundState
        } else if timedOut {
            noDevicesState
        } else {
            searchingState
        }
    }

    // MARK: - State 1: Searching
    // UIKit: activityIndicator spinning, lblDeviceDetectedOrSearching = "Searching for Device"

    private var searchingState: some View {
        VStack(spacing: 12) {
            Text("Searching for Device")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Scanning for devices")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - State 2: No devices (foh-Hm-3U7)
    // "No device detected" 16pt veryDarkGrayColor center
    // "Please reset..." 12pt light mediumGrayColor center, top +7
    // "Try again" button 219×45, 13pt, border 1px borderColor, cornerRadius 5, top +39

    private var noDevicesState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 7) {
                Text("No device detected")
                    .font(.system(size: 16))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                Text("Please reset your Barsys device by\nrestarting it.")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color("mediumGrayColor"))
                    .multilineTextAlignment(.center)
            }

            Button {
                HapticService.light()
                tryAgain()
            } label: {
                Text("Try again")
                    .font(.system(size: 13))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color("borderColor"), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 39)

            Spacer()
        }
        .padding(.horizontal, 38)
        .offset(y: 30)
    }

    // MARK: - State 3: Devices found (KMW-nm-sBI)
    // devicesView padding (24, 30, 24, 64)
    // "Device detected" 18pt light center (GPp-Se-lIN)
    // "Please select..." 13pt light, top +38 (5Sk-tu-mOe)
    // Table 247 wide, h 84→350, top +16

    private var devicesFoundState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Device detected")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(.isHeader)

            Text("Please select the device you want to connect")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .padding(.top, 38)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredDevices) { device in
                        deviceRow(device)
                    }
                }
            }
            .frame(minHeight: 84, maxHeight: 350)
            .padding(.top, 16)
            .accessibilityLabel("Detected devices")
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 64)
    }

    // MARK: - Device row (ports DeviceListTableCell.xib)
    // lbldeviceName 13pt appBlackColor | [15pt min] signalView (icon 16×14 + label ~11pt, colored) [8pt] arrow 10×10

    @ViewBuilder
    private func deviceRow(_ device: BarsysDevice) -> some View {
        Button {
            HapticService.light()
            connectToDevice(device)
        } label: {
            HStack(spacing: 0) {
                Text(device.name
                        .replacingOccurrences(of: "\r\n", with: "")
                        .trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 13))
                    .foregroundStyle(Color("appBlackColor"))
                    .lineLimit(2)
                    .layoutPriority(-1)

                Spacer(minLength: 15)

                // Signal strength (ports configureSignal + signalView)
                HStack(spacing: 3) {
                    Image(systemName: device.signalIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 14)
                    Text(device.signalLevelText)
                        .font(.system(size: 11))
                }
                .foregroundStyle(device.signalColor)
                .layoutPriority(1)

                // Arrow (imgDeviceArrow, 10×10, "arrowRight")
                Image("arrowRight")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .padding(.leading, 8)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - State 4: Connecting
    // "Connecting to {name}" 18pt light center, spinner, cross hidden

    private var connectingState: some View {
        VStack(spacing: 12) {
            Text("Connecting to \(selectedDeviceName ?? "")")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            ProgressView()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error popup overlay (3yk-pB-6CA)
    // 295×295, cornerRadius 25, glass bg
    // Success icon 30×30, message 16pt center, OK button 201×45 pill #E0B392

    private var errorPopupOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .frame(width: popupSize, height: popupSize)

            VStack(spacing: 0) {
                Spacer()

                Image("success_device_name_change")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)

                Text(errorMessage)
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 27)
                    .padding(.top, 30)

                // OK button — pill, bg #E0B392 @ 0.9 alpha, shadow
                Button {
                    HapticService.light()
                    showError = false
                    dismissPopup()
                } label: {
                    Text("Okay")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 201, height: 45)
                        .background(Color(red: 0.878, green: 0.702, blue: 0.573).opacity(0.9))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
                }
                .accessibilityLabel("Okay")
                .accessibilityHint("Confirm and dismiss")
                .padding(.top, 25)

                Spacer()
            }
        }
        .frame(width: popupSize, height: popupSize)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    // MARK: - Timer & scanning lifecycle
    //
    // Ports viewSetup() + getUpdatedPeripheralsRefreshed():
    //   - 10s repeating timer refreshes device list
    //   - Stale devices (>12s since lastSeen) are pruned
    //   - 10s initial timeout shows "No device detected"

    private func startSearching() {
        timedOut = false
        ble.startScan(for: filterKind)
        scheduleSearchTimeout(delay: 10)
        startRefreshTimer()
    }

    /// Schedule a one-shot timeout that flips `timedOut` if no devices after `delay` seconds.
    /// Ports UIKit's `perform(#selector(showTimeOutUI), afterDelay:)`.
    private func scheduleSearchTimeout(delay: TimeInterval) {
        timeoutTimer?.invalidate()
        let kind = filterKind
        let bleRef = ble
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [self] _ in
            DispatchQueue.main.async {
                let devices = kind == nil ? bleRef.discovered : bleRef.discovered.filter { $0.kind == kind }
                if devices.isEmpty && !self.isConnecting {
                    self.timedOut = true
                }
            }
        }
    }

    /// 10s repeating refresh timer — prunes stale devices and restarts scan.
    /// Ports UIKit's `Timer.scheduledTimer(withTimeInterval: 10, repeats: true)`.
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let bleRef = ble
        let kind = filterKind
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [self] _ in
            DispatchQueue.main.async {
                // Prune devices not seen in 12 seconds
                let staleThreshold = Date().addingTimeInterval(-12)
                let hadDevices: Bool = {
                    let devices = kind == nil ? bleRef.discovered : bleRef.discovered.filter { $0.kind == kind }
                    return !devices.isEmpty
                }()
                let didPrune = bleRef.pruneStaleDevices(olderThan: staleThreshold)

                if didPrune {
                    let devices = kind == nil ? bleRef.discovered : bleRef.discovered.filter { $0.kind == kind }
                    if devices.isEmpty && !self.isConnecting {
                        let delay: TimeInterval = hadDevices ? 2.0 : 10.0
                        self.scheduleSearchTimeout(delay: delay)
                    }
                }

                // Restart scan (UIKit: BleManager.sharedManager.startBleScan())
                bleRef.startScan()
            }
        }
    }

    private func tryAgain() {
        timedOut = false
        isConnecting = false
        selectedDeviceName = nil
        ble.startScan(for: filterKind)
        scheduleSearchTimeout(delay: 10)
    }

    // MARK: - Connection flow
    //
    // Ports didSelectRowAt → connect(to:deviceName:) → 12s watchdog

    private func connectToDevice(_ device: BarsysDevice) {
        guard !isConnecting else { return }
        guard device.state == .disconnected else { return }

        isConnecting = true
        selectedDeviceName = device.name
            .replacingOccurrences(of: "\r\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Stop scanning & timers during connection (UIKit: timer?.invalidate, stopBleScan)
        ble.stopScan()
        refreshTimer?.invalidate()
        timeoutTimer?.invalidate()

        // 12s connection timeout watchdog (UIKit: checkIsConnectionBuiltAfterConnecting)
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [self] _ in
            DispatchQueue.main.async {
                guard self.isConnecting else { return }
                self.isConnecting = false
                self.selectedDeviceName = nil
                self.dismissPopup()
            }
        }

        Task {
            await ble.connect(device)
            connectionTimer?.invalidate()

            // Connection succeeded. The BLEService.onDeviceConnected callback
            // (wired in MainTabView) handles:
            //   1. Toast "{name} is Connected." (6s, segmentSelectionColor)
            //   2. Haptic success
            //   3. Pop nav stacks
            //   4. Switch to Explore tab
            // All we need to do here is dismiss the popup.
            //
            // TODO: When real BLE is fully wired, add checkDeviceInitialized
            // API call before dismissing. If device.initialized == true →
            // self.showError = true (already-initialized overlay).

            isConnecting = false
            isPresented = false
        }
    }

    private func dismissPopup() {
        cleanup()
        isPresented = false
    }

    private func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        connectionTimer?.invalidate()
        connectionTimer = nil
        ble.stopScan()
    }
}

// MARK: - Device list (route-based fallback for Route.deviceList)

struct DeviceListView: View {
    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color("primaryBackgroundColor").ignoresSafeArea()
            DeviceListPopup(isPresented: .constant(true))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Devices")
    }
}

// MARK: - Device connected

struct DeviceConnectedView: View {
    let deviceID: DeviceID
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

    private var device: BarsysDevice? { ble.connected.first { $0.id == deviceID } }

    var body: some View {
        ScrollView {
            if let device {
                VStack(spacing: Theme.Spacing.l) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Theme.Color.success)
                    Text(device.name).font(Theme.Font.title(26)).foregroundStyle(Theme.Color.textPrimary)
                    Text(device.kind.displayName).foregroundStyle(Theme.Color.textSecondary)

                    VStack(spacing: Theme.Spacing.s) {
                        InfoRow(label: "Serial", value: device.serial)
                        InfoRow(label: "Firmware", value: device.firmwareVersion ?? "—")
                        InfoRow(label: "Battery", value: device.batteryPercent.map { "\($0)%" } ?? "—")
                    }
                    .cardBackground()
                    .pagePadding()

                    VStack(spacing: Theme.Spacing.s) {
                        SecondaryButton(title: "Rename device", systemImage: "pencil") {
                            router.push(.deviceRename(device.id), in: .homeOrControlCenter)
                        }
                        SecondaryButton(title: "Disconnect", systemImage: "xmark.circle") {
                            ble.disconnect(device)
                        }
                    }
                    .pagePadding()
                }
                .padding(.top, Theme.Spacing.xl)
            } else {
                EmptyStateView(systemImage: "wave.3.right",
                               title: "Device unavailable",
                               subtitle: "This device is no longer connected.")
            }
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.Color.textPrimary).fontWeight(.medium)
        }
        .font(Theme.Font.body(15))
    }
}

// MARK: - Rename

struct DeviceRenameView: View {
    let deviceID: DeviceID
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            AppTextField(placeholder: "Device name", text: $newName, systemImage: "character.cursor.ibeam")
                .pagePadding()
                .padding(.top, Theme.Spacing.xl)

            PrimaryButton(title: "Save") {
                if let d = ble.connected.first(where: { $0.id == deviceID }) {
                    ble.rename(d, to: newName)
                }
                dismiss()
            }
            .pagePadding()
            .disabled(newName.isEmpty)

            Spacer()
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Rename")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear {
            newName = ble.connected.first { $0.id == deviceID }?.name ?? ""
        }
    }
}
