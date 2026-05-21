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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService

    /// Bumped by the `orientationDidChangeNotification` observer wired
    /// into `body.onAppear` so iPad rotation (which keeps
    /// `regular/regular` size classes in both orientations) still
    /// triggers a SwiftUI re-evaluation of the `isLandscape` layout
    /// switch. Same pattern used by ControlCenterScreens for its grid.
    @State private var orientationTick: Int = 0

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

    // MARK: - Manual-input state (1:1 UIKit `txtInput` / `txtInputDecimals`)
    //
    // UIKit overlays two `UITextField`s on the picker center row
    // (`Joa-xS-fU7` whole, `3yS-P6-FJF` decimal — 80×50 each, font
    // 45pt, `textColor = .clear` so the picker's `attributedTitleForRow`
    // is what the user actually reads). Tapping focuses the field;
    // `addDoneCancelToolbar` wires Done → validate+snap, Cancel → revert.
    // We mirror that here with two `TextField`s + `FocusState` so
    // typing falls through to the picker on commit.

    /// Buffer for the whole-component text field. UIKit `txtInput.text`.
    @State private var wholeFieldText: String = "0"
    /// Buffer for the decimal-component text field. UIKit
    /// `txtInputDecimals.text`. Only used in `.oz` mode.
    @State private var decimalFieldText: String = "00"
    /// Snapshot of `wholeRow` taken at editing-begin so Cancel can
    /// revert without leaving stale picker state. UIKit
    /// `checkIsValueSame`.
    @State private var preEditWholeRow: Int = 0
    @State private var preEditDecimalRow: Int = 0
    /// Snapshot of `quantityMl` taken alongside the picker rows when
    /// editing begins, so Cancel restores the canonical ml value
    /// exactly (no float-drift from re-deriving it through the
    /// `oz → ml` conversion). UIKit equivalent: the `defaultValue`
    /// remains untouched until `tapDone` so a `Cancel` already had
    /// the original ml stored on the ViewModel.
    @State private var preEditQuantityMl: Double = 0
    /// Tracks which (if any) of the manual-input fields holds focus.
    /// Drives the keyboard toolbar AND the "show typed text on top of
    /// picker" visual that mirrors UIKit's
    /// `pickerView.reloadComponent(0)` while `checkIsUserChangingQty`.
    @FocusState private var focusedField: ManualInputField?

    enum ManualInputField: Hashable { case whole, decimal }

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

    /// Save button enabled state — gated by the SAME per-unit
    /// minimums UIKit uses, so the disabled / alert behaviour is
    /// byte-for-byte consistent:
    ///
    ///   ┌────────┬────────────────────────────────────────────┬─────────────────────┐
    ///   │  Unit  │  UIKit constant                            │ SwiftUI gate        │
    ///   ├────────┼────────────────────────────────────────────┼─────────────────────┤
    ///   │  .ml   │  NumericConstants.minimumQtyDouble (5.0)   │ quantityMl ≥ 5      │
    ///   │  .oz   │  NumericConstants.minimumQtyInOzDouble     │ currentOzValue() ≥  │
    ///   │        │                                  (0.17)    │                0.17 │
    ///   └────────┴────────────────────────────────────────────┴─────────────────────┘
    ///
    /// These are the same values UIKit checks in three places:
    ///   • `validateAndPrepareSaveData` (save tap → alert if below
    ///     minimum). Both branches compare `defaultValue` (ml) to
    ///     `minimumQtyDouble = 5.0`; the alert text differs by unit
    ///     (`enterMinimumQtyAlertML` "Minimum quantity allowed is
    ///     5 ml.", `enterMinimumQtyAlertOZ` "Minimum quantity
    ///     allowed is 0.17 Oz.").
    ///   • `shouldRevertSegment(0)` (oz → ml flip) — reverts when
    ///     `valueInOzActual < minimumQtyInOzDouble`.
    ///   • `shouldRevertSegment(1)` (ml → oz flip) — reverts when
    ///     `quantitySelectedRowIndex < 5` (ml row index = ml value).
    ///
    /// Using `currentOzValue()` directly (instead of converting
    /// quantityMl back to oz) avoids the float drift across
    /// `*ounceValue` / `/ounceValue` round-trips. The save button
    /// state lines up exactly with the oz picker rows the user sees.
    ///
    /// `handleSave` still runs the matching UIKit
    /// `validateAndPrepareSaveData` chain as defence-in-depth — so
    /// any code path that bypasses the gate (a future deep-link, a
    /// stale router seed) still surfaces the correct minimum-quantity
    /// alert instead of saving an invalid value.
    private var isSaveEnabled: Bool {
        if selectedUnit == .ml {
            return quantityMl >= NumericConstants.minimumQtyDouble
        } else {
            return currentOzValue() >= NumericConstants.minimumQtyInOzDouble
        }
    }

    /// `true` whenever the canvas is wider than tall — iPhone
    /// landscape OR iPad in landscape orientation.
    ///   • iPhone landscape: `verticalSizeClass == .compact` is the
    ///     authoritative signal.
    ///   • iPad: stays `regular/regular` in both orientations, so we
    ///     fall back to a `UIScreen` bounds compare. `orientationTick`
    ///     is read here purely so SwiftUI re-evaluates the flag when
    ///     the rotation observer increments it.
    /// Used by `body` to swap between the portrait stack and the
    /// landscape side-by-side layout requested by QA (units +
    /// segmented + save + description on the LEFT, picker on the
    /// RIGHT).
    private var isLandscape: Bool {
        _ = orientationTick
        if verticalSizeClass == .compact { return true }
        if UIDevice.current.userInterfaceIdiom == .pad {
            let bounds = UIScreen.main.bounds
            return bounds.width > bounds.height
        }
        return false
    }

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

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button — UIKit `aiP-o8-GAQ`. Routed through the
            // standard `.toolbar` API so iOS 26+ wraps it in a
            // Liquid-Glass capsule automatically (matches the back
            // button on Preferences, MyProfile, RecipeDetail, etc.).
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticService.light()
                    dismiss()
                } label: {
                    Image("back")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 15,
                            height: UIDevice.current.userInterfaceIdiom == .pad ? 22 : 15
                        )
                        .foregroundStyle(Color("appBlackColor"))
                }
                .accessibilityLabel("Back")
            }

            // Center: device ICON ONLY (if connected). UIKit
            // `SelectQuantityViewController.swift` hides
            // `lblDeviceName` in `viewDidLoad` and never reverses
            // it; only the 25×25 `imgDevice` is visible.
            //
            // Gated on `ble.isAnyDeviceConnected` first (a direct
            // `@Published` read) so SwiftUI re-evaluates the toolbar
            // when the BLE connection state changes — matching the
            // pattern used by MyProfile / Preferences / ScanIngredients
            // / Favorites. Reading only `!deviceImageName.isEmpty`
            // hides this dependency behind method calls and the
            // principal item can stay missing after a late connect.
            if ble.isAnyDeviceConnected, !deviceImageName.isEmpty {
                ToolbarItem(placement: .principal) {
                    DevicePrincipalIcon(assetName: deviceImageName,
                                        accessibilityLabel: deviceDisplayName)
                }
            }

            // Right: fav + profile — shared 100×48 glass pill
            // (iOS 26+) or bare 61×24 icon stack (pre-26).
            // 1:1 UIKit `navigationRightGlassView` parity, identical
            // to PreferencesView / MyProfileView / ControlCenter.
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

            // Keyboard accessory toolbar — UIKit
            // `addDoneCancelToolbar(onDone:onCancel:)` attached to
            // both `txtInput` and `txtInputDecimals`. SwiftUI's
            // `.keyboard` placement surfaces the same Cancel/Done
            // pair above the decimal-pad keyboard:
            //   • Cancel → `onCancelManualInput` (UIKit `onCancel`
            //     / `onCancelForDecimalsField`) — reverts the picker
            //     rows to their pre-edit snapshot.
            //   • Done → `onDoneManualInput` (UIKit `tapDone` /
            //     `tapDoneForDecimalsField`) — validates, caps, and
            //     snaps the picker to the typed value.
            ToolbarItemGroup(placement: .keyboard) {
                Button(ConstantButtonsTitle.cancelButtonTitle) {
                    onCancelManualInput()
                }
                Spacer()
                Button("Done") {
                    onDoneManualInput()
                }
                .fontWeight(.semibold)
            }
        }
        // Flat `primaryBackgroundColor` nav bar so the iOS 26
        // top-right glass pill renders against the same canvas as
        // HomeView (ChooseOptions) — makes the material blur +
        // capsule stroke read identical to PreferencesView, MyProfile,
        // ControlCenter, etc. Without this, the nav-bar picks up a
        // lighter Liquid-Glass tint than the page body.
        .chooseOptionsStyleNavBar()
        // Re-enable swipe-back gesture (custom back chevron above
        // hides the system one, which would otherwise disable
        // `interactivePopGestureRecognizer`).
        .interactivePopGestureEnabled()
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
        .onAppear {
            seedFromRouterIfNeeded()
            // iPad keeps `regular/regular` size classes in both
            // orientations, so the iPad branch of `isLandscape` reads
            // `UIScreen.main.bounds` instead. That sample never
            // updates without an explicit rotation notification, so
            // we kick UIKit to start emitting them here (mirroring
            // `ControlCenterScreens`).
            if !UIDevice.current.isGeneratingDeviceOrientationNotifications {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            }
        }
        // Re-evaluate `isLandscape` on every rotation. iPhone gets
        // this for free through `verticalSizeClass`; iPad needs the
        // explicit tick because its size classes stay regular/regular.
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIDevice.orientationDidChangeNotification
            )
        ) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                orientationTick &+= 1
            }
        }
    }

    // MARK: - Portrait body
    //
    // Vertical stack: units row at top, picker below, Save + maximum
    // volume pinned to the bottom via `safeAreaInset`. This is the
    // 1:1 UIKit storyboard layout.

    @ViewBuilder
    private var portraitBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Units row — UIKit `qO5-ij-LNB` (height 40pt).
                unitsRow
                    .padding(.horizontal, 17)
                    .padding(.top, 10)

                // Picker — UIKit `U93-ue-cgA` (327×300, 24pt
                // leading/trailing). The ZStack here is sized to
                // match the UIKit `pickerView` frame so the centre
                // band (where the picker's selection sits and where
                // the manual-input TextFields hover) lines up
                // pixel-for-pixel with the storyboard.
                pickerStack
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
        }
        // Bottom container — UIKit `Bgh-7a-Hfr` (122pt tall), pinned
        // via `safeAreaInset` so the Save button stays visible
        // regardless of content size. Using `safeAreaInset` instead of
        // a sibling `VStack` keeps `ScrollView` as the root view —
        // iOS 26's Liquid-Glass nav bar attaches to the scrollable
        // surface, which is what restores the glass capsule around
        // the back button + the right-hand favourites/profile pill.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                maximumVolumeLabel
                saveButton
            }
            .padding(.horizontal, 17)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(Color("primaryBackgroundColor"))
        }
    }

    // MARK: - Landscape body
    //
    // Two columns, side by side. The LEFT column stacks the Units
    // section ABOVE the Save section (Save button + Maximum Volume
    // caption). The RIGHT column holds the picker. The split keeps
    // the long-form fields together on one side and lets the wheel
    // breathe on the other:
    //
    //   ┌──────────────────────────┬───────────────────────────┐
    //   │  Units                   │                           │
    //   │  Your preferred …        │     ┌────┬─┬────┐         │
    //   │  [ ML │ OZ ]             │     │    │ │    │         │
    //   │                          │     │ 10 │•│ 00 │         │
    //   │  ┌────────────┐          │     │    │ │    │         │
    //   │  │   Save     │          │     └────┴─┴────┘         │
    //   │  └────────────┘          │                           │
    //   │  Maximum Volume: 750 ml. │                           │
    //   └──────────────────────────┴───────────────────────────┘
    //
    // Layout choices:
    //   • Outer `HStack` uses `.top` alignment so the Units section
    //     pins to the top of the canvas while a `Spacer` between
    //     Units and Save pushes Save toward the vertical middle —
    //     keeping the LEFT column readable top-down regardless of
    //     canvas height.
    //   • Each column uses `frame(maxWidth: .infinity)` so they
    //     share the canvas 50/50.
    //   • The picker sits inside its own VStack so the wheel is
    //     vertically centred against the LEFT column's content.

    @ViewBuilder
    private var landscapeBody: some View {
        HStack(alignment: .center, spacing: 24) {
            // ─── LEFT column: Units section + Save section in a
            //     single VStack with `.leading` alignment.
            //
            // Switching the outer VStack to `.leading` (and the
            // inner Save VStack to `.leading` too) pins the
            // following four leading edges to the SAME X:
            //
            //     • "Units" label
            //     • "Your preferred measuring unit." caption
            //     • ML / OZ segmented control
            //     • Save button
            //     • Maximum Volume caption
            //
            // That gives the Save button the same leading X as the
            // ML/OZ control above it — which is exactly the user's
            // ask ("leading of save button and ml oz button set
            // similar leading").
            //
            // The whole VStack is still vertically centred inside
            // the column via `.frame(maxHeight: .infinity,
            // alignment: .leading)` (which resolves to centre Y +
            // leading X).
            VStack(alignment: .leading, spacing: 28) {
                // 1. Units section — UIKit `qO5-ij-LNB` content
                //    stacked vertically (title + caption + ML/OZ
                //    segmented control). Already `.leading`
                //    internally, so all three rows hug X=0.
                unitsRowLandscape

                // 2. Save section — Save / Add button on top with
                //    the "Maximum Volume" caption beneath, both
                //    pinned to the SAME leading edge as the ML/OZ
                //    segmented control directly above.
                VStack(alignment: .leading, spacing: 10) {
                    saveButton
                    maximumVolumeLabel
                }
            }
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .leading)

            // ─── RIGHT column: picker (vertically centred). ───
            pickerStack
                .frame(width: 240, height: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .center)
                .padding(.trailing, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared building blocks

    /// Save / Add button — UIKit `K1N-67-kPf`. 150×45, 20pt corner
    /// radius. UIKit `SelectQuantityViewController.bindViewModel`
    /// toggles the background between `sideMenuSelectionColor`
    /// (enabled) and `UIColor.lightGray` (disabled) via the
    /// `onUpdateSaveButtonState` callback — mirrored here through
    /// `isSaveEnabled`. Font is `AppFontClass.font(.body)` ≈ 17pt
    /// regular.
    @ViewBuilder
    private var saveButton: some View {
        Button {
            HapticService.success()
            handleSave()
        } label: {
            Text(isAddingNewIngredient ? "Add" : "Save")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.white)
                .frame(width: 150, height: 45)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSaveEnabled
                              ? Color("sideMenuSelectionColor")
                              : Color("lightGrayColor"))
                )
        }
        .disabled(!isSaveEnabled)
        .accessibilityLabel(isAddingNewIngredient ? "Add" : "Save")
        .accessibilityHint("Saves the selected quantity")
    }

    /// Maximum-volume label — UIKit `pP0-XI-Ftn`. 17pt semibold,
    /// `mediumLightGrayColor`, centred.
    @ViewBuilder
    private var maximumVolumeLabel: some View {
        Text(minimumVolumeText)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color("mediumLightGrayColor"))
            .multilineTextAlignment(.center)
            .accessibilityLabel(minimumVolumeText)
    }

    /// Landscape variant of `unitsRow`. Same content (Units title,
    /// caption, ML/OZ segmented control), but the segmented control
    /// drops UNDER the description so the LEFT column reads top-down
    /// instead of left-right. Matches the user request — "units
    /// label and ml oz in left side in landscape".
    @ViewBuilder
    private var unitsRowLandscape: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Units")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color("veryDarkGrayColor"))
                Text("Your preferred measuring unit.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color("appBlackColor"))
            }

            unitSegmentedControl
                .frame(width: 100, height: 31)
        }
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
    //
    // 1:1 with UIKit `pickerView` (`U93-ue-cgA` — 327×300pt, row
    // height 48pt, component width 80pt from
    // `pickerView(_:widthForComponent:)`) with TWO overlay
    // `UITextField`s (`Joa-xS-fU7`, `3yS-P6-FJF`) sitting at the
    // picker centre. SwiftUI replicates this with a `ZStack`:
    //
    //   • Background layer: `Picker(.wheel)` per UIKit component —
    //     ml has 1 picker (whole), oz has 2 pickers (whole + decimal).
    //     Frame width 80pt (UIKit `widthForComponent` = 80), height
    //     300pt (UIKit `pickerView` frame). 5pt gap matches UIKit
    //     stackView spacing `b7K-9c-B39`.
    //
    //   • Overlay layer: invisible `TextField`s at the same 80×50pt
    //     centre that capture tap → keyboard → manual entry. UIKit
    //     hides their text via `textColor = .clear`; SwiftUI uses
    //     `.foregroundStyle(.clear)` with `.tint(black)` so the caret
    //     remains visible while the picker's bold centre row reads as
    //     the on-screen value (matching `attributedTitleForRow`).
    //
    //   • Centre marker: 7×7 `roundCorners=3.5` black dot (UIKit
    //     `lblQtyFullStop` `H8Y-PZ-vjJ`), only in `.oz` mode. The
    //     storyboard label has `text=""`, `backgroundColor=black`,
    //     `width=7`, `height=7`, `roundCorners=3.5` — so it is a
    //     CIRCLE, NOT a literal "." glyph. We mirror that with
    //     `Circle().fill(.black).frame(width: 7, height: 7)`.

    @ViewBuilder
    private var pickerStack: some View {
        ZStack {
            // ─── Background: native UIPickerView-backed wheel(s) ───
            pickerWheels

            // ─── Overlay: tappable invisible text fields ───
            manualInputOverlay

            // ─── Centre marker: 7×7 black dot (oz only) ───
            if selectedUnit == .oz {
                Circle()
                    .fill(Color("appBlackColor"))
                    .frame(width: 7, height: 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var pickerWheels: some View {
        HStack(spacing: 5) {
            // Whole component — always shown. UIKit picker component 0.
            Picker("Whole quantity", selection: wholeRowBinding) {
                ForEach(wholeArray.indices, id: \.self) { idx in
                    Text("\(wholeArray[idx])")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color("appBlackColor"))
                        .tag(idx)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 80, height: 300)
            .clipped()

            if selectedUnit == .oz {
                // Decimal component — UIKit picker component 1.
                Picker("Decimal", selection: decimalRowBinding) {
                    ForEach(decimalArray.indices, id: \.self) { idx in
                        Text(decimalArray[idx])
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color("appBlackColor"))
                            .tag(idx)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 80, height: 300)
                .clipped()
            }
        }
    }

    // MARK: - Custom picker bindings (user-vs-programmatic gate)
    //
    // **Why a custom Binding instead of `$wholeRow` / `$decimalRow`**:
    //
    // UIKit's `pickerView(_:didSelectRow:inComponent:)` only fires
    // for USER-driven scrolls. The programmatic
    // `pickerView.selectRow(_:inComponent:animated:)` calls UIKit
    // makes inside `handleSegmentChange` / `setupPickerInitialSelection`
    // do NOT trigger the delegate, so `defaultValue` (the canonical
    // ml value) is preserved across ml↔oz transitions.
    //
    // SwiftUI's `.onChange(of:)` is symmetric — it fires for BOTH
    // user gestures and `@State` mutations. That meant the previous
    // implementation re-derived `quantityMl` from the picker rows
    // every time `positionPickerForCurrentQuantity` adjusted them
    // for a unit flip, drifting the value:
    //
    //   • Start: `quantityMl = 100` (user picked 100 ml)
    //   • Tap OZ → `positionPicker` sets `wholeRow=3, decimalRow=38`
    //     → `.onChange` fires → `recomputeQuantity` runs:
    //       `quantityMl = 3.38 / 0.033814 = 99.959`  ← DRIFT
    //   • Save at oz mode → posts 99.959 ml instead of 100 ml.
    //
    // The custom Binding pattern restores UIKit's user-vs-programmatic
    // split: the setter closure is invoked ONLY when SwiftUI's
    // Picker pushes a value through the binding (user gesture).
    // Direct `wholeRow = X` assignments by our own code (unit-switch
    // positioning, seed, manual-input commit, cancel-restore) update
    // the `@State` storage without ever calling the binding's
    // `set`. So `recomputeQuantity()` only runs on real user picker
    // scrolls — exactly the UIKit semantics.

    /// User-driven setter for the whole-component picker. Mirrors
    /// UIKit `pickerView(_:didSelectRow:inComponent: 0)`.
    private var wholeRowBinding: Binding<Int> {
        Binding<Int>(
            get: { wholeRow },
            set: { newValue in
                wholeRow = newValue
                // User scrolled — recompute the canonical ml value,
                // re-clamp the decimal row if we landed on the cap,
                // and refresh the manual-input buffers.
                recomputeQuantity()
                ensureDecimalWithinCap()
                syncFieldTextsFromRows()
            }
        )
    }

    /// User-driven setter for the decimal-component picker. Mirrors
    /// UIKit `pickerView(_:didSelectRow:inComponent: 1)`.
    private var decimalRowBinding: Binding<Int> {
        Binding<Int>(
            get: { decimalRow },
            set: { newValue in
                decimalRow = newValue
                recomputeQuantity()
                syncFieldTextsFromRows()
            }
        )
    }

    /// Tappable TextField overlay matching UIKit `Joa-xS-fU7` (whole)
    /// and `3yS-P6-FJF` (decimal). 80×50pt each, 5pt spacing, sat at
    /// the picker's centre band.
    ///
    /// **UIKit fidelity trick**: the UIKit fields have
    /// `textColor = .clear` and the picker's `attributedTitleForRow`
    /// reads `txtInput.text` to render the typed value at the centre
    /// row. SwiftUI's `Picker(.wheel)` does not expose its centre row
    /// for override, so we approximate by toggling the TextField's
    /// foreground:
    ///   • **Unfocused** → text is `.clear` so the picker's own bold
    ///     centre row reads through (exactly UIKit's resting state).
    ///   • **Focused** → text becomes black + opaque background so it
    ///     visually covers the picker centre row while the user types,
    ///     mirroring UIKit's "picker shows the typed value" effect.
    /// The 28pt bold font matches the picker rows so the on-screen
    /// number looks identical regardless of which layer is on top.
    @ViewBuilder
    private var manualInputOverlay: some View {
        HStack(spacing: 5) {
            // Whole-input TextField — UIKit `Joa-xS-fU7`.
            TextField("", text: $wholeFieldText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    focusedField == .whole
                        ? Color("appBlackColor")
                        : Color.clear
                )
                .tint(Color("appBlackColor").opacity(0.7))
                .frame(width: 80, height: 50)
                .background(
                    focusedField == .whole
                        ? Color("primaryBackgroundColor")
                        : Color.clear
                )
                .focused($focusedField, equals: .whole)
                .accessibilityLabel("Quantity value")
                .accessibilityHint("Enter quantity amount")
                .onChange(of: wholeFieldText) { newValue in
                    // UIKit `shouldChangeCharactersIn` runs on every
                    // keystroke. Sanitised here on `onChange` so the
                    // bound state never holds an invalid string.
                    let sanitised = sanitiseInput(newValue,
                                                  forField: .whole)
                    if sanitised != newValue {
                        wholeFieldText = sanitised
                    }
                }

            if selectedUnit == .oz {
                // Decimal-input TextField — UIKit `3yS-P6-FJF`. Only
                // mounted on oz to match `txtInputDecimals.isHidden`
                // logic in `setupView`.
                TextField("", text: $decimalFieldText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        focusedField == .decimal
                            ? Color("appBlackColor")
                            : Color.clear
                    )
                    .tint(Color("appBlackColor").opacity(0.7))
                    .frame(width: 80, height: 50)
                    .background(
                        focusedField == .decimal
                            ? Color("primaryBackgroundColor")
                            : Color.clear
                    )
                    .focused($focusedField, equals: .decimal)
                    .accessibilityLabel("Decimal value")
                    .accessibilityHint("Enter decimal portion")
                    .onChange(of: decimalFieldText) { newValue in
                        let sanitised = sanitiseInput(newValue,
                                                      forField: .decimal)
                        if sanitised != newValue {
                            decimalFieldText = sanitised
                        }
                    }
            }
        }
        .onChange(of: focusedField) { newValue in
            if newValue != nil {
                // UIKit `textFieldDidBeginEditing` — snapshot the
                // picker rows AND the canonical `quantityMl` so a
                // Cancel restores the exact pre-edit state. We
                // snapshot quantityMl separately because deriving
                // it from `oz` picker rows after Cancel would drift
                // it slightly (3.38 oz → 99.959 ml, not the original
                // 100). UIKit avoids the drift by leaving
                // `defaultValue` untouched during text-field edits;
                // we mirror that by snapshotting + restoring.
                preEditWholeRow = wholeRow
                preEditDecimalRow = decimalRow
                preEditQuantityMl = quantityMl
                syncFieldTextsFromRows()
            }
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
        // Initial text-field buffers must match the picker, otherwise
        // tapping the (invisible) field for the first time would
        // present a stale "0" against a non-zero picker selection.
        syncFieldTextsFromRows()
    }

    /// Snaps both picker components to the row(s) representing
    /// `quantityMl` in the current unit. UIKit
    /// `setupPickerInitialSelection`.
    ///
    /// ml ↔ oz conversion uses the SAME constant UIKit's
    /// `computeOzDefaultValue` uses: the free-floating `ounceValue`
    /// (= 0.033814 — multiplier from ml → oz). UIKit's reverse
    /// formula is `defaultValue = ozValue / ounceValue`. The
    /// previous SwiftUI port used the unrelated `oneMlValue`
    /// (= 29.5735) for multiplication, which is NOT the exact
    /// inverse of `ounceValue`. At the extreme cap that drift
    /// pushed 25.36 oz → 750.06 ml (≥ 750 cap) so Save was rejected
    /// with "exceeds 750 ml" even though UIKit allows the same
    /// picker selection — the QA-reported "cannot add 750 ml in
    /// refill station" failure. Dividing by `ounceValue` instead
    /// preserves UIKit's byte-for-byte conversion (25.36 oz →
    /// 749.985 ml < 750 cap).
    private func positionPickerForCurrentQuantity() {
        if selectedUnit == .ml {
            let target = Int(quantityMl.rounded())
            wholeRow = clampWholeRow(target)
        } else {
            // ml → oz: multiply by `ounceValue` to mirror UIKit's
            // `Quantity.convertDisplayForMixListIngredients` which uses
            // the same 0.033814 factor in the ml→oz direction.
            let oz = quantityMl * ounceValue
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
        // Re-sync the manual-input buffers so the (invisible) text
        // field shows the same value the picker just snapped to in
        // the new unit. UIKit's `handleSegmentChange` triggers the
        // same sync via its `onUpdateInputFieldText` /
        // `onUpdateDecimalFieldText` callbacks.
        syncFieldTextsFromRows()
    }

    // MARK: - Recompute quantity from picker rows

    /// Whenever the picker rows change, recompute `quantityMl` so
    /// the validation + save use the live value. UIKit
    /// `handlePickerDidSelectRow` + `computeOzDefaultValue`.
    ///
    /// **Critical conversion fix (QA: "cannot add 750 ml in refill")**
    /// UIKit's `computeOzDefaultValue`
    /// (SelectQuantityViewModel+PickerData.swift L128-134) computes
    /// `defaultValue = valueInOZSelected / ounceValue` where
    /// `ounceValue = NumericConstants.ounceConversionFactor` (= 0.033814).
    /// The previous SwiftUI port multiplied by `oneMlValue` (= 29.5735)
    /// — that constant is NOT the exact inverse of `ounceValue`. At the
    /// oz extreme:
    ///   • UIKit:    25.36 / 0.033814 ≈ 749.985 ml ✓ (under 750 cap)
    ///   • SwiftUI:  25.36 × 29.5735 ≈ 750.064 ml ✗ (over 750 cap)
    /// That 0.08 ml drift made `handleSave`'s `quantityMl > 750` check
    /// fire and surface the "exceeds 750 ml" alert at the maximum oz
    /// selection — blocking the entire "refill to full" flow in oz
    /// mode. Dividing by `ounceValue` matches UIKit byte-for-byte.
    private func recomputeQuantity() {
        if selectedUnit == .ml {
            let row = clampWholeRow(wholeRow)
            quantityMl = Double(wholeArray[row])
        } else {
            quantityMl = currentOzValue() / ounceValue
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

    // MARK: - Manual input → picker sync
    //
    // UIKit's tap-Done flow is split across
    // `SelectQuantityViewController+Actions.tapDone()` /
    // `tapDoneForDecimalsField()` (UI side) and the ViewModel's
    // `processTapDone(_:_:)` / `processTapDoneForDecimalsField(_:)`
    // (state side). The behaviour:
    //
    //   • If the user typed > max ⇒ snap picker to the cap row AND
    //     surface the matching "exceeds N" alert.
    //   • If the user typed a number that fits ⇒ snap picker to that
    //     row, recompute `defaultValue`.
    //   • Cancel ⇒ revert both pickers to their pre-edit rows; UIKit
    //     `handleOnCancel` / `handleOnCancelForDecimalsField` toggles
    //     `checkIsUserChangingQty / checkIsUserChangingDecimalQty`
    //     off and reloads the picker components.

    /// UIKit `tapDone` + `processTapDone(_:_:)`.
    private func onDoneManualInput() {
        let editingField = focusedField
        focusedField = nil

        if selectedUnit == .ml {
            applyMlManualInput()
        } else {
            // For oz, apply BOTH fields on Done so the picker
            // snaps to the typed whole + decimal pair in one shot.
            applyOzManualInput(editingField: editingField)
        }
    }

    /// UIKit `onCancel` / `onCancelForDecimalsField`. Reverts the
    /// picker rows AND the canonical `quantityMl` to their pre-edit
    /// values. We DO NOT call `recomputeQuantity` here — re-deriving
    /// `quantityMl` from the (restored) oz picker rows would drift
    /// it (e.g. 100 ml → 3.38 oz → 99.959 ml). Restoring the
    /// snapshot directly is byte-for-byte UIKit parity.
    private func onCancelManualInput() {
        wholeRow = preEditWholeRow
        decimalRow = preEditDecimalRow
        quantityMl = preEditQuantityMl
        focusedField = nil
        syncFieldTextsFromRows()
    }

    /// UIKit `processTapDone(_:_:)` for the ml branch. The picker
    /// snaps to `min(value, maxRow)` and an alert appears when the
    /// typed value exceeded the device cap (`> 750` for 360,
    /// `> 1500` for Coaster/Shaker).
    private func applyMlManualInput() {
        let typed = Double(wholeFieldText) ?? 0
        let cap: Double = ble.isBarsys360Connected()
            ? NumericConstants.maximumQuantityDoubleMLFor360
            : NumericConstants.maximumQuantityDoubleMLForCoaster
        let capAlert: String = ble.isBarsys360Connected()
            ? Constants.enterQuantityAlert750Ml
            : Constants.enterQuantityAlert1500Ml

        if typed > cap {
            wholeRow = clampWholeRow(wholeArray.count - 1)
            recomputeQuantity()
            syncFieldTextsFromRows()
            alertMessage = capAlert
            return
        }
        // Round to the nearest whole row (UIKit uses
        // `defaultTemp?.rounded()`).
        let rounded = Int(typed.rounded())
        wholeRow = clampWholeRow(rounded)
        recomputeQuantity()
        syncFieldTextsFromRows()
    }

    /// UIKit `processTapDone(_:_:)` (oz branch) +
    /// `processTapDoneForDecimalsField(_:)`. Caps to 25.36 / 50.72 Oz
    /// when the typed value would exceed the device limit, otherwise
    /// snaps both picker components and re-syncs the field text.
    private func applyOzManualInput(editingField: ManualInputField?) {
        let typedWhole = Double(wholeFieldText) ?? 0
        let typedDec = Double(decimalFieldText) ?? 0

        let is360 = ble.isBarsys360Connected()
        let wholeMax: Int = is360 ? 25 : 50
        let decMaxAtCap: Int = is360 ? 36 : 72
        let exceedAlert: String = is360
            ? Constants.enterQuantityAlert25OZ
            : Constants.enterQuantityAlert50OZ

        // Above the whole-cap → snap to the maximum oz value AND
        // alert (UIKit's "> 25" / "> 50" branches in
        // `processTapDone`).
        if typedWhole > Double(wholeMax) {
            wholeRow = clampWholeRow(wholeMax)
            // Decimal array shrinks to (decMaxAtCap + 1) entries when
            // whole == cap. After recomputing `decimalArray`, the
            // top-row index equals `decMaxAtCap`.
            decimalRow = decMaxAtCap
            recomputeQuantity()
            syncFieldTextsFromRows()
            alertMessage = exceedAlert
            return
        }

        // Fits in the whole cap — snap whole.
        let wholeRowIdx = Int(typedWhole)
        wholeRow = clampWholeRow(wholeRowIdx)

        // Decimal: when sitting on the max whole row the decimal
        // array is capped at decMaxAtCap; clamp the typed decimal
        // before assigning so we never overshoot the picker.
        let decTypedInt = Int(typedDec)
        if wholeRow == wholeMax {
            decimalRow = min(decTypedInt, decMaxAtCap)
            if decTypedInt > decMaxAtCap {
                // UIKit's `processTapDoneForDecimalsField` surfaces
                // the SAME 25.36/50.72 alert when the decimal is
                // overflowed at the cap row.
                recomputeQuantity()
                syncFieldTextsFromRows()
                alertMessage = exceedAlert
                return
            }
        } else {
            decimalRow = clampDecimalRow(decTypedInt)
        }

        recomputeQuantity()
        syncFieldTextsFromRows()
    }

    /// UIKit `shouldChangeCharactersIn(textField:range:replacementString:)`
    /// — port of the per-keystroke filter from
    /// `SelectQuantityViewModel.shouldChangeCharacters(in:range:replacementString:)`.
    /// • ml: digits only, no decimal separator, max 4 chars (cap
    ///   1500 is 4 digits).
    /// • oz whole: max 2 chars, no decimal separator.
    /// • oz decimal: max 2 chars, no decimal separator.
    private func sanitiseInput(_ raw: String,
                               forField field: ManualInputField) -> String {
        // Strip everything that isn't a digit. UIKit forbids the
        // decimal separator outright for both ml and the split
        // oz fields (the whole and decimal arrive in separate
        // text fields).
        var filtered = raw.filter { $0.isNumber }

        let maxLength: Int
        if selectedUnit == .ml {
            // UIKit `newText.count > 4` ⇒ reject.
            maxLength = 4
        } else {
            // UIKit `newText.count > 2` ⇒ reject.
            maxLength = 2
        }
        if filtered.count > maxLength {
            filtered = String(filtered.prefix(maxLength))
        }
        return filtered
    }

    /// Keeps the field-text buffers in lock-step with the picker row
    /// state. Called whenever the picker selection or unit changes so
    /// the (invisible) text field always reads the same value the
    /// picker renders. Equivalent to UIKit's
    /// `onUpdateInputFieldText` / `onUpdateDecimalFieldText`
    /// callbacks firing on every `pickerView(_:didSelectRow:)`.
    private func syncFieldTextsFromRows() {
        guard !wholeArray.isEmpty else { return }
        let safeWhole = clampWholeRow(wholeRow)
        wholeFieldText = "\(wholeArray[safeWhole])"
        if selectedUnit == .oz, !decimalArray.isEmpty {
            let safeDec = clampDecimalRow(decimalRow)
            decimalFieldText = decimalArray[safeDec]
        } else {
            decimalFieldText = "00"
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
