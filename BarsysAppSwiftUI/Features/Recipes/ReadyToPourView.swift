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

    /// 1:1 port of UIKit title matrix
    /// (`ReadyToPourListViewController.setupView` L184-204 +
    /// `tabSelection(index:)` L24-63):
    ///
    ///   • On init, `mixlist != nil` → title = `mixlist.name`
    ///     (the pre-selected mixlist from Setup-Stations).
    ///   • Recipes tab + Barsys 360 connected (or SpeakEasy) →
    ///     `Constants.readyToPourTitle` ("Ready to Pour").
    ///   • Recipes tab + non-360 devices → `"Recipes"`.
    ///   • Mixlists tab + `mixlists.count == 1` → single mixlist's
    ///     name (UIKit auto-promotes that mixlist's recipes to the
    ///     tab's body — no card list shown).
    ///   • Mixlists tab + `mixlists.count > 1` → `"Mixlists"`
    ///     (UIKit shows the card list; on drill-in, title flips
    ///     to the drilled mixlist's name).
    ///   • Mixlists tab + count == 0 → `"Mixlists"` (fallback).
    private var screenTitle: String {
        // Drill-down (multi-mixlist state with a selected one) OR
        // single-auto-select wins over the tab-level default.
        if let ml = selectedMixlist { return ml.displayName }
        if selectedTab == .mixlists {
            if mixlists.count == 1 {
                return mixlists[0].displayName
            }
            return Constants.mixlistsTitle
        }
        // Recipes tab.
        if ble.isBarsys360Connected() || AppStateManager.shared.isSpeakEasyCase {
            return Constants.readyToPourTitle
        }
        return "Recipes"
    }

    /// 1:1 port of UIKit `ReadyToPourListViewModel.numberOfMixlistRows`:
    ///
    /// ```
    /// if mixlists.count > 1 && mixlist != nil {
    ///     return mixlist?.recipes?.count ?? 0     // drilled-in
    /// } else if mixlists.count == 1 {
    ///     return mixlists[0].recipes?.count ?? 0  // auto-selected
    /// } else {
    ///     return mixlists.count                   // card list
    /// }
    /// ```
    ///
    /// Drives BOTH the row source (recipes vs mixlist cards) and
    /// the correct "no data" empty-state copy.
    ///
    /// `recipesShownOnMixlistsTab` returns the recipe array to
    /// render as rows; nil means "render mixlist cards instead".
    private var recipesShownOnMixlistsTab: [Recipe]? {
        // Dedupe by recipe id — UIKit's SQL JOIN naturally dedupes via
        // the `mixlistrecipes` PK; SwiftUI keeps the API array verbatim,
        // so a mixlist payload with the same recipe twice (or a stale
        // selectedMixlist set before `CatalogService.preload()`'s dedupe
        // pass) would render duplicate rows. Without dedup, ForEach
        // renders both rows with the same `id`, and SwiftUI's
        // reconciliation only updates ONE of them when the favourite
        // state flips — the visible "tap heart, nothing happens on the
        // duplicate" bug the user reported.
        //
        // Always re-resolve the source from the LIVE `mixlists` array
        // by id rather than reading the cached `selectedMixlist` struct
        // directly. `selectedMixlist` is a value type captured when the
        // user drilled in, so it doesn't pick up the fresh
        // `isFavourite` flag projection that `loadData()` applies on
        // every storage refresh — without this re-resolve, tapping a
        // heart icon on a drilled-in mixlist row left the icon stuck on
        // the pre-tap state until the user backed out and re-entered.
        let source: [Recipe]?
        if mixlists.count > 1, let selected = selectedMixlist {
            let live = mixlists.first(where: { $0.id == selected.id }) ?? selected
            source = live.recipes ?? []
        } else if mixlists.count == 1 {
            source = mixlists[0].recipes ?? []
        } else {
            return nil
        }
        guard let arr = source else { return nil }
        var seen = Set<RecipeID>()
        return arr.filter { seen.insert($0.id).inserted }
    }

    /// Recipes to show on the Recipes tab. UIKit
    /// `numberOfRecipeRows` = `recipes.count` directly; drill-down
    /// into a mixlist only happens on the MIXLISTS tab. Previous
    /// SwiftUI port collapsed both tabs through a shared
    /// `displayRecipes` which broke the UIKit tab-independence
    /// semantic — tapping the Mixlists tab on a drill-down also
    /// flipped the Recipes tab's rows, which UIKit never does.
    private var displayRecipes: [Recipe] { recipes }

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

            // 1:1 port of UIKit
            // `ReadyToPourListViewController+TableView.numberOfMixlistRows`
            // + `cellForRowAt` matrix:
            //
            //   Recipes tab → rows = `recipes`.
            //   Mixlists tab + count == 1 → rows = `mixlists[0].recipes`
            //     (no card list; auto-drill-in to the lone mixlist).
            //   Mixlists tab + count > 1 + drilled-in → rows =
            //     `selectedMixlist.recipes`.
            //   Mixlists tab + count > 1 + NOT drilled-in → rows =
            //     mixlist CARDS.
            //   Mixlists tab + count == 0 → empty-state label.
            if selectedTab == .recipes {
                if displayRecipes.isEmpty {
                    noDataView(text: "No recipes available.\nTry adding ingredients to your Barsys 360 stations.")
                } else {
                    recipesListView
                }
            } else {
                // Mixlists tab.
                if let mlRecipes = recipesShownOnMixlistsTab {
                    // Either `mixlists.count == 1` (auto-promote) or
                    // `mixlists.count > 1 && selectedMixlist != nil`
                    // (drill-down). Either way render as recipe rows.
                    if mlRecipes.isEmpty {
                        noDataView(text: "No recipes in this mixlist.")
                    } else {
                        recipesListView(overrideRecipes: mlRecipes)
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
            // 1:1 port of UIKit
            // `RecipesCoordinator.showReadyToPour(…)` → assigns
            // `readyToPourVc.mixlist = mixlist` BEFORE push, and
            // `ReadyToPourListViewModel.initialTabSetup()`:
            //
            //   func initialTabSetup() {
            //       if mixlist != nil {
            //           tabSelectedIndex = 1        // MIXLISTS tab
            //       } else {
            //           tabSelectedIndex = 0        // RECIPES tab
            //       }
            //   }
            //
            // When the user comes from Setup Stations, the pushed
            // mixlist is the ONLY one they care about — UIKit flips
            // straight to the Mixlists tab, sets the screen title to
            // the mixlist name (via the tab-switching code that reads
            // `viewModel.mixlists[0].name` when `mixlists.count == 1`),
            // and `reloadRecipesData` fetches that mixlist's recipes
            // via `storage.fetchAllRecipesIdBase(for: mixlistId)`.
            //
            // SwiftUI equivalent: consume the pre-selected mixlist
            // from `router.setupStationsContext.mixlist` here and
            // set both `selectedMixlist` (title + recipe source) and
            // `selectedTab = .mixlists` (matches UIKit
            // `tabSelectedIndex = 1`). Then clear the context so
            // subsequent Control-Center entries don't see stale
            // setup data.
            if let ctx = router.setupStationsContext {
                selectedMixlist = ctx.mixlist
                selectedTab = .mixlists
                router.setupStationsContext = nil
            }
            // 1:1 port of UIKit
            // `MixlistsUpdateClass.updateMixlists(controller:)` +
            // `getBarsys360ReadyToPourRecipes { recipes in … }` chain
            // that runs BEFORE `RecipesCoordinator.showReadyToPour(…)`
            // pushes this screen (see
            // `StationsMenuViewModel+StationSetup.updateAllStationsWithRecipeIngredients`
            // L60-84 and the analogous calls from BarBot / My Bar
            // entry points).
            //
            // Running the refresh inside THIS view's `.onAppear`
            // rather than at every call site means every entry
            // point (setup-stations Proceed, BarBot "Show my
            // ready-to-pour", My Bar "Ready to Pour", tab switches)
            // renders the latest recipes/mixlists without each
            // call-site having to remember to refresh first. The
            // internal 30-second throttle in `CatalogService.preload`
            // makes this safe — rapid re-entries skip the network
            // call and just re-read storage.
            Task {
                await env.catalog.preload()
                await loadData()
                // 1:1 port of UIKit
                // `ReadyToPourListViewModel.reloadRecipesData()`
                // single-mixlist branch (L223-233):
                //
                //   guard let mixlistId = mixlist?.id else { return }
                //   storage.fetchAllRecipesIdBase(for: mixlistId) { fetched in
                //       self.recipes = fetched
                //       self.onRecipesReloaded?()
                //   }
                //
                // After the catalog refresh lands, look the
                // pre-selected mixlist up in the freshly-upserted
                // storage so its `recipes` array is populated with
                // the server's latest recipe payload — the initial
                // `ctx.mixlist` value captured at setup-time may
                // have been a stub with no nested `recipes`.
                await MainActor.run {
                    if let preselected = selectedMixlist,
                       let fresh = env.storage.allMixlists()
                        .first(where: { $0.id == preselected.id }) {
                        selectedMixlist = fresh
                    }
                }
            }
        }
        // 1:1 with UIKit `ReadyToPourListViewController+Search.swift`
        // `getMixlists` (L67-85). When the Mixlists tab loads an empty
        // list, surface the "No mixlists available — Tap Explore"
        // alert; the "Explore" action pushes MixlistViewController
        // (the "Cocktail Kits" mixlists list), NOT the explore-
        // recipes screen.
        .barsysPopup($noMixlistsPopup, onPrimary: {
            // Primary (RIGHT, "Explore") — 1:1 port of UIKit L76-78:
            //   `UIStoryboard(name: .mixlist).instantiateViewController(
            //    withIdentifier: .mixlist) as? MixlistViewController`
            //   `navigationController?.pushViewController(mixlistVc,…)`
            // The SwiftUI equivalent is `.mixlistList` (see
            // AppRouter.swift L75: `mixlistList  // "Cocktail Kits" —
            // ports MixlistViewController`). Previously this pushed
            // `.exploreRecipes` — the recipes-list screen — which
            // diverged from UIKit: the user tapped "Explore mixlists"
            // and landed on recipes instead of the Cocktail Kits list.
            router.push(.mixlistList)
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

    /// Renders the recipe-row list. `overrideRecipes` is used by the
    /// Mixlists tab's auto-promote / drill-in branches so those rows
    /// come from `mixlists[0].recipes` or `selectedMixlist.recipes`
    /// — matching UIKit `cellForRowAt` + `numberOfMixlistRows` which
    /// switches between `recipes`, `mixlist?.recipes`, and
    /// `mixlists[0].recipes` based on the `(tab, mixlists.count,
    /// mixlist != nil)` matrix.
    @ViewBuilder
    private func recipesListView(overrideRecipes: [Recipe]? = nil) -> some View {
        let cellWidth = UIScreen.main.bounds.width - 48
        let rowHeight = cellWidth / 2
        let source = overrideRecipes ?? displayRecipes

        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(source) { recipe in
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

    /// Computed-property shim so call-sites that referenced
    /// `recipesListView` as a View (not a function) still work. The
    /// function overload above handles the Mixlists-tab case with an
    /// explicit override.
    private var recipesListView: some View { recipesListView(overrideRecipes: nil) }

    // MARK: - Mixlists list (MixlistRowCell reuse)

    private var mixlistsListView: some View {
        let cellWidth = UIScreen.main.bounds.width - 48
        let rowHeight = cellWidth / 2

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(mixlists) { mixlist in
                    Button {
                        HapticService.light()
                        // 1:1 port of UIKit
                        // `ReadyToPourListViewController+TableView.didSelectRowAt`
                        // mixlists-tab branch (L310-330) when
                        // `mixlists.count > 1 && mixlist == nil`:
                        //
                        //   viewModel.selectMixlist(at: indexPath.row)
                        //   // mixlist = mixlists[row]; triggers
                        //   // onMixlistNameChanged + reloadRecipesData
                        //
                        // User stays on the MIXLISTS tab — drill-down
                        // renders the mixlist's recipes in the same
                        // tab body. Previously this port flipped
                        // `selectedTab = .recipes` on drill, which
                        // broke UIKit's tab-independence: Mixlists
                        // tap never changes to the Recipes tab.
                        selectedMixlist = mixlist
                        // selectedTab stays on .mixlists; body
                        // switches to recipe rows via
                        // `recipesShownOnMixlistsTab`.
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
                    // 1:1 port of UIKit
                    // `ReadyToPourListViewModel.selectRecipesTab()`
                    // + `didPressMixlistsButton` / `didPressRecipesButton`:
                    //
                    //   func selectRecipesTab() {
                    //       if mixlist != nil && mixlists.count > 1 {
                    //           mixlist = nil            // clear drill
                    //       }
                    //       tabSelectedIndex = 0
                    //   }
                    //
                    // Tapping Recipes clears the multi-mixlist drill-
                    // down (so user returns to the full Recipes list).
                    // Tapping Mixlists clears the drill-down too so
                    // the user lands back on the mixlist-card list
                    // (or auto-promoted single mixlist, matching
                    // UIKit's `numberOfMixlistRows` branch).
                    if tab == .recipes && mixlists.count > 1 {
                        selectedMixlist = nil
                    }
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
            recipes = uniqueByID(env.storage.allRecipes())
            mixlists = uniqueByID(env.storage.allMixlists().map(dedupedMixlist))
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

        // Step 3: `allowedIngredients` — 1:1 with UIKit
        // `MixlistsUpdateClass.getBarsys360ReadyToPourRecipes` L114-118:
        //
        // ```
        // for (pairIndex, ingredient) in AppNavigationState.shared.stationArray.enumerated() {
        //     if (ingredient.category.primary != nil || ingredient.category.primary != "") &&
        //        (ingredient.category.secondary != nil || ingredient.category.secondary != "") {
        //         allowedIngredients.append((
        //             primary: ingredient.category.primary?.lowercased(),
        //             secondary: ingredient.category.secondary?.lowercased()
        //         ))
        //     }
        // }
        // ```
        //
        // The guard `primary != nil || primary != ""` is tautologically
        // true for every station (nil → second clause true; non-nil →
        // first clause true), so UIKit ALWAYS pushes 6 entries into
        // `allowedIngredients` — including empty slots as
        // `("", "")` pairs. The previous SwiftUI port skipped empty
        // slots which made Ready-to-Pour STRICTER than UIKit and
        // hid legacy / user-created recipes whose ingredients have
        // blank categories (a blank-category recipe ingredient
        // matches an empty-station `("","")` pair in UIKit).
        //
        // Include ALL stations so the SQL filter sees the same
        // permissive allow-list UIKit produces.
        let allowed: [(primary: String, secondary: String)] = stations.map { slot in
            let p = (slot.category?.primary ?? "").lowercased()
            let s = (slot.category?.secondary ?? "").lowercased()
            return (primary: p, secondary: s)
        }

        // Step 4: run the same filter UIKit does — every non-garnish
        // ingredient must match an assigned station category pair, and
        // the recipe must have at least one such ingredient.
        // Belt-and-suspenders dedup at the @State boundary so a stray
        // duplicate from any upstream layer (API payload, persisted
        // cache, future storage-layer change) cannot leak duplicate
        // rows into the rendered list.
        recipes = uniqueByID(env.storage.recipesMatchingIngredients(allowed))
        mixlists = uniqueByID(
            env.storage.readyToPourMixlists(
                allowedIngredients: allowed,
                barsys360Only: true
            ).map(dedupedMixlist)
        )
    }

    /// Drop duplicate elements that share the same `id`, keeping the
    /// first occurrence. Generic over `Identifiable` so it works for
    /// both `[Recipe]` and `[Mixlist]`.
    private func uniqueByID<Element: Identifiable>(_ items: [Element]) -> [Element] {
        var seen = Set<Element.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// Return a copy of the mixlist whose nested `recipes` array has
    /// any same-id duplicates stripped (keeping the first occurrence).
    /// `MockStorageService.allMixlists()` already projects + dedupes
    /// nested recipes; this is a render-side guarantee that survives
    /// future storage-layer changes.
    private func dedupedMixlist(_ mixlist: Mixlist) -> Mixlist {
        guard let nested = mixlist.recipes, !nested.isEmpty else { return mixlist }
        var seen = Set<RecipeID>()
        let deduped = nested.filter { seen.insert($0.id).inserted }
        if deduped.count == nested.count { return mixlist }
        var copy = mixlist
        copy.recipes = deduped
        return copy
    }

    // MARK: - Actions

    private func toggleFavourite(_ recipe: Recipe) {
        HapticService.light()
        // Read the AUTHORITATIVE current state from the favs Set, not
        // from the recipe struct's flag. The struct flag can diverge
        // from the favs Set after a `CatalogService.preload()` re-fetch
        // (the API recipe payload doesn't carry isFavourite, so the
        // upsert resets the flag while the favs Set still has the id).
        // Driving `willBeFav` off `recipe.isFavourite` was causing the
        // wrong toggle direction — user tapped "Add to Favorites" on a
        // row showing a hollow heart, but storage already had the id and
        // `toggleFavorite` actually REMOVED it.
        let isCurrentlyFav = env.storage.favorites().contains(recipe.id)
        let willBeFav = !isCurrentlyFav
        env.storage.setFavorite(recipe.id, isFavorite: willBeFav)

        // Synchronously flip the in-flight `recipes` + `mixlists` arrays
        // so the ForEach re-renders the heart icon on the SAME tap. A
        // subsequent `loadData()` for Barsys 360 users hits an async
        // `StationsAPIService.loadStations(...)` round-trip (1-2s on a
        // real device) — without this in-place mutation the row stays
        // visually stuck on the pre-tap state until the station fetch
        // finishes. Mutating both `recipes` and `mixlists[].recipes`
        // mirrors what storage's `allRecipes()` + `allMixlists()` would
        // return on the next read, just without waiting for the network.
        applyFavouriteToLocalState(recipeID: recipe.id, isFavourite: willBeFav)

        // Re-read from storage to update UI on the main actor so the
        // ForEach re-renders with the fresh isFavourite flag in the
        // same render pass as the tap.
        Task { @MainActor in await loadData() }
        Task {
            do {
                _ = try await env.api.likeUnlike(recipeId: recipe.id.value, isLike: willBeFav)
            } catch {
                // Revert on failure — explicit setFavorite back to the
                // pre-tap state, not toggle, so we don't bounce twice.
                env.storage.setFavorite(recipe.id, isFavorite: isCurrentlyFav)
                await MainActor.run {
                    applyFavouriteToLocalState(recipeID: recipe.id, isFavourite: isCurrentlyFav)
                    Task { await loadData() }
                }
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

    /// Synchronously mirror a favourite-state change onto every local
    /// copy of the recipe — top-level `recipes` (Recipes-tab source)
    /// AND the nested `recipes` arrays inside each `mixlists[i]`
    /// (Mixlists-tab source). Lets the ForEach re-render instantly on
    /// tap without waiting for the next `loadData()` round-trip.
    private func applyFavouriteToLocalState(recipeID: RecipeID, isFavourite: Bool) {
        for i in recipes.indices where recipes[i].id == recipeID {
            recipes[i].isFavourite = isFavourite
        }
        for i in mixlists.indices {
            guard var nested = mixlists[i].recipes else { continue }
            var didMutate = false
            for j in nested.indices where nested[j].id == recipeID {
                nested[j].isFavourite = isFavourite
                didMutate = true
            }
            if didMutate { mixlists[i].recipes = nested }
        }
        if let selected = selectedMixlist,
           let live = mixlists.first(where: { $0.id == selected.id }) {
            selectedMixlist = live
        }
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
        // 1:1 port of UIKit
        // `ReadyToPourListViewController+Actions.swift` →
        // `RecipeCraftingClass.craftRecipeFromRecipeListing(...)` →
        // `checkBarsys360Craftability` preflight for Barsys 360
        // (same validation chain as Recipe Page + BarBot). Without
        // this, tapping Craft on a Ready-to-Pour row when a
        // station happens to be mid-refill, perishable-expired,
        // or missing the ingredient pushes CraftingView and
        // surfaces the error inside — UIKit catches it here
        // BEFORE pushing.
        if ble.isBarsys360Connected() {
            Task { @MainActor in
                await validateAndPushBarsys360Craft(recipe)
            }
            return
        }
        // Coaster / Shaker: 5 ml clamp handled inside CraftingViewModel,
        // go straight to the crafting screen.
        router.push(.crafting(recipe.id))
    }

    /// Ports the Barsys-360 branch of UIKit
    /// `RecipeCraftingClass.craftRecipeFromRecipeListing` +
    /// `craft360RecipeForUpdatedQuantity` preflight: fetch live
    /// stations, validate every base/mixer ingredient has a matching
    /// station with sufficient quantity, block on expired perishables,
    /// only then push `.crafting`.
    @MainActor
    private func validateAndPushBarsys360Craft(_ recipe: Recipe) async {
        let deviceName = ble.getConnectedDeviceName()
        guard !deviceName.isEmpty else {
            env.alerts.show(title: Constants.deviceNotConnected)
            return
        }
        env.loading.show("Checking stations…")
        let freshStations = await StationsAPIService.loadStations(deviceName: deviceName)
        env.loading.hide()

        // Extract base/mixer (non-garnish, non-additional), unique by
        // lowercased name — matches UIKit
        // `RecipePageViewModel+DataLoading.swift` L27 +
        // `.unique(by: { $0.name.lowercased() })`.
        let rawBaseAndMixer = (recipe.ingredients ?? []).filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            // Matches UIKit `fetchMatchingRecipeLists` SQL filter:
            // `NOT IN ('garnish', 'additionals', 'additional')` —
            // both plural and singular `additional*` variants are
            // excluded from base/mixer.
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        var seen = Set<String>()
        var baseAndMixer: [Ingredient] = []
        for ing in rawBaseAndMixer {
            let key = ing.name.lowercased()
            if key.isEmpty { continue }
            if seen.insert(key).inserted { baseAndMixer.append(ing) }
        }

        // 5 ml minimum — UIKit fires `lowIngredientQty` alert when any
        // base/mixer falls below the threshold.
        for ing in baseAndMixer {
            if (ing.quantity ?? 0) < 5.0 {
                env.alerts.show(title: Constants.lowIngredientQty)
                return
            }
        }

        // All-6-empty guard.
        let emptyCount = freshStations.filter {
            $0.ingredientName.isEmpty || $0.ingredientName == Constants.emptyDoubleDash
        }.count
        if emptyCount == 6 {
            env.alerts.show(title: Constants.ingredientDoesNotExistInStation)
            return
        }

        // Per-ingredient match + quantity check.
        for ing in baseAndMixer {
            let rp = (ing.category?.primary ?? "").lowercased()
            let rs = (ing.category?.secondary ?? "").lowercased()
            let matching = freshStations.first { slot in
                let sp = (slot.category?.primary ?? "").lowercased()
                let ss = (slot.category?.secondary ?? "").lowercased()
                return !sp.isEmpty && sp == rp && ss == rs
            }
            guard let station = matching else {
                env.alerts.show(title: Constants.ingredientDoesNotExistInStation)
                return
            }
            if !station.ingredientName.isEmpty,
               station.ingredientQuantity < (ing.quantity ?? 0) {
                env.alerts.show(title: Constants.insufficientIngredientQuantityFor360)
                return
            }
        }

        // Perishable-expired guard — UIKit
        // `ReadyToPourListViewController.viewWillAppear` L297-305
        // shows the same popup when stations are perishable-expired.
        // Mirror here so the craft button honours it too.
        // `isPerishableExpired` = raw perishable flag AND updated_at
        // older than 24h. Matches UIKit `getPerishableArray`.
        let expired = freshStations.filter { $0.isPerishableExpired }
        if !expired.isEmpty {
            env.alerts.show(
                title: Constants.perishableDescriptionTitle,
                primaryTitle: Constants.cleanAlertTitle,
                secondaryTitle: Constants.okayButtonTitle,
                onPrimary: {
                    router.setupStationsContext = nil
                    router.push(.stationCleaning)
                },
                onSecondary: {
                    // UIKit "Okay" is a no-op — stay on Ready to Pour.
                }
            )
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

    /// Reactive dark-mode awareness. UIKit
    /// `PrimaryOrangeButton.makeOrangeStyle()` pins the brand gradient
    /// to the LIGHT-mode peach-tan orange regardless of appearance —
    /// the `brandGradientTop` / `brandGradientBottom` colour assets in
    /// the SwiftUI port resolve to near-black in dark appearance, so
    /// reading them directly turns the Craft pill into an invisible
    /// dark blob on the dark Ready-to-Pour canvas. Same override
    /// recipe used by `RecipesScreens.primaryOrangeButtonBackground`
    /// (recipe detail Craft button) — hard-code the light-mode RGB
    /// in dark mode so the capsule stays visible + consistent across
    /// every craft entry point.
    @Environment(\.colorScheme) private var colorScheme

    private var isFavourite: Bool { recipe.isFavourite ?? false }

    private var optimizedImageURL: URL? {
        guard let raw = recipe.image?.url, !raw.isEmpty else { return nil }
        return raw.getImageUrl()
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
                        // Dark-mode override: same as
                        // `RecipesScreens` Craft-button text at
                        // line 1431 — hard-code `.black` when the
                        // background is pinned to the light-mode
                        // peach-tan gradient, because `appBlackColor`
                        // asset resolves to near-white `#E5E5EA`
                        // in dark mode which would render as
                        // low-contrast white on the orange pill.
                        // Light mode keeps `appBlackColor` for
                        // bit-identical existing rendering.
                        .foregroundStyle(colorScheme == .dark
                                         ? Color.black
                                         : Color("appBlackColor"))
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
            return Theme.Color.softWhiteText
        }
    }

    // 1:1 with UIKit `PrimaryOrangeButton.makeOrangeStyle()` applied at
    // runtime (ReadyToPourListViewController+TableView L54-57 gates on
    // `#available(iOS 26.0, *)`).

    @ViewBuilder
    private var craftButtonBackground: some View {
        if #available(iOS 26.0, *) {
            // Dark-mode-aware brand gradient. Light mode resolves
            // through the existing `brandGradientTop` /
            // `brandGradientBottom` colour assets (bit-identical
            // pixels — light pass unchanged). Dark mode hard-codes
            // the LIGHT-mode orange RGB so the capsule stays
            // peach-tan instead of collapsing into the asset's
            // near-black dark-appearance variant.
            //
            // Same treatment applied to the Recipe Page Craft button
            // (RecipesScreens.swift `primaryOrangeButtonBackground`),
            // the station-cleaning Clean / Continue / Stop buttons
            // (ControlCenterScreens.swift `brandButtonLabel`), and
            // now the Ready-to-Pour row Craft button — every brand
            // CTA renders identically in dark mode.
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.980, green: 0.878, blue: 0.800),
                        Color(red: 0.949, green: 0.761, blue: 0.631)
                    ]
                    : [
                        Color("brandGradientTop"),
                        Color("brandGradientBottom")
                    ],
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
        return raw.getImageUrl()
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
