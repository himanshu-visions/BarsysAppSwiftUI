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
        VStack(alignment: .leading, spacing: 0) {
            // Page title — "Units" 24pt, leading 24, top 18
            Text("Units")
                .font(.system(size: 24))
                .foregroundStyle(Color("appBlackColor"))
                .padding(.leading, 24)
                .padding(.top, 18)

            // Unit selection row — ports UIKit unitSegmentedControl
            // UIKit: segmented control 72×32 on right, selectedSegmentTintColor = brandTanColor
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Units")
                        .font(.system(size: 16))
                        .foregroundStyle(Color("appBlackColor"))
                    Text("Your preferred measuring unit.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("mediumGrayColor"))
                }
                Spacer()
                // Segmented control matching UIKit: brandTanColor selected tint
                Picker("", selection: $preferences.measurementUnit) {
                    Text("ML").tag(MeasurementUnit.ml)
                    Text("OZ").tag(MeasurementUnit.oz)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .onAppear {
                    // Match UIKit selectedSegmentTintColor = brandTanColor
                    UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(named: "brandTanColor")
                    UISegmentedControl.appearance().setTitleTextAttributes(
                        [.foregroundColor: UIColor.black], for: .selected
                    )
                    UISegmentedControl.appearance().setTitleTextAttributes(
                        [.foregroundColor: UIColor.black.withAlphaComponent(0.6)], for: .normal
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer()
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
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color("appBlackColor"))
                }
            }

            // Center: device icon + name (if connected)
            if isConnected {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(deviceIconName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 25, height: 25)
                        Text(deviceKindName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color("appBlackColor"))
                    }
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
                    .listRowBackground(Color.white)
                }
            }
            .searchable(text: $query, prompt: "Search country")
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
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
                .listRowBackground(Color.white)
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

// MARK: - Select quantity

struct SelectQuantityView: View {
    /// UIKit `SelectQuantityViewController` receives a
    /// `StationCleaningFlow` (`flowToAdd`) whose `stationName` +
    /// `ingredientName` + `category` + `perishable` flags seed the
    /// refill. In SwiftUI we thread at minimum the ingredient name
    /// through the route; if callers need the full context they can
    /// park it on `router.pendingStationUpdate` before pushing.
    let ingredientName: String
    /// Optional originating station — when present, UIKit preserves it
    /// through the `getStationsDataNotif` payload so the refill lands
    /// on the SAME station regardless of selection changes made after
    /// the refill screen is pushed.
    var stationName: String? = nil
    /// Optional perishable flag carried over from the originating
    /// `StationCleaningFlow`.
    var isPerishable: Bool = false
    /// Optional category carried over from the originating
    /// `StationCleaningFlow`.
    var primaryCategory: String? = nil
    var secondaryCategory: String? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var quantity: Double = 30

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Text(ingredientName).font(Theme.Font.title())
                .foregroundStyle(Theme.Color.textPrimary)

            Text("\(Int(quantity)) ml")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.brand)

            Slider(value: $quantity, in: 5...250, step: 5)
                .tint(Theme.Color.brand)
                .pagePadding()

            HStack(spacing: Theme.Spacing.m) {
                ForEach([15, 30, 45, 60, 90], id: \.self) { v in
                    Button {
                        quantity = Double(v)
                    } label: {
                        Text("\(v)")
                            .font(Theme.Font.body(14))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.Color.surface, in: Capsule())
                            .foregroundStyle(Theme.Color.textPrimary)
                    }
                }
            }

            Spacer()

            PrimaryButton(title: "Confirm") { confirmRefill() }.pagePadding()
        }
        .padding(.vertical, Theme.Spacing.xl)
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Quantity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    /// 1:1 port of UIKit
    /// `SelectQuantityViewController.didPressConfirmAction`:
    ///   1. Posts `NotificationCenter.default.post(name: .getStationsDataNotif,
    ///                                             userInfo: [ingredient / quantity / category / … ])`
    ///   2. `navigationController?.popViewController(animated: true)`
    ///
    /// SwiftUI replaces the NotificationCenter hop with
    /// `router.postStationRefill(...)` — `StationsMenuView` observes
    /// `router.getStationsRefillTick` in `.onChange(of:)` and PUTs the
    /// station config + refetches + hides loader exactly like UIKit.
    private func confirmRefill() {
        HapticService.light()
        router.postStationRefill(
            AppRouter.PendingStationUpdate(
                ingredientName: ingredientName,
                quantityMl: quantity,
                primaryCategory: primaryCategory,
                secondaryCategory: secondaryCategory,
                isPerishable: isPerishable,
                isAddingNewIngredient: false, // refill, not add
                stationName: stationName
            )
        )
        dismiss()
    }
}
