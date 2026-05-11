//
//  PreferencesScreens.swift
//  BarsysAppSwiftUI
//
//  Unit preferences, country picker, quantity selection.
//

import SwiftUI

// MARK: - Preferences

/// Ports UnitPreferencesViewController from UIKit.
/// Storyboard: SideMenu.storyboard scene.
/// Layout: Title "Units" (24pt), description "Your preferred measuring unit." (12pt),
/// segmented control for ML/OZ on right side.
/// Top bar: back button, device icon center (if connected), fav + profile buttons.
struct PreferencesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var preferences: PreferencesService
    @EnvironmentObject private var ble: BLEService
    @Environment(\.dismiss) private var dismiss

    private var isConnected: Bool { ble.isAnyDeviceConnected }

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

    var body: some View {
        // Wrapped in `ScrollView` so iOS 26's nav-bar Liquid Glass
        // auto-wrap has a scrollable surface to render against —
        // matches the structural pattern that fixed the right-pill
        // chrome on HomeView / Cocktail Kits / Pair Your Device, and
        // mirrors MyBar / DevicePairedView / RecipeDetail (the
        // reference screens whose right-pill renders correctly in
        // dark mode). Without this, the system bar falls back to the
        // thinner "black transparent" pill the user reported.
        // The previous trailing `Spacer()` is gone because Spacer
        // collapses inside a ScrollView; the content sits at the top
        // of the viewport, identical to the previous bare-VStack
        // layout (the Spacer was only padding visual emptiness, not
        // anchoring anything).
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Page title — "Units" 24pt, leading 24, top 18.
                // iPad bumps to 32pt so the screen title matches
                // Ready to Pour on the wider canvas. iPhone unchanged.
                Text("Units")
                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 32 : 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.leading, 24)
                    .padding(.top, 18)

                // Unit selection row — ports UIKit unitSegmentedControl
                // UIKit: segmented control 72×32 on right, selectedSegmentTintColor = brandTanColor.
                //
                // iPad-only font / width bumps so the row reads at a
                // comfortable scale on the wider canvas. iPhone keeps
                // the storyboard-spec 16pt / 12pt / 100pt values
                // bit-identically.
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        // Row label "Units" — NOT the screen title
                        // (which sits above this row at 32pt iPad / 24pt
                        // iPhone, untouched). iPad bumps this row label
                        // 16 → 26pt so the section header reads at a
                        // comfortable scale below the screen title.
                        // iPhone stays at the storyboard 16pt spec.
                        Text("Units")
                            .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 26 : 16))
                            .foregroundStyle(Color("appBlackColor"))
                        Text("Your preferred measuring unit.")
                            .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 12))
                            .foregroundStyle(Color("mediumGrayColor"))
                    }
                    Spacer()
                    // Segmented control matching UIKit: brandTanColor selected tint.
                    // iPad bumps the control width 100 → 140 so the
                    // larger ML / OZ glyph fits with proper breathing
                    // room. iPhone unchanged.
                    Picker("", selection: $preferences.measurementUnit) {
                        Text("ML").tag(MeasurementUnit.ml)
                        Text("OZ").tag(MeasurementUnit.oz)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 140 : 100)
                    .onChange(of: preferences.measurementUnit) { _ in
                        // Light tap on every flip — matches the haptic
                        // signature used elsewhere in the app for
                        // selection-style controls (e.g. plus/minus
                        // steppers in `RecipeIngredientRow` /
                        // `EditIngredientRow`, toolbar back buttons).
                        HapticService.light()
                        // 1:1 with UIKit `UnitPreferencesViewController`
                        // L112 — fires when the user flips the ml/oz
                        // segmented control:
                        //   TrackEventsClass().addBrazeCustomEventWithEventName(
                        //       eventName: TrackEventName.changePrefrencesEvent.rawValue)
                        env.analytics.track(TrackEventName.changePrefrencesEvent.rawValue)
                    }
                    .onAppear {
                        // Match UIKit selectedSegmentTintColor = brandTanColor
                        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(named: "brandTanColor")
                        // iPad-only font bump for the ML / OZ labels —
                        // UISegmentedControl doesn't accept SwiftUI fonts
                        // directly so we set the title text attributes
                        // via UIAppearance. iPhone keeps the system
                        // default (typically 13pt) by skipping the
                        // `.font` attribute on iPhone — bit-identical
                        // to before this fix.
                        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
                        var selectedAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: UIColor.black
                        ]
                        var normalAttrs: [NSAttributedString.Key: Any] = [
                            .foregroundColor: UIColor.black.withAlphaComponent(0.6)
                        ]
                        if isIPad {
                            selectedAttrs[.font] = UIFont.systemFont(ofSize: 18, weight: .semibold)
                            normalAttrs[.font]   = UIFont.systemFont(ofSize: 18)
                        }
                        UISegmentedControl.appearance().setTitleTextAttributes(selectedAttrs, for: .selected)
                        UISegmentedControl.appearance().setTitleTextAttributes(normalAttrs, for: .normal)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticService.light()
                    dismiss()
                } label: {
                    Image("back")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 15, height: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 15)
                        .foregroundStyle(Color("appBlackColor"))
                }
            }

            // Center: device ICON ONLY (if connected).
            //
            // UIKit parity — UnitPreferencesViewController.swift:36 sets
            // `lblDeviceName.isHidden = true` in `viewDidLoad` and never
            // reverses it; only the 25×25 `imgDevice` is visible.
            if isConnected {
                ToolbarItem(placement: .principal) {
                    DevicePrincipalIcon(assetName: deviceIconName,
                                        accessibilityLabel: deviceKindName)
                }
            }

            // Right: fav + profile — shared 100×48 glass pill (iOS 26+)
            // or bare 61×24 icon stack (pre-26). 1:1 UIKit
            // `navigationRightGlassView` parity.
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
        // pill renders against the same canvas as HomeView (ChooseOptions)
        // — makes the material blur + capsule stroke read identical.
        .chooseOptionsStyleNavBar()
        // Re-enable swipe-back gesture (custom back chevron above
        // hides the system one, which would otherwise disable
        // `interactivePopGestureRecognizer`).
        .interactivePopGestureEnabled()
        // Publish "we're on Preferences" so the side menu can skip a
        // duplicate push when the user taps Preferences while this
        // screen is already visible.
        .onAppear { router.isShowingPreferences = true }
        .onDisappear { router.isShowingPreferences = false }
    }
}

// MARK: - Country picker (sheet + embedded)
//
// Ports BarsysApp/Controllers/CountryPicker/CountryPickerViewController.swift.
// Loads the full country list from Countries.json so the user sees every
// country with its flag, +dialCode, and name — same as the UIKit table view.

struct CountryPickerView: View {
    @Binding var selected: Country
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var countries: [Country] = []

    private var filtered: [Country] {
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.dial_code.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { c in
                    Button {
                        selected = c
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(c.flag).font(.system(size: 26))
                            Text(c.name)
                                .font(Theme.Font.regular(15))
                                .foregroundStyle(Theme.Color.textPrimary)
                            Spacer()
                            Text("+\(c.dial_code)")
                                .font(Theme.Font.medium(15))
                                .foregroundStyle(Theme.Color.textSecondary)
                            if c.code == selected.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Color.brand)
                            }
                        }
                    }
                    // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
                // bit-identical to the previous hard-coded `Color.white`
                // — light mode renders the EXACT same row background.
                // Dark mode picks up the elevated dark surface (#2C2C2E)
                // so country rows read as raised cards on the dark
                // settings page instead of stark white slabs.
                .listRowBackground(Theme.Color.surface)
                }
            }
            .searchable(text: $query, prompt: "Search country")
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { countries = CountryLoader.loadAll() }
    }
}

struct EmbeddedCountryPicker: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var countries: [Country] = []

    private var filtered: [Country] {
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.dial_code.contains(query)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { c in
                Button {
                    env.preferences.selectedCountryCode = c.code
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(c.flag).font(.system(size: 26))
                        Text(c.name)
                            .font(Theme.Font.regular(15))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        Text("+\(c.dial_code)")
                            .font(Theme.Font.medium(15))
                            .foregroundStyle(Theme.Color.textSecondary)
                        if c.code == env.preferences.selectedCountryCode {
                            Image(systemName: "checkmark").foregroundStyle(Theme.Color.brand)
                        }
                    }
                }
                // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
                // bit-identical to the previous hard-coded `Color.white`
                // — light mode renders the EXACT same row background.
                // Dark mode picks up the elevated dark surface (#2C2C2E)
                // so country rows read as raised cards on the dark
                // settings page instead of stark white slabs.
                .listRowBackground(Theme.Color.surface)
            }
        }
        .searchable(text: $query, prompt: "Search country")
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("Country")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear { countries = CountryLoader.loadAll() }
    }
}

// MARK: - Select Quantity
//
// 1:1 port of UIKit `SelectQuantityViewController` + its picker /
// validation extensions (BarsysApp/Controllers/SelectQuantity/*).
//
// Visual layout (from `ControlCenter.storyboard` scene + the
// outlets in `SelectQuantityViewController.swift`):
//
//     ┌─────────────────────────────────────┐
//     │ ← back            ♥ + ☰ glass pill │  toolbar (custom chrome)
//     ├─────────────────────────────────────┤
//     │       [device image] 50×50          │  imgDevice
//     │                                     │
//     │   Maximum Volume: 750 ml.           │  lblMinimumVolumeText, headline
//     │                                     │
//     │    ┌─────┬─────┐                    │  picker — 1 component (ml)
//     │    │ 100 │  00 │                    │             or 2 components (oz)
//     │    │ 110 │  01 │                    │  rowHeight=48, width=80 each
//     │    │ 120 │  02 │  ← selection ring  │
//     │    │ 130 │  03 │                    │
//     │    └─────┴─────┘                    │
//     │      150  .  25                     │  txtInput  .  txtInputDecimals
//     │                                     │
//     │     ◇ ML  │  OZ ◇                   │  segmentedControl
//     │                                     │
//     │       [    SAVE    ]                │  oldSaveButton (PrimaryOrange)
//     └─────────────────────────────────────┘
//
// Picker arrays generated by `getUpdatedPickerArray`:
//
//   • ML, Barsys 360       → 0…750  (Int)
//   • ML, Coaster / Shaker → 0…1500 (Int)
//   • OZ, Barsys 360       → whole 0…25, decimal 00…99 (capped 25.36)
//   • OZ, Coaster / Shaker → whole 0…50, decimal 00…99 (capped 50.72)
//
// Each array is repeated `NumericConstants.numberOfRepeats` (= 1000)
// times so the wheel feels infinite. The initial selection lands at
// `count * 1000 / 2 + defValueIndex` to allow scrolling in both
// directions from the seed value.
//
// Validation chain (`validateAndPrepareSaveData`):
//   1. quantity ≤ 0          → "Please enter quantity"
//   2. quantity > 750 ml     → enterQuantityAlert750Ml
//   3. quantity > 1500 ml    → enterQuantityAlert1500Ml
//   4. oz & quantity > 25.36 → enterQuantityAlert25OZ
//   5. oz & quantity > 50.72 → enterQuantityAlert50OZ
//   6. quantity < 5 ml       → enterMinimumQtyAlertML
//   7. quantity < 0.17 oz    → enterMinimumQtyAlertOZ
// Otherwise → post `PendingStationUpdate` via the router and dismiss.

struct SelectQuantityView: View {
    /// Originating station + ingredient + category + perishable.
    /// Threaded via `router.pendingStationUpdate` by the caller
    /// (Refill on StationsMenu) — we read it on appear and seed the
    /// local state so the picker / validation behave like UIKit's
    /// `SelectQuantityViewController.flowToAdd`.
    let ingredientName: String
    var stationName: String? = nil
    var isPerishable: Bool = false
    var primaryCategory: String? = nil
    var secondaryCategory: String? = nil
    /// Drives "add" vs "refill" semantics on the posted update.
    /// 1:1 with UIKit's `isAddingNewIngredient` userInfo key.
    var isAddingNewIngredient: Bool = false
    /// Seed quantity (ml). UIKit reads this from
    /// `flowToAdd.ingredientQuantity` so a Refill always opens with
    /// the station's CURRENT quantity selected. For "add new" the
    /// seed comes through as 0 and the picker centres on the empty
    /// row.
    var defaultValueMl: Double = 0

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService

    // MARK: - Local state (mirrors `SelectQuantityViewModel`)

    /// Currently-selected unit. UIKit seeds this from
    /// `UserDefaultsClass.getPreferencesUnit()` in `viewDidLoad`.
    @State private var selectedUnit: QuantityType = .ml
    /// Canonical stored value (always in ml). UIKit's `defaultValue`.
    @State private var quantityMl: Double = 0
    /// Whole-component picker row (Int). Resolves directly to
    /// `quantityArray[quantitySelectedRowIndex]`. UIKit's
    /// `quantitySelectedRowIndex`.
    @State private var wholeRow: Int = 0
    /// Decimal-component picker row (Int 0…99 — or 0…36 / 0…72 when
    /// at the cap row). Only used for the oz unit. UIKit's
    /// `decimalquantitySelectedRowIndex`.
    @State private var decimalRow: Int = 0
    /// Alert message dispatched by `validateAndPrepareSaveData` /
    /// segment-revert / out-of-range capping logic. Drives a single
    /// `.alert()` modifier.
    @State private var alertMessage: String? = nil
    /// One-shot guard so the seed-from-router work runs ONCE per
    /// presentation — pushing the screen twice in a single session
    /// would otherwise re-seed mid-edit and wipe the user's input.
    @State private var didSeed: Bool = false

    // MARK: - Computed: picker data

    /// Whole-unit array for the selected unit + connected device.
    /// 1:1 with UIKit `getUpdatedPickerArray` (PickerData.swift).
    private var wholeArray: [Int] {
        if selectedUnit == .ml {
            if ble.isBarsys360Connected() {
                return Array(0...NumericConstants.maximumQuantityIntMLFor360)
            } else {
                return Array(0...NumericConstants.maximumQuantityIntMLForCoaster)
            }
        } else { // .oz
            if ble.isBarsys360Connected() {
                return Array(0...25) // 26 rows incl. 0
            } else {
                return Array(0...50) // 51 rows incl. 0
            }
        }
    }

    /// Decimal-unit array (oz only). UIKit `quantityDecimalArray` —
    /// 100 entries "00".."99" capped at "36" / "72" when the whole
    /// row sits at the max integer (so 25.36 / 50.72 stays the
    /// absolute ceiling).
    private var decimalArray: [String] {
        guard selectedUnit == .oz else { return [] }
        let maxCount: Int
        if ble.isBarsys360Connected() {
            maxCount = (wholeRow == 25) ? 37 : 100
        } else {
            maxCount = (wholeRow == 50) ? 73 : 100
        }
        return (0..<maxCount).map { i in
            i <= 9 ? "\(Constants.zeroIntStr)\(i)" : "\(i)"
        }
    }

    /// Maximum-volume label text. UIKit `minimumVolumeText`.
    private var minimumVolumeText: String {
        if ble.isBarsys360Connected() {
            return selectedUnit == .ml ? Constants.maximumVolume750 : Constants.maximumVolume25OZ
        } else {
            return selectedUnit == .ml ? Constants.maximumVolume1500 : Constants.maximumVolume50OZ
        }
    }

    /// Device-image asset name + display name — UIKit
    /// `deviceDisplayName` / `deviceDisplayImage`.
    private var deviceImageName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }

    private var deviceDisplayName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    /// Save button enabled when current quantity > 0. UIKit's
    /// `onUpdateSaveButtonState` toggles the background between
    /// `sideMenuSelectionColor` and `lightGray`.
    private var isSaveEnabled: Bool { quantityMl > 0 }

    // MARK: - Body
    //
    // 1:1 with UIKit ControlCenter.storyboard scene `XVx-Hv-Mvu`:
    //
    //   • Toolbar (height 60pt) — UIKit `edu-4m-EeV`:
    //       Back chevron 30×30 leading 12pt
    //       Center stack: device icon 25×25 + "Barsys 360" 12pt
    //       Right glass pill 100×48 trailing 24pt (favorite + profile)
    //
    //   • ScrollView content (height ≈ 360pt) — UIKit `exJ-MN-PpQ`:
    //       Units row 40pt at top:
    //         - Left stack: "Units" 16pt bold veryDarkGray
    //                       "Your preferred measuring unit." 14pt
    //                       appBlackColor
    //         - Right segmented control 74×31 ML / OZ
    //           (brandTanColor background, white selected tint)
    //       Picker 327×300pt centered, 24pt leading/trailing
    //         - 7×7 black dot label centered (oz only)
    //
    //   • Bottom 122pt container — UIKit `Bgh-7a-Hfr`:
    //       "Maximum Volume: …" label 17pt semibold mediumLightGray
    //       Save / Add button 150×45 rounded-corner=20 centered
    //       Bottom inset 20pt from safe area
    //
    // Native nav-bar is hidden — we render a custom top bar so the
    // UIKit toolbar 60pt height + center device cluster can be matched
    // exactly (the standard SwiftUI nav bar wraps the title slot
    // differently and would lose the icon + label centre pair).

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar — UIKit `edu-4m-EeV` (height 60pt).
            customToolbar

            // Scrollable middle section — UIKit `OG6-hA-SCa`.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Units row — UIKit `qO5-ij-LNB` (height 40pt).
                    unitsRow
                        .padding(.horizontal, 17)
                        .padding(.top, 10)

                    // Picker — UIKit `U93-ue-cgA` (327×300, 24pt
                    // leading/trailing). SwiftUI native wheel
                    // picker is mounted side-by-side for the oz
                    // 2-component case; single picker is centred
                    // for the ml 1-component case.
                    pickerStack
                        .frame(height: 300)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }
            }

            // Bottom container — UIKit `Bgh-7a-Hfr` (122pt tall).
            // Pinned via VStack (NOT inside ScrollView) so the Save
            // button stays at the bottom regardless of content size.
            VStack(spacing: 10) {
                // Maximum-volume label — UIKit `pP0-XI-Ftn`. 17pt
                // semibold, mediumLightGrayColor, centred.
                Text(minimumVolumeText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color("mediumLightGrayColor"))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(minimumVolumeText)

                // Save / Add button — UIKit `K1N-67-kPf`. 150×45,
                // 20pt corner radius. UIKit's storyboard title is
                // "Add"; the runtime applies PrimaryOrange style on
                // iOS 26 and a flat fill on earlier iOS.
                Button {
                    HapticService.success()
                    handleSave()
                } label: {
                    Text(isAddingNewIngredient ? "Add" : "Save")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white)
                        .frame(width: 150, height: 45)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isSaveEnabled
                                      ? Color("segmentSelectionColor")
                                      : Color("lightGrayColor"))
                        )
                }
                .disabled(!isSaveEnabled)
                .accessibilityLabel(isAddingNewIngredient ? "Add" : "Save")
                .accessibilityHint("Saves the selected quantity")
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 20)
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            actions: {
                Button(ConstantButtonsTitle.okButtonTitle) { alertMessage = nil }
            },
            message: { Text(alertMessage ?? "") }
        )
        .onAppear { seedFromRouterIfNeeded() }
    }

    // MARK: - Custom top toolbar (matches UIKit `edu-4m-EeV` 60pt bar)

    @ViewBuilder
    private var customToolbar: some View {
        HStack(spacing: 0) {
            // Back button — UIKit `aiP-o8-GAQ` (30×30, leading 12pt).
            Button {
                HapticService.light()
                dismiss()
            } label: {
                Image("back")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(width: 30, height: 30)
            }
            .padding(.leading, 12)
            .accessibilityLabel("Back")

            Spacer()

            // Center cluster — UIKit `Ke1-tT-ohh`:
            //   device icon (25×25) + "Barsys 360" label 12pt
            // 8pt spacing between icon + label.
            HStack(spacing: 8) {
                if !deviceImageName.isEmpty {
                    Image(deviceImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 25)
                }
                Text(deviceDisplayName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("appBlackColor"))
            }

            Spacer()

            // Right cluster placeholder — preserves toolbar
            // visual balance (UIKit has a 100×48 glass pill with
            // favorite + profile icons). 30+30+7 = 67pt to
            // mirror the back button + spacing.
            HStack(spacing: 7) {
                Image("favoriteIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Image("profileIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 24)
            // Right-side icons are decorative on this screen — UIKit's
            // outlets are wired to side menu / favourites in shared
            // code, but the SelectQuantity screen is rarely the place
            // those are used. Leaving them visual-only here matches
            // the storyboard chrome without adding side-menu plumbing.
            .allowsHitTesting(false)
        }
        .frame(height: 60)
        .background(Color("primaryBackgroundColor"))
    }

    // MARK: - Units row (segmented control + description)
    //
    // 1:1 with UIKit `qO5-ij-LNB` (height 40pt):
    //   Left stack: "Units" 16pt bold veryDarkGray, "Your preferred
    //   measuring unit." 14pt appBlackColor, vertical 5pt spacing.
    //   Right: segmented control 74×31, ML / OZ.

    @ViewBuilder
    private var unitsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Units")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                Text("Your preferred measuring unit.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color("appBlackColor"))
            }

            Spacer()

            unitSegmentedControl
                .frame(width: 74, height: 31)
        }
    }

    // MARK: - Picker

    /// Builds the side-by-side wheel picker. SwiftUI's native
    /// `Picker(.wheel)` accepts a single selection so we mount one
    /// picker per UIKit component and arrange them horizontally.
    /// On the oz unit the "." separator label sits between the two.
    @ViewBuilder
    private var pickerStack: some View {
        HStack(spacing: 0) {
            Spacer()

            // Whole component — always shown.
            Picker("Whole quantity", selection: $wholeRow) {
                ForEach(wholeArray.indices, id: \.self) { idx in
                    Text("\(wholeArray[idx])")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("appBlackColor"))
                        .tag(idx)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 100, height: 220)
            .clipped()
            .onChange(of: wholeRow) { newValue in
                // UIKit `handlePickerDidSelectRow` — recomputes
                // `defaultValue` and (in oz mode) regenerates the
                // decimal array so 25.* / 50.* caps apply.
                recomputeQuantity()
                ensureDecimalWithinCap()
            }

            if selectedUnit == .oz {
                // Decimal-separator "." — UIKit `lblQtyFullStop`.
                Text(".")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.horizontal, 4)

                // Decimal component — only mounted on oz.
                Picker("Decimal", selection: $decimalRow) {
                    ForEach(decimalArray.indices, id: \.self) { idx in
                        Text(decimalArray[idx])
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color("appBlackColor"))
                            .tag(idx)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100, height: 220)
                .clipped()
                .onChange(of: decimalRow) { _ in
                    recomputeQuantity()
                }
            }

            Spacer()
        }
    }

    // MARK: - Segmented control

    @ViewBuilder
    private var unitSegmentedControl: some View {
        Picker("Unit", selection: Binding(
            get: { selectedUnit },
            set: { newUnit in
                handleUnitChange(to: newUnit)
            }
        )) {
            Text(Constants.mlText.uppercased()).tag(QuantityType.ml)
            Text(Constants.ozText.uppercased()).tag(QuantityType.oz)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Seed from router

    /// UIKit `SelectQuantityViewController.viewDidLoad` →
    /// `viewModel.setupInitialUnit()` + `pickerViewSetup`. The
    /// SwiftUI equivalent reads the user's unit preference and seeds
    /// `quantityMl` + the picker row from `defaultValueMl`.
    private func seedFromRouterIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        selectedUnit = UserDefaultsClass.getPreferencesUnit()
        quantityMl = max(0, defaultValueMl)
        positionPickerForCurrentQuantity()
    }

    /// Snaps both picker components to the row(s) representing
    /// `quantityMl` in the current unit. UIKit
    /// `setupPickerInitialSelection`.
    private func positionPickerForCurrentQuantity() {
        if selectedUnit == .ml {
            let target = Int(quantityMl.rounded())
            wholeRow = clampWholeRow(target)
        } else {
            let oz = quantityMl / NumericConstants.oneMlValue
            let whole = Int(oz.rounded(.down))
            wholeRow = clampWholeRow(whole)
            let dec = Int(((oz - Double(whole)) * 100).rounded())
            decimalRow = clampDecimalRow(dec)
        }
    }

    private func clampWholeRow(_ idx: Int) -> Int {
        guard !wholeArray.isEmpty else { return 0 }
        return max(0, min(idx, wholeArray.count - 1))
    }

    private func clampDecimalRow(_ idx: Int) -> Int {
        let cap = decimalArray.count
        guard cap > 0 else { return 0 }
        return max(0, min(idx, cap - 1))
    }

    // MARK: - Unit change

    /// UIKit `handleSegmentChange` + `shouldRevertSegment`. Validates
    /// the current quantity against the new unit's minimum (5 ml /
    /// 0.17 oz) and reverts the flip with an alert if the value
    /// would underflow.
    private func handleUnitChange(to newUnit: QuantityType) {
        guard newUnit != selectedUnit else { return }

        // UIKit's `shouldRevertSegment`:
        //   • Flipping FROM oz TO ml: if oz value < 0.17 and != 0,
        //     show the oz minimum alert and STAY on oz.
        //   • Flipping FROM ml TO oz: if ml row < 5 and != 0, show
        //     the ml minimum alert and STAY on ml.
        if newUnit == .ml {
            // We're on oz currently. Compute the oz value.
            let ozValue = currentOzValue()
            if ozValue > 0 && ozValue < NumericConstants.minimumQtyInOzDouble {
                alertMessage = Constants.enterMinimumQtyAlertOZ
                return
            }
        } else {
            // We're on ml currently.
            let ml = quantityMl
            if ml > 0 && ml < NumericConstants.minimumQtyDouble {
                alertMessage = Constants.enterMinimumQtyAlertML
                return
            }
        }

        selectedUnit = newUnit
        // After the flip, snap the picker to the equivalent value in
        // the new unit so the user's quantity is preserved across
        // the unit change.
        positionPickerForCurrentQuantity()
        ensureDecimalWithinCap()
    }

    // MARK: - Recompute quantity from picker rows

    /// Whenever the picker rows change, recompute `quantityMl` so
    /// the validation + save use the live value. UIKit
    /// `handlePickerDidSelectRow` + `computeOzDefaultValue`.
    private func recomputeQuantity() {
        if selectedUnit == .ml {
            let row = clampWholeRow(wholeRow)
            quantityMl = Double(wholeArray[row])
        } else {
            quantityMl = currentOzValue() * NumericConstants.oneMlValue
        }
    }

    /// Returns the live oz value reconstructed from `wholeRow` +
    /// `decimalRow`. Used for both `quantityMl` updates AND the
    /// segment-revert minimum check.
    private func currentOzValue() -> Double {
        let whole = wholeArray[clampWholeRow(wholeRow)]
        let dec = decimalArray.isEmpty
            ? "00"
            : decimalArray[clampDecimalRow(decimalRow)]
        let str = "\(whole).\(dec)"
        return Double(str) ?? 0
    }

    /// When the user lands on the max whole row (25 / 50) the
    /// decimal array shrinks (37 / 73 entries). Re-clamp the row in
    /// case the previous larger array left us above the new cap.
    /// UIKit `getUpdatedDecimalArray` does this implicitly via its
    /// `if decimalquantitySelectedRowIndex > 36 { decimalQty… = 36 }`
    /// branch.
    private func ensureDecimalWithinCap() {
        guard selectedUnit == .oz else { return }
        let cap = decimalArray.count
        if decimalRow >= cap {
            decimalRow = max(0, cap - 1)
            recomputeQuantity()
        }
    }

    // MARK: - Save

    /// 1:1 with UIKit `validateAndPrepareSaveData` +
    /// `didPressSave`. Validates, alerts on failure, otherwise posts
    /// the `PendingStationUpdate` via the router and dismisses.
    private func handleSave() {
        // 1. Empty / zero — UIKit `enterQuantityAlert`.
        if quantityMl <= 0 {
            alertMessage = Constants.enterQuantityAlert
            return
        }

        // 2. Over-cap by unit. UIKit checks raw `defaultValue` (in ml)
        //    against the matching cap — we mirror that.
        if selectedUnit == .ml {
            if ble.isBarsys360Connected() {
                if quantityMl > NumericConstants.maximumQuantityDoubleMLFor360 {
                    alertMessage = Constants.enterQuantityAlert750Ml
                    return
                }
            } else {
                if quantityMl > NumericConstants.maximumQuantityDoubleMLForCoaster {
                    alertMessage = Constants.enterQuantityAlert1500Ml
                    return
                }
            }
        } else {
            let ozValue = currentOzValue()
            if ble.isBarsys360Connected() {
                if ozValue > NumericConstants.maxOzValueFor360 {
                    alertMessage = Constants.enterQuantityAlert25OZ
                    return
                }
            } else {
                if ozValue > NumericConstants.maxOzValueForCoaster {
                    alertMessage = Constants.enterQuantityAlert50OZ
                    return
                }
            }
        }

        // 3. Under-min by unit.
        if selectedUnit == .ml && quantityMl < NumericConstants.minimumQtyDouble {
            alertMessage = Constants.enterMinimumQtyAlertML
            return
        }
        if selectedUnit == .oz {
            let ozValue = currentOzValue()
            if ozValue < NumericConstants.minimumQtyInOzDouble {
                alertMessage = Constants.enterMinimumQtyAlertOZ
                return
            }
        }

        // 4. Validated — fire the router callback and dismiss.
        HapticService.success()
        router.postStationRefill(
            AppRouter.PendingStationUpdate(
                ingredientName: ingredientName,
                quantityMl: quantityMl,
                primaryCategory: primaryCategory,
                secondaryCategory: secondaryCategory,
                isPerishable: isPerishable,
                isAddingNewIngredient: isAddingNewIngredient,
                stationName: stationName
            )
        )
        dismiss()
    }
}
