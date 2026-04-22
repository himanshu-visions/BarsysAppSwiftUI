//
//  ReadyToPourView.swift
//  BarsysAppSwiftUI
//
//  1:1 port of `ReadyToPourListViewController` + its +TableView,
//  +Search, +Actions extensions.
//
//  UIKit hierarchy (storyboard ReadyToPour scene):
//   • 60pt header: back chevron, device-info principal, glass
//     navigation pill (favourite + profile).
//   • Title: "Ready To Pour" / mixlist name, system 24pt, appBlackColor.
//   • Two tables (recipes + mixlists), toggled by bottom tab bar.
//   • Bottom tab bar: "Recipes" / "Mixlists" tabs, 45pt height,
//     roundCorners 8, selected=white+bold / deselected=clear+regular.
//   • No-data label: bold 20pt, mediumLightGrayColor, centered.
//
//  Data flow:
//   • Recipes filtered via `readyToPourMixlists` / `recipesMatchingIngredients`
//     from storage using the device's station ingredients.
//   • Each recipe row: glass card, image, title, ingredients, favourite
//     button, craft button — same MixlistDetailTableViewCell layout.
//

import SwiftUI

// MARK: - Tab enum

private enum ReadyToPourTab: Int, CaseIterable {
    case recipes = 0
    case mixlists = 1
    var title: String { self == .recipes ? "Recipes" : "Mixlists" }
}

// MARK: - View

struct ReadyToPourView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

    @State private var selectedTab: ReadyToPourTab = .recipes
    @State private var recipes: [Recipe] = []
    @State private var mixlists: [Mixlist] = []
    @State private var selectedMixlist: Mixlist? = nil
    @State private var didLoad = false

    /// 1:1 with UIKit `ReadyToPourListViewController+Search.swift`
    /// `getMixlists` (L67-85). When the Mixlists tab is loaded and
    /// the array is empty, a modal alert prompts the user to tap
    /// "Explore" (→ push MixlistViewController) or "Dismiss".
    @State private var noMixlistsPopup: BarsysPopup? = nil

    // Toolbar device helpers
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

    /// UIKit title: mixlist name when viewing a mixlist, "Ready To Pour" otherwise.
    private var screenTitle: String {
        if let ml = selectedMixlist { return ml.displayName }
        return Constants.readyToPourTitle
    }

    /// Recipes for display — if a mixlist is selected show its recipes,
    /// otherwise show the matched ready-to-pour recipes.
    private var displayRecipes: [Recipe] {
        if let ml = selectedMixlist { return ml.recipes ?? [] }
        return recipes
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title — UIKit: x=24 y=65, system 24pt, appBlackColor, 2 lines
            Text(screenTitle)
                .font(.system(size: 24))
                .foregroundStyle(Color("appBlackColor"))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            // Content area
            if selectedTab == .recipes {
                if displayRecipes.isEmpty {
                    noDataView(text: "No recipes available.\nTry adding ingredients to your Barsys 360 stations.")
                } else {
                    recipesListView
                }
            } else {
                if selectedMixlist != nil {
                    // Showing recipes within a selected mixlist
                    if displayRecipes.isEmpty {
                        noDataView(text: "No recipes in this mixlist.")
                    } else {
                        recipesListView
                    }
                } else if mixlists.isEmpty {
                    noDataView(text: "No mixlists available.\nTry adding ingredients to your Barsys 360 stations.")
                } else {
                    mixlistsListView
                }
            }

            Spacer(minLength: 0)

            // Bottom tab bar — UIKit: oNM-a6-h0g, two equal buttons, 45pt, 8pt corners
            if !AppStateManager.shared.isSpeakEasyCase {
                tabBar
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .chooseOptionsStyleNavBar()
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            Task { await loadData() }
        }
        // 1:1 with UIKit `ReadyToPourListViewController+Search.swift`
        // `getMixlists` (L67-85). When the Mixlists tab loads an empty
        // list, surface the "No mixlists available — Tap Explore"
        // alert; Continue routes to the Explore Mixlists screen,
        // Dismiss closes silently.
        .barsysPopup($noMixlistsPopup, onPrimary: {
            // Primary (RIGHT, "Explore") — push MixlistView under the
            // current tab, matching UIKit's `navigationController?.push
            // (MixlistViewController)`.
            router.push(.exploreRecipes)
        }, onSecondary: {
            // Secondary (LEFT, "Dismiss") — no-op.
        })
        .onChange(of: selectedTab) { newTab in
            triggerNoMixlistsAlertIfNeeded(tab: newTab)
        }
    }

    /// Shows the UIKit "No mixlists available" alert when the user
    /// selects the Mixlists tab and the fetched list is empty. Guarded
    /// against re-showing if the alert is already up and against
    /// showing inside a selected-mixlist drill-down.
    private func triggerNoMixlistsAlertIfNeeded(tab: ReadyToPourTab) {
        guard tab == .mixlists else { return }
        guard selectedMixlist == nil else { return }
        guard didLoad else { return }
        guard mixlists.isEmpty else { return }
        guard noMixlistsPopup == nil else { return }
        noMixlistsPopup = .confirm(
            title: Constants.noMixlistsTapExploreMessage,
            message: nil,
            primaryTitle: ConstantButtonsTitle.exploreButtonTitle,
            secondaryTitle: ConstantButtonsTitle.dismissButtonTitle,
            primaryFillColor: "segmentSelectionColor",
            isCloseHidden: true
        )
    }

    // MARK: - Recipes list (MixlistDetailTableViewCell layout)

    private var recipesListView: some View {
        let cellWidth = UIScreen.main.bounds.width - 48
        let rowHeight = cellWidth / 2

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayRecipes) { recipe in
                    Button {
                        router.push(.recipeDetail(recipe.id))
                    } label: {
                        ReadyToPourRecipeRow(
                            recipe: recipe,
                            cellHeight: rowHeight,
                            onFavourite: { toggleFavourite(recipe) },
                            onCraft: { craftRecipe(recipe) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 15)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Mixlists list (MixlistRowCell reuse)

    private var mixlistsListView: some View {
        let cellWidth = UIScreen.main.bounds.width - 48
        let rowHeight = cellWidth / 2

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(mixlists) { mixlist in
                    Button {
                        HapticService.light()
                        selectedMixlist = mixlist
                        selectedTab = .recipes
                    } label: {
                        MixlistRowForReadyToPour(
                            mixlist: mixlist,
                            cellHeight: rowHeight
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 15)
            .padding(.bottom, 80)
        }
    }

    // MARK: - No data — UIKit: 1XD-UN-SbS, bold 20pt, mediumLightGrayColor, centered

    private func noDataView(text: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color("mediumLightGrayColor"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab bar — UIKit: two equal buttons, selected=white+bold, deselected=clear+regular

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(ReadyToPourTab.allCases, id: \.self) { tab in
                Button {
                    HapticService.light()
                    if tab == .mixlists && selectedMixlist != nil {
                        selectedMixlist = nil
                    }
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 14, weight: selectedTab == tab ? .bold : .regular))
                        // Selected-state text — preserve EXACT pure
                        // black in light mode (bit-identical to the
                        // previous hard-coded `Color.black`); switch
                        // to a near-white tone in dark mode for
                        // legibility on the dark surface pill.
                        // Trait-resolved at draw time → light pixels
                        // are unchanged.
                        .foregroundStyle(
                            selectedTab == tab
                                ? Color(UIColor { trait in
                                    trait.userInterfaceStyle == .dark
                                        ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                                        : UIColor.black // EXACT historical
                                })
                                : Color("unSelectedColor")
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 45)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                // Selected pill bg — `Theme.Color.surface`
                                // light = pure white sRGB(1, 1, 1),
                                // bit-identical to the previous
                                // `Color.white`. Dark mode picks up
                                // elevated dark surface (#2C2C2E) so
                                // the selected tab reads as a raised
                                // pill against the dark Ready-to-Pour
                                // page. Unselected stays clear.
                                .fill(selectedTab == tab ? Theme.Color.surface : Color.clear)
                        )
                }
                .buttonStyle(BounceButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // UIKit parity — icon only, 25×25, name label hidden
        // (ReadyToPourListViewController.swift:186 sets
        // `lblDeviceName.isHidden = true` and never reverses it).
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

    // MARK: - Data loading

    /// 1:1 port of UIKit
    /// `MixlistsUpdateClass.getBarsys360ReadyToPourRecipes` +
    /// `MixlistsUpdateClass.getBarsys360ReadyToPourMixlists`
    /// (MixlistsUpdateClass.swift L97-125 / L208-236):
    ///
    ///   1. Fetch the 6 A–F stations from the server.
    ///   2. If there are zero stations OR every station's ingredient
    ///      name is empty → return `[]` (no recipes / mixlists).
    ///   3. Build `allowedIngredients = [(primary, secondary)]` from
    ///      the currently-assigned station categories.
    ///   4. Delegate to `DBManager._fetchMatchingRecipeLists(...)` /
    ///      `_fetchReadyToPourMixlist(...)` which SQL-filter to only
    ///      keep recipes (and mixlists of recipes) whose **every**
    ///      non-garnish / non-additional ingredient's
    ///      `(categoryPrimary, categorySecondary)` pair is in the
    ///      allowed set — and which have **at least one** non-garnish
    ///      ingredient (the SQL uses an INNER JOIN which drops empty
    ///      recipes).
    ///
    /// The SwiftUI equivalents already exist in `StorageService`:
    ///   • `recipesMatchingIngredients(_:)` → mirrors
    ///     `_fetchMatchingRecipeLists`.
    ///   • `readyToPourMixlists(allowedIngredients:barsys360Only:)` →
    ///     mirrors `_fetchReadyToPourMixlist`.
    ///
    /// Previous bug: `loadData()` called `storage.allRecipes()
    /// .filter { barsys360Compatible == true }` which only checked
    /// a precomputed compatibility flag — NOT the currently-assigned
    /// stations. That surfaced recipes that had ingredients missing
    /// from the device (Barsys 360 cannot pour them) AND recipes
    /// with zero ingredients.
    @MainActor
    private func loadData() async {
        guard ble.isBarsys360Connected() else {
            // Non-360 devices don't have the per-station matching flow
            // in UIKit either — keep the existing "show everything"
            // fallback so Coaster / Shaker behaviour is unchanged.
            recipes = env.storage.allRecipes()
            mixlists = env.storage.allMixlists()
            return
        }

        let deviceName = ble.getConnectedDeviceName()
        let stations = await StationsAPIService.loadStations(deviceName: deviceName)

        // Step 2: empty station list OR every slot empty → show nothing.
        // Mirrors UIKit L99-110 — the two explicit `completion([])`
        // early-returns.
        guard !stations.isEmpty else {
            recipes = []
            mixlists = []
            return
        }
        let hasAnyIngredient = stations.contains { !$0.ingredientName.isEmpty }
        guard hasAnyIngredient else {
            recipes = []
            mixlists = []
            return
        }

        // Step 3: `allowedIngredients` from the currently-assigned
        // stations only. UIKit's loop
        // (MixlistsUpdateClass.swift L114-118) iterates every slot and
        // uses a tautological guard `primary != nil || primary != ""`
        // which is always true — harmless because empty slots have
        // empty category pairs that no recipe ingredient matches.
        // We take the cleaner route: skip slots with no assigned
        // ingredient, which yields the exact same SQL-filter result
        // but avoids pushing dummy `("","")` pairs downstream.
        let allowed: [(primary: String, secondary: String)] = stations.compactMap { slot in
            guard !slot.ingredientName.isEmpty else { return nil }
            let p = (slot.category?.primary ?? "").lowercased()
            let s = (slot.category?.secondary ?? "").lowercased()
            return (primary: p, secondary: s)
        }

        // Step 4: run the same filter UIKit does — every non-garnish
        // ingredient must match an assigned station category pair, and
        // the recipe must have at least one such ingredient.
        recipes = env.storage.recipesMatchingIngredients(allowed)
        mixlists = env.storage.readyToPourMixlists(
            allowedIngredients: allowed,
            barsys360Only: true
        )
    }

    // MARK: - Actions

    private func toggleFavourite(_ recipe: Recipe) {
        HapticService.light()
        let willBeFav = !(recipe.isFavourite ?? false)
        env.storage.toggleFavorite(recipe.id)
        // Re-read from storage to update UI
        Task { await loadData() }
        Task {
            do {
                _ = try await env.api.likeUnlike(recipeId: recipe.id.value, isLike: willBeFav)
            } catch {
                env.storage.toggleFavorite(recipe.id)
                await loadData()
            }
        }
        env.analytics.track(
            (willBeFav ? TrackEventName.favouriteRecipeAdded
                       : TrackEventName.favouriteRecipeRemoved).rawValue
        )
        env.alerts.show(message: willBeFav
                        ? Constants.likeSuccessMessage
                        : Constants.unlikeSuccessMessage)
    }

    private func craftRecipe(_ recipe: Recipe) {
        HapticService.light()
        guard ble.isAnyDeviceConnected else {
            // UIKit `ReadyToPourListViewController+Actions.swift` L92/L116 —
            // sets `pendingConnectionSource = .recipeCrafting` before
            // pushing PairYourDevice so the connect callback returns
            // to Ready to Pour (not Explore).
            router.promptPairDevice(isConnected: ble.isAnyDeviceConnected,
                                    source: .recipeCrafting)
            return
        }
        router.push(.crafting(recipe.id))
    }
}

// MARK: - ReadyToPourRecipeRow (ports MixlistDetailTableViewCell)
//
// Same layout as MixlistDetailRecipeRow but includes craft button.
// UIKit: glass card, 16pt corners, image 50% width 1:1, title 16pt,
// ingredients 10pt, craft button 29pt, favourite button 30×30.

struct ReadyToPourRecipeRow: View {
    let recipe: Recipe
    let cellHeight: CGFloat
    let onFavourite: () -> Void
    let onCraft: () -> Void

    private var isFavourite: Bool { recipe.isFavourite ?? false }

    private var optimizedImageURL: URL? {
        guard let raw = recipe.image?.url, !raw.isEmpty else { return nil }
        let optimized = raw
            .replacingOccurrences(of: "https://storage.googleapis.com/barsys-images-production/",
                                  with: "https://api.barsys.com/api/optimizeImage?fileUrl=https://media.barsys.com/")
        return URL(string: optimized)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left half — title + ingredients + craft button
            VStack(alignment: .leading, spacing: 0) {
                Text(recipe.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)

                if let info = recipe.ingredientNames, !info.isEmpty {
                    Text(info)
                        .font(.system(size: 10))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)

                // Craft button — 1:1 with UIKit recipe row craft button.
                //
                //   Pre-iOS 26 (ReadyToPourListViewController+TableView L35-38):
                //     backgroundColor = white
                //     roundCorners = BarsysCornerRadius.small (8pt)
                //     border 1pt craftButtonBorderColor
                //     font system 10pt semibold, black title
                //
                //   iOS 26+ (same file L54-57):
                //     `cell.craftButton.makeOrangeStyle()` — capsule
                //     (height/2) + brand gradient (brandGradientTop →
                //     brandGradientBottom), no border.
                //
                // Previously the SwiftUI row rendered the pre-26 white
                // style on all iOS versions — this broke the visual
                // rhythm on iOS 26 devices where the rest of the app
                // switches to gradient-capsule primary buttons.
                Button {
                    onCraft()
                } label: {
                    Text(Constants.craftTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .background(craftButtonBackground)
                        .overlay(craftButtonBorder)
                        .clipShape(craftButtonShape)
                }
                .buttonStyle(BounceButtonStyle())
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right half — image + favourite button
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: optimizedImageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        Color("lightBorderGrayColor")
                    case .failure:
                        Image("myDrink")
                            .resizable().aspectRatio(contentMode: .fit)
                            .padding(16)
                    @unknown default:
                        Color("lightBorderGrayColor")
                    }
                }
                .frame(width: cellHeight, height: cellHeight)
                .background(Color("lightBorderGrayColor"))
                .clipped()

                // Favourite button — UIKit: 30×30 (40×40 iOS 26+), prominentGlass
                Button { onFavourite() } label: {
                    Image(isFavourite ? "favIconRecipeSelected" : "favIconRecipe")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .frame(width: favButtonSize, height: favButtonSize)
                        .foregroundStyle(favButtonTint)
                }
                .glassButtonIfAvailable(size: favButtonSize)
                .buttonStyle(BounceButtonStyle())
                .padding(.top, 5)
                .padding(.trailing, 5)
            }
        }
        .frame(height: cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 12)
    }

    private var favButtonSize: CGFloat {
        if #available(iOS 26.0, *) { return 40 } else { return 30 }
    }
    private var favButtonTint: Color {
        if #available(iOS 26.0, *) {
            return Color.black.opacity(0.3)
        } else {
            return Color.white
        }
    }

    // 1:1 with UIKit `PrimaryOrangeButton.makeOrangeStyle()` applied at
    // runtime (ReadyToPourListViewController+TableView L54-57 gates on
    // `#available(iOS 26.0, *)`).

    @ViewBuilder
    private var craftButtonBackground: some View {
        if #available(iOS 26.0, *) {
            LinearGradient(
                colors: [Color("brandGradientTop"),
                         Color("brandGradientBottom")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
            // bit-identical to the previous hard-coded `Color.white`,
            // so light mode renders the EXACT same Craft button bg.
            // Dark mode picks up the elevated dark surface (#2C2C2E)
            // for adaptive pre-iOS 26 rendering.
            Theme.Color.surface
        }
    }

    @ViewBuilder
    private var craftButtonBorder: some View {
        if #available(iOS 26.0, *) {
            // UIKit `makeOrangeStyle()` has no explicit border — the
            // glass-highlight gradient on the capsule provides edge
            // definition by itself.
            EmptyView()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
        }
    }

    private var craftButtonShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - MixlistRowForReadyToPour (simplified mixlist cell)

struct MixlistRowForReadyToPour: View {
    let mixlist: Mixlist
    let cellHeight: CGFloat

    private var optimizedImageURL: URL? {
        guard let raw = mixlist.image?.url, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(mixlist.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let info = mixlist.ingredientNames, !info.isEmpty {
                    Text(info)
                        .font(.system(size: 10))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            AsyncImage(url: optimizedImageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    Color("lightBorderGrayColor")
                default:
                    Image("myDrink")
                        .resizable().aspectRatio(contentMode: .fit)
                        .padding(16)
                }
            }
            .frame(width: cellHeight, height: cellHeight)
            .background(Color("lightBorderGrayColor"))
            .clipped()
        }
        .frame(height: cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 12)
    }
}
