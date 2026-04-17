//
//  MyBarScreens.swift
//  BarsysAppSwiftUI
//

import SwiftUI

// MARK: - MyBar — 1:1 port of `MyBarViewController`
//
// UIKit hierarchy reproduced here:
//   • 60pt nav (back chevron, device-info principal, favourites button +
//     glass profile circle trailing — same pattern as the rest of the app).
//   • Two SECTION HEADERS with count badges:
//       - "Liquor (n)"  — base/spirit ingredients
//       - "Mixers (n)"  — mixer ingredients
//     Headers use AppFontClass.callout semibold + caption1 count badge in
//     `mediumLightGrayColor`.
//   • Each ingredient row: neomorphic pill, 14pt corner radius, bg
//     `tertiaryBackgroundColor` (#EDEDED), `appBlackColor` 14pt label,
//     36×36 delete button at trailing using the `deleteImg` asset.
//   • Bottom action bar (always visible when a device is connected):
//       - Empty state  → ["Take a Photo", "Add from Gallery"]
//       - Data state   → ["Add Photo", "Show Recipes"]
//   • Empty state body: wineglass icon + "No Ingredients Yet" + sub-copy +
//     two CTA buttons that route to the scan-ingredients screen.
//   • Delete tap → confirmation alert mirroring UIKit
//     `Constants.doYouWantToDeleteIngredient` / Yes-No buttons.
//   • Search filters across both sections by name (mirrors
//     `searchAndCloseButton` toggle in UIKit even though the storyboard
//     hides search by default).
//
// Functional parity:
//   • Two-category split via `category?.primary == "base"` vs `"mixer"`
//     (matches UIKit `processServerResponse()` mapping).
//   • `env.storage.toggleMyBar(_:)` performs the local removal — the real
//     `MyBarApiService` DELETE call hooks into the same path in production.
//   • `Constants.takeAPhoto / addFromPhotos / showRecipes` reused from
//     UIKit string table.

struct MyBarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

    @State private var query = ""
    @State private var pendingDelete: Ingredient?
    @State private var deletePopup: BarsysPopup? = nil

    /// All ingredients filtered by search query.
    private var allIngredients: [Ingredient] {
        let items = env.storage.myBarIngredients()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Ports `viewModel.liqourIngredientsArray`.
    private var liquorIngredients: [Ingredient] {
        allIngredients
            .filter { ($0.category?.primary ?? "").lowercased() == "base" }
            .sorted { $0.name < $1.name }
    }

    /// Ports `viewModel.mixerIngredientsArray`.
    private var mixerIngredients: [Ingredient] {
        allIngredients
            .filter { ($0.category?.primary ?? "").lowercased() == "mixer" }
            .sorted { $0.name < $1.name }
    }

    private var hasData: Bool {
        !liquorIngredients.isEmpty || !mixerIngredients.isEmpty
    }

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
        Group {
            if hasData {
                contentList
            } else {
                emptyState
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Flat `primaryBackgroundColor` nav bar so the top-right
        // `NavigationRightGlassButtons` pill renders on the same canvas
        // HomeView (ChooseOptions) uses — making the glass look
        // identical across both screens.
        .chooseOptionsStyleNavBar()
        .safeAreaInset(edge: .bottom) { bottomActionBar }
        // Delete ingredient popup — glass-card style matching UIKit
        .barsysPopup($deletePopup, onPrimary: {
            if let ingredient = pendingDelete {
                env.storage.toggleMyBar(ingredient)
            }
            pendingDelete = nil
        }, onSecondary: {
            pendingDelete = nil
        })
    }

    // MARK: - Content list

    @ViewBuilder
    private var contentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                searchField
                if !liquorIngredients.isEmpty {
                    section(title: "Liquor", items: liquorIngredients)
                }
                if !mixerIngredients.isEmpty {
                    section(title: "Mixers", items: mixerIngredients)
                }
                Color.clear.frame(height: 100) // bottom action-bar clearance
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "magnifyingglass" : "xmark")
                .font(.system(size: 14))
                .foregroundStyle(Color("mediumGrayColor"))
                .frame(width: 36, height: 44)
                .onTapGesture { if !query.isEmpty { query = "" } }
            TextField("Search My Bar", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(Color("appBlackColor"))
                .submitLabel(.search)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("barbotBorderColor"), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section(title: String, items: [Ingredient]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("appBlackColor"))
                Text("(\(items.count))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("mediumLightGrayColor"))
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(items.count) item\(items.count == 1 ? "" : "s")")

            VStack(spacing: 8) {
                ForEach(items) { ingredient in
                    ingredientRow(ingredient)
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        HStack(spacing: 12) {
            Text(ingredient.name)
                .font(.system(size: 14))
                .foregroundStyle(Color("appBlackColor"))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                HapticService.light()
                pendingDelete = ingredient
                deletePopup = .confirm(
                    title: "Delete ingredient?",
                    message: "Remove \(ingredient.name) from your bar?",
                    primaryTitle: ConstantButtonsTitle.deleteButtonTitle,
                    secondaryTitle: ConstantButtonsTitle.cancelButtonTitle,
                    isDestructive: true
                )
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color("mediumGrayColor"))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(ingredient.name)")
            .accessibilityHint("Removes this ingredient from your bar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("tertiaryBackgroundColor"))
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "wineglass")
                .font(.system(size: 56))
                .foregroundStyle(Color("mediumGrayColor"))
            Text("No Ingredients Yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color("appBlackColor"))
            Text("Add spirits and mixers to build your bar.")
                .font(.system(size: 14))
                .foregroundStyle(Color("mediumLightGrayColor"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No ingredients yet. Add spirits and mixers to build your bar.")
    }

    // MARK: - Bottom action bar

    @ViewBuilder
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            // Glass cancel capsule — secondary CTA.
            Button {
                HapticService.light()
                router.push(.scanIngredients, in: .myBar)
            } label: {
                Label(hasData ? "Add Photo" : "Take a Photo",
                      systemImage: "camera.fill")
                    .cancelCapsule(height: 45, cornerRadius: 8)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(hasData ? "Add Photo" : "Take a Photo")
            .accessibilityHint("Scan an ingredient with the camera")

            // Brand gradient capsule — primary CTA.
            Button {
                HapticService.light()
                if hasData {
                    router.push(.exploreRecipes, in: .myBar)
                } else {
                    router.push(.scanIngredients, in: .myBar)
                }
            } label: {
                Label(hasData ? "Show Recipes" : "Add from Gallery",
                      systemImage: hasData ? "list.bullet.rectangle" : "photo")
                    .brandCapsule(height: 45, cornerRadius: 8)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(hasData ? "Show Recipes" : "Add from Gallery")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(Theme.Gradient.bottomScrim)
    }

    // MARK: - Toolbar (60pt nav parity)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // UIKit parity — icon only, 25×25, name label hidden
        // (MyBarViewController.swift:153 sets `lblDeviceName.isHidden
        // = true` in `viewWillAppear` and never reverses it).
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
}

struct ScanIngredientsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var scanned: String?

    var body: some View {
        ZStack {
            QRScannerView(onScan: { code in
                scanned = code
                env.alerts.show(message: "Scanned ingredient code: \(code)")
            }, onCancel: {
                dismiss()
            })
            .ignoresSafeArea()

            VStack {
                Spacer()
                Text("Point the camera at an ingredient barcode")
                    .font(Theme.Font.body(14))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.m)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Scan ingredient")
        .navigationBarTitleDisplayMode(.inline)
    }
}
