//
//  ControlCenterScreens.swift
//  BarsysAppSwiftUI
//
//  ControlCenter + DevicePaired + StationsMenu + StationCleaning.
//  Full port of ControlCenterViewController + DevicePairedViewController.
//

import SwiftUI

// MARK: - ControlCenterItem (ports ControlCenterModel.swift)

struct ControlCenterItem: Identifiable, Hashable {
    let id = UUID()
    let imageName: String
    let name: String
}

// MARK: - ControlCenter
//
// Full port of ControlCenterViewController from UIKit.
// Storyboard scene 6A9-BD-hXY in ControlCenter.storyboard.
//
// Layout: top bar (60pt) with back/device-info/fav/profile,
// "Control Center" title (24pt), description, 2-column grid of
// action tiles with shadows. Items vary by connected device type.

struct ControlCenterView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService

    @State private var showDevicePopup = false
    @State private var showResetAlert = false
    /// 1:1 with UIKit `ControlCenterViewController` L191-202 — Tutorial
    /// menu presents `TutorialViewController` modally (`overFullScreen`)
    /// with a device-specific video URL.
    @State private var showTutorialPlayer = false
    @State private var tutorialVideoURL: URL? = nil

    // 2 columns, 18pt spacing (UIKit overrides XIB's 10pt to 18pt)
    private let columns = [GridItem(.flexible(), spacing: 18),
                           GridItem(.flexible(), spacing: 18)]

    /// Ports ControlCenterViewModel.getDataArrayAccordingToConnectedDevice()
    private var items: [ControlCenterItem] {
        if ble.isBarsys360Connected() {
            return [
                .init(imageName: "stationClean",        name: "Station clean"),
                .init(imageName: "disconnectBluetooth", name: "Disconnect"),
                .init(imageName: "systemReset",         name: "System reset"),
                .init(imageName: "book",                name: "Tutorial"),
                .init(imageName: "stationMenu",         name: "Station menu")
            ]
        } else if ble.isCoasterConnected() {
            return [
                .init(imageName: "disconnectBluetooth", name: "Disconnect"),
                .init(imageName: "systemReset",         name: "System reset"),
                .init(imageName: "book",                name: "Tutorial")
            ]
        } else if ble.isBarsysShakerConnected() {
            return [
                .init(imageName: "disconnectBluetooth", name: "Disconnect"),
                .init(imageName: "systemReset",         name: "System reset"),
                .init(imageName: "book",                name: "Tutorial"),
                .init(imageName: "manualShaker",        name: "Quick Spin")
            ]
        }
        return []
    }

    /// Device name to show in header center
    private var deviceName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    /// Device icon asset name (must match Assets.xcassets naming with underscores)
    private var deviceIconName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }

    /// Description text varies by device type
    private var descriptionText: String {
        if ble.isBarsys360Connected() {
            return Constants.descriptionControlCenterFor360
        }
        return Constants.descriptionControlCenterForCoaster
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title — UwJ-H2-jbU, 24pt, appBlackColor, leading 24
                Text("Control Center")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.leading, 24)
                    .padding(.top, 0)

                // Description — BjM-cP-3cB, 12pt, appBlackColor, leading 24, top +20
                Text(descriptionText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Grid of tiles — UIKit: 40pt leading/trailing, 18pt spacing
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(items) { item in
                        ControlCenterTile(item: item) { tap(item) }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 56)
            }
            .padding(.vertical, 16)
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button — imgExploreSmall, goes to Explore tab
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticService.light()
                    router.selectedTab = .explore
                } label: {
                    Image("imgExploreSmall")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 25)
                        .foregroundStyle(Color("appBlackColor"))
                }
            }

            // Center: device ICON ONLY.
            //
            // UIKit parity — ControlCenterViewController.swift:85 sets
            // `lblDeviceName.isHidden = true` in `setupView()` and never
            // reverses it. Only the 25×25 `imgDevice` is visible in the
            // centre of the custom nav bar (storyboard constraints
            // `GX2-LX-msO` / `c9K-iH-4Xf` pin imgDevice to 25×25).
            if !deviceIconName.isEmpty {
                ToolbarItem(placement: .principal) {
                    Image(deviceIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 25)
                        .accessibilityLabel(deviceName)
                }
            }

            // Right: favourite + profile — shared 100×48 glass pill
            // (iOS 26+) / bare 61×24 icon stack (pre-26). 1:1 UIKit
            // `navigationRightGlassView`.
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
        .fullScreenCover(isPresented: $showDevicePopup) {
            DeviceConnectedPopup(isPresented: $showDevicePopup)
                .background(ClearBGHelper())
        }
        // 1:1 with UIKit `present(tutorialVc, animated: true)` from
        // `ControlCenterViewController` L202: device-specific tutorial
        // video, modal full-screen, dismisses via the X button or the
        // close callback. The TutorialView's `onDismiss` initializer
        // routes the close back through this `showTutorialPlayer` flag
        // (instead of `router.didFinishTutorial()` which is reserved
        // for the first-launch onboarding flow).
        .fullScreenCover(isPresented: $showTutorialPlayer) {
            TutorialView(
                videoURL: tutorialVideoURL,
                onDismiss: { showTutorialPlayer = false }
            )
        }
        // System Reset alert — 1:1 port of `sendSystemResetCommand()`
        // in UIKit `ControlCenterViewController.swift` L127-L142.
        // UIKit: `showCustomAlertMultipleButtons(title: "Are you sure
        // you want to reset the system?", cancelButtonTitle: "Yes",
        // continueButtonTitle: "No")`.
        //   "Yes" = cancelAction  → writeCommand(.cancel) (firmware "202")
        //                            + track `systemResetControlCenter`
        //                            + toast "System Reset"
        //   "No"  = okAction      → dismiss
        //
        // `ble.send(.cancel)` returns `false` when no peripheral is
        // connected (or the write characteristic isn't resolved yet).
        // UIKit's `try writeCommand(.cancel)` throws in that case and
        // logs; here we surface a toast so the user knows why nothing
        // happened.
        .alert(Constants.systemReset, isPresented: $showResetAlert) {
            Button(ConstantButtonsTitle.yesButtonTitle) {
                HapticService.medium()
                let sent = ble.send(.cancel)
                if sent {
                    env.toast.show(Constants.systemResetSuccess,
                                   color: Color("segmentSelectionColor"), duration: 6)
                    env.analytics.track(TrackEventName.systemResetControlCenter.rawValue)
                } else {
                    // Mirrors UIKit `appLog.error` log line for BLE write
                    // failures — but user-facing so we surface the real
                    // failure mode (no peripheral connected).
                    env.toast.show(Constants.deviceNotConnected,
                                   color: Color("errorLabelColor"), duration: 3)
                }
            }
            Button(ConstantButtonsTitle.noButtonTitle, role: .cancel) {}
        }
        .task {
            env.analytics.track(TrackEventName.controlCenterViewed.rawValue)
        }
    }

    private func tap(_ item: ControlCenterItem) {
        HapticService.light()
        switch item.name.lowercased() {
        case "station clean":
            router.push(.stationCleaning)
            env.analytics.track(TrackEventName.controlCenterCleanStationViewed.rawValue)
        case "station menu":
            router.push(.stationsMenu)
            env.analytics.track(TrackEventName.controlCenterStationMenuViewed.rawValue)
        case "disconnect":
            // UIKit opens DeviceConnectedPopup (not direct disconnect)
            showDevicePopup = true
        case "system reset":
            showResetAlert = true
        case "tutorial":
            // 1:1 with UIKit `ControlCenterViewController` L182-203.
            //
            // **Important** — Control Center's Tutorial menu does NOT
            // use the first-time `getXxxConnectedNotFirstTime()` flag.
            // That logic ONLY belongs to the Explore screen
            // (`DevicePairedView.decideTutorialOnAppear`), which auto-
            // shows the tutorial card the first time a user pairs each
            // device kind, then hides it on subsequent visits.
            //
            // Control Center's Tutorial menu is a USER-INITIATED action
            // (tap the menu item) and ALWAYS opens the modal — the only
            // logic here is picking which device-specific video URL to
            // play:
            //   • Coaster or Shaker connected → barsysCoasterUrl
            //   • Barsys 360 connected         → barsys360VideoUrl
            //   • Otherwise (defensive)        → barsys360VideoUrl
            //   (matches `tutorialVc.videoURL` initial value in
            //    `TutorialViewController.swift` L19).
            let url: URL?
            if ble.isCoasterConnected() || ble.isBarsysShakerConnected() {
                url = URL(string: VideoURLConstants.barsysCoasterUrl)
            } else if ble.isBarsys360Connected() {
                url = URL(string: VideoURLConstants.barsys360VideoUrl)
            } else {
                url = URL(string: VideoURLConstants.barsys360VideoUrl)
            }
            tutorialVideoURL = url
            env.analytics.track(TrackEventName.controlCenterTutorialsViewed.rawValue)
            showTutorialPlayer = true
        case "quick spin":
            ble.send(.manualSpinStart)
        default:
            break
        }
    }
}

// MARK: - ClearBGHelper for fullScreenCover transparency

private struct ClearBGHelper: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); DispatchQueue.main.async { v.superview?.superview?.backgroundColor = .clear }; return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - ControlCenterTile
//
// Ports ControlCenterCollectionViewCell.xib:
//   Inner card 120×120 inside 136 outer, 8pt padding, 8pt cornerRadius
//   Shadow: lightGray, 0.15 opacity, offset(0,3), radius 10
//   Icon: ~33% of container width, centered with +10pt Y offset
//   Label: 12pt system, mediumLightGrayColor, center

struct ControlCenterTile: View {
    let item: ControlCenterItem
    let action: () -> Void

    /// Reactive theme awareness — used ONLY to re-tint the tile icon
    /// in dark mode. The Control Center tile icons (`stationClean`,
    /// `disconnectBluetooth`, `systemReset`, `book`, `stationMenu`,
    /// `manualShaker`) are raw dark-grey PNGs. Light mode renders
    /// them directly against the white `Theme.Color.surface` tile;
    /// that works fine. Dark mode uses the elevated dark surface
    /// (`#2C2C2E`), and without `.renderingMode(.template)` the
    /// `.foregroundStyle` modifier is a no-op, so the dark PNG sinks
    /// into the dark tile background and the user can't tell what
    /// icon is inside (reported as "very blur in dark mode, unable
    /// to see the icons"). Template-rendering in dark mode lets the
    /// `mediumLightGrayColor` asset resolve to `#AEAEAE` and makes
    /// each glyph legible against the dark surface.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Icon area (top ~74% of card).
                //
                // Light mode keeps the raw PNG so pixels stay bit-
                // identical to the existing UIKit-parity rendering.
                // Dark mode template-tints with `mediumLightGrayColor`
                // (which resolves to the adaptive `#AEAEAE` dark value)
                // so the glyph reads as a clear light-grey icon on
                // the dark tile instead of sinking into the surface.
                Group {
                    if colorScheme == .dark {
                        Image(item.imageName)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(Color("mediumLightGrayColor"))
                    } else {
                        Image(item.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: 40, height: 40)
                .padding(.top, 30)

                Spacer()

                // Label — 12pt, mediumLightGrayColor, center.
                // Same asset swap as the icon above — bit-identical
                // #6F6F6F in light, adaptive light-gray in dark.
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("mediumLightGrayColor"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.bottom, 17)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
            // bit-identical to the previous hard-coded `Color.white`,
            // so each Control Center tile is the EXACT same white
            // card in light mode. Dark mode picks up the elevated
            // dark surface (#2C2C2E) so the tile reads as a raised
            // card on the dark Control Center canvas — visually
            // consistent with the rest of the app's adapted cards.
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // Shadow: UIKit lightGray, 0.15, offset(0,3), radius 10
            .shadow(color: Color.gray.opacity(0.15), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .padding(8) // 8pt padding from outer cell to inner card
    }
}

// MARK: - DevicePairedView
//
// Full port of DevicePairedViewController — the Explore screen shown after
// successful device connection. Storyboard scene aiH-4D-C2c.
//
// Cell sizes from UIKit:
//   Main grid (DevicePairedCell):  width = (345-15)/2 = 165pt, h = width + label + 40
//     Image: 1:1 square, 12pt corners. Label: 16pt medium charcoalGray, center, 2 lines max
//   Recommended (RecommendedRecipeCell): 300×170, 16pt corners
//     Left: title 16pt + ingredients 11pt. Right: image 50% width. Heart 30×30
//   Partnership (PartnershipCollectionViewCell): responsive width, h=190
//     Image 12pt corners + label 14pt medium center, 8pt spacing
//   Social (SocialMediaCollectionViewCell): responsive width, h=285
//     Full-bleed image, 12pt corners

struct DevicePairedView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService

    @State private var showDevicePopup = false
    @State private var favourites: Set<Int> = []

    // MARK: - Tutorial-card session state
    //
    // 1:1 port of UIKit `DevicePairedViewController` Tutorial flow:
    //
    //   override func viewDidLoad() {
    //       // 1. Snapshot visibility ONCE on load
    //       viewTutorial.isHidden = viewModel.shouldHideTutorial()
    //   }
    //
    //   private func setupTutorialVideoIfNeeded() {
    //       // 2. Get URL AND flip the per-device "seen" flag
    //       if let videoURL = viewModel.tutorialVideoURLAndMarkShown() {
    //           viewTutorial.isHidden = false
    //           playerView?.setupPlayer(with: videoURL, ...)
    //       } else {
    //           viewTutorial.isHidden = true
    //       }
    //   }
    //
    // CRITICAL — UIKit flips the "seen" flag AS THE SCREEN LOADS, NOT
    // when the user taps the play button. The tutorial card stays
    // visible for the WHOLE session even after the flag is flipped;
    // it only hides on the NEXT visit.
    //
    // SwiftUI mirror:
    //   • `tutorialDecisionMade` — guards the one-time `onAppear`
    //     side effect so re-renders don't re-flip the flag.
    //   • `hideTutorialThisSession` — snapshot of `shouldHideTutorial`
    //     at first appear; the card binds to THIS, not the live
    //     UserDefaults value. So once the screen has decided "show",
    //     the card stays visible until the user navigates away.
    //   • `tutorialVideoURL` — URL captured on first appear, used by
    //     the play-button tap to feed the modal `TutorialView`.

    @State private var tutorialDecisionMade: Bool = false
    @State private var hideTutorialThisSession: Bool = true
    @State private var tutorialVideoURL: URL? = nil
    /// Drives the modal `TutorialView` cover when the user taps the
    /// inline play card. Mirrors UIKit's `present(tutorialVc, animated: true)`.
    @State private var showTutorialPlayer = false

    // MARK: - Computed state

    /// Whether any BLE device is currently connected.
    private var isConnected: Bool { ble.isAnyDeviceConnected }

    /// 1:1 port of UIKit
    /// `DevicePairedViewModel.shouldHideTutorial()` (L149-158):
    ///
    ///   if isShakerConnected   → return getShakerConnectedNotFirstTime()
    ///   if isCoasterConnected  → return getCoasterConnectedNotFirstTime()
    ///   if isBarsys360Connected → return getBarsys360ConnectedNotFirstTime()
    ///   else                    → return true (no device → no tutorial)
    ///
    /// PURE READER — does not mutate any UserDefaults state. Called
    /// once per session by `decideTutorialOnAppear()` to snapshot the
    /// initial "show or hide" decision.
    private func shouldHideTutorialNow() -> Bool {
        if ble.isBarsysShakerConnected() {
            return UserDefaultsClass.getShakerConnectedNotFirstTime()
        } else if ble.isCoasterConnected() {
            return UserDefaultsClass.getCoasterConnectedNotFirstTime()
        } else if ble.isBarsys360Connected() {
            return UserDefaultsClass.getBarsys360ConnectedNotFirstTime()
        }
        return true
    }

    /// 1:1 port of UIKit
    /// `DevicePairedViewModel.tutorialVideoURLAndMarkShown()` (L162-177):
    /// returns the device-specific video URL AND marks the device as
    /// "shown" in UserDefaults so subsequent connections skip the card.
    /// CALLED EXACTLY ONCE per Explore-screen session via
    /// `decideTutorialOnAppear()`.
    private func tutorialVideoURLAndMarkShown() -> URL? {
        if ble.isBarsysShakerConnected() {
            if UserDefaultsClass.getShakerConnectedNotFirstTime() { return nil }
            UserDefaultsClass.saveShakerConnectedNotFirstTime(true)
            return URL(string: VideoURLConstants.barsysShakerUrl)
        } else if ble.isCoasterConnected() {
            if UserDefaultsClass.getCoasterConnectedNotFirstTime() { return nil }
            UserDefaultsClass.saveCoasterConnectedNotFirstTime(true)
            return URL(string: VideoURLConstants.barsysCoasterUrl)
        } else if ble.isBarsys360Connected() {
            if UserDefaultsClass.getBarsys360ConnectedNotFirstTime() { return nil }
            UserDefaultsClass.saveBarsys360ConnectedNotFirstTime(true)
            return URL(string: VideoURLConstants.barsys360VideoUrl)
        }
        return nil
    }

    /// Returns the device-specific tutorial URL WITHOUT marking it shown.
    /// Used as a fallback when the play-button tap fires AFTER the
    /// first-time flag has already been consumed by `decideTutorialOnAppear`
    /// (the card stays visible during the same session even though the
    /// flag now reads true).
    private var tutorialVideoURLForCurrentDevice: URL? {
        if ble.isBarsys360Connected() {
            return URL(string: VideoURLConstants.barsys360VideoUrl)
        } else if ble.isCoasterConnected() {
            return URL(string: VideoURLConstants.barsysCoasterUrl)
        } else if ble.isBarsysShakerConnected() {
            return URL(string: VideoURLConstants.barsysShakerUrl)
        }
        return nil
    }

    /// 1:1 with UIKit
    /// `DevicePairedViewController.viewDidLoad` + `setupTutorialVideoIfNeeded`
    /// chain. Runs ONCE per Explore-screen appearance:
    ///   1. Snapshot `shouldHideTutorialNow()` into `hideTutorialThisSession`
    ///      (the card visibility binding for this session).
    ///   2. Call `tutorialVideoURLAndMarkShown()` to get the device URL
    ///      AND flip the per-device "seen" flag — exact UIKit semantics.
    ///   3. Set the `tutorialDecisionMade` guard so re-renders / tab
    ///      switches do NOT re-flip the flag.
    ///
    /// On NEXT Explore visit the snapshot reads the flipped flag → card
    /// hides automatically — matching UIKit's "tutorial only shown on
    /// first connection per device kind" rule.
    private func decideTutorialOnAppear() {
        guard !tutorialDecisionMade else { return }
        tutorialDecisionMade = true
        // Read the flag BEFORE the mark-shown call.
        hideTutorialThisSession = shouldHideTutorialNow()
        // Mark this device kind as "tutorial seen" — only mutates if
        // the flag was previously false (the per-device guard inside).
        // Captures the URL so the play-button tap can present the
        // modal with the right video.
        let url = tutorialVideoURLAndMarkShown()
                  ?? tutorialVideoURLForCurrentDevice
        tutorialVideoURL = url
    }

    // MARK: - Data (ports DevicePairedViewModel.buildDevicePairedArray)
    //
    // UIKit: SAME DevicePairedViewController is root of Explore tab for
    // BOTH connected and disconnected. Grid items differ:
    //   360 connected: "Ready to Pour", "Explore Cocktail Kits", "Host an Event", "Party Mode"
    //   Coaster/Shaker connected: "Explore Recipes", "Explore Cocktail Kits", "Host an Event", "Party Mode"
    //   Disconnected: "Explore Recipes", "Explore Cocktail Kits", "Host an Event", "Party Mode"

    private var menuItems: [(name: String, image: String)] {
        let is360 = ble.isBarsys360Connected()
        let firstItem: (String, String) = is360
            ? ("Ready to Pour", "readyToPourImage")
            : ("Explore Recipes", "exploreRecipesNew")
        return [
            firstItem,
            ("Explore Cocktail Kits", "exploreCocktailsKitNew"),
            ("Host an Event", "hostAnEventNew"),
            ("Party Mode", "partyModeNew")
        ]
    }

    private let recommendedRecipes: [(id: String, title: String, desc: String, image: String)] = [
        ("1de7b1b0", "Long Island Iced Tea", "Gin, White Rum, Tequila, Triple sec, Cola, Vodka", "recommended_recipes_1"),
        ("db9bf71f", "Negroni", "Gin, Campari, Vermouth", "recommended_recipes_2"),
        ("8f8970ee", "Perfect Patrón Margarita", "Patrón, Cointreau, Fresh Lime Juice, Simple Syrup", "recommended_recipes_3"),
        ("463c492d", "Aperol Spritz", "Prosecco, Aperol, Soda Water", "recommended_recipes_4"),
        ("190b93d2", "Espresso Martini", "Vodka, Coffee Liqueur, Simple Syrup, Espresso", "recommended_recipes_5")
    ]

    private let partnerships: [(name: String, image: String)] = [
        ("Bathtub Gin", "partnership_1"),
        ("Dead Rabbit", "partnership_2"),
        ("Ciel Social Club", "partnership_3")
    ]

    private let socialMedia: [String] = ["social_thumb_1", "social_thumb_2", "social_thumb_3"]

    // MARK: - Device info helpers

    private var deviceKindName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    private var deviceIconName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }

    private var tutorialDescription: String {
        if ble.isBarsys360Connected() {
            return "Watch the video for a step-by-step guide on how to use your Barsys 360"
        }
        if ble.isCoasterConnected() {
            return "Watch the video for a step-by-step guide on how to use your Barsys Coaster"
        }
        return "Watch the video for a step-by-step guide on how to use your Barsys Shaker"
    }

    // Main grid: 2 columns, spacing 15 → cell width = (containerWidth - 15) / 2
    private let gridColumns = [GridItem(.flexible(), spacing: 15),
                                GridItem(.flexible(), spacing: 15)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ══════════════════════════════════════════════════
                // TUTORIAL SECTION (zhz-bS-M3B)
                //
                // 1:1 with UIKit `DevicePairedViewController.viewTutorial`:
                //   • Visibility gated by `viewModel.shouldHideTutorial()` —
                //     hidden once the user has been shown the per-device
                //     tutorial (UserDefaults flag), shown otherwise.
                //   • Video container 345×194, 20pt corners, BLACK bg.
                //   • Play/Pause button (`SX9-es-vHC`) covers the full
                //     345×194 area, image `play_thumb` (24×24 natural size,
                //     scaled to 60pt for inline preview), wired to
                //     `didPressPlayPauseButton:` which presents the
                //     modal `TutorialViewController` via the SAME video
                //     URL (device-specific).
                //   • Tapping anywhere on the video card opens the
                //     full-screen TutorialView modal.
                // ══════════════════════════════════════════════════
                // 1:1 with UIKit `viewTutorial.isHidden` snapshot:
                // visibility uses the SESSION snapshot, not a live read.
                // Once the screen decides "show", the card stays for
                // this whole session even though the per-device flag
                // has already been flipped to true by
                // `decideTutorialOnAppear()`.
                if isConnected && !hideTutorialThisSession {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tutorial")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color("charcoalGrayColor"))
                            .padding(.top, 17)

                        Text(tutorialDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(Color("charcoalGrayColor"))
                            .padding(.top, 4)

                        // 1:1 with UIKit `SX9-es-vHC` — full-frame
                        // play/pause button (345×194). UIKit storyboard
                        // wires this to `didPressPlayPauseButton:` which
                        // routes to the inline VideoPlayerManager. We
                        // present the modal `TutorialView` instead so the
                        // user gets the same tutorial experience as the
                        // Control Center → Tutorial menu (no inline
                        // player needed).
                        //
                        // The URL was already captured by
                        // `decideTutorialOnAppear()` (which also flipped
                        // the per-device "seen" flag). The tap just
                        // presents the modal — NO second mark-shown call.
                        Button {
                            HapticService.light()
                            // Fallback to live-resolved URL if the cached
                            // value is somehow nil (defensive — shouldn't
                            // happen since `decideTutorialOnAppear` runs
                            // before the card is rendered).
                            if tutorialVideoURL == nil {
                                tutorialVideoURL = tutorialVideoURLForCurrentDevice
                            }
                            showTutorialPlayer = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black)
                                // 60pt visual scale of the 24×24 play_thumb
                                // asset, white tint to match UIKit's button
                                // tintColor (white=1, alpha=1).
                                Image("play_thumb")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                    .foregroundStyle(.white)
                            }
                            .frame(height: 194)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityLabel("Play tutorial video")
                        .accessibilityHint("Opens the tutorial video for the connected device")
                        .padding(.top, 15)
                    }
                    .padding(.horizontal, 24)
                }

                // ══════════════════════════════════════════════════
                // MAIN GRID — 4 items, 2 cols (DevicePairedCell)
                //
                // Re-analysed against UIKit `DevicePairedCell.xib`:
                //   • Cell outer:      200 × 270
                //   • Container view:  200 × 270, cornerRadius 12
                //   • imgMixlist:      0,0,200,200 (SQUARE top),
                //                      `contentMode = scaleAspectFill`,
                //                      `clipsSubviews = YES`,
                //                      cornerRadius 12 (userDefinedRuntimeAttribute)
                //   • lblMixlistName:  x=8, y=210, 184×30
                //                      system 16pt medium, charcoalGrayColor,
                //                      center-aligned, 2 lines, tailTruncation
                //   • Vertical layout: 200 (image) + 10 gap + 30 (label) + 30 (bottom) = 270
                //
                // **Key fix**: the image uses `scaleAspectFill`, NOT
                // `scaleAspectFit`. With `.fit`, photo assets like
                // `readyToPourImage` show letterbox bars around the
                // subject (because the source image isn't exactly
                // square). UIKit's `.fill + clipsToBounds` crops to
                // the 1:1 square so the image always fills the frame
                // edge-to-edge — matches the visible layout of
                // `exploreRecipesNew`, `exploreCocktailsKitNew`, etc.
                // in the shipping app.
                // Cell width on 393pt screen: (393 − 24·2 − 15) / 2 ≈ 165pt.
                // ══════════════════════════════════════════════════
                LazyVGrid(columns: gridColumns, spacing: 0) {
                    ForEach(Array(menuItems.enumerated()), id: \.offset) { _, item in
                        Button {
                            HapticService.light()
                            handleMenuTap(item.name)
                        } label: {
                            VStack(spacing: 0) {
                                // `Color.clear` is the sizing root — gives
                                // us a stable 1:1 frame regardless of the
                                // source image's intrinsic aspect ratio.
                                // The `Image` is the overlay using
                                // `.aspectRatio(.fill)` to mimic UIKit's
                                // `scaleAspectFill`. `.clipped()` inside
                                // the overlay + `clipShape` on the
                                // container provide the same
                                // `clipsToBounds = YES` behaviour.
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(
                                        Image(item.image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                // lblMixlistName — system 16pt medium,
                                // charcoalGray, center, 2 lines max.
                                // UIKit frame: 184pt wide × 30pt tall,
                                // 10pt below the image (y=210).
                                Text(item.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color("charcoalGrayColor"))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .frame(height: 30)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 10)  // 10pt image→label gap (y=210 − y=200)
                                    .padding(.bottom, 30) // matches 30pt cell bottom
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // ══════════════════════════════════════════════════
                // RECOMMENDED RECIPES (RecommendedRecipeCell)
                // Cell: 300×170, 16pt corners
                // Left: title 16pt (14pt padding, 3 lines) + ingredients 11pt unSelectedColor (4 lines, 12pt gap)
                // Right: image 50% width (150×170), scaleAspectFill
                // Heart: 30×30, 6pt from top-right of image
                // ══════════════════════════════════════════════════
                sectionHeader("We think you'll love these")
                    .padding(.top, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(recommendedRecipes.enumerated()), id: \.offset) { idx, recipe in
                            ZStack(alignment: .topTrailing) {
                                HStack(spacing: 0) {
                                    // Left text area (50%)
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(recipe.title)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color("charcoalGrayColor"))
                                            .lineLimit(3)
                                        Text(recipe.desc)
                                            .font(.system(size: 11))
                                            // `unSelectedColor` light value is sRGB(0.584,
                                            // 0.584, 0.584) — bit-identical to the previous
                                            // hard-coded `Color(red: 0.584, …)` (#959595), so
                                            // light mode renders the EXACT same description
                                            // pixels. Dark mode picks up the adaptive
                                            // mid-gray (#8E8E93) so the ingredient line
                                            // stays legible against the dark recommended-row
                                            // surface. This was always the UIKit asset name —
                                            // see comment at L743 ("ingredients 11pt unSelectedColor").
                                            .foregroundStyle(Color("unSelectedColor"))
                                            .lineLimit(4)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)

                                    // Right image (50% = 150pt of 300)
                                    Image(recipe.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 150, height: 170)
                                        .clipped()
                                }

                                // Heart/favourite button (30×30, 6pt from top-right)
                                Button {
                                    HapticService.light()
                                    if favourites.contains(idx) {
                                        favourites.remove(idx)
                                    } else {
                                        favourites.insert(idx)
                                    }
                                } label: {
                                    Image(favourites.contains(idx) ? "favIconRecipeSelected" : "favIconRecipe")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 22, height: 20)
                                        .frame(width: 30, height: 30)
                                }
                                .padding(.top, 6)
                                .padding(.trailing, 6)
                            }
                            .frame(width: 300, height: 170)
                            .background(Color("warmBackgroundColor"))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 12)

                // ══════════════════════════════════════════════════
                // PARTNERSHIPS (PartnershipCollectionViewCell)
                // Cell: responsive width ≈ (screenW - 24 - 32) / 2.15, h=190
                // Image: fill width, height = width, 12pt corners
                // Label: 14pt medium charcoalGray center, 8pt below image
                // ══════════════════════════════════════════════════
                sectionHeader("Partnerships")
                    .padding(.top, 24)

                GeometryReader { geo in
                    let cardW = (geo.size.width - 24 - 32) / 2.15
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(partnerships.enumerated()), id: \.offset) { _, p in
                                VStack(spacing: 8) {
                                    Image(p.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: cardW, height: cardW)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(p.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color("charcoalGrayColor"))
                                        .frame(width: cardW)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .frame(height: 210) // image ≈ 165 + 8 spacing + 20 label + buffer
                .padding(.top, 12)

                // ══════════════════════════════════════════════════
                // SOCIAL MEDIA (SocialMediaCollectionViewCell)
                // Cell: responsive width, h=285, full-bleed image, 12pt corners
                // ══════════════════════════════════════════════════
                sectionHeader("Connect with Barsys online")
                    .padding(.top, 16)

                GeometryReader { geo in
                    let cardW = (geo.size.width - 24 - 32) / 2.15
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(socialMedia.enumerated()), id: \.offset) { _, img in
                                Image(img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: cardW, height: 285)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .frame(height: 285)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button — only shown when connected (UIKit: btnBack.isHidden = true initially)
            // When connected, taps open DeviceConnectedPopup (ports didPressBackButton)
            if isConnected {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticService.light()
                        showDevicePopup = true
                    } label: {
                        Image("back")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
            }

            // Center: device ICON 25×25 ONLY — ONLY when connected.
            //
            // UIKit parity — ControlCenterViewController.swift:85 sets
            // `lblDeviceName.isHidden = true` in `setupView()` and never
            // reverses it. Only the `imgDevice` is visible.
            if isConnected {
                ToolbarItem(placement: .principal) {
                    Image(deviceIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 25)
                        .accessibilityLabel(deviceKindName)
                }
            }

            // Right: fav + profile — shared 100×48 glass pill (iOS 26+)
            // or bare 61×24 icon stack (pre-26). 1:1 UIKit
            // `navigationRightGlassView`.
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
        .fullScreenCover(isPresented: $showDevicePopup) {
            DeviceConnectedPopup(isPresented: $showDevicePopup)
                .background(ClearBGHelper())
        }
        // Tutorial modal — 1:1 with UIKit
        // `present(tutorialVc, animated: true)` from
        // `DevicePairedViewController.didPressPlayPauseButton(_:)`
        // (the inline play card on the Explore screen tutorial section).
        // Routes through the same `TutorialView(videoURL:onDismiss:)`
        // initializer the Control Center tutorial menu uses.
        .fullScreenCover(isPresented: $showTutorialPlayer) {
            TutorialView(
                videoURL: tutorialVideoURL,
                onDismiss: { showTutorialPlayer = false }
            )
        }
        // 1:1 with UIKit `DevicePairedViewController.viewDidLoad`
        // → `setupTutorialVideoIfNeeded()`: snapshot the show/hide
        // decision AND flip the per-device "seen" flag exactly once
        // per Explore-screen appearance. Re-renders / tab swaps don't
        // re-trigger because of the `tutorialDecisionMade` guard
        // inside `decideTutorialOnAppear()`.
        .onAppear {
            decideTutorialOnAppear()
        }
        // Re-decide if the user reconnects to a different device kind
        // mid-session (e.g. switches from Coaster → Barsys 360). Each
        // device kind has its own first-time flag, so a new connection
        // gets its own evaluation.
        .onChange(of: ble.isAnyDeviceConnected) { connected in
            if connected {
                // Reset the guard so the new device kind re-evaluates.
                tutorialDecisionMade = false
                decideTutorialOnAppear()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color("charcoalGrayColor"))
            .padding(.leading, 24)
    }

    // Ports didSelectItemAt for mainCollectionView
    private func handleMenuTap(_ name: String) {
        switch name {
        case "Ready to Pour":
            router.push(.readyToPour)
        case "Explore Recipes":
            router.push(.exploreRecipes)
        case "Explore Cocktail Kits":
            router.push(.mixlistList)
        case "Host an Event":
            router.selectedTab = .barBot
        case "Party Mode":
            env.toast.show("Coming Soon!", color: Color("segmentSelectionColor"), duration: 3)
        default:
            break
        }
    }
}

// MARK: - StationSlot

struct StationSlot: Identifiable, Hashable {
    let station: StationName
    var ingredientName: String
    var ingredientQuantity: Double
    var isPerishable: Bool
    /// 1:1 parity with UIKit `StationCleaningFlow.category` — carries
    /// the server-side primary / secondary / flavour-tags so the
    /// setup-stations auto-map algorithm can match mixlist ingredients
    /// to stations by category rather than by brittle name equality.
    /// Also re-sent on PATCH so the server keeps the category intact.
    var category: IngredientCategory? = nil
    /// 1:1 parity with UIKit `StationCleaningFlow.updatedAt` — the
    /// server-owned ISO-8601 timestamp for the station's last refill.
    /// Required to preserve perishable expiry across FLUSH / refill
    /// cycles (UIKit `ConfigurationStationBodyUpdated` re-sends this
    /// value so the 24-hour timer doesn't reset).
    var updatedAt: String? = nil
    var id: StationName { station }

    var isEmpty: Bool {
        ingredientName.isEmpty || ingredientName == Constants.emptyDoubleDash
    }
}

// MARK: - StationsMenuView (1:1 port of `StationsMenuViewController`)
//
// UIKit reference:
//   • 60pt custom nav (back + device + favorite + glass profile)
//   • Title "Stations" — `lblTitle`, AppFontClass.title1 (24pt), x=24
//   • Select-station container — corner 16, 1pt borderColor, w = screen-48
//       - "Select Station" header — AppFontClass.headline (16pt)
//       - 6 station buttons A-F (30×30 circle, tag 1-6,
//         sideMenuSelectionColor when selected, lightGrayColor border,
//         AppFontClass.title3 18pt)
//       - Station image 279×246 ("stationA"…"stationF" assets)
//       - ingredientNameButton — caption1 (12pt) brand colour
//       - 1pt borderColor divider
//       - progressMessageButton — caption1 (12pt) lightGray
//   • TableView of 6 `StationCleaningFlowTableViewCell` (375×63 each)
//   • Bottom 87pt stack — Clean, Refill, AddIngredient, Proceed (each 45pt,
//     selectively visible per state).
//
// Origin matrix:
//   • controlCenter + occupied → [Clean, Refill]
//   • controlCenter + empty    → [Add Ingredient]
//   • setupStationsFlow        → [Proceed]

// MARK: - StationsAPIService
//
// 1:1 port of UIKit `StationsServiceApi.getStationsFromServer(deviceName:)`:
//   GET https://defteros-service-47447659942.us-central1.run.app/api/v1/devices/{deviceName}
// Response: `StationsResponseModel` → `configuration.stations.{a..f}`
// Each `StationsData` has metric, quantity, updated_at, is_perishable,
// ingredient_name, category.
//
// The SwiftUI port parses that JSON directly into `[StationSlot]` so the
// UI shows live device data instead of six empty slots.

enum StationsAPIService {
    /// Decoded response shape (subset — only the fields we render).
    private struct Response: Decodable {
        let configuration: Configuration?
        struct Configuration: Decodable {
            let stations: Stations?
            struct Stations: Decodable {
                let A, B, C, D, E, F: Slot?
            }
            struct Slot: Decodable {
                let metric: String?
                let quantity: String?
                let updated_at: String?
                let is_perishable: Bool?
                let ingredient_name: String?
                /// 1:1 parity with UIKit `StationsData.category` — the
                /// server echoes back the primary/secondary/flavour_tags
                /// that were sent on the last PATCH. We parse + preserve
                /// it so the setup-stations auto-map algorithm can do
                /// category-based matching (UIKit `setupStationsAction`
                /// L49 branches on `category.primary + category.secondary`).
                let category: CategoryPayload?
            }
            struct CategoryPayload: Decodable {
                let primary: String?
                let secondary: String?
                let flavour_tags: [String]?
            }
        }
    }

    /// Perishable threshold (24 hours = 86 400 seconds) — matches UIKit
    /// `NumericConstants.perishableInterval` used in
    /// `StationCleaningFlowViewModel+StationMapping.getPerishableArray()`.
    static let perishableIntervalSeconds: TimeInterval = 86_400

    /// True when an `is_perishable` station's `updated_at` is older than
    /// `perishableIntervalSeconds`. Mirrors UIKit branching in
    /// `cellColorState(for:)` + Refill-button state machine.
    private static func isExpired(updatedAt: String?, isPerishable: Bool) -> Bool {
        guard isPerishable, let raw = updatedAt, !raw.isEmpty else { return false }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = parser.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
        guard let date = parsed else { return false }
        return Date().timeIntervalSince(date) > perishableIntervalSeconds
    }

    /// Base URL + endpoint matched to UIKit `GlobalConstants.baseUrlForRecipes`
    /// + `AppAPI.getAndUpdateStationsApi` (`devices/`).
    private static let baseURL =
        "https://defteros-service-47447659942.us-central1.run.app/api/v1/"

    // MARK: - Authorized request helper (1:1 port of UIKit
    // `NetworkingUtility.createRequest(urlString:method:timeout:includeAuth:contentType:)`)
    //
    // Critical parity rules ported verbatim:
    //   • Bearer header is ALWAYS set — even when the session token is
    //     empty, UIKit sends `"Bearer "` (trailing space). Many servers
    //     branch on header presence vs value, so omitting the header
    //     entirely (as the previous SwiftUI port did) changes the
    //     server's auth code path.
    //   • Content-Type defaults to `application/json`.
    //   • Timeout defaults to 60 seconds.
    //
    // Using this helper across all station endpoints guarantees the
    // exact request bytes match what UIKit produces in Release mode.
    private static func authorizedRequest(url: URL,
                                          method: String,
                                          contentType: String = "application/json",
                                          timeout: TimeInterval = 60) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        // Always set, matching UIKit — empty token still produces the
        // literal "Bearer " header value.
        let token = UserDefaultsClass.getSessionToken() ?? ""
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    // MARK: - Update station (ports `StationsServiceApi.updateStation`)
    //
    // PUT `{baseURL}devices/{encodedDeviceName}/stations/{STATION}`
    // body: JSON-encoded `ConfigurationStationBody` OR
    //       `ConfigurationStationBodyUpdated` (+updated_at) when the
    //       ingredient is perishable and we need the server to retain
    //       the original timestamp (see UIKit L59-63).
    //
    // Used by the cleaning flow to either:
    //   • update the station after a FLUSH cycle (preserves perishable
    //     updated_at if the ingredient is perishable), OR
    //   • remove the station after a CLEAN cycle (body has
    //     ingredient_name=null, quantity="0", is_perishable=false).

    // 1:1 port of UIKit `ConfigurationStationBody` +
    // `ConfigurationStationBodyUpdated` (StationsResponseModel.swift
    // L149-L187). Critical: UIKit wraps `ingredientName` with the
    // `@NullCodable` property wrapper which ALWAYS writes the key —
    // encoding `null` when the value is nil, a string otherwise.
    //
    // Default Swift `JSONEncoder` OMITS optional keys when nil, so a
    // plain `ingredient_name: String? = nil` produces
    //     { "metric": "ML", "quantity": "0", "is_perishable": false }
    // whereas UIKit produces
    //     { "metric": "ML", "quantity": "0",
    //       "ingredient_name": null, "is_perishable": false }
    //
    // This matters for `removeStation` — if the server branches on
    // "ingredient_name present == explicit clear" vs "absent == no
    // change", the two payloads take DIFFERENT code paths. The custom
    // `encode(to:)` below always emits the `ingredient_name` key so
    // the server sees the same bytes UIKit sends.
    struct StationUpdateBody: Encodable {
        var metric: String = "ML"
        var quantity: String = "0"
        /// Null when we want the server to clear this field (remove
        /// flow). Matches UIKit `@NullCodable` behaviour exactly.
        var ingredient_name: String? = nil
        var is_perishable: Bool = false
        /// Optional category object — OMITTED when nil (matches UIKit
        /// `Category?` without NullCodable). When removing a station
        /// UIKit passes an empty `Category(primary: "", secondary: "",
        /// flavour_tags: [])` instead of nil so the object is present.
        var category: CategoryPayload? = nil
        /// Only encoded when the station is perishable + `isUpdatedAtNeeded`
        /// in UIKit — keeps the server-owned timestamp stable across an
        /// update (otherwise perishable expiry would reset every time
        /// the user taps Refill). OMITTED when nil.
        var updated_at: String? = nil

        struct CategoryPayload: Encodable {
            var primary: String?
            var secondary: String?
            var flavour_tags: [String]?
        }

        enum CodingKeys: String, CodingKey {
            case metric, quantity, ingredient_name, is_perishable,
                 category, updated_at
        }

        /// Custom encoder to emit `ingredient_name: null` when nil
        /// (UIKit `@NullCodable` parity) while keeping other optionals
        /// "omit-if-nil" for byte-identical match with
        /// `ConfigurationStationBody` / `ConfigurationStationBodyUpdated`.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(metric, forKey: .metric)
            try container.encode(quantity, forKey: .quantity)
            // Always emit the key — null when nil, string when set.
            if let name = ingredient_name {
                try container.encode(name, forKey: .ingredient_name)
            } else {
                try container.encodeNil(forKey: .ingredient_name)
            }
            try container.encode(is_perishable, forKey: .is_perishable)
            // Optional, omit-if-nil (matches UIKit `Category?`).
            try container.encodeIfPresent(category, forKey: .category)
            try container.encodeIfPresent(updated_at, forKey: .updated_at)
        }

        func toJSON() -> Data? {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            return try? enc.encode(self)
        }
    }

    @discardableResult
    static func updateStation(deviceName: String,
                              station: StationName,
                              body: StationUpdateBody) async -> Bool {
        guard !deviceName.isEmpty,
              let encoded = deviceName.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)devices/device-number/\(encoded)/stations/\(station.rawValue)")
        else { return false }

        var request = authorizedRequest(url: url, method: "PUT")
        request.httpBody = body.toJSON()

        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }

    /// Shortcut: wipe a station. Matches UIKit
    /// `buildRemoveStationConfig()` — metric=ML, quantity=0,
    /// ingredient_name=nil, is_perishable=false, category=empty.
    @discardableResult
    static func removeStation(deviceName: String,
                              station: StationName) async -> Bool {
        let body = StationUpdateBody(
            metric: "ML",
            quantity: "0",
            ingredient_name: nil,
            is_perishable: false,
            category: StationUpdateBody.CategoryPayload(
                primary: "", secondary: "", flavour_tags: []
            ),
            updated_at: nil
        )
        return await updateStation(deviceName: deviceName,
                                   station: station,
                                   body: body)
    }

    /// PATCH `{baseURL}devices/{encodedDeviceName}` with a full
    /// `configuration.stations` JSON. Ports
    /// `StationsServiceApi.updateAllStationsTogetherWithPatch`.
    /// Used by the Setup-Stations flow to commit all 6 stations in one
    /// shot before the user leaves the screen.
    @discardableResult
    static func patchAllStations(deviceName: String,
                                 stations: [StationSlot]) async -> Bool {
        guard !deviceName.isEmpty,
              let encoded = deviceName.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed),
              // UIKit `AppAPI.getAndUpdateStationsApi = "devices/device-number/"`.
              let url = URL(string: "\(baseURL)devices/device-number/\(encoded)")
        else { return false }

        var stationsDict: [String: Any] = [:]
        for slot in stations {
            stationsDict[slot.station.rawValue] = [
                "metric": "ML",
                "quantity": "\(Int(slot.ingredientQuantity))",
                "ingredient_name": slot.ingredientName.isEmpty
                    ? NSNull() as Any
                    : slot.ingredientName as Any,
                "is_perishable": slot.isPerishable
            ]
        }
        let body: [String: Any] = [
            "configuration": ["stations": stationsDict]
        ]

        var request = authorizedRequest(url: url, method: "PATCH")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }

    /// Fetches the 6 A–F stations for the given device name. Returns an
    /// empty array on any failure so callers can safely fall back to the
    /// default all-empty layout.
    ///
    /// **Path fix**: UIKit `ApiConstants.swift` L41 defines
    /// `getAndUpdateStationsApi = "devices/device-number/"`, NOT
    /// `"devices/"`. The previous SwiftUI port missed the
    /// `device-number/` segment and returned 404 every time, leaving
    /// the cleaning + station-menu screens with a blank grid. The real
    /// full URL is:
    ///   `{baseURL}devices/device-number/{deviceName}`
    static func loadStations(deviceName: String) async -> [StationSlot] {
        guard !deviceName.isEmpty,
              // UIKit: `(deviceName ?? "").addingPercentEncoding(
              // withAllowedCharacters: .urlPathAllowed) ?? (deviceName ?? "")`
              // — falls back to the raw name when encoding fails. We
              // mirror that with the `?? deviceName` fallback.
              let url = URL(string: "\(baseURL)devices/device-number/\(deviceName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceName)")
        else { return [] }

        let request = authorizedRequest(url: url, method: "GET")

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0

            // 1:1 port of UIKit `getStationsFromServer` (L32-44):
            // when the server reports "device not found", fall through
            // to `save360InitialDeviceStationsOnlyFirstTime` which POSTs
            // a skeleton config. We detect that by:
            //   (a) 404 / 400 status AND the error body mentions "device not found"
            //   (b) 200 with `message` or `error` == "device not found"
            // Either way, seed six empty stations and return them.
            let body = try? JSONDecoder().decode(StationsErrorEnvelope.self, from: data)
            let errorMessage = (body?.message ?? body?.error ?? "").lowercased()
            if errorMessage == "device not found"
                || statusCode == 404 || statusCode == 400 {
                _ = await seedInitialStations(deviceName: deviceName)
                return StationName.allCases.map {
                    StationSlot(station: $0, ingredientName: "",
                                ingredientQuantity: 0, isPerishable: false)
                }
            }

            guard (200..<300).contains(statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let stations = decoded.configuration?.stations else { return [] }
            let raw: [(StationName, Response.Configuration.Slot?)] = [
                (.a, stations.A), (.b, stations.B), (.c, stations.C),
                (.d, stations.D), (.e, stations.E), (.f, stations.F)
            ]
            return raw.map { (name, slot) in
                let qtyStr = slot?.quantity ?? "0"
                let qty = Double(qtyStr) ?? 0
                let perishableFlag = slot?.is_perishable ?? false
                let expired = isExpired(updatedAt: slot?.updated_at,
                                        isPerishable: perishableFlag)
                // Translate the server's category payload into the
                // domain `IngredientCategory` we use everywhere else
                // in the app. Nil when the server omitted the object.
                let category: IngredientCategory? = slot?.category.map {
                    IngredientCategory(
                        primary: $0.primary,
                        secondary: $0.secondary,
                        flavourTags: $0.flavour_tags
                    )
                }
                return StationSlot(
                    station: name,
                    ingredientName: slot?.ingredient_name ?? "",
                    ingredientQuantity: qty,
                    isPerishable: expired,
                    category: category,
                    updatedAt: slot?.updated_at
                )
            }
        } catch {
            return []
        }
    }

    /// Decodes either `{ "message": "..." }` or `{ "error": "..." }`.
    private struct StationsErrorEnvelope: Decodable {
        let message: String?
        let error: String?
    }

    /// Ports UIKit `save360InitialDeviceStationsOnlyFirstTime` —
    /// POSTs `{baseURL}devices` with a skeleton configuration so the
    /// server creates the device record with six empty A–F stations.
    /// Called when the GET returned "device not found".
    /// 1:1 port of UIKit
    /// `StationsServiceApi.save360InitialDeviceStationsOnlyFirstTime`
    /// (StationsServiceApi.swift L93-L120). Sends the HAND-BUILT JSON
    /// string UIKit uses verbatim so the server receives byte-identical
    /// bytes (ordering, whitespace, key casing). UIKit's exact body:
    ///
    /// ```
    /// {
    ///   "configuration": {
    ///     "stations": {
    ///       "A": { "ingredient_name": null, "is_perishable": false,
    ///              "metric": "ML", "quantity": null, "updated_at": null },
    ///       "B": { ... }, "C": { ... }, "D": { ... },
    ///       "E": { ... }, "F": { ... }
    ///     }
    ///   },
    ///   "created_at": null,
    ///   "device_number": "{name}",
    ///   "device_type_id":  null,
    ///   "id": null,
    ///   "updated_at": null
    /// }
    /// ```
    ///
    /// Endpoint: POST `{base}devices` with 60s timeout.
    @discardableResult
    private static func seedInitialStations(deviceName: String) async -> Bool {
        // Use the UIKit-shaped URL (no "device-number/" — this is the
        // create endpoint, not the get/update one).
        guard let url = URL(string: "\(baseURL)devices") else { return false }
        // Build the JSON string verbatim — matches UIKit L94 exactly.
        let stationEntry = """
        {
            "ingredient_name": null,
            "is_perishable": false,
            "metric": "ML",
            "quantity": null,
            "updated_at": null
        }
        """
        let jsonBody = """
        {
          "configuration": {
            "stations": {
              "A": \(stationEntry),
              "B": \(stationEntry),
              "C": \(stationEntry),
              "D": \(stationEntry),
              "E": \(stationEntry),
              "F": \(stationEntry)
            }
          },
          "created_at": null,
          "device_number": "\(deviceName)",
          "device_type_id":  null,
          "id": null,
          "updated_at": null
        }
        """
        var request = authorizedRequest(url: url, method: "POST")
        request.httpBody = jsonBody.data(using: .utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }

}

final class StationsMenuViewModel: ObservableObject {
    @Published var stations: [StationSlot] = StationName.allCases.map {
        StationSlot(station: $0, ingredientName: "", ingredientQuantity: 0, isPerishable: false)
    }
    /// Ports `selectedStationName` (default `.a`).
    @Published var selectedStation: StationName = .a
    /// Ports `stationsOrigin`.
    @Published var origin: StationsMenuOrigin = .controlCenter
    /// True while a `loadStations()` request is in flight.
    @Published var isLoading: Bool = false

    var selectedSlot: StationSlot? {
        stations.first(where: { $0.station == selectedStation })
    }

    var isSelectedStationOccupied: Bool { !(selectedSlot?.isEmpty ?? true) }
    var hasPerishableIngredients: Bool { stations.contains { $0.isPerishable } }

    /// One-shot guard for the UIKit "Pour ingredients into the machine
    /// as shown" alert on setup-stations entry. UIKit models it on
    /// `StationsMenuViewModel.isPouringPopUpShownOnce` — the popup
    /// renders the FIRST TIME the setup-stations flow shows buttons
    /// and never again for the remainder of the VM lifetime (even if
    /// the user toggles tabs / re-enters the station selector).
    @Published var isPouringPopUpShownOnce: Bool = false

    func setIngredient(_ name: String, quantityMl: Double, isPerishable: Bool, at station: StationName) {
        guard let idx = stations.firstIndex(where: { $0.station == station }) else { return }
        stations[idx].ingredientName = name
        stations[idx].ingredientQuantity = quantityMl
        stations[idx].isPerishable = isPerishable
    }

    /// 1:1 port of UIKit `StationsMenuViewModel.updateSingleStation(...)`
    /// — PATCHes the device with the new ingredient/quantity/category/
    /// perishable configuration, then re-fetches the full 6-station grid
    /// so the UI mirrors the server truth.
    ///
    /// UIKit sequence (StationsMenuViewController+IngredientDetection):
    ///   1. showGlassLoader("Updating Station")
    ///   2. StationsServiceApi.updateStation(…) PUT
    ///   3. Analytics event (trackStationUpdate)
    ///   4. MixlistsUpdateClass().getStationsHere { … }  // refetch
    ///   5. hideGlassLoader()
    ///   6. onStationsUpdated?()  // reload tableView + bottom buttons
    @MainActor
    func persistIngredient(
        _ name: String,
        quantityMl: Double,
        isPerishable: Bool,
        at station: StationName,
        deviceName: String,
        primaryCategory: String? = "",
        secondaryCategory: String? = "",
        loadingService: LoadingState
    ) async {
        setIngredient(name, quantityMl: quantityMl,
                      isPerishable: isPerishable, at: station)
        guard !deviceName.isEmpty else { return }
        loadingService.show("Updating Station")
        let body = StationsAPIService.StationUpdateBody(
            metric: "ML",
            quantity: "\(quantityMl)",
            ingredient_name: name,
            is_perishable: isPerishable,
            category: StationsAPIService.StationUpdateBody.CategoryPayload(
                primary: primaryCategory ?? "",
                secondary: secondaryCategory ?? "",
                flavour_tags: []
            ),
            updated_at: nil
        )
        _ = await StationsAPIService.updateStation(
            deviceName: deviceName,
            station: station,
            body: body
        )
        // Refetch stations so the UI reflects the server truth
        // (UIKit calls `MixlistsUpdateClass().getStationsHere`).
        await loadStations(deviceName: deviceName)
        loadingService.hide()
    }

    func clear(_ station: StationName) {
        guard let idx = stations.firstIndex(where: { $0.station == station }) else { return }
        stations[idx].ingredientName = ""
        stations[idx].ingredientQuantity = 0
        stations[idx].isPerishable = false
    }

    /// Ports UIKit `MixlistsUpdateClass().getStationsHere { stationsArray in … }`
    /// which wraps `StationsServiceApi.getStationsFromServer`. Fetches
    /// the device's 6 stations from the API and publishes them.
    @MainActor
    func loadStations(deviceName: String) async {
        guard !deviceName.isEmpty else { return }
        isLoading = true
        let fetched = await StationsAPIService.loadStations(deviceName: deviceName)
        isLoading = false
        guard !fetched.isEmpty else { return }
        // Preserve A-F ordering — if the backend returned a partial set,
        // fill any missing station with the existing (empty) slot.
        var merged = stations
        for slot in fetched {
            if let idx = merged.firstIndex(where: { $0.station == slot.station }) {
                merged[idx] = slot
            }
        }
        stations = merged
    }
}

struct StationsMenuView: View {
    @StateObject private var viewModel = StationsMenuViewModel()
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService
    /// Used by the setup-stations flow to pop back to MixlistDetail
    /// once the PATCH succeeds. In control-center mode this stays
    /// unused — user navigates manually.
    @Environment(\.dismiss) private var dismiss

    /// Reactive theme awareness — used ONLY by the brand-orange
    /// primary action buttons ("Add Ingredient" / "Refill" /
    /// "Proceed to Fill Stations") to override the dark-appearance
    /// variant of the `brandGradientTop` / `brandGradientBottom`
    /// colour assets (which wrongly resolve to dark grey / near-black
    /// in dark mode) back to the light-mode orange RGB so the
    /// buttons stay readable in dark mode. Light mode is untouched.
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Image-detection pipeline state
    //
    // 1:1 port of `StationsMenuViewController+IngredientDetection`:
    //   1. User taps "Add Ingredient" → `showImagePicker = true`
    //   2. Photo picker → onPick(image)
    //   3. Image POSTed to `UploadIngredientsImage().uploadImageAndGetIngredientsResponse(...)`
    //      → returns [ingredientName] (single or multiple).
    //   4. If multiple → `BarsysPopup.multipleIngredients` chooser.
    //      If one    → directly `addIngredient(name:)`.
    //   5. ViewModel calls `StationsServiceApi.updateStation(...)` PUT
    //      and refreshes via `loadStations(...)`.
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .camera
    @State private var pickedImage: UIImage?
    @State private var popup: BarsysPopup?

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title — 1:1 port of UIKit `lblTitle` which is set by
                // `computeBottomButtonsState().titleText`:
                //   • `setupStationsFlow` → "Fill Stations"
                //   • `controlCenter`     → "Stations"
                // Font: system 24pt regular, `appBlackColor`, leading 24.
                Text(titleText)
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                // Select-station container card
                StationSelectorCard(
                    stations: viewModel.stations,
                    selected: viewModel.selectedStation,
                    progressMessage: progressMessage,
                    ingredientName: viewModel.selectedSlot?.ingredientName ?? "",
                    onSelect: { viewModel.selectedStation = $0 }
                )
                .padding(.horizontal, 24)

                // TableView of 6 station rows (StationCleaningFlowTableViewCell)
                VStack(spacing: 0) {
                    ForEach(viewModel.stations) { slot in
                        StationCleaningFlowTableRow(
                            slot: slot,
                            isSelected: slot.station == viewModel.selectedStation,
                            unit: env.preferences.measurementUnit
                        )
                        .onTapGesture {
                            HapticService.light()
                            viewModel.selectedStation = slot.station
                        }
                    }
                }
                .padding(.horizontal, 0)

                Color.clear.frame(height: 110)
            }
            .padding(.bottom, 16)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
        .safeAreaInset(edge: .bottom) { bottomActions }
        // Load the 6 A–F stations from the real device endpoint on
        // appear. Mirrors UIKit `viewWillAppear` → `viewModel.loadStations`.
        //
        // Bug fix (getStations race):
        // Previous code used `.task(id: ble.getConnectedDeviceName())`
        // AND called `ble.getConnectedDeviceName()` a second time inside
        // the closure — so when the BLE layer's `customName` flickered
        // (reconnect, name propagation delay) the task re-fired with an
        // empty string and `loadStations` early-returned without data.
        // Now we cache the name once, retry briefly if it's momentarily
        // empty (BLE connect handshake can take up to ~300 ms to
        // publish the name), and gate on `isAnyDeviceConnected` to
        // avoid spinning when nothing is paired.
        .task {
            // 1:1 port of UIKit setup-mode pre-population:
            // `StationsMenuViewController.viewWillAppear` branches on
            // `ingredientsArrayForSetUpStationsMapped.isEmpty` — if the
            // caller already provided the mapped array, skip the GET
            // and seed the UI from the context instead.
            if let ctx = router.setupStationsContext {
                viewModel.origin = .recipeCrafting
                viewModel.stations = ctx.mappedSlots
                viewModel.selectedStation =
                    ctx.mappedSlots.first?.station ?? .a
                // 1:1 port of UIKit one-shot pouring popup:
                // `StationsMenuViewModel.computeBottomButtonsState()`
                // sets `shouldShowPouringPopup = true` the FIRST time
                // it's called in setup-stations mode (guarded by
                // `isPouringPopUpShownOnce`). UIKit shows the alert
                // automatically when the screen lands, NOT on the
                // proceed-button tap.
                if !viewModel.isPouringPopUpShownOnce {
                    viewModel.isPouringPopUpShownOnce = true
                    env.alerts.show(
                        title: Constants.pourIngredientsIntoMachine,
                        message: "",
                        primary: ConstantButtonsTitle.continueButtonTitle
                    )
                }
                return
            }
            viewModel.origin = .controlCenter
            var deviceName = ble.getConnectedDeviceName()
            var retries = 3
            while deviceName.isEmpty && retries > 0 && ble.isAnyDeviceConnected {
                try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
                deviceName = ble.getConnectedDeviceName()
                retries -= 1
            }
            guard !deviceName.isEmpty else { return }
            await viewModel.loadStations(deviceName: deviceName)
        }
        // 1:1 port of UIKit
        // `StationCleaningFlowViewController.didPressBackButton`
        // tail-delay:
        //   DelayedAction.afterBleResponse(seconds: 1.0) {
        //       topVC.refreshOnlyWhenComesFromStationsCleanScreen()
        //   }
        // The cleaning screen posts `signalStationsRefreshAfterCleaning()`
        // right before popping the nav stack; we observe the tick here
        // and refetch stations so the just-cleaned quantity (= 0) lands
        // in the UI without the user having to navigate away and back.
        .onChange(of: router.stationsRefreshAfterCleaningTick) { _ in
            Task { @MainActor in
                let deviceName = ble.getConnectedDeviceName()
                guard !deviceName.isEmpty else { return }
                await viewModel.loadStations(deviceName: deviceName)
            }
        }
        // 1:1 port of UIKit `getStationsDataNotif` NotificationCenter
        // observer on `StationsMenuViewController`. `SelectQuantityView`
        // (the Refill screen) posts a `PendingStationUpdate` via
        // `router.postStationRefill(...)`; we consume it exactly once
        // per post by reading + clearing the parked payload and
        // PUTting the new config via `persistIngredient`.
        .onChange(of: router.getStationsRefillTick) { _ in
            guard let update = router.pendingStationUpdate else { return }
            router.pendingStationUpdate = nil
            Task { @MainActor in
                // UIKit maps the stationName from the payload back to a
                // StationName enum — the SelectQuantityVC may have
                // targeted a specific station different from the one
                // currently selected, so we honour `update.stationName`
                // over `viewModel.selectedStation` when present.
                let targetStation: StationName = {
                    if let s = update.stationName,
                       let match = StationName.allCases.first(
                           where: { $0.rawValue.lowercased() == s.lowercased() }
                       ) { return match }
                    return viewModel.selectedStation
                }()
                await viewModel.persistIngredient(
                    update.ingredientName,
                    quantityMl: update.quantityMl,
                    isPerishable: update.isPerishable,
                    at: targetStation,
                    deviceName: ble.getConnectedDeviceName(),
                    primaryCategory: update.primaryCategory,
                    secondaryCategory: update.secondaryCategory,
                    loadingService: env.loading
                )
            }
        }
        // Image-detection sheet — ports `showActionSheetForImagePicker`.
        .sheet(isPresented: $showImagePicker) {
            BarBotImagePicker(image: $pickedImage,
                              source: imagePickerSource)
                .ignoresSafeArea()
        }
        // When a photo is chosen, simulate the UIKit upload pipeline by
        // showing the ingredient picker. The real
        // `UploadIngredientsImage` POST is plugged in here in production
        // — the picker just needs the resulting `[String]` of detected
        // ingredient names.
        .onChange(of: pickedImage) { newImage in
            guard newImage != nil else { return }
            // Placeholder detection result; replaced by the live API
            // call when the upload service is wired up.
            let detected = ["Vodka", "Gin", "Tequila", "Rum", "Whiskey"]
            popup = .multipleIngredients(
                title: "Pick the detected ingredient",
                ingredients: detected
            )
            pickedImage = nil
        }
        // Unified glass popup overlay (alerts, confirms, ingredient
        // chooser, manual-spinning, waiting, shaker-flat warning).
        .barsysPopup($popup, onPickIngredient: { ingredientName in
            // 1:1 port of UIKit
            // `StationsMenuViewController.getStationsNotificationCame`:
            // after ingredient detection the controller fires a
            // NotificationCenter post → `updateSingleStation` which
            // 1. shows glass loader "Updating Station"
            // 2. PUTs the station config
            // 3. refetches stations
            // 4. hides the loader
            //
            // We mirror that exactly so the SwiftUI callback has the
            // same visible feedback AND the same backend persistence
            // — the previous port only mutated local state which meant
            // the stations reverted on the next `loadStations` call.
            Task { @MainActor in
                await viewModel.persistIngredient(
                    ingredientName,
                    quantityMl: 30,
                    isPerishable: false,
                    at: viewModel.selectedStation,
                    deviceName: ble.getConnectedDeviceName(),
                    loadingService: env.loading
                )
                env.alerts.show(
                    title: "Ingredient added",
                    message: "\(ingredientName) added to Station \(viewModel.selectedStation.rawValue)."
                )
            }
        })
    }

    // Mirrors UIKit's progressMessageButton text (caption1, lightGray).
    private var progressMessage: String {
        viewModel.selectedSlot?.isEmpty == true
            ? Constants.emptyStation
            : Constants.cleaningProcessMessage
    }

    /// 1:1 port of UIKit `computeBottomButtonsState().titleText`:
    ///   • `setupStationsFlow` → `Constants.fillStationsTitle`
    ///   • `controlCenter`     → `Constants.stationsTitle`
    private var titleText: String {
        switch viewModel.origin {
        case .barBot, .recipeCrafting: return Constants.fillStationsTitle
        case .controlCenter:           return Constants.stationsTitle
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // UIKit parity — icon only, 25×25, name label hidden
        // (StationsMenuViewController.swift:123 /
        //  StationCleaningFlowViewController.swift:185 both set
        //  `lblDeviceName.isHidden = true` and never reverse it).
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                Image(deviceIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .accessibilityLabel(deviceKindName)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Shared 100×48 glass pill (iOS 26+) / bare 61×24 icon stack
            // (pre-26). 1:1 UIKit `navigationRightGlassView` parity.
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

    // Bottom action stack — visibility per `computeBottomButtonsState()`.
    @ViewBuilder
    private var bottomActions: some View {
        let isOccupied = viewModel.isSelectedStationOccupied
        let perishableLocking = viewModel.hasPerishableIngredients
        VStack(spacing: 0) {
            switch viewModel.origin {
            case .barBot, .recipeCrafting:
                // 1:1 port of UIKit
                // `StationsMenuViewController.didPressProceedToFillStationsAction`:
                //   → directly calls `updateAllStationsWithRecipeIngredients`
                //     WITHOUT any confirmation popup (UIKit displayed the
                //     "Pour ingredients into the machine" alert ONCE on
                //     screen entry via `isPouringPopUpShownOnce`, not on
                //     the bottom-button tap).
                //
                //   Sequence: PATCH stations → on success pop nav stack
                //   back to MixlistDetailView → clear setup context.
                primaryActionButton(title: Constants.proceedToFillStations,
                                    color: Theme.Color.brand) {
                    HapticService.medium()
                    Task { @MainActor in
                        await persistSetupStations()
                    }
                }
            case .controlCenter:
                // Bottom-action truth table (per latest product spec,
                // cross-checked against UIKit
                // `StationsMenuViewController.setupBottomButtonsUI` +
                // `StationsMenuViewModel.computeBottomButtonsState` +
                // `computeRefillButtonState`):
                //
                //   ┌────────────────────┬──────────┬───────────┬──────────────┐
                //   │ state              │ Clean    │ Refill    │ Add Ingred.  │
                //   ├────────────────────┼──────────┼───────────┼──────────────┤
                //   │ occupied, no peri. │ VISIBLE  │ VISIBLE   │ hidden       │
                //   │                    │          │ enabled   │              │
                //   │ occupied, peri.    │ VISIBLE  │ VISIBLE   │ hidden       │
                //   │                    │          │ DISABLED  │              │
                //   │                    │          │ grey text │              │
                //   │ empty, peri.       │ VISIBLE  │ hidden    │ hidden       │
                //   │                    │ (only)   │           │              │
                //   │ empty, no peri.    │ VISIBLE  │ hidden    │ VISIBLE      │
                //   └────────────────────┴──────────┴───────────┴──────────────┘
                //
                // Rules:
                //   • Clean is ALWAYS VISIBLE in control-center
                //     origin.
                //   • Refill only appears when the selected slot is
                //     occupied. When any station on-screen is
                //     perishable-expired, Refill stays visible but is
                //     disabled with light-grey title colour (UIKit
                //     `btnRefill.setTitleColor(.lightGrayColor)` +
                //     `isUserInteractionEnabled = false`, fill stays
                //     orange via `makeOrangeStyle()`).
                //   • Add Ingredient only appears when the selected
                //     slot is empty AND no perishable-expired station
                //     exists (mirroring UIKit's
                //     `shouldHideAddIngredient == perishableAvailable`
                //     override).
                if isOccupied {
                    // UIKit stack gRn-1d-c0y: spacing=8, distribution=fillEqually.
                    HStack(spacing: 8) {
                        primaryActionButton(title: "Clean", color: Color.white,
                                            textColor: Color("appBlackColor"),
                                            stroke: Color("borderColor")) {
                            router.push(.stationCleaning)
                        }
                        // Refill button — orange fill ALWAYS (matches
                        // UIKit `makeOrangeStyle()` called
                        // unconditionally); text colour drops to
                        // `lightGrayColor` when perishable is present
                        // to signal the disabled state; taps are
                        // blocked via both `.disabled(…)` and the
                        // `guard` inside the action closure.
                        refillButton(perishableLocking: perishableLocking)
                    }
                } else if perishableLocking {
                    // Empty slot + perishable-expired station on
                    // screen → only Clean is actionable. Rendered as
                    // a single full-width Clean button (no companion
                    // in the HStack) so the user's attention is
                    // pinned to the required recovery action.
                    primaryActionButton(title: "Clean", color: Color.white,
                                        textColor: Color("appBlackColor"),
                                        stroke: Color("borderColor")) {
                        router.push(.stationCleaning)
                    }
                } else {
                    // Empty slot + no perishable → Clean AND Add
                    // Ingredient. UIKit's raw visibility logic hides
                    // Clean in this case (it stays at the
                    // `BottomButtonsState.cleanHidden` default of
                    // true for the empty branch), but the product
                    // spec surfaces Clean alongside Add Ingredient so
                    // the user can always reach the cleaning flow
                    // without first having to occupy a station.
                    HStack(spacing: 8) {
                        primaryActionButton(title: "Clean", color: Color.white,
                                            textColor: Color("appBlackColor"),
                                            stroke: Color("borderColor")) {
                            router.push(.stationCleaning)
                        }
                        primaryActionButton(title: "Add Ingredient",
                                            color: Theme.Color.brand) {
                            // UIKit triggers image picker → ingredient detection.
                            // SwiftUI: open the photo picker; the result is
                            // routed through `pickedImage` → detection
                            // pipeline → `BarsysPopup.multipleIngredients`.
                            imagePickerSource = .camera
                            showImagePicker = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [Theme.Color.background.opacity(0), Theme.Color.background],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // 45pt-tall button matching UIKit's bottom-stack convention.
    /// Bottom-bar CTA helper. Brand colour gets the brand gradient
    /// capsule (matches UIKit `PrimaryOrangeButton`); white / other
    /// colours get the gradient-bordered cancel capsule (matches
    /// `applyCancelCapsuleGradientBorderStyle`).
    private func primaryActionButton(title: String,
                                     color: Color,
                                     textColor: Color = .white,
                                     stroke: Color? = nil,
                                     action: @escaping () -> Void) -> some View {
        Button {
            HapticService.light()
            action()
        } label: {
            if color == Theme.Color.brand {
                // Use the dark-mode-aware inlined brand capsule so
                // "Add Ingredient" (+ the sister brand-orange
                // buttons on this screen: "Refill" / "Proceed to Fill
                // Stations") stay the intended peach-tan gradient in
                // dark mode instead of collapsing into the asset's
                // dark-appearance variant (near-black).
                brandOrangeCapsuleLabel(title: title)
            } else {
                Text(title).cancelCapsule(height: 45,
                                          cornerRadius: 22.5,
                                          textColor: textColor)
            }
        }
        .buttonStyle(BounceButtonStyle())
    }

    /// Inlined `brandCapsule(height: 45, cornerRadius: 22.5)` with a
    /// dark-mode-only gradient override + a `textColor` parameter so
    /// callers can grey-out the title (e.g. Refill when a perishable
    /// station is locking the screen) without sacrificing the brand
    /// orange fill. UIKit `btnRefill.setTitleColor(.lightGrayColor)`
    /// + `btnRefill.makeOrangeStyle()` does the same: orange pill,
    /// grey letters when disabled.
    ///
    /// Shared-helper divergence (same reason as other screens):
    /// `brandGradientTop` / `brandGradientBottom` have a
    /// dark-appearance variant that resolves to near-black, which
    /// would make the pill invisible in dark mode. Hard-coded light-
    /// mode RGB in the dark branch keeps the pill orange.
    private func brandOrangeCapsuleLabel(title: String,
                                         textColor: SwiftUI.Color = .black) -> some View {
        let height: CGFloat = 45
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        let gradientColors: [SwiftUI.Color] = colorScheme == .dark
            ? [
                // Explicit light-mode values from
                // brandGradientTop.colorset / brandGradientBottom.colorset.
                SwiftUI.Color(red: 0.980, green: 0.878, blue: 0.800),
                SwiftUI.Color(red: 0.949, green: 0.761, blue: 0.631)
            ]
            : [
                // Light mode — unchanged, resolves via the existing
                // colour assets so light-mode pixels stay bit-
                // identical to the existing UIKit-parity rendering.
                SwiftUI.Color("brandGradientTop"),
                SwiftUI.Color("brandGradientBottom")
            ]
        return Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        RoundedRectangle(cornerRadius: height / 2,
                                         style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 22.5,
                                         style: .continuous)
                            .fill(Theme.Color.segmentSelection)
                    }
                }
            )
            .barsysShadow(.floatingButton)
    }

    /// Refill button — 1:1 port of UIKit
    /// `StationsMenuViewController.setBottomButtonsAccordingToPerishableCount`
    /// (L162-172) + `computeRefillButtonState` (L250-257):
    ///
    ///   • Fill: ALWAYS brand orange. UIKit calls
    ///     `btnRefill.makeOrangeStyle()` unconditionally, so the pill
    ///     never fades to grey — only the title does.
    ///   • Text: `.lightGrayColor` when any perishable-expired
    ///     station exists anywhere on screen, `.black` otherwise.
    ///     Mirrors UIKit
    ///     `setTitleColor(perishableAvailable ? .lightGrayColor :
    ///     .black, for: .normal)`.
    ///   • Taps: disabled when perishable. Belt-and-braces with a
    ///     `guard !perishableLocking` inside the action, matching
    ///     UIKit's `btnRefill.isUserInteractionEnabled = refillState.isEnabled`.
    @ViewBuilder
    private func refillButton(perishableLocking: Bool) -> some View {
        // `lightGrayColor` asset resolves to UIKit
        // `#999999` in light / `#8E8E93` in dark — same asset UIKit
        // uses for `.lightGrayColor`.
        let titleColor: SwiftUI.Color = perishableLocking
            ? SwiftUI.Color("lightGrayColor")
            : SwiftUI.Color.black
        Button {
            HapticService.light()
            // 1:1 port of UIKit
            // `StationsMenuViewController.didPressRefillButton`:
            //   let flowToAdd = viewModel.flowForRefill()
            //   ControlCenterCoordinator(…).showSelectQuantity(...)
            guard !perishableLocking else { return }
            let slot = viewModel.selectedSlot
            router.pendingStationUpdate = AppRouter.PendingStationUpdate(
                ingredientName: slot?.ingredientName ?? "",
                quantityMl: slot?.ingredientQuantity ?? 0,
                primaryCategory: nil, // category not modelled on StationSlot
                secondaryCategory: nil,
                isPerishable: slot?.isPerishable ?? false,
                isAddingNewIngredient: false,
                stationName: viewModel.selectedStation.rawValue
            )
            router.push(.selectQuantity(slot?.ingredientName
                ?? viewModel.selectedStation.rawValue))
        } label: {
            brandOrangeCapsuleLabel(title: "Refill", textColor: titleColor)
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(perishableLocking)
    }

    /// Commit the mapped-setup stations to the server, then pop back
    /// to the mixlist detail so the user can tap "Craft" on any
    /// recipe.
    ///
    /// 1:1 port of UIKit
    /// `StationsMenuViewModel+StationSetup.updateAllStationsWithRecipeIngredients`:
    ///   • Build the full `configuration.stations` dict.
    ///   • PATCH `{baseURL}devices/device-number/{deviceName}`.
    ///   • On success, UIKit refetches stations then navigates to
    ///     `ReadyToPourListViewController`. In SwiftUI we pop back to
    ///     MixlistDetailView (the user's previous screen) which
    ///     already shows the mixlist's recipes with working Craft
    ///     buttons — architecturally equivalent without adding a
    ///     dedicated "Ready To Pour" listing.
    @MainActor
    private func persistSetupStations() async {
        let deviceName = ble.getConnectedDeviceName()
        guard !deviceName.isEmpty else {
            env.alerts.show(title: Constants.deviceNotConnected)
            return
        }
        env.loading.show("Saving stations…")
        let ok = await StationsAPIService.patchAllStations(
            deviceName: deviceName,
            stations: viewModel.stations
        )
        env.loading.hide()
        guard ok else {
            env.alerts.show(title: "Setup failed",
                            message: "Couldn't save stations. Please try again.")
            return
        }
        // Clear the transient setup context — the flow is complete.
        router.setupStationsContext = nil
        HapticService.success()
        // Pop back to MixlistDetailView.
        dismiss()
    }
}

// MARK: - Station selector card (shared by Stations menu + Cleaning flow)

struct StationSelectorCard: View {
    let stations: [StationSlot]
    let selected: StationName
    let progressMessage: String
    let ingredientName: String
    let onSelect: (StationName) -> Void

    var body: some View {
        // UIKit uses NON-UNIFORM spacing inside the card. Storyboard
        // offsets (from selectStationView top):
        //   "Select Station" title:  y=16   (top padding)
        //   Station buttons:         y=55   (title→buttons gap = 20pt)
        //   Station image:           y=111  (buttons→image gap = 26pt)
        //   Ingredient name:         y=362  (image→ingredient gap = 5pt)
        //   Progress message:        y=400  (ingredient→progress gap = 0)
        VStack(alignment: .leading, spacing: 0) {
            Text("Select Station")
                // UIKit: system 16pt (storyboard `lpp-uw-aEx`), appBlackColor
                .font(.system(size: 16))
                .foregroundStyle(Color("appBlackColor"))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Title → buttons: 20pt gap
            Spacer().frame(height: 20)

            // 1:1 port of UIKit `updateStationNameSelectionUI` +
            // storyboard A-F button stack (`e3w-KK-sLe` distribution
            // `equalSpacing`, buttons tag 1-6, size 30×30, font 18pt):
            //   Title color stays BLACK in every state (storyboard default).
            HStack(spacing: 0) {
                ForEach(Array(StationName.allCases.enumerated()),
                        id: \.element) { idx, st in
                    let isSelected = selected == st
                    Button {
                        HapticService.selection()
                        onSelect(st)
                    } label: {
                        Text(st.rawValue)
                            .font(.system(size: 18))
                            // Trait-resolved at draw time: light branch
                            // returns EXACT pure black (`UIColor.black`,
                            // bit-identical to the previous hard-coded
                            // `Color.black`); dark branch returns near-
                            // white so the station-number digit stays
                            // legible on the dark Control Center
                            // background AND on the orange selected
                            // circle.
                            .foregroundStyle(Color(UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                    ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                                    : UIColor.black // EXACT historical
                            }))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle().fill(
                                    isSelected
                                        ? Color("sideMenuSelectionColor")
                                        : Color.clear
                                )
                            )
                            .overlay(
                                Circle().stroke(
                                    isSelected
                                        ? Color.clear
                                        // Same adaptive treatment as the
                                        // text — preserves the EXACT
                                        // historical black ring in light
                                        // and switches to a near-white
                                        // ring in dark for visibility on
                                        // the dark page background.
                                        : Color(UIColor { trait in
                                            trait.userInterfaceStyle == .dark
                                                ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                                                : UIColor.black // EXACT historical
                                        }),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Station \(st.rawValue)")

                    if idx < StationName.allCases.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Buttons → image: 26pt gap
            Spacer().frame(height: 26)

            // Station diagram — UIKit: 279×246, scaleAspectFit
            Image("station\(selected.rawValue)")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 246)

            // Image → ingredient name: 5pt gap
            Spacer().frame(height: 5)

            // Top border separator above ingredient name (UIKit: 24B-uV-JXg)
            Rectangle()
                .fill(Color("borderColor"))
                .frame(height: 1)

            // Ingredient name — UIKit: 12pt system, black text,
            // user interaction disabled, height 38pt
            Text(ingredientName.isEmpty ? "—" : ingredientName)
                .font(Theme.Font.of(.caption1))
                .foregroundStyle(Color("appBlackColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38)

            // Bottom border separator (UIKit: PlR-w6-kk7) above progress message
            Rectangle()
                .fill(Color("borderColor"))
                .frame(height: 1)

            // Progress message — UIKit: 12pt system, black text,
            // height 45pt, user interaction disabled
            Text(progressMessage)
                .font(Theme.Font.of(.caption1))
                .foregroundStyle(Color("appBlackColor"))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 45)
        }
        // UIKit inner padding: 24pt horizontal, 16pt top, 0pt bottom
        // (progress message extends to card bottom edge)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color("borderColor"), lineWidth: 1)
        )
    }
}

// MARK: - Station cleaning flow table row (ports StationCleaningFlowTableViewCell)
//
// XIB measurements (cell 375×63):
//   • viewGlass:      x=0  y=6  w=375 h=51 (glass effect, xlarge corners)
//   • stationLabel:   x=24 y=18.67 w=80 h=14, caption1 (12pt)
//   • ingredientLabel: x=109 y=5 w=146 h=41, caption1 multiline
//   • quantityLabel:  x=260 y=18.67 w=91 h=14, caption1 right-aligned
//
// Selection / colour rules — 1:1 port of
// `StationCleaningFlowViewController+TableView.swift` cellForRowAt
// (L43-70). The cell ONLY communicates state through text colour +
// font weight:
//   • selected  → `.charcoalGrayColor` + semibold caption1
//   • normal    → `.lightGrayColor`   + regular caption1
//   • perishable → `.perishableColor` + regular caption1
// The UIKit cell sets `selectedBackgroundView?.backgroundColor =
// .sideMenuSelectionColor` AND `setSelected` overrides `selectionStyle
// = .none`, which suppresses the tinted highlight entirely — so the
// row NEVER gets a persistent background tint. Mirror that here by
// keeping the background identical regardless of `isSelected`.
//
// Glass / gradient rules — 1:1 port of the #available branch:
//   • iOS 26+   → `addGlassEffect(cornerRadius: xlarge=20, alpha:1.0)`
//                 which is a UIGlassEffect(.regular) visual effect view
//                 at 20pt corners, no border.
//   • iOS < 26  → roundCorners = pill=24, 1pt #F2F2F2 border, +
//                 `addGradientLayer(colors: [.black@0.1, .white@0.1])`
//                 (default startPoint (0,0) → endPoint (1,1), diagonal
//                 top-leading → bottom-trailing).
struct StationCleaningFlowTableRow: View {
    let slot: StationSlot
    let isSelected: Bool
    let unit: MeasurementUnit

    private var displayQuantity: String {
        guard !slot.isEmpty else { return "" }
        switch unit {
        case .ml: return String(format: "%.0f ml", slot.ingredientQuantity)
        case .oz: return String(format: "%.2f oz", slot.ingredientQuantity / 29.5735)
        }
    }

    /// 1:1 port of UIKit `cellColorState(for:)` → `switch` at L46-55
    /// in `StationCleaningFlowViewController+TableView.swift`.
    /// Perishable always wins; otherwise selected drives charcoal,
    /// unselected drives light grey.
    private var textColor: Color {
        if slot.isPerishable { return Color("perishableColor") }
        return isSelected ? Color("charcoalGrayColor") : Color("lightGrayColor")
    }

    /// 1:1 port of UIKit L44: selected → semibold caption1, otherwise
    /// regular caption1. Perishable stations use the regular weight
    /// (the UIKit code applies weight based on selection only).
    private var rowFont: Font {
        isSelected
            ? Theme.Font.of(.caption1, .semibold)
            : Theme.Font.of(.caption1)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Station label (e.g. "Station A")
            // UIKit: x=24 w=80 — but row now has 24pt horizontal padding
            // from the parent, so inner leading is relative to the cell edge.
            Text("Station \(slot.station.rawValue)")
                .font(rowFont)
                .foregroundStyle(textColor)
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 16)

            // Ingredient name (multi-line, caption1)
            Text(slot.isEmpty ? "—" : slot.ingredientName)
                .font(rowFont)
                .foregroundStyle(textColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)

            // Quantity (right-aligned)
            Text(displayQuantity)
                .font(rowFont)
                .foregroundStyle(textColor)
                .frame(width: 91, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 51)
        .background(StationCleaningRowBackground())
        .padding(.vertical, 6)
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Station \(slot.station.rawValue), \(slot.isEmpty ? "empty" : slot.ingredientName), \(displayQuantity)")
    }
}

/// 1:1 port of the version-gated glass / gradient block in
/// `StationCleaningFlowViewController+TableView.swift` L63-70:
///
/// ```
/// if #available(iOS 26.0, *) {
///     cell.viewGlass.addGlassEffect(cornerRadius: BarsysCornerRadius.xlarge, alpha: 1.0)
/// } else {
///     cell.viewGlass.roundCorners = BarsysCornerRadius.pill
///     cell.viewGlass.layer.borderWidth = 1.0
///     cell.viewGlass.addGradientLayer(colors: [UIColor.black.withAlphaComponent(0.1),
///                                              UIColor.white.withAlphaComponent(0.1)])
///     cell.viewGlass.layer.borderColor = UIColor.init(hex: "#F2F2F2").cgColor
/// }
/// ```
///
/// Selection does NOT change the background — UIKit sets
/// `selectionStyle = .none` in `setSelected(_:animated:)` which
/// suppresses `selectedBackgroundView`.  Text colour + font weight
/// are the sole selection affordance.
private struct StationCleaningRowBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            // `addGlassEffect(cornerRadius: xlarge=20, alpha: 1.0)` —
            // UIGlassEffect(.regular). No border (isBorderEnabled
            // defaults to false and the UIKit call site relies on the
            // default). `.regularMaterial` is the documented SwiftUI
            // bridge.
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .fill(.regularMaterial)
        } else {
            // Pre-iOS 26: 24pt corner, 1pt solid #F2F2F2 border, and a
            // diagonal (top-leading → bottom-trailing) gradient layer
            // from black@10% to white@10%. UIKit's
            // `addGradientLayer` defaults to startPoint (0,0) and
            // endPoint (1,1) — matched by `.topLeading` / `.bottomTrailing`.
            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.1),
                                 Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        // #F2F2F2 = 242,242,242 sRGB.
                        .stroke(Color(red: 242.0 / 255.0,
                                      green: 242.0 / 255.0,
                                      blue: 242.0 / 255.0),
                                lineWidth: 1)
                )
        }
    }
}

// MARK: - StationCleaningFlowViewModel

/// Ports UIKit `BackPressState` (StationCleaningFlowViewController.swift).
/// `.handling` blocks navigation pop while the device acks a stop/cancel
/// command sent in response to the user pressing back during a dispense.
enum BackPressState { case ready, handling }

@MainActor
final class StationCleaningFlowViewModel: ObservableObject {
    @Published var currentFlow: CleaningFlow = .initialEmptySetup
    @Published var processState: CleaningProcessState = .idle
    @Published var cleaningMode: CleaningMode = .clean
    @Published var selectedStation: StationName = .a
    @Published var progress: Double = 0
    @Published var backPressState: BackPressState = .ready
    @Published var isLoading: Bool = false
    @Published var stations: [StationSlot] = StationName.allCases.map {
        StationSlot(station: $0, ingredientName: "", ingredientQuantity: 0, isPerishable: false)
    }

    // MARK: - Alert triggers (ports UIKit `onShow…Alert` callbacks)
    //
    // UIKit routes these through the delegate callbacks
    // `onShowPerishableCleanedAlert` and `onShowDifferentStationsAlert`
    // on the ViewModel; the VC's `bindViewModel()` wires them to
    // `showCustomAlert(…)`. In SwiftUI we surface them as published
    // triggers that `StationCleaningView.onChange(of:)` observes and
    // forwards to the shared `env.alerts` overlay.

    /// Set to `true` once the cleaning flow lands on a perishable
    /// station's cleanComplete — view picks it up and shows the
    /// "Perishable Ingredients Cleaned" alert → pop.
    @Published var shouldShowPerishableCleanedAlert: Bool = false

    /// Payload for the "Proceed to clean" different-stations alert.
    /// Non-nil means the view should show the alert; the view clears
    /// it after presentation.
    @Published var pendingDifferentStationAlert: DifferentStationAlertPayload?

    /// Strongly-typed payload for the different-station alert, mirroring
    /// UIKit `onShowDifferentStationsAlert = { stationNamesStr, stationName in … }`.
    struct DifferentStationAlertPayload: Equatable {
        /// Comma-joined display string for the alert body, e.g. "A, C".
        let stationNamesDisplay: String
        /// Station the user was trying to act on — passed back to
        /// `handleDifferentStationAlertContinue` on confirm.
        let targetStation: StationName
    }

    /// 1:1 port of UIKit
    /// `viewModel.handleDifferentStationAlertContinue(stationName:)`:
    /// flips the selected station, resets the flow to the initial empty
    /// setup state, and restarts the cleaning sequence so the conflict
    /// can be resolved before the user continues. UIKit then invokes
    /// `applyFlowUI(.initialEmptySetup)` + `tableView.reloadData()`,
    /// which SwiftUI does automatically via `@Published` bindings.
    func handleDifferentStationAlertContinue(targetStation: StationName) {
        selectedStation = targetStation
        currentFlow = .initialEmptySetup
        processState = .idle
    }

    /// Ports UIKit `MixlistsUpdateClass().getStationsHere { … }` wrapping
    /// `StationsServiceApi.getStationsFromServer`. The cleaning screen
    /// needs real station data to decide whether to flush (ingredient
    /// quantity > 0) or go straight to clean mode.
    func loadStations(deviceName: String) async {
        guard !deviceName.isEmpty else { return }
        isLoading = true
        let fetched = await StationsAPIService.loadStations(deviceName: deviceName)
        isLoading = false
        guard !fetched.isEmpty else { return }
        var merged = stations
        for slot in fetched {
            if let idx = merged.firstIndex(where: { $0.station == slot.station }) {
                merged[idx] = slot
            }
        }
        stations = merged
    }

    /// Demo simulator timer used only when no real device is connected,
    /// so the UI is still walkable. Disabled when `BLEService.lastResponse`
    /// drives the state machine.
    private var simulatorTimer: Timer?
    private var useSimulator: Bool = true

    var isSelectedStationEmpty: Bool {
        stations.first(where: { $0.station == selectedStation })?.isEmpty ?? true
    }

    /// Ports `selectedStationLabel()` from UIKit ViewModel — caption1 text
    /// shown under the station card.
    var progressMessage: String {
        switch currentFlow {
        case .initialEmptySetup:
            return isSelectedStationEmpty ? Constants.emptyStation : Constants.cleaningProcessMessage
        case .placeGlassStart, .placeGlassAfterPourCleaningSolution:
            return Constants.placeGlass
        case .dispensingInProgress:
            return cleaningMode == .flush ? Constants.flushingInProgress : Constants.cleaningInProgress
        case .pourCleaningSolution: return Constants.pourCleaningSolution
        case .cleaningComplete: return Constants.cleaningComplete
        case .removeGlassAndContinue: return Constants.removeGlass
        case .cancelled: return ""
        }
    }

    enum CleaningButton { case clean, cancel, pause, stop, `continue` }

    /// 1:1 port of UIKit
    /// `StationCleaningFlowViewModel.visibleButtons(for flow:)`:
    ///
    /// ```
    /// case .initialEmptySetup, .cleaningComplete  → [.clean]
    /// case .placeGlassStart,
    ///      .placeGlassAfterPourCleaningSolution   → [.cancel]
    /// case .dispensingInProgress                  → [.pause, .stop]
    /// case .pourCleaningSolution                  → [.continue]
    /// case .removeGlassAndContinue, .cancelled    → []
    /// ```
    ///
    /// `.cancelled` returning EMPTY is important — UIKit hides all
    /// buttons while waiting for the `cancelAcknowledged` / data-flushed
    /// round-trip, which then flips the flow back to `.initialEmptySetup`
    /// and the Clean button re-appears. Returning `[.clean]` here would
    /// let the user tap Clean before the device finished acknowledging.
    func visibleButtons() -> Set<CleaningButton> {
        switch currentFlow {
        case .initialEmptySetup, .cleaningComplete: return [.clean]
        case .placeGlassStart, .placeGlassAfterPourCleaningSolution: return [.cancel]
        case .dispensingInProgress: return [.pause, .stop]
        case .pourCleaningSolution: return [.continue]
        case .removeGlassAndContinue, .cancelled: return []
        }
    }

    /// Ports UIKit `stationChangeAllowedFlows` guard — user can only switch
    /// stations when nothing is in flight on the device.
    private static let stationChangeAllowedFlows: Set<CleaningFlow> = [
        .initialEmptySetup, .pourCleaningSolution, .cleaningComplete, .cancelled
    ]

    func selectStation(_ station: StationName) {
        guard Self.stationChangeAllowedFlows.contains(currentFlow) else { return }
        currentFlow = .initialEmptySetup
        processState = .idle
        selectedStation = station
    }

    // MARK: - Button taps (mirror UIKit +BleCommands extension)

    /// Ports `prepareCleanInitiation()` — branches on remaining ingredient
    /// quantity to choose flush vs clean mode.
    func tapClean(ble: BLEService) {
        processState = .idle
        useSimulator = !ble.isAnyDeviceConnected
        let station = stations.first { $0.station == selectedStation }
        if let station, station.ingredientQuantity > 0 {
            cleaningMode = .flush
            currentFlow = .placeGlassStart
            _ = ble.send(.flushStation(stationNumber: selectedStation.tag))
            startSimulatorIfNeeded()
        } else {
            cleaningMode = .clean
            currentFlow = .pourCleaningSolution
        }
    }

    /// Ports `prepareContinueAfterPourSolution()` — second phase after the
    /// user pours cleaning solution and taps Continue.
    func tapContinueAfterPourSolution(ble: BLEService) {
        guard currentFlow == .pourCleaningSolution else { return }
        cleaningMode = .clean
        currentFlow = .placeGlassStart
        _ = ble.send(.flushStation(stationNumber: selectedStation.tag))
        startSimulatorIfNeeded()
    }

    func tapPause(ble: BLEService) {
        processState = .paused
        ble.send(.pauseDispense)
        simulatorTimer?.invalidate()
    }

    func tapStop(ble: BLEService) {
        processState = .cancelling
        ble.send(.stopDispense)
        simulatorTimer?.invalidate()
        currentFlow = .initialEmptySetup
        progress = 0
    }

    /// 1:1 port of UIKit `didPressCancelButton(_:)` +
    /// `viewModel.handleCancel()`:
    ///   • When dispensing → `.stopDispense` (same as Stop, graceful).
    ///   • Otherwise        → `.cancel`.
    ///
    /// Both variants keep `processState = .cancelling` so the next BLE
    /// response transitions correctly.
    func tapCancel(ble: BLEService) {
        processState = .cancelling
        if currentFlow == .dispensingInProgress {
            ble.send(.stopDispense)
        } else {
            ble.send(.cancel)
        }
        simulatorTimer?.invalidate()
        // Don't prematurely flip `currentFlow` — wait for the device's
        // cancelAcknowledged / stationCleanAcknowledged response to drive
        // the final transition (UIKit relies on that round-trip).
        progress = 0
    }

    /// Ports UIKit `handleBackPress()` — returns whether the nav stack can
    /// pop immediately. If a dispense is active, the back press sends
    /// `stopDispense` first and waits for the device's
    /// `cancelAcknowledged` / `glassRemoved` response before popping.
    func handleBackPress(ble: BLEService) -> Bool {
        if processState == .dispensing {
            backPressState = .handling
            ble.send(.stopDispense)
            return false
        }
        if processState == .paused || currentFlow == .placeGlassStart
            || currentFlow == .placeGlassAfterPourCleaningSolution {
            backPressState = .handling
            ble.send(.cancel)
            return false
        }
        return true
    }

    // MARK: - BLE response routing
    //
    // 1:1 port of UIKit `StationCleaningFlowViewController+BleResponse.swift`.
    // The view subscribes to `ble.$lastResponse` and forwards each event
    // to `dispatch(_:ble:)` which mutates the state machine.

    // 1:1 port of UIKit `StationCleaningFlowViewController+BleResponse.swift`.
    //
    // Stale-response guard (UIKit L21): ignore responses when the
    // cleaning session hasn't started yet (processState==.idle AND
    // currentFlow==.initialEmptySetup). Without this, leftover frames
    // from a previous dispense can flip the fresh VC's state before the
    // user hits Clean.
    //
    // BLE events handled (firmware codes in comments):
    //   "218,{n},405"  → dispensingStarted(n)       → .dispensingInProgress
    //   "210,401" / "217,40{1,2,5}" → glassLifted    → placeGlass{Start|AfterPour}
    //   "217,401" / "219,401" → glassPlaced         → .dispensingInProgress
    //   "202,401"             → cancelAcknowledged  → popBack or .cancelled
    //   "227,406"             → dispensePaused      → (no-op)
    //   "221,405"             → allIngredientsPoured → .removeGlassAndContinue
    //   "227,496"             → glassRemovedDuringDispense → (no-op per UIKit)
    //   "219,405"             → glassWaiting        → placeGlassAfterPour
    //   "221,401"             → glassRemoved        → complex branching
    //   "227,401"             → cleanComplete       → delayed 1.5s transition
    //   "227,{n},401"         → stationCleanAcknowledged → cancelling flip
    func dispatch(_ response: BleResponse, ble: BLEService) {
        // Stale-response guard (UIKit L21).
        guard processState != .idle || currentFlow != .initialEmptySetup else { return }

        let stationNumber = selectedStation.tag

        switch response {
        case .dispensingStarted(let n) where n == stationNumber:
            currentFlow = .dispensingInProgress
            processState = .dispensing
            simulatorTimer?.invalidate() // real device taking over

        case .glassLifted:
            // 210,401 / 217,402 / 217,405 — Waiting / Glass lift detected.
            if processState == .dispensing || processState == .paused {
                currentFlow = .placeGlassAfterPourCleaningSolution
            } else {
                currentFlow = .placeGlassStart
            }

        case .glassPlaced:
            // 217,401 / 219,401 — Glass Placed / Glass Detected → resume dispense.
            currentFlow = .dispensingInProgress

        case .cancelAcknowledged:
            // 202,401 — device acknowledged cancel. If back-press was in
            // flight and we weren't paused, the UIKit VC pops the nav
            // stack here. We expose a flag the view can observe + pop.
            if backPressState == .handling && processState != .paused {
                currentFlow = .cancelled
                processState = .idle
                return
            }
            currentFlow = .cancelled

        case .dispensePaused:
            // 227,406 — paused ack. No state change (UIKit: `break`).
            break

        case .allIngredientsPoured:
            // 221,405 — Remove Glass.
            currentFlow = .removeGlassAndContinue

        case .glassRemovedDuringDispense:
            // 227,496 — glass removed by user while dispensing.
            // UIKit explicitly does NOTHING here (`break`), so neither do we.
            break

        case .glassWaiting:
            // 219,405 — waiting for the glass.
            currentFlow = .placeGlassAfterPourCleaningSolution

        case .glassRemoved:
            // 221,401 — complex branching based on process + cleaning mode.
            handleGlassRemovedDuringCleaning(ble: ble)
            return // handleGlassRemovedDuringCleaning emits the final UI flip.

        case .cleanComplete:
            // 227,401 — the critical event. UIKit delays 1.5s before the
            // UI flip so the device has time to seat the glass arm.
            simulatorTimer?.invalidate()
            scheduleCleanCompleteTransition(ble: ble)
            return

        case .stationCleanAcknowledged(let n) where n == stationNumber:
            // 227,{stationNumber},401 — per-station ack. When we sent a
            // stop during flush or clean, this is the signal to reset
            // back to initial empty setup (UIKit L96-109).
            if cleaningMode == .flush {
                if processState == .cancelling {
                    cleaningMode = .clean
                    currentFlow = .initialEmptySetup
                    processState = .idle
                }
            } else {
                if processState == .cancelling {
                    currentFlow = .initialEmptySetup
                    processState = .idle
                }
            }

        default:
            break
        }
    }

    /// UIKit `DelayedAction.afterBleResponse(seconds: 1.5)` before UI
    /// flips on cleanComplete — gives the device time to seat the glass
    /// arm before we swap labels.
    private func scheduleCleanCompleteTransition(ble: BLEService) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            // Capture perishable state BEFORE we mutate the station —
            // UIKit's `onShowPerishableCleanedAlert` callback fires
            // when the cleaned station was flagged perishable, and it
            // needs the pre-reset state to make the decision.
            let cleanedWasPerishable = self.stations.first(
                where: { $0.station == self.selectedStation }
            )?.isPerishable == true
            if self.cleaningMode == .flush {
                self.cleaningMode = .clean
                self.currentFlow = .pourCleaningSolution
                // UIKit calls `updateStation(stationName:)` after flush
                // completes to persist the zeroed quantity server-side.
                Task { [ble] in
                    await self.persistFlushComplete(ble: ble)
                }
            } else {
                self.currentFlow = .cleaningComplete
                // UIKit calls `removeStation(stationName:)` after full
                // clean completes so the station goes back to empty.
                Task { [ble] in
                    await self.persistCleanComplete(ble: ble)
                }
                // 1:1 port of UIKit `onShowPerishableCleanedAlert`:
                // after a full clean on a station that was holding a
                // perishable ingredient, the flow presents the
                // "Perishable Ingredients Cleaned" alert and pops back
                // to the Stations menu when the user dismisses it.
                if cleanedWasPerishable {
                    self.shouldShowPerishableCleanedAlert = true
                }
            }
            self.progress = 1.0
        }
    }

    /// Ports UIKit `handleGlassRemovedDuringCleaning` — the 221,401
    /// response has 3-way branching on paused / cancelling / running.
    private func handleGlassRemovedDuringCleaning(ble: BLEService) {
        // Paused → go back to "place glass after pour" screen.
        if processState == .paused {
            currentFlow = .placeGlassAfterPourCleaningSolution
            return
        }
        // Cancelling or running (not paused) both converge on:
        //   • flush mode → finish flush, transition to pourCleaningSolution,
        //                  persist the flush update on the server.
        //   • clean mode → finalize clean, transition to cleaningComplete,
        //                  remove station on the server.
        if cleaningMode == .flush {
            cleaningMode = .clean
            currentFlow = .pourCleaningSolution
            Task { [ble] in await self.persistFlushComplete(ble: ble) }
        } else {
            currentFlow = .cleaningComplete
            Task { [ble] in await self.persistCleanComplete(ble: ble) }
        }
    }

    /// After a FLUSH cycle, UIKit calls `updateStation(stationName:)`
    /// which PUTs the same station config WITH quantity cleared. We
    /// mirror that with `StationsAPIService.updateStation(...)`.
    ///
    /// Bug fix (perishable timer reset):
    /// UIKit `StationsServiceApi.updateStation(..., isupdatedDateNeeded:
    /// true, ...)` (L62-63) sends the ORIGINAL `updated_at` timestamp
    /// back to the server so the perishable 24-hour expiry counter
    /// doesn't reset every time the user refills / flushes. Earlier
    /// SwiftUI port passed `updated_at: nil`, which caused the server
    /// to stamp `Date.now` and silently re-extend perishable timers.
    /// Now we forward the slot's `updatedAt` so the expiry stays tied
    /// to when the user *actually* poured the ingredient in.
    private func persistFlushComplete(ble: BLEService) async {
        guard let idx = stations.firstIndex(where: { $0.station == selectedStation })
        else { return }
        let slot = stations[idx]
        // Match UIKit `buildUpdateStationConfig`:
        //   metric=ML, quantity=0, ingredient_name=slot.ingredientName,
        //   is_perishable=slot.isPerishable,
        //   category=slot.category,
        //   updated_at=slot.updatedAt (preserved for perishable parity).
        let category: StationsAPIService.StationUpdateBody.CategoryPayload? =
            slot.category.map {
                .init(primary: $0.primary,
                      secondary: $0.secondary,
                      flavour_tags: $0.flavourTags)
            }
        let body = StationsAPIService.StationUpdateBody(
            metric: "ML",
            quantity: "0",
            ingredient_name: slot.ingredientName.isEmpty ? nil : slot.ingredientName,
            is_perishable: slot.isPerishable,
            category: category,
            // Perishable? Preserve the original server timestamp.
            // Non-perishable? Let the server stamp Date.now (nil → omit).
            updated_at: slot.isPerishable ? slot.updatedAt : nil
        )
        let deviceName = ble.getConnectedDeviceName()
        _ = await StationsAPIService.updateStation(deviceName: deviceName,
                                                   station: selectedStation,
                                                   body: body)
        await MainActor.run {
            self.stations[idx].ingredientQuantity = 0
        }
    }

    /// After a full CLEAN cycle, UIKit calls `removeStation(stationName:)`
    /// which wipes the station (ingredient_name=nil, quantity=0, category
    /// empty, is_perishable=false).
    private func persistCleanComplete(ble: BLEService) async {
        let deviceName = ble.getConnectedDeviceName()
        _ = await StationsAPIService.removeStation(deviceName: deviceName,
                                                   station: selectedStation)
        await MainActor.run {
            if let idx = self.stations.firstIndex(where: { $0.station == self.selectedStation }) {
                self.stations[idx].ingredientName = ""
                self.stations[idx].ingredientQuantity = 0
                self.stations[idx].isPerishable = false
            }
        }
    }

    // MARK: - Demo simulator (only when no real device)
    //
    // When no physical Barsys is paired, the cleaning flow needs
    // something to drive `progress` so the UI is walkable in the
    // simulator. We mimic the firmware's "cleanComplete" event by
    // flipping state locally when progress hits 1.0 — this is the
    // same final state `handleCleanFinishedLocally` used to produce
    // before the full UIKit state-machine port was landed.
    //
    // Note: NO server-side persistence here (no device = no stations
    // to update). Real-device flows still go through
    // `persistFlushComplete` / `persistCleanComplete` via `dispatch`.
    private func startSimulatorIfNeeded() {
        guard useSimulator else { return }
        currentFlow = .dispensingInProgress
        processState = .dispensing
        progress = 0
        simulatorTimer?.invalidate()
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                guard self.processState == .dispensing else { return }
                self.progress = min(self.progress + 0.01, 1)
                if self.progress >= 1 {
                    t.invalidate()
                    self.finishSimulatedClean()
                }
            }
        }
    }

    /// Simulator-only clean completion. Mirrors the final state the
    /// real-device path reaches via `scheduleCleanCompleteTransition` /
    /// `handleGlassRemovedDuringCleaning`, but without the API calls:
    ///   • FLUSH → promote to CLEAN mode, ask user to pour cleaning
    ///            solution.
    ///   • CLEAN → flip to `.cleaningComplete`, wipe the selected
    ///            station locally.
    private func finishSimulatedClean() {
        if let idx = stations.firstIndex(where: { $0.station == selectedStation }) {
            stations[idx].ingredientQuantity = 0
            stations[idx].ingredientName = ""
            stations[idx].isPerishable = false
        }
        if cleaningMode == .flush {
            cleaningMode = .clean
            currentFlow = .pourCleaningSolution
            processState = .idle
            progress = 0
        } else {
            currentFlow = .cleaningComplete
            processState = .idle
            progress = 1.0
        }
    }
}

/// Lightweight no-op fallback used by the demo simulator path when the
/// real `BLEService` instance isn't reachable from a Timer closure.
private extension BLEService {
    static let simulatedFallback: BLEService = .init()
}

// MARK: - StationCleaningView (1:1 port of `StationCleaningFlowViewController`)
//
// UIKit reference (ControlCenter.storyboard scene IHa-G7-R7V):
//   • 60pt nav bar (back + device + favorite + glass profile)
//   • Reuses the StationSelectorCard so users can switch stations between
//     cleans without leaving the screen.
//   • Inline status table — 6 stations, current ingredient + quantity.
//   • Bottom dynamic CTAs driven by `CleaningFlow`:
//       initialEmptySetup / cleaningComplete  → [Clean]
//       placeGlass*                           → [Cancel]
//       dispensingInProgress                  → [Pause, Stop]
//       pourCleaningSolution                  → [Continue]
//   • BLE commands sent at each transition:
//       Clean (qty>0) → flush mode → flushStation(n)
//       Clean (qty=0) → clean mode → pourCleaningSolution prompt → Continue
//                     → flushStation(n)
//       Pause         → pauseDispense
//       Stop          → stopDispense (resets to setup)
//       Cancel        → cancel
//   • Flush→Clean two-phase: after flush completes, automatically transitions
//     to clean mode and re-prompts for cleaning solution.

struct StationCleaningView: View {
    @StateObject private var viewModel = StationCleaningFlowViewModel()
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService
    /// Reactive theme awareness — used ONLY by the brand-orange
    /// action buttons ("Clean" / "Stop") to override the
    /// dark-appearance variant of the `brandGradientTop` /
    /// `brandGradientBottom` colour assets (which wrongly resolve to
    /// dark grey / near-black in dark mode) back to the light-mode
    /// orange RGB so the capsule stays readable in dark mode.
    /// Light mode is untouched.
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1:1 port of storyboard `vua-fG-0F6`:
                //   text="Clean Stations" (plural)
                //   system 24pt (regular, NOT bold)
                //   textColor `appBlackColor`
                //   leading 24pt
                Text("Clean Stations")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                StationSelectorCard(
                    stations: viewModel.stations,
                    selected: viewModel.selectedStation,
                    progressMessage: viewModel.progressMessage.isEmpty
                        ? Constants.cleaningProcessMessage
                        : viewModel.progressMessage,
                    ingredientName: viewModel.stations
                        .first { $0.station == viewModel.selectedStation }?
                        .ingredientName ?? "",
                    onSelect: { viewModel.selectStation($0) }
                )
                .padding(.horizontal, 24)

                // Progress ring — visible only during the dispensing phase.
                if viewModel.processState == .dispensing
                    || viewModel.currentFlow == .dispensingInProgress {
                    progressRing
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }

                // Inline 6-row station table (read-only; selection mirrors card).
                VStack(spacing: 0) {
                    ForEach(viewModel.stations) { slot in
                        StationCleaningFlowTableRow(
                            slot: slot,
                            isSelected: slot.station == viewModel.selectedStation,
                            unit: env.preferences.measurementUnit
                        )
                        .onTapGesture {
                            HapticService.light()
                            viewModel.selectStation(slot.station)
                        }
                    }
                }

                Color.clear.frame(height: 110)
            }
            .padding(.bottom, 16)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
        .safeAreaInset(edge: .bottom) { bottomActions }
        // Publish "we're on the cleaning screen" so the disconnect
        // handler shows the during-crafting alert + error haptic
        // (UIKit treats StationCleaningFlowVC the same as crafting
        // for disconnect-alert purposes — `BleManagerDelegate+Disconnect`
        // L69-72).
        .onAppear { router.activeCraftingScreen = .stationCleaning }
        .onDisappear {
            if router.activeCraftingScreen == .stationCleaning {
                router.activeCraftingScreen = nil
            }
        }
        // Load the 6 A–F stations from the real device on appear so
        // `tapClean()` can correctly decide flush-vs-clean based on the
        // current ingredient quantity.
        //
        // Bug fix (getStations race): earlier version called
        // `ble.getConnectedDeviceName()` twice — as the task `id:` AND
        // inside the closure — so a transient empty name during BLE
        // reconnect caused `loadStations` to early-return and the grid
        // to render blank until the user navigated away and back.
        // Now: cache name once, retry briefly if empty, gate on
        // device-connected.
        .task {
            var deviceName = ble.getConnectedDeviceName()
            var retries = 3
            while deviceName.isEmpty && retries > 0 && ble.isAnyDeviceConnected {
                try? await Task.sleep(nanoseconds: 150_000_000)
                deviceName = ble.getConnectedDeviceName()
                retries -= 1
            }
            guard !deviceName.isEmpty else { return }
            await viewModel.loadStations(deviceName: deviceName)
        }
        // Subscribe to BLE responses — drives the cleaning state machine
        // off real device events when a peripheral is connected.
        // Mirrors UIKit `bleDidReceiveData(_:)` → `+BleResponse` switch.
        .onReceive(ble.$lastResponse.compactMap { $0 }) { response in
            viewModel.dispatch(response, ble: ble)
        }
        // 1:1 port of UIKit
        // `StationCleaningFlowViewController.viewDidDisappear` L311-321:
        //   viewModel.processState = .cancelling
        //   if currentFlowIs == .dispensingInProgress {
        //       writeCommand(.stopDispense)
        //   } else {
        //       writeCommand(.cancel)
        //   }
        // This ensures the firmware never gets left in a half-initiated
        // cleaning cycle when the user navigates away (back gesture,
        // tab switch, side-menu navigation, etc.). Without this the
        // device keeps waiting for a glass and the next screen's
        // BLE commands stack on top of a half-cancelled job.
        //
        // Also ports the `DelayedAction.afterBleResponse(seconds: 1.0) {
        //     topVC.refreshOnlyWhenComesFromStationsCleanScreen()
        // }` tail-delay from `didPressBackButton` — we fire the router
        // signal here so any `StationsMenuView` beneath us on the nav
        // stack picks up the refresh via its own `.onChange` observer.
        .onDisappear {
            viewModel.processState = .cancelling
            if viewModel.currentFlow == .dispensingInProgress {
                _ = ble.send(.stopDispense)
            } else {
                _ = ble.send(.cancel)
            }
            Task { @MainActor in
                // UIKit: 1-second delay so the firmware has time to
                // acknowledge the cancel/stop before we refetch.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                router.signalStationsRefreshAfterCleaning()
            }
        }
        // 1:1 port of UIKit
        // `viewModel.onShowPerishableCleanedAlert = { [weak self] in
        //     self.showCustomAlert(
        //         continueButtonTitleStr: "Continue",
        //         title: Constants.perishableIngredientsCleaned,
        //         stationsNameStr: "") { _ in
        //             self.navigationController?.popViewController(animated: true)
        //     }
        // }`
        //
        // Triggered when the cleaning flow completes on a perishable
        // station — we show the "Perishable Ingredients Cleaned" alert
        // and pop the view once the user taps Continue (via the
        // router's navigation-stack pop).
        .onChange(of: viewModel.shouldShowPerishableCleanedAlert) { shouldShow in
            guard shouldShow else { return }
            viewModel.shouldShowPerishableCleanedAlert = false
            env.alerts.show(
                title: Constants.perishableIngredientsCleaned,
                message: "",
                primary: ConstantButtonsTitle.continueButtonTitle,
                action: {
                    // Dismiss the cleaning screen — routes back to the
                    // Stations menu which will pick up the refresh tick
                    // we've already posted in `onDisappear`.
                    router.popTop()
                }
            )
        }
        // 1:1 port of UIKit
        // `viewModel.onShowDifferentStationsAlert`:
        //   self.showCustomAlert(
        //       continueButtonTitleStr: "Continue",
        //       title: Constants.proceedToClean,
        //       stationsNameStr: stationNameStr
        //   ) { … handle → continue station cleanup flow … }
        //
        // Shown when the `differentIngredientsInStationsAre` pipeline
        // flags that the currently-loaded station has mismatched
        // ingredients across the mixlist's recipes and the device must
        // clean one station before the user can re-configure it.
        .onChange(of: viewModel.pendingDifferentStationAlert) { alert in
            guard let alert else { return }
            viewModel.pendingDifferentStationAlert = nil
            env.alerts.show(
                title: Constants.proceedToClean,
                message: alert.stationNamesDisplay,
                primary: ConstantButtonsTitle.continueButtonTitle,
                action: {
                    viewModel.handleDifferentStationAlertContinue(
                        targetStation: alert.targetStation
                    )
                }
            )
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color("borderColor"), lineWidth: 10)
                .frame(width: 180, height: 180)
            Circle()
                .trim(from: 0, to: viewModel.progress)
                .stroke(Theme.Color.brand,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 180, height: 180)
                .animation(.linear(duration: 0.08), value: viewModel.progress)
            VStack(spacing: 4) {
                Text("\(Int(viewModel.progress * 100))%")
                    .font(Theme.Font.bold(28))
                    .foregroundStyle(Color("appBlackColor"))
                Text(viewModel.cleaningMode == .flush ? "Flush" : "Clean")
                    .font(Theme.Font.of(.caption1, .semibold))
                    .foregroundStyle(Color("mediumLightGrayColor"))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // UIKit parity — icon only, 25×25, name label hidden
        // (StationsMenuViewController.swift:123 /
        //  StationCleaningFlowViewController.swift:185 both set
        //  `lblDeviceName.isHidden = true` and never reverse it).
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                Image(deviceIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .accessibilityLabel(deviceKindName)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Shared 100×48 glass pill (iOS 26+) / bare 61×24 icon stack
            // (pre-26). 1:1 UIKit `navigationRightGlassView` parity.
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

    @ViewBuilder
    private var bottomActions: some View {
        let buttons = viewModel.visibleButtons()
        VStack(spacing: 10) {
            if buttons.contains(.clean) {
                // Clean button — uses the dark-mode-aware
                // `cleanButtonLabel()` helper instead of the shared
                // `actionButton(…, color: .brand)` path so the
                // peach-tan gradient stays visible in dark mode. The
                // Continue / Stop brand buttons below KEEP their
                // existing `actionButton(…, color: .brand)` routing
                // (and therefore the shared `.brandCapsule` helper)
                // — per the product spec "Only clean button need to
                // fix in dark mode" — so this change is strictly
                // scoped to the Clean CTA.
                Button {
                    HapticService.light()
                    // 1:1 port of UIKit `didPressCleanButton`:
                    //   self.showGlassLoader(message: "Cleaning")
                    //   ...write BLE command...
                    //   DelayedAction.afterBleResponse(seconds: 2.0) {
                    //       self?.hideGlassLoader()
                    //   }
                    // The loader covers the BLE round-trip so the user
                    // sees visual feedback while the firmware is
                    // acknowledging the flush/clean command.
                    env.loading.show("Cleaning")
                    viewModel.tapClean(ble: ble)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        env.loading.hide()
                    }
                } label: {
                    cleanButtonLabel()
                }
                .buttonStyle(BounceButtonStyle())
            }
            if buttons.contains(.continue) {
                actionButton(ConstantButtonsTitle.continueButtonTitle,
                             color: Theme.Color.brand) {
                    viewModel.tapContinueAfterPourSolution(ble: ble)
                }
            }
            if buttons.contains(.pause) || buttons.contains(.stop) {
                // UIKit stack tP9-r1-gEb: spacing=8, distribution=fillEqually
                HStack(spacing: 8) {
                    if buttons.contains(.pause) {
                        actionButton("Pause", color: Color.white,
                                     textColor: Color("appBlackColor"),
                                     stroke: Color("borderColor")) {
                            viewModel.tapPause(ble: ble)
                        }
                    }
                    if buttons.contains(.stop) {
                        actionButton("Stop", color: Theme.Color.brand) {
                            viewModel.tapStop(ble: ble)
                        }
                    }
                }
            }
            if buttons.contains(.cancel) {
                actionButton(ConstantButtonsTitle.cancelButtonTitle,
                             color: Color.white,
                             textColor: Color("appBlackColor"),
                             stroke: Color("borderColor")) {
                    // 1:1 port of UIKit `didPressCancelButton`:
                    //   viewModel.handleCancel()
                    //   self.showGlassLoader(message: "Cancelling")
                    //   ...write .stopDispense or .cancel BLE command...
                    //   DelayedAction.afterBleResponse(seconds: 2.0) {
                    //       self?.hideGlassLoader()
                    //   }
                    env.loading.show("Cancelling")
                    viewModel.tapCancel(ble: ble)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        env.loading.hide()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [Theme.Color.background.opacity(0), Theme.Color.background],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// Cleaning-flow CTA helper. Brand-coloured backgrounds get the
    /// brand gradient capsule; white-coloured (Pause/Cancel) get the
    /// gradient-bordered glass capsule. Mirrors UIKit's
    /// `PrimaryOrangeButton.makeOrangeStyle()` /
    /// `applyCancelCapsuleGradientBorderStyle()` split.
    private func actionButton(_ title: String,
                              color: Color,
                              textColor: Color = .white,
                              stroke: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button {
            HapticService.light()
            action()
        } label: {
            if color == Theme.Color.brand {
                Text(title).brandCapsule(height: 45, cornerRadius: 22.5)
            } else {
                Text(title).cancelCapsule(height: 45,
                                          cornerRadius: 22.5,
                                          textColor: textColor)
            }
        }
        .buttonStyle(BounceButtonStyle())
    }

    /// Dark-mode-aware "Clean" button — scoped strictly to the Clean
    /// CTA (not the Continue / Stop brand buttons on the same
    /// screen) per the product spec's "only the Clean button"
    /// instruction.
    ///
    /// Recipe: inlined `brandCapsule(height: 45, cornerRadius: 22.5)`
    /// with a dark-mode gradient override. Light mode resolves
    /// through the existing `brandGradientTop` /
    /// `brandGradientBottom` colour assets (bit-identical pixels).
    /// Dark mode hard-codes the LIGHT-mode brand-orange RGB so the
    /// capsule stays peach-tan instead of collapsing into the
    /// asset's near-black dark-appearance variant.
    private func cleanButtonLabel() -> some View {
        let height: CGFloat = 45
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        let gradientColors: [SwiftUI.Color] = colorScheme == .dark
            ? [
                // Explicit light-mode values pulled from
                // brandGradientTop.colorset / brandGradientBottom.colorset.
                SwiftUI.Color(red: 0.980, green: 0.878, blue: 0.800),
                SwiftUI.Color(red: 0.949, green: 0.761, blue: 0.631)
            ]
            : [
                // Light mode — resolves via colour assets exactly
                // like the shared helper, so light-mode pixels stay
                // bit-identical to the existing UIKit-parity
                // rendering.
                SwiftUI.Color("brandGradientTop"),
                SwiftUI.Color("brandGradientBottom")
            ]
        return Text("Clean")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SwiftUI.Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        RoundedRectangle(cornerRadius: height / 2,
                                         style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 22.5,
                                         style: .continuous)
                            .fill(Theme.Color.segmentSelection)
                    }
                }
            )
            .barsysShadow(.floatingButton)
    }
}
