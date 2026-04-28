//
//  MixlistsScreens.swift
//  BarsysAppSwiftUI
//
//  Full port of MixlistViewController + MixlistDetailViewController +
//  EditMixlistViewController.
//
//  MixlistList: "Cocktail Kits" screen with searchable list of mixlists.
//  Cell: CocktailsForYouTableViewCell — image 85×85 + title 16pt +
//  ingredients 10pt, glass effect, favourite hidden.

import SwiftUI

// MARK: - Mixlist List ("Cocktail Kits")
//
// Full port of MixlistViewController.
// Layout: "Cocktail Kits" title (24pt), search bar (44pt, 12pt corners),
// table of CocktailsForYouTableViewCell rows.
// Device icon shown in top bar when connected.
// For Barsys 360: only shows 360-compatible mixlists.

struct MixlistListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var catalog: CatalogService
    @EnvironmentObject private var ble: BLEService

    @State private var query = ""

    private var isConnected: Bool { ble.isAnyDeviceConnected }

    /// Bottom breathing room above the tab bar on Cocktail Kits / Mixlists.
    /// iOS 26+ glass tab bar → 20pt (bit-identical to before);
    /// pre-iOS 26 opaque tab bar → 37pt so the last kit row doesn't
    /// graze the hairline. Mirrors `MyBarView.bottomBarBottomInset`.
    private var mixlistListBottomInset: CGFloat {
        if #available(iOS 26.0, *) { 20 } else { 37 }
    }

    /// Filtered mixlists — ports mixlistSearchResults().
    /// For Barsys 360: only 360-compatible mixlists (ports retrieveMixlistBarsys360).
    /// Search matches mixlist name, ingredient names, and recipe names.
    private var filtered: [Mixlist] {
        var source = catalog.mixlists
        // UIKit: if Barsys 360 connected, filter to 360-compatible only
        if ble.isBarsys360Connected() {
            source = source.filter { $0.barsys360Compatible == true }
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return source
        }
        // UIKit uses `words.contains` (ANY word matches)
        let words = query.lowercased().split(separator: " ").map(String.init)
        return source.filter { m in
            let name = m.displayName.lowercased()
            let ingredients = (m.ingredientNames ?? "").lowercased()
            let recipeNames = (m.recipes ?? []).compactMap { $0.name?.lowercased() }
            return words.contains { word in
                name.contains(word) ||
                ingredients.contains(word) ||
                recipeNames.contains { $0.contains(word) }
            }
        }
    }

    // Device info helpers
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
        // Title + search bar are now hosted INSIDE the outer ScrollView so
        // there's a scrollable surface directly under the nav bar.
        // MyBarView (correct, MyBarScreens.swift:567) and DevicePairedView
        // (correct, ControlCenterScreens.swift:638) follow the same
        // pattern; iOS 26's nav-bar Liquid Glass auto-wrap relies on
        // having scrollable material under the bar to render the
        // silvery-frosted right-pill the user sees on those screens.
        // The previous layout had the Title + SearchBar as static
        // VStack rows OUTSIDE the ScrollView, which left the bar with
        // no material to blur through and produced the "black
        // transparent" pill the user reported on Cocktail Kits.
        ScrollView(showsIndicators: false) {
            // Compute deterministic row geometry ONCE per layout so
            // every row in the LazyVStack reports the same size on
            // first render — eliminates the scroll-zoom artefact.
            //   • Page horizontal padding: 24pt left + 24pt right = 48
            //   • Cell width = screen width − 48
            //   • Image (square) = 50% of cell width  ⇒  cell height
            //     = cell width / 2.
            let cellWidth = UIScreen.main.bounds.width - 48
            let rowHeight = cellWidth / 2

            VStack(spacing: 0) {
                // Title — "Cocktail Kits" 24pt, appBlackColor
                Text("Cocktail Kits")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Search bar — uses shared `BarsysSearchBar` for 1:1 UIKit
                // parity with `viewSearch` + `txtSearch` + `searchAndCloseButton`
                // (Mixlist.storyboard scene `Q4y-Gs-Lbh`). Replaces the
                // previous inline implementation which used SF Symbols
                // instead of the `exploreSearch` / `crossIcon` assets, a
                // 16pt placeholder font instead of 14pt, and a white
                // background instead of the UIKit transparent container.
                BarsysSearchBar(query: $query)
                    .padding(.horizontal, 24)
                    .padding(.top, 15)

                // Mixlist list
                if filtered.isEmpty {
                    Text("No results to display")
                        .font(.system(size: 16))
                        .foregroundStyle(Color("mediumGrayColor"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                        .padding(.bottom, mixlistListBottomInset)
                } else {
                    if catalog.isLoading && catalog.mixlists.isEmpty {
                        ProgressView("Loading cocktail kits...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { mixlist in
                            Button {
                                HapticService.light()
                                router.push(.mixlistDetail(mixlist.id))
                            } label: {
                                MixlistRowCell(mixlist: mixlist, cellHeight: rowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                    // iOS 26+ glass tab bar blurs over the last row —
                    // 20pt is fine and bit-identical to before. Pre-
                    // iOS 26's opaque tab bar + hairline was grazing
                    // the last mixlist row; bump to 37pt only on pre-26
                    // (same scale as `MyBarView.bottomBarBottomInset`).
                    .padding(.bottom, mixlistListBottomInset)
                }
            }
        }
        .refreshable {
            await catalog.refresh()
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // 1:1 with DevicePairedView (ControlCenterScreens.swift:960) —
        // same toolbar bookkeeping as the reference screens so the
        // right-pill auto-glass renders the silvery material instead
        // of the thinner "black transparent" pill.
        .navigationBarBackButtonHidden(true)
        // 1:1 port of UIKit `MixlistViewController.viewDidLoad` +
        // `viewWillAppear` staleness check:
        //
        //   if cacheMixlists.isEmpty || AppStateManager.shared.areCacheRecipesStale {
        //       MixlistsUpdateClass().updateMixlists(trigger: .manual, ...)
        //   }
        //
        // Without this `.task` the Cocktail Kits screen would appear
        // empty any time the user navigated here before the app's
        // bootstrap preload completed, or when the data was stale
        // after an hour. `ExploreRecipesView` has the same task; the
        // previous SwiftUI port was missing it on MixlistListView,
        // so Cocktail Kits rendered "No results to display" forever
        // until the user pulled to refresh.
        //
        // `refreshIfStale` is gated on a 1-hour `lastFetchTimestamp`
        // (`AppStateManager.cacheExpirationInterval = 3600`); if the
        // cache was populated by the bootstrap `preload()` call
        // inside this window the task is a no-op. `refresh()` is
        // called unconditionally when storage is empty so the first
        // launch with zero cached mixlists always triggers a fetch.
        .task {
            if catalog.mixlists.isEmpty {
                await catalog.refresh()
            } else {
                await catalog.refreshIfStale()
            }
        }
        .onAppear {
            // 1:1 with UIKit `MixlistViewController` L73 —
            //   TrackEventsClass().addBrazeCustomEventWithEventName(
            //       eventName: TrackEventName.viewMixlistsListing.rawValue)
            // Fires every time the Cocktail Kits / Mixlists tab
            // becomes visible so Braze can track content-discovery
            // sessions and trigger IAMs accordingly.
            env.analytics.track(TrackEventName.viewMixlistsListing.rawValue)
        }
        .toolbar {
            // Center: device ICON ONLY (only when connected).
            //
            // UIKit parity — MixlistViewController.swift:86 sets
            // `lblDeviceName.isHidden = true` in `setupView()` and never
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
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
    }
}

// MARK: - Mixlist Row Cell
//
// Ports CocktailsForYouTableViewCell.xib:
//   innerView: glass effect, 16pt corners
//   HStack: [VStack: title 16pt 2 lines + ingredients 10pt | image 85×85 1:1]
//   Favourite button hidden in mixlist view.
//   Cell height: ~140pt

/// Ports CocktailsForYouTableViewCell from UIKit screenshots.
/// Layout: LEFT side = text (title + ingredients), RIGHT side = image (50% width, full height).
/// No favourite button visible (hidden in UIKit MixlistViewController).
/// Glass material background with white border.
struct MixlistRowCell: View {
    let mixlist: Mixlist
    /// Deterministic side length of the square image, computed ONCE by the
    /// parent list. Locking the row height eliminates the zoom/pop that
    /// LazyVStack causes when each row is measured for the first time
    /// because of an `aspectRatio(1, .fit)` constraint on the image.
    let cellHeight: CGFloat

    private var optimizedImageURL: URL? {
        guard let raw = mixlist.image?.url, !raw.isEmpty else { return nil }
        return raw.getImageUrl()
    }

    var body: some View {
        // Ports CocktailsForYouTableViewCell.xib EXACTLY by re-reading its
        // runtime constraints (not the IB design-time frame snapshot):
        //
        //   • rowHeight=140 (table row height — content auto-sizes upward).
        //   • innerView (id="2dq-ri-LGg") glass card pinned to all 4 edges
        //     of the wrapping stack; corner radius 16 via roundCorners=16
        //     userDefinedRuntimeAttribute, plus addGlassEffect(...).
        //   • cocktailImage (id="6yp-SH-CTj"):
        //       — `image.width = innerView.width × 0.5`  (multiplier 0.5)
        //       — `image.width : image.height = 1 : 1`   (square)
        //       — top/trailing/bottom pinned to innerView (full inner height)
        //       — placeholder `myDrink`, bg `lightBorderGrayColor`
        //     ⇒ Image is 50% of the cell width, square, full inner height.
        //   • cocktailTitleLabel: top=16, leading=16, trailing=image.leading-16
        //     font system 16pt, ≤2 lines (set to 4 in
        //     MixlistViewController+TableView for the cocktail-kits list).
        //   • cocktailIngredientLabel: top=title.bottom+16, leading=16,
        //     trailing=image.leading-16, bottom ≥ innerView.bottom-16
        //     font system 10pt, lines=0 (unlimited).
        //   • favoriteButton: 30×30 top-right of innerView (top=5,
        //     trailing=5) — hidden in cocktail-kits list (`isHidden = true`).
        //   • Bottom 12pt spacer image (height=12) inside the stack.
        //
        // SwiftUI realisation: HStack with two equal-width columns, each
        // taking 50% of the row width. The image column drives card height
        // because of the 1:1 aspect ratio.
        HStack(spacing: 0) {
            // Left half — text column. Uniform sizing: title max 3 lines,
            // ingredients max 6 lines, both truncate so every row is the
            // same height as the square image (50% of cell width).
            VStack(alignment: .leading, spacing: 12) {
                Text(mixlist.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let ingredients = mixlist.ingredientNames, !ingredients.isEmpty {
                    Text(ingredients)
                        .font(.system(size: 10))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right half — explicit `cellHeight × cellHeight` square so
            // SwiftUI never has to re-measure the row when it scrolls into
            // view. Because the parent passes `cellHeight = (cellWidth)/2`,
            // this preserves the UIKit constraint `image.width = innerView.width × 0.5`
            // + 1:1 aspect ratio without using `.aspectRatio()` at runtime.
            AsyncImage(url: optimizedImageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    Color("lightBorderGrayColor")
                default:
                    Image("myDrink")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                }
            }
            .frame(width: cellHeight, height: cellHeight)
            .background(Color("lightBorderGrayColor"))
            .clipped()
        }
        // Lock the entire row to the deterministic height so every cell in
        // the LazyVStack measures the same on first appearance. This is the
        // single change that removes the scroll-zoom/pop behaviour.
        .frame(height: cellHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 12) // 12pt bottom spacer inside the parent stack
    }
}

// MARK: - Mixlist Detail
//
// Ports MixlistDetailViewController + its extensions:
//   • 60pt custom nav bar (back • device info • favorite • glass profile).
//   • Banner image (scaleAspectFill) with mixlist name bold body font.
//   • Tabs: Recipes / Ingredients (bold black when selected, unSelectedColor
//     otherwise), 48pt row with underline bar.
//   • Recipes list → MixlistDetailTableViewCell-styled rows (image 47×47
//     scaleAspectFill, title 16pt 4-lines, info 10pt, craft 301×29 8pt
//     radius with 1pt craftButtonBorderColor border, favorite 30×30 tint).
//   • Ingredients list → RecipeIngredientRow in read-only mode (+/- hidden).
//   • Bottom "Setup Stations" button visible only when Barsys360 connected.
//   • Recipe tap → pushes RecipeDetailView.
//   • Craft button → BLE-gated craft, navigates to .crafting or .pairDevice.
//   • Favorite button → env.storage.toggleFavorite + toast.

struct MixlistDetailView: View {
    let mixlistID: MixlistID
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    /// Observes `CatalogService` directly so the screen re-renders when
    /// the catalog publishes new data — including the offline → online
    /// rising edge handled by `CatalogService.handleConnectionRestored()`.
    /// Without this binding, `MixlistDetailView` only reads through the
    /// non-observable `env.storage`, so a fresh fetch triggered by the
    /// `.barsysConnectionRestored` notification would update storage
    /// silently and the user would still see the empty / stale state
    /// they hit while offline. Reading `catalog.mixlists` /
    /// `catalog.recipes` registers SwiftUI dependencies on the
    /// `@Published` arrays so re-renders happen automatically.
    @EnvironmentObject private var catalog: CatalogService
    /// Reactive theme awareness — used ONLY by the bottom
    /// "Setup Stations" primary-orange button to override the
    /// dark-appearance variant of the `brandGradientTop` /
    /// `brandGradientBottom` colour assets (which wrongly resolve to
    /// dark grey / near-black in dark mode) back to the light-mode
    /// orange RGB so the button stays readable in dark mode.
    /// Light mode is untouched.
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: MixlistDetailTab = .recipes
    @State private var showMoreSheet: Bool = false

    /// Forces `recipes` to re-evaluate after a heart-toggle that goes
    /// through `env.storage.toggleFavorite(_:)`. `MockStorageService`
    /// is a plain class (not `ObservableObject`), so mutations don't
    /// broadcast. Without this trigger the heart icon stays pinned to
    /// its pre-toggle state because SwiftUI never re-runs the
    /// `mixlist?.recipes` lookup. Same pattern as
    /// `FavoritesView.favouritesRefreshTick` — UIKit
    /// `MixlistDetailViewController` re-fetches the recipe array after
    /// the success alert dismisses; this tick plays the same role.
    @State private var favouritesRefreshTick: Int = 0

    enum MixlistDetailTab: Int, CaseIterable { case recipes, ingredients }

    /// Reads through `catalog.mixlists` (`@Published`) so a new mixlist
    /// list arriving via `CatalogService.preload()` (fresh fetch,
    /// connection-restored retry, pull-to-refresh) immediately
    /// re-renders this screen. Falls back to `env.storage` for the
    /// edge case where the catalog hasn't published yet but the
    /// underlying storage already has the mixlist (covers the
    /// `bootstrap → splash → screen mount` race).
    private var mixlist: Mixlist? {
        catalog.mixlists.first { $0.id == mixlistID }
            ?? env.storage.allMixlists().first { $0.id == mixlistID }
    }

    private var recipes: [Recipe] {
        // Reading the tick registers it as a dependency — SwiftUI
        // re-runs `recipes` (and the `MixlistDetailRecipeRow` ForEach)
        // on every heart toggle.
        let _ = favouritesRefreshTick
        // Reading `catalog.recipes` registers a dependency on the
        // catalog's `@Published` array so a connection-restored
        // re-fetch (`CatalogService.handleConnectionRestored()`) also
        // re-renders this view. Discard binding — only the dependency
        // matters; the actual lookup goes through `env.storage` first
        // because `toggleFavorite` mutates the storage dictionary
        // synchronously while `catalog.recipes` only updates after a
        // full `preload()`.
        let _ = catalog.recipes

        // Resolve recipe IDs via the mixlist's snapshot (preferred) or
        // its bare `recipeIDs` list.
        let ids: [RecipeID] = {
            if let cached = mixlist?.recipes, !cached.isEmpty {
                return cached.map(\.id)
            }
            return mixlist?.recipeIDs ?? []
        }()
        // Lookup order — **storage first** so the heart icon picks up
        // the latest `isFavourite` flag the same render frame the user
        // taps it. Falling back to `catalog.recipes` for the rare
        // edge case where the recipe was published to catalog before
        // storage caught up, and finally to the mixlist's cached
        // snapshot (which has stale `isFavourite` but at least
        // resolves the row's static fields like name / image).
        // UIKit `BarsysRecipeTableViewCell.configure()` re-reads the
        // SQLite row on every tableView reload — same idea, just
        // through the storage dictionary instead of SQLite.
        return ids.compactMap { id in
            env.storage.recipe(by: id)
                ?? catalog.recipes.first(where: { $0.id == id })
                ?? mixlist?.recipes?.first(where: { $0.id == id })
        }
    }

    /// 1:1 port of UIKit
    /// `MixlistDetailViewModel.baseAndMixerIngredientsArr` — the
    /// BASE+MIXER-only (NO garnish, NO additional) distinct
    /// ingredient list for the Ingredients tab.
    ///
    /// UIKit reference (RecipePageViewModel+DataLoading.swift L27):
    /// ```
    /// self.baseAndMixerIngredientsArr =
    ///     self.recipe?.ingredients?.filter({
    ///         $0.category?.primary?.lowercased() ?? "" != "garnish" &&
    ///         $0.category?.primary?.lowercased() ?? "" != "additional"
    ///     }) ?? []
    /// ```
    /// plus `.unique(by: { $0.name.lowercased() })`. The Mixlist
    /// detail variant is the same filter applied across every
    /// recipe's ingredients (aggregation), then deduped by
    /// lowercased name — equivalent to UIKit's SQL
    /// `fetchDistinctIngredientName(for:)` which returns DISTINCT
    /// rows filtered to base/mixer only.
    ///
    /// User-reported bug: "The Velvet Stir: A Martini Affair shows
    /// 13+ ingredients in SwiftUI but only 6 in UIKit". The
    /// previous aggregator dedup by name PASSED garnishes +
    /// additionals through, so the union of every recipe's
    /// garnishes (olive, cherry, twist, zest, salt rim, …) +
    /// additionals inflated the ingredient tab to a long list.
    /// UIKit hides those on the Mixlist detail ingredients tab
    /// because the tab is a "what do I need to stock" list, and
    /// garnishes/additionals are per-drink UI decorations tracked
    /// separately by the crafting flow.
    private var aggregatedIngredients: [Ingredient] {
        var seen: [String: Ingredient] = [:]
        for r in recipes {
            for i in r.ingredients ?? [] {
                let primary = (i.category?.primary ?? "").lowercased()
                // Match UIKit `!= "garnish" && != "additional"` filter
                // verbatim. Ingredients with no category at all (nil /
                // empty primary) DO pass through — UIKit's guard uses
                // `?? ""` which leaves those in the base/mixer bucket
                // by default (legacy / user-created recipes without
                // category data).
                // UIKit SQL: NOT IN ('garnish','additionals','additional').
                if primary == "garnish" || primary == "additional" || primary == "additionals" { continue }
                let key = i.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !key.isEmpty else { continue }
                if seen[key] == nil { seen[key] = i }
            }
        }
        return Array(seen.values).sorted { $0.name < $1.name }
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
            if let mixlist {
                content(mixlist)
            } else {
                EmptyStateView(systemImage: "square.stack.3d.up",
                               title: "Mixlist not found",
                               subtitle: "This mixlist no longer exists.")
            }
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            // 1:1 with UIKit `MixlistDetailViewModel` L219 Braze call
            // — fires every time the Mixlist detail lands. Property
            // dictionary mirrors UIKit L219-226:
            //   source, mixlist_id, mixlist_name, mixlist_image,
            //   recipes, deviceType, deviceId
            // The SwiftUI port passes the same keys so Braze segments
            // / IAM triggers set up against the UIKit events keep
            // working untouched.
            guard let mixlist else { return }
            let recipesList: [[String: Any]] = recipes.map { r in
                [
                    "id": r.id.value,
                    "name": r.displayName,
                    "image": r.image?.url ?? ""
                ]
            }
            var props: [String: Any] = [
                "source": "barsys",
                "mixlist_id": mixlist.id.value,
                "mixlist_name": mixlist.displayName,
                "mixlist_image": mixlist.image?.url ?? "",
                "recipes": recipesList
            ]
            if let connected = ble.connected.first {
                props["deviceId"] = connected.name
                props["deviceType"] = connected.kind.displayName
            }
            env.analytics.track(TrackEventName.viewMixlist.rawValue,
                                properties: props)
        }
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill (`NavigationRightGlassButtons`) renders on the same
        // canvas HomeView (ChooseOptions) uses — matching look / feel
        // across both screens.
        .chooseOptionsStyleNavBar()
        .confirmationDialog("More",
                            isPresented: $showMoreSheet,
                            titleVisibility: .hidden) {
            if let mixlist {
                Button("Edit Mixlist") {
                    router.push(.mixlistEdit(mixlist.id))
                }
                Button("Delete Mixlist", role: .destructive) {
                    env.alerts.show(title: "Delete this mixlist?",
                                    message: "This action cannot be undone.")
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    @ViewBuilder
    private func content(_ mixlist: Mixlist) -> some View {
        ScrollView {
            // Parent VStack spacing 0 — UIKit uses hard-coded constants
            // (image top=0, title top = image.bottom + 19, tabs bar top
            // = title.bottom + 19) rather than a uniform stack spacing.
            // Previous 12pt implicit gap compounded with the explicit
            // `.padding(.top, 6)` on the title so the layout drifted
            // by ~13pt below UIKit.
            VStack(alignment: .leading, spacing: 0) {
                banner(for: mixlist)

                // Mixlist title — storyboard `jHp-tM-EQo`:
                //   boldSystem 16pt, `appBlackColor`, leading/trailing = 24,
                //   top = `AWF-ly-2Vd.bottom + 19` (constraint `X4y-C1-ARS`).
                Text(mixlist.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.horizontal, 24)
                    .padding(.top, 19)

                tabsBar

                switch selectedTab {
                case .recipes:    recipesList
                case .ingredients: ingredientsList
                }
                // Conditional clearance — only reserve space under the
                // bottom action row when a Barsys 360 is connected and
                // the Setup-Stations CTA is actually rendered. Without
                // this guard, the ScrollView content would have a
                // dead 120pt strip at the bottom on Coaster / Shaker /
                // no-device states, visible as trailing grey.
                if shouldShowSetupStations {
                    Color.clear.frame(height: 120)
                }
            }
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) { bottomButtonRow(for: mixlist) }
    }

    // MARK: - Banner — ports `imgMixlist` (`AWF-ly-2Vd`):
    //
    // Storyboard constraints (Mixlist.storyboard MixlistDetailViewController):
    //   • `56N-ek-dao`  imgMixlist.leading  = BtQ-eq-P87.leading  + 24
    //   • `tTa-AP-hxa`  imgMixlist.trailing = BtQ-eq-P87.trailing − 24
    //   • `QTZ-h6-yvL`  imgMixlist.width    = imgMixlist.height   (1:1)
    //   • `1oj-VG-x09`  imgMixlist.top      = BtQ-eq-P87.top      (0pt)
    //   • `X4y-C1-ARS`  jHp-tM-EQo.top      = imgMixlist.bottom   + 19
    //   • roundCorners userDefinedRuntimeAttribute = 12
    //   • scaleAspectFill + clipsToBounds=true
    //   • backgroundColor = `lightBorderGrayColor`
    //   • placeholder = `myDrink`
    //
    // A previous port set this to 16pt based on a screenshot — that
    // was a misreading. The storyboard is authoritative and specifies
    // 24pt on both sides; on iPhone 15 Pro / 16 Pro the difference is
    // 16pt of extra width (~5% of the image area) which visibly
    // misaligns every downstream row.
    private func banner(for mixlist: Mixlist) -> some View {
        // Fluctuation fix:
        // Previous layout put `.aspectRatio(1, contentMode: .fit)` on
        // the `AsyncImage` itself. While the network image is loading
        // (`.empty` phase) the `AsyncImage` reports zero intrinsic
        // size — so `aspectRatio(1, .fit)` on zero-by-zero is still
        // zero. The banner rendered at ~0 pt tall, the ScrollView
        // relaid out, and when the image arrived the view snapped to
        // its full square height. On mid-tier hardware that reflow is
        // visible as a "jump" when you first enter the screen.
        //
        // Fix: use a `Color` placeholder as the sizing root. `Color`
        // has infinite intrinsic size, so `aspectRatio(1, .fit)`
        // immediately pins to `min(width, height) = width` since the
        // parent provides width. The AsyncImage is overlaid on top of
        // that locked frame — it can load at any size without
        // perturbing layout.
        Color("lightBorderGrayColor")
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(
                AsyncImage(url: URL(string: mixlist.imageURL)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        // Show placeholder immediately so the banner has
                        // content on first paint.
                        Image("myDrink")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(40)
                    case .failure:
                        Image("myDrink")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(40)
                    @unknown default:
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // UIKit storyboard constants `56N-ek-dao` + `tTa-AP-hxa`:
            // 24pt leading / 24pt trailing — matches RecipeDetail +
            // ExploreRecipes + every other banner in the app.
            .padding(.horizontal, 24)
            // Shadow disabled while the image is loading would cause a
            // second reflow if enabled. Leaving the banner shadow-less
            // matches the UIKit `imgMixlist` outlet (no shadow
            // userDefinedRuntimeAttribute).
    }

    // MARK: - Tabs bar
    //
    // 1:1 port of the UIKit `selectTab(_:)` logic in
    // `MixlistDetailViewController.swift` L233-L251:
    //
    //   • Two buttons laid out horizontally: "Recipes" (mixlistRecipeButton)
    //     | "Ingredients" (mixlistIngredientButton).
    //   • Between them, a static vertical divider (`segmentSeparator`
    //     image view, IBOutlet `g4L-dm-e3j` in the storyboard) — NOT an
    //     underline bar below.
    //   • Selected button: `AppFontClass.font(.callout, weight: .bold)`
    //     (14pt bold) + `titleColor = .black` (appBlackColor).
    //   • Unselected button: `AppFontClass.font(.callout)` (14pt regular)
    //     + `titleColor = .unSelectedColor`.
    //   • No underline / no bottom line — the visual cue is purely
    //     weight + colour on the two titles.
    private var tabsBar: some View {
        // UIKit container `nqX-a1-I5P` is 48pt tall. Inside sits a
        // fillEqually stackView `PSK-7l-HSg` with 20pt spacing,
        // center-aligned. The `segmentSeparator` (`VQ0-Uc-bs2`) is a
        // 1×14 BLACK image view absolutely positioned at the exact
        // horizontal center of the screen (NOT inside the stack) — it
        // reads as a thin "|" between the two titles.
        //
        // Parent stack `SK8-0N-Xcn` pins this row at
        //   leading=24 / trailing=24 / top = title.bottom + 19
        // (constraints `svh-iN-pfx`, `Mih-CO-Uhk`, `ouo-EL-ZPp`).
        ZStack {
            HStack(spacing: 20) {
                tabButton(.recipes, title: "Recipes")
                tabButton(.ingredients, title: "Ingredients")
            }
            // segmentSeparator — 1×14 black vertical rule, centered.
            // Trait-resolved at draw time so the light variant is the
            // EXACT historical `UIColor.black` (bit-identical pixels in
            // light mode), and the dark variant is near-white so the
            // separator stays visible between the Recipes / Ingredients
            // tab labels on the dark Mixlist Detail header.
            Rectangle()
                .fill(Color(UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.white
                        : UIColor.black // EXACT historical black
                }))
                .frame(width: 1, height: 14)
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
        .padding(.top, 19)
    }

    private func tabButton(_ tab: MixlistDetailTab, title: String) -> some View {
        let selected = selectedTab == tab
        return Button {
            HapticService.selection()
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color("appBlackColor") : Color("unSelectedColor"))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Recipes tab

    @ViewBuilder
    private var recipesList: some View {
        if recipes.isEmpty {
            Text("No recipes yet.")
                .font(Theme.Font.of(.callout))
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        } else {
            // UIKit `SK8-0N-Xcn` pins the list at leading/trailing=24pt
            // (constraints `svh-iN-pfx` / `Mih-CO-Uhk`). The previous
            // port used 16pt which made the list ~16pt wider than
            // UIKit and broke the alignment with the banner / title /
            // tabs bar above.
            let cellWidth = UIScreen.main.bounds.width - 48
            let rowHeight = cellWidth / 2
            VStack(spacing: 10) {
                ForEach(recipes) { recipe in
                    MixlistDetailRecipeRow(
                        recipe: recipe,
                        isFavourite: recipe.isFavourite ?? false,
                        cellHeight: rowHeight,
                        onOpen: { router.push(.recipeDetail(recipe.id)) },
                        onCraft: { craft(recipe) },
                        onFavorite: { toggleFav(recipe) }
                    )
                }
            }
            .padding(.horizontal, 24)
            // UIKit parent stack `SK8-0N-Xcn` spacing=16: the 16pt gap
            // between the tabs bar and the list is supplied here.
            .padding(.top, 16)
        }
    }

    // MARK: - Ingredients tab

    @ViewBuilder
    private var ingredientsList: some View {
        if aggregatedIngredients.isEmpty {
            Text("No ingredients found.")
                .font(Theme.Font.of(.callout))
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        } else {
            VStack(spacing: 8) {
                ForEach(aggregatedIngredients) { ing in
                    RecipeIngredientRow(
                        ingredient: ing,
                        unit: env.preferences.measurementUnit,
                        readOnly: true,
                        onMinus: {}, onPlus: {}, onEdit: { _ in }
                    )
                }
            }
            // Aligned with UIKit `SK8-0N-Xcn`: leading/trailing=24
            // + 16pt top spacing matches the parent stack's `spacing=16`
            // between the tabs bar and the ingredients table.
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    // MARK: - Bottom action row
    //
    // Re-analysed against UIKit `MixlistDetailViewController.swift`:
    //   • L92:  `moreButton.addBounceEffect()`
    //   • L161: iOS <26 → `moreButton.makeBorder(1, .craftButtonBorderColor)`
    //           + `bottomButtonStackView.isHidden = true`
    //   • L168: iOS 26+ → `bottomButtonStackView.isHidden = !shouldShowSetupStations`
    //           + `roundTopCorners(radius: 12)` + `addGlassEffect`
    //   • L172: `setupStationButton.makeOrangeStyle()` (brand gradient)
    //   • L173: `moreButton.applyCancelCapsuleGradientBorderStyle()`
    //   • L190-192: setup = `!shouldShowSetupStations`, stack =
    //               `!shouldShowSetupStations`, **moreButton.isHidden = true (ALWAYS)**
    //
    // Key findings:
    //   1. `moreButton` is in the storyboard but **always hidden at
    //      runtime** — UIKit sets `moreButton.isHidden = true`
    //      unconditionally on every state change. The visible layout
    //      in production is ONLY the orange "Setup Stations" button.
    //   2. The entire `bottomButtonStackView` is hidden when
    //      `!shouldShowSetupStations`, i.e. when no Barsys 360 is
    //      connected OR when the detail originated from the
    //      Ready-to-Pour listing.
    //   3. `shouldShowSetupStations` (MixlistDetailViewModel L86-93):
    //         false if `detailOrigin == .readyToPour`
    //         true  if `bleService.isBarsys360Connected()`
    //         false otherwise.
    //
    // The SwiftUI port now mirrors that exactly — when the condition
    // is false we return an `EmptyView` so the `.safeAreaInset`
    // reserves NO space (matching UIKit hiding the whole stack view
    // via `isHidden = true` which collapses its intrinsic height).
    @ViewBuilder
    private func bottomButtonRow(for mixlist: Mixlist) -> some View {
        if shouldShowSetupStations {
            HStack(spacing: 8) {
                // "Setup Stations" — `setupStationButton.makeOrangeStyle()`
                // (brand-orange gradient) via `PrimaryOrangeButton`
                // runtime style. Bounce effect on tap.
                //
                // 1:1 port of UIKit `didPressSetupStationButton`
                // (MixlistDetailViewController.swift L325-336):
                //   1. `HapticService.shared.light()`
                //   2. `await ConnectionMonitor.shared.isConnected` →
                //      internet-required alert on false.
                //   3. `RecipeCraftingClass().setupStationsAction(...)`
                Button {
                    HapticService.light()
                    setupStations(for: mixlist)
                } label: {
                    // Inlined `brandCapsule(height: 45, cornerRadius: 8)`
                    // so the gradient can branch on `colorScheme`
                    // without modifying the shared helper. The shared
                    // `.brandCapsule` treatment resolves
                    // `brandGradientTop` / `brandGradientBottom` via
                    // the asset catalog, and those assets have a
                    // dark-appearance variant that renders as near-
                    // black — which made the Setup Stations button
                    // invisible in dark mode. UIKit's
                    // `PrimaryOrangeButton.makeOrangeStyle()` always
                    // uses the light-mode brand-orange gradient
                    // regardless of appearance, so we mirror that by
                    // hard-coding the light-mode RGB in the dark-
                    // mode branch. Light-mode pixels stay bit-
                    // identical (same asset resolution as before).
                    setupStationsLabel
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel("Setup Stations")
                .accessibilityHint("Opens station setup for this mixlist")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(Theme.Gradient.bottomScrim)
        } else {
            // Matches UIKit: when `shouldShowSetupStations == false`,
            // the entire bottomButtonStackView is hidden + zero-height.
            // No safeAreaInset reservation → no phantom bottom space
            // that would cause layout fluctuation on appear.
            EmptyView()
        }
    }

    /// Setup Stations button label — the brand-capsule treatment
    /// with a dark-mode-only gradient override. Light mode behaviour
    /// is bit-identical to the shared `brandCapsule(height: 45,
    /// cornerRadius: 8)` helper: same font (system 16pt semibold),
    /// same black text, same asset-resolved gradient, same
    /// `floatingButton` shadow. In dark mode we swap the gradient's
    /// colour stops to the explicit light-mode RGB so the capsule
    /// stays orange instead of resolving to the asset catalog's
    /// dark-appearance variant (which is near-black).
    private var setupStationsLabel: some View {
        let height: CGFloat = 45
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        // Light mode: resolves via `brandGradientTop.colorset` /
        // `brandGradientBottom.colorset` — unchanged.
        // Dark mode: explicit light-mode RGB pulled from those asset
        // files so the capsule stays brand-orange.
        let gradientColors: [SwiftUI.Color] = colorScheme == .dark
            ? [
                SwiftUI.Color(red: 0.980, green: 0.878, blue: 0.800),
                SwiftUI.Color(red: 0.949, green: 0.761, blue: 0.631)
            ]
            : [
                SwiftUI.Color("brandGradientTop"),
                SwiftUI.Color("brandGradientBottom")
            ]
        return Text("Setup Stations")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SwiftUI.Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        // UIKit: CAGradientLayer with height/2 corner
                        // radius on iOS 26 (capsule).
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
                        // Pre-26: flat `segmentSelection` with 8pt
                        // corner radius. Unchanged from shared helper.
                        RoundedRectangle(cornerRadius: 8,
                                         style: .continuous)
                            .fill(Theme.Color.segmentSelection)
                    }
                }
            )
            .barsysShadow(.floatingButton)
    }

    /// 1:1 port of UIKit `MixlistDetailViewModel.shouldShowSetupStations`
    /// (MixlistDetailViewModel.swift L86-93):
    ///   • `false` when the screen was opened from Ready-to-Pour
    ///     (the user is already inside the "make a drink" flow).
    ///   • `true` when a Barsys 360 is paired + connected.
    ///   • `false` otherwise (no device, or a Coaster / Shaker
    ///     connected — those devices don't have stations).
    ///
    /// SwiftUI equivalent: we always branch on the live `ble`
    /// environment object. The `detailOrigin == .readyToPour` gate
    /// isn't wired yet since the SwiftUI Ready-to-Pour listing isn't
    /// ported, but the condition is a no-op in that case (user can't
    /// get to MixlistDetail from Ready-to-Pour in the current port).
    private var shouldShowSetupStations: Bool {
        ble.isBarsys360Connected()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // UIKit parity — icon only, 25×25, name label hidden
        // (MixlistDetailViewController.swift:103 sets
        // `lblDeviceName.isHidden = true` and never reverses it).
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                DevicePrincipalIcon(assetName: deviceIconName,
                                    accessibilityLabel: deviceKindName)
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

    // MARK: - Actions

    /// 1:1 port of UIKit `MixlistDetailViewController.didPressCraftButton`
    /// (+actions extension). Exact order of operations from UIKit:
    ///   1. `HapticService.shared.light()`
    ///   2. `await ConnectionMonitor.shared.isConnected` — bail with
    ///      `Constants.internetConnectionMessage` alert on false.
    ///   3. Device check — if no Barsys 360 / Coaster / Shaker
    ///      connected, route to PairDevice (UIKit opens
    ///      `openPairYourDeviceWhenNotConnected()`).
    ///   4. For Barsys 360 (station-based) devices, UIKit routes through
    ///      `craft360RecipeForUpdatedQuantity` which validates that every
    ///      recipe ingredient exists on a station with sufficient
    ///      quantity. Mismatched → `ingredientDoesNotExistInStation`
    ///      alert. Insufficient qty → `insufficientIngredientQuantityFor360`.
    ///      Perishable expired → `perishableDescriptionTitle` Clean/Okay
    ///      decision alert.
    ///   5. For Coaster / Shaker (socket-less) devices, UIKit skips the
    ///      station validation and pushes directly to `CraftingViewController`.
    private func craft(_ recipe: Recipe) {
        HapticService.light()
        guard ble.isAnyDeviceConnected else {
            // UIKit `openPairYourDeviceWhenNotConnected()` +
            // `pendingConnectionSource = .recipeCrafting`: show the
            // confirmation alert AND mark the flow so the BLE connect
            // callback pops back to this screen instead of switching
            // to Explore.
            router.promptPairDevice(isConnected: ble.isAnyDeviceConnected,
                                    source: .recipeCrafting)
            return
        }
        // For Barsys 360 we perform the station-match + perishable
        // validation. Coaster / Shaker go straight to crafting.
        if ble.isBarsys360Connected() {
            Task { @MainActor in
                await craft360WithValidation(recipe)
            }
        } else {
            router.push(.crafting(recipe.id))
        }
    }

    /// 1:1 port of UIKit
    /// `RecipeCraftingClass.craft360RecipeForUpdatedQuantity`
    /// (BarsysApp/Controllers/Crafting/Crafting Class/RecipeCraftingClass+StationSetup.swift L8-99):
    ///   • GET current stations.
    ///   • For every recipe ingredient, look up a matching station by
    ///     `category.primary + category.secondary` (lowercased).
    ///   • If no match → "Ingredient doesn't exist in station…".
    ///   • If match but station qty < ingredient qty → "Please check
    ///     your station(s): one or more ingredients have insufficient
    ///     quantity.".
    ///   • If any station is perishable-expired →
    ///     "Ingredients may be spoiled…" Clean/Okay alert.
    ///   • Otherwise → push CraftingView.
    @MainActor
    private func craft360WithValidation(_ recipe: Recipe) async {
        let deviceName = ble.getConnectedDeviceName()
        guard !deviceName.isEmpty else {
            env.alerts.show(title: Constants.deviceNotConnected)
            return
        }
        env.loading.show("Checking stations…")
        let stations = await StationsAPIService.loadStations(deviceName: deviceName)
        env.loading.hide()

        // 1:1 with Recipe Page craft validation
        // (`RecipesScreens.validateAndPushBarsys360Craft` L1825-1845)
        // and UIKit `RecipePageViewModel.checkBarsys360Craftability`:
        // ONLY base + mixer ingredients get matched against stations.
        // Garnish and additional ingredients are display-only — they
        // don't get poured from a station and almost always ship with
        // blank or non-matching categories, so including them in the
        // loop makes the validation incorrectly reject craftable
        // recipes with the "Ingredient doesn't exist in station.
        // Set up station first." alert.
        //
        // The previous mixlist-detail port iterated `recipe.ingredients`
        // verbatim — meaning a recipe with, say, a lemon-wedge garnish
        // whose category is `(garnish, "")` would fail station matching
        // even though the Recipe Page's craft button for the SAME
        // recipe passes. Matches UIKit `baseAndMixerIngredientsArr`
        // used by both craft paths.
        let baseAndMixer = (recipe.ingredients ?? []).filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        // 4a: validate every base/mixer ingredient has a category-matched
        // station with enough quantity.
        for ing in baseAndMixer {
            let primary = (ing.category?.primary ?? "").lowercased()
            let secondary = (ing.category?.secondary ?? "").lowercased()
            let match = stations.first {
                ($0.category?.primary ?? "").lowercased() == primary
                && ($0.category?.secondary ?? "").lowercased() == secondary
                && !($0.ingredientName.isEmpty)
            }
            guard let matched = match else {
                env.alerts.show(title: Constants.ingredientDoesNotExistInStation)
                return
            }
            if matched.ingredientQuantity < (ing.quantity ?? 0) {
                env.alerts.show(title: Constants.insufficientIngredientQuantityFor360)
                return
            }
        }

        // 4b: perishable-expired detection. Raw `isPerishable` flag
        // plus updated_at > 24h ago — matches UIKit
        // `getPerishableArrayFromIngredientsArr`.
        let perishable = stations.filter { $0.isPerishableExpired }
        if !perishable.isEmpty {
            env.alerts.show(
                title: Constants.perishableDescriptionTitle,
                message: "",
                primaryTitle: Constants.cleanAlertTitle,
                secondaryTitle: Constants.okayButtonTitle,
                onPrimary: {
                    HapticService.light()
                    router.push(.stationCleaning)
                },
                onSecondary: {}
            )
            return
        }

        // All good — push CraftingView.
        router.push(.crafting(recipe.id))
    }

    // MARK: - Setup-Stations flow (1:1 port of
    // `RecipeCraftingClass+StationSetup.setupStationsAction` in UIKit)
    //
    // UIKit entry:
    //   `MixlistDetailViewController.didPressSetupStationButton`
    //   → `RecipeCraftingClass().setupStationsAction(
    //        controller: self, mixlist: mixlist,
    //        baseAndMixerIngredientsArr: baseAndMixerArr, …)`
    //
    // High-level steps (UIKit L101-223 of `RecipeCraftingClass+StationSetup.swift`):
    //
    //  1. GET current stations via `MixlistsUpdateClass().getStationsHere`.
    //  2. Build `mixlistIngredientsWithStationName` — each mixlist
    //     ingredient tagged with primary/secondary category + quantity
    //     `NumericConstants.maximumQuantityIntMLFor360` (750 ml default).
    //  3. For each current station:
    //       • If it already holds a mixlist ingredient → keep it.
    //       • If it's empty → mark index as "blank".
    //  4. Compute `unused` = mixlist ingredients not already on a station.
    //  5. Fill blanks in order with `unused` entries.
    //  6. For stations that have ingredients NOT in the mixlist → replace
    //     them with remaining `unused` entries + record them in
    //     `changedStations`.
    //  7. Translate `changedStations` → `differentStationsToCleanArr`
    //     (only stations that previously had a real ingredient need
    //     cleaning before the new mixlist ingredient is poured in).
    //  8. Compute `perishableArray` — any current station whose
    //     `is_perishable` timer expired (>24 h since `updated_at`).
    //  9. Decision:
    //       • cleaning OR perishable → show `perishableDescriptionTitle`
    //         alert with `[Clean | Okay]` buttons. Clean → navigate to
    //         the cleaning flow with `.setupStationsFlow` origin;
    //         Okay → dismiss (user stays on mixlist detail).
    //       • otherwise → push `StationsMenu` in setup mode, which
    //         displays the mapped ingredients and a single "Continue"
    //         button that PATCHes + navigates to crafting with
    //         `skipPourConfirmation = true`.
    //
    // NB: for UI parity the SwiftUI port uses the app's standard alert
    // service (AppEnvironment.alerts) and defers the cleaning
    // navigation to `.stationCleaning` (which reads the same
    // `router.setupStationsContext`).
    private func setupStations(for mixlist: Mixlist) {
        // Step 0: Pre-flight — the button is already hidden when a
        // non-Barsys360 device is connected, but also block if no
        // device at all. UIKit uses the same guard in
        // `craft360RecipeForUpdatedQuantity` (L10-17).
        guard ble.isBarsys360Connected() else {
            // 1:1 with UIKit `openPairYourDeviceWhenNotConnected()` +
            // `.recipeCrafting` source — mixlist setup requires a
            // Barsys 360 which is a crafting-flow prerequisite.
            router.promptPairDevice(isConnected: ble.isAnyDeviceConnected,
                                    source: .recipeCrafting)
            return
        }

        // Step 1: Collect the mixlist's base + mixer ingredients (the
        // "actualBaseAndMixerArrOfMixlist" UIKit array). Aggregated
        // across every recipe in the mixlist — non-empty category + name,
        // de-duplicated by name (lowercased).
        let baseAndMixer = collectMixlistBaseAndMixer(mixlist)

        // UIKit L183: "The selected mixlist contains more than 6 ingredients."
        // guard — show an error if the aggregated list can't fit on 6
        // stations.
        guard baseAndMixer.count <= 6 else {
            env.alerts.show(title: Constants.selectedMixlistContainsMoreThanSixIngredients)
            return
        }

        // Step 2: Kick off the async `getStations → auto-map → route`
        // pipeline. Pull the device name ONCE (don't call twice in
        // .task(id:) + body — UIKit bug documented in STATIONS_API
        // getStations analysis).
        let deviceName = ble.getConnectedDeviceName()
        guard !deviceName.isEmpty else {
            env.alerts.show(title: Constants.deviceNotConnected)
            return
        }

        Task { @MainActor in
            // `LoadingState` API mirrors UIKit's `SpinnerHelper.show/hide` —
            // `.show(_ message:)` to present, `.hide()` to dismiss.
            env.loading.show("Setting up…")
            let currentStations = await StationsAPIService.loadStations(
                deviceName: deviceName
            )
            env.loading.hide()

            // Run the UIKit auto-assignment algorithm. Stations that
            // were previously occupied but now hold a non-mixlist
            // ingredient end up in `stationsToClean`.
            let result = RecipeCraftingSetup.autoMap(
                mixlistIngredients: baseAndMixer,
                currentStations: currentStations
            )

            // Detect perishable-expired stations (`updated_at` older
            // than 24 h and `is_perishable == true`). Matches UIKit
            // `getPerishableArrayFromIngredientsArr`. Uses
            // `isPerishableExpired` computed property — NOT the raw
            // `isPerishable` flag, which returns true for any
            // station holding a perishable ingredient regardless of
            // time elapsed. Without the expired-check, freshly-filled
            // perishables (e.g. just-added Cream) would route the
            // user back into cleaning on every setup pass.
            let perishableExpired = currentStations.filter { $0.isPerishableExpired }

            let needsCleaning = !result.stationsToClean.isEmpty
                             || !perishableExpired.isEmpty

            // Publish the context so `StationsMenuView` / the cleaning
            // flow can read it on appear.
            router.setupStationsContext = SetupStationsContext(
                mixlist: mixlist,
                baseAndMixerIngredients: baseAndMixer,
                mappedSlots: result.mappedSlots,
                requiresCleaning: needsCleaning,
                stationsToClean: result.stationsToClean + perishableExpired
            )

            // 1:1 port of UIKit
            // `RecipeCraftingClass+StationSetup.setupStationsAction`
            // L149-164:
            //
            // ```
            // if differentStationsToCleanArr.count > 0 || perishableObject != nil {
            //     if let navVC = controller.navigationController {
            //         ControlCenterCoordinator.init(navigationController: navVC)
            //             .showStationCleaningFlow(
            //                 stationsOrigin: .setupStationsFlow,
            //                 baseAndMixerIngredients: baseAndMixerIngredientsArr,
            //                 mixlist: mixlist,
            //                 mixlistOrRecipeIngredients: finalArrayMapped
            //             )
            //     }
            // } else {
            //     … push StationsMenu in setupStationsFlow …
            // }
            // ```
            //
            // UIKit routes DIRECTLY to the cleaning screen — there is
            // NO intermediate "Ingredients may be spoiled. Clean the
            // machine before use." confirmation popup at this step.
            // The cleaning screen's own callbacks
            // (`onShowDifferentStationsAlert` → "Proceed to clean",
            //  `onShowPerishableCleanedAlert` → "Perishable
            //   Ingredients Cleaned") fire the right alerts from
            // WITHIN the cleaning screen once it lands and finishes
            // `getDifferentIngredientsInMixlistIngredients`.
            //
            // The previous SwiftUI port added an extra
            // `perishableDescriptionTitle` Clean/Okay popup here,
            // which:
            //   • is not in UIKit (user-reported "wrong perishable
            //     alert keeps popping up"),
            //   • gave "Okay" an abort-setup side-effect that
            //     silently wiped `setupStationsContext` without any
            //     obvious affordance for the user to proceed after
            //     declining, and
            //   • interrupted the flow with a popup before the
            //     cleaning screen could surface its own
            //     "Proceed to clean" alert, so the user saw two
            //     back-to-back alerts in the setup path.
            //
            // Direct push matches UIKit byte-for-byte.
            HapticService.light()
            if needsCleaning {
                router.push(.stationCleaning)
            } else {
                router.push(.stationsMenu)
            }
        }
    }

    /// 1:1 port of UIKit
    /// `MixlistDetailViewModel.baseAndMixerIngredientsArr`:
    /// aggregate the union of base + mixer ingredients across every
    /// recipe in the mixlist, de-duplicated by ingredient name
    /// (lowercased, whitespace-trimmed). Garnishes and "additional"
    /// decorations are deliberately excluded because they don't go on
    /// stations (UIKit splits these via `IngredientCategory.isBaseOrMixer`).
    private func collectMixlistBaseAndMixer(_ mixlist: Mixlist) -> [Ingredient] {
        var seen: [String: Ingredient] = [:]
        for recipe in (mixlist.recipes ?? []) {
            for ing in (recipe.ingredients ?? []) {
                let trimmed = ing.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                // UIKit treats `category.primary == "garnish"` (and nil
                // categories) as NOT base/mixer — skip them.
                let primary = (ing.category?.primary ?? "").lowercased()
                // UIKit SQL: NOT IN ('garnish','additionals','additional').
                if primary == "garnish" || primary == "additional" || primary == "additionals" { continue }
                let key = trimmed.lowercased()
                if seen[key] == nil { seen[key] = ing }
            }
        }
        return Array(seen.values).sorted { $0.name < $1.name }
    }

    /// 1:1 port of UIKit `MixlistDetailViewModel.performLikeUnlike(at:controller:)`:
    ///   1. Toggle local storage (isFavourite + favCreatedAt)
    ///   2. Call likeUnlikeApi (fire-and-forget)
    ///   3. Show toast
    /// UIKit also does `storage.updateFavouriteStatus(forRecipeId:isFavourite:)`
    /// — our `toggleFavorite` now handles that (sets isFavourite + favCreatedAt).
    private func toggleFav(_ recipe: Recipe) {
        HapticService.light()
        let wasFav = recipe.isFavourite ?? false
        let willBeFav = !wasFav
        env.storage.toggleFavorite(recipe.id)
        // Force the `recipes` computed property to re-run so the heart
        // icon swaps between `favIconRecipe` ↔ `favIconRecipeSelected`
        // immediately. Without this bump, `MockStorageService` mutates
        // silently (no `ObservableObject` broadcast) and the row keeps
        // its pre-tap rendering until the screen is left and re-entered.
        favouritesRefreshTick &+= 1
        // Fire-and-forget API call (1:1 UIKit: FavoriteRecipeApiService.likeUnlikeApi)
        Task {
            _ = try? await env.api.likeUnlike(
                recipeId: recipe.id.value, isLike: willBeFav)
        }
        env.analytics.track(
            (willBeFav ? TrackEventName.favouriteRecipeAdded
                       : TrackEventName.favouriteRecipeRemoved).rawValue
        )
        env.alerts.show(message: wasFav ? Constants.unlikeSuccessMessage : Constants.likeSuccessMessage)
    }
}

// MARK: - Mixlist recipe row (ports MixlistDetailTableViewCell)
//
// **Re-analysed runtime constraints (NOT IB design-time frame snapshots):**
//   • `image.width = innerView.width × 0.5`           (id="VKZ-2m-DkK")
//   • `image.width = image.height` (1:1 square)       (id="2gl-fW-Dgu")
//   • image top/trailing/bottom pinned to innerView   (full inner height)
// → Image is **50% of cell width, square, full inner-card height**.
//
// LEFT half (in xib order top→bottom):
//   • drinkLabel:    top=16, leading=16, trailing=image.leading-16
//                    font 16pt, 4 lines (set programmatically), charcoal
//   • drinkInfoLabel: top=drinkLabel.bottom+16, leading=16,
//                     trailing=image.leading-16, bottom=innerView.bottom-15
//                     font 10pt, 0 lines (unlimited), mediumLightGray
//   • craftButton: leading=16, trailing=image.leading-16, height=29,
//                  bottom=innerView.bottom-10, title "Craft" 10pt black,
//                  roundCorners=8, 1pt craftButtonBorderColor stroke
// RIGHT half:
//   • drinkThumbImage: 50% × square, scaleAspectFill, `myDrink` placeholder,
//                      `lightBorderGrayColor` background
//   • favouriteButton: 30×30 (40×40 iOS 26+), top=innerView.top+5,
//                      trailing=innerView.trailing-5 (overlaps image's
//                      top-right corner). favIconRecipe / favIconRecipeSelected.
// Plus: 12pt bottom spacer image after the inner card.
struct MixlistDetailRecipeRow: View {
    let recipe: Recipe
    let isFavourite: Bool
    /// Locked square side passed by the parent list (same convention as
    /// MixlistRowCell / RecipeRowCell). Removes scroll-zoom artefacts.
    let cellHeight: CGFloat
    let onOpen: () -> Void
    let onCraft: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left half: title (top) → ingredients (middle) → Craft (bottom).
            // Uniform row height: title 3 lines, ingredients 6 lines max.
            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let info = recipe.ingredientNames, !info.isEmpty {
                    Text(info)
                        .font(.system(size: 10))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !recipe.subtitle.isEmpty {
                    Text(recipe.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                // Craft button — height=29, full-width within left half,
                // 8pt corner radius, 1pt craftButtonBorderColor stroke.
                Button {
                    HapticService.light()
                    onCraft()
                } label: {
                    Text(Constants.craftTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .background(
                            // `Theme.Color.surface` light = pure white
                            // sRGB(1, 1, 1), bit-identical to the previous
                            // hard-coded `Color.white`, so the Craft pill
                            // is the EXACT same white capsule in light
                            // mode. Dark mode picks up the elevated
                            // dark surface (#2C2C2E) so the pill stops
                            // being a stark white slab on the dark
                            // recipe row card.
                            RoundedRectangle(cornerRadius: 8).fill(Theme.Color.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
                        )
                }
                .buttonStyle(BounceButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right half: explicit `cellHeight × cellHeight` square — no
            // aspect-ratio recalculation, no scroll-zoom.
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: recipe.imageURL)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        Color("lightBorderGrayColor")
                    case .failure:
                        Image("myDrink").resizable().aspectRatio(contentMode: .fit).padding(16)
                    @unknown default:
                        Color("lightBorderGrayColor")
                    }
                }
                .frame(width: cellHeight, height: cellHeight)
                .background(Color("lightBorderGrayColor"))
                .clipped()

                Button {
                    HapticService.light()
                    onFavorite()
                } label: {
                    Image(isFavourite ? "favIconRecipeSelected" : "favIconRecipe")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Theme.Color.softWhiteText)
                }
                .buttonStyle(BounceButtonStyle())
                .padding(.top, 5)
                .padding(.trailing, 5)
                .accessibilityLabel("Favourite")
            }
        }
        .frame(height: cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
                // bit-identical to the previous hard-coded `Color.white`,
                // so each Mixlist Detail recipe row remains the EXACT
                // same white card in light mode. Dark mode picks up
                // the elevated dark surface (#2C2C2E) so the row reads
                // as a raised card on the dark Mixlist Detail canvas
                // — matching the History rows / BarBot bubbles.
                .fill(Theme.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen() }
        .padding(.bottom, 12) // 12pt bottom spacer (xib `r8k-xs-Rck`)
    }
}

// MARK: - Edit Mixlist

struct EditMixlistView: View {
    let mixlistID: MixlistID?
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var descriptionText = ""

    var body: some View {
        Form {
            Section("Details") {
                TextField(Constants.pleaseAddMixlistName, text: $name)
                TextField("Description", text: $descriptionText)
            }
            Button(ConstantButtonsTitle.saveButtonTitle) {
                var m = Mixlist(id: mixlistID ?? MixlistID(),
                                name: name,
                                description: descriptionText,
                                recipes: [])
                if let id = mixlistID, let existing = env.storage.allMixlists().first(where: { $0.id == id }) {
                    m = Mixlist(id: id,
                                name: name,
                                description: descriptionText,
                                tags: existing.tags,
                                recipes: existing.recipes,
                                image: existing.image,
                                barsys360Compatible: existing.barsys360Compatible,
                                slug: existing.slug,
                                ingredientNames: existing.ingredientNames)
                }
                env.storage.upsert(mixlist: m)
                env.alerts.show(message: Constants.mixlistAddMessage)
                dismiss()
            }
            .foregroundStyle(Theme.Color.brand)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
        .navigationTitle("Edit mixlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear {
            if let id = mixlistID, let m = env.storage.allMixlists().first(where: { $0.id == id }) {
                name = m.name ?? ""
                descriptionText = m.description ?? ""
            }
        }
    }
}

// MARK: - RecipeCraftingSetup
//
// 1:1 port of UIKit `RecipeCraftingClass+StationSetup.setupStationsAction`
// (BarsysApp/Controllers/Crafting/Crafting Class/RecipeCraftingClass+StationSetup.swift
// L101-223). Pure-data helper — no UI, no side effects — so it can be
// unit-tested independently and called from any entry point
// (MixlistDetail, RecipePage customize flow, BarBot mixlist tile, etc.).
//
// ALGORITHM (UIKit source, paraphrased):
//   0. `mixlistIngredientsWithStationName` = each mixlist ingredient
//      tagged with `primary + secondary` (lowercased) + default 750 ml.
//   1. `finalArrayMapped = currentStations` (we mutate a copy).
//   2. Walk `finalArrayMapped`:
//        - If station already has an ingredient (`!name.isEmpty`) →
//          push into `usedIngredients` so we never re-assign the same
//          mixlist ingredient twice.
//        - Else → push index into `blankIndices`.
//   3. `unused` = mixlist ingredients NOT already in `usedIngredients`
//      (matched by primary+secondary lowercase, falling back to name).
//   4. Fill `blankIndices` in order with `unused` — pop the front each
//      time. If ALL 6 stations were blank, UIKit adds every filled
//      station to `changedStations` so the setup flow still records
//      them (UIKit L146-148).
//   5. Walk filled stations again:
//        - If a station's current ingredient is NOT in the mixlist
//          (by primary+secondary) → replace with next `unused` entry
//          and record the station name in `changedStations`.
//   6. `stationsToClean` = stations from `changedStations` whose
//      PREVIOUS ingredient was non-empty (those contain an old
//      ingredient that physically needs to be flushed before the new
//      mixlist ingredient can be poured in).
//
// Output:
//   • `mappedSlots`     — the 6-station array (A–F) with the mixlist
//                         ingredients now assigned.
//   • `stationsToClean` — stations requiring a cleaning cycle before
//                         the crafting flow can start.
enum RecipeCraftingSetup {

    struct Result: Equatable {
        let mappedSlots: [StationSlot]
        let stationsToClean: [StationSlot]
    }

    /// Temporary struct mirroring UIKit's `MixlistIngredientTemp` —
    /// key/value pairs carrying name, quantity, primary, secondary
    /// during the mapping walk. Kept internal to this algorithm.
    private struct TempIngredient {
        var name: String
        var quantity: Double
        var primary: String
        var secondary: String
        /// Keep the original Ingredient so we can copy back category +
        /// perishable flag onto the mapped StationSlot (UIKit L141-144,
        /// L175-177).
        var source: Ingredient
    }

    static func autoMap(mixlistIngredients: [Ingredient],
                        currentStations: [StationSlot]) -> Result {
        // Sort the 6 stations A→F so we always produce a deterministic
        // A→F output array (UIKit relies on station tag order
        // everywhere).
        let stationsArrPrevious = currentStations.sorted {
            $0.station.rawValue < $1.station.rawValue
        }
        var finalArrayMapped = stationsArrPrevious

        // Step 0: build `mixlistIngredientsWithStationName`.
        // UIKit L104-107: default each entry to `maximumQuantityIntMLFor360`
        // (750 ml) regardless of recipe quantity — the setup flow isn't
        // bound by individual recipe quantities, just stocking choices.
        let mixlistTemps: [TempIngredient] = mixlistIngredients.map { ing in
            TempIngredient(
                name: ing.name,
                quantity: Double(NumericConstants.maximumQuantityIntMLFor360),
                primary: (ing.category?.primary ?? "").lowercased(),
                secondary: (ing.category?.secondary ?? "").lowercased(),
                source: ing
            )
        }

        // Step 2: usedIngredients (filled stations) + blankIndices.
        var usedIngredients: [TempIngredient] = []
        var blankIndices: [Int] = []
        for (idx, slot) in finalArrayMapped.enumerated() {
            if !slot.ingredientName.isEmpty
                && slot.ingredientName != Constants.emptyDoubleDash {
                usedIngredients.append(TempIngredient(
                    name: slot.ingredientName,
                    quantity: slot.ingredientQuantity,
                    primary: (slot.category?.primary ?? "").lowercased(),
                    secondary: (slot.category?.secondary ?? "").lowercased(),
                    source: Ingredient(
                        name: slot.ingredientName,
                        category: slot.category,
                        quantity: slot.ingredientQuantity,
                        perishable: slot.isPerishable
                    )
                ))
            } else {
                blankIndices.append(idx)
            }
        }

        // Step 3: filter mixlistTemps down to entries not already on a
        // station. UIKit matches via `isSameIngredient` = primary+secondary
        // equality; fall back to name equality when both categories are
        // empty (handles legacy user-created recipes without categories).
        var unused: [TempIngredient] = mixlistTemps.filter { mix in
            !usedIngredients.contains(where: { Self.isSameIngredient(mix, $0) })
        }

        var changedStations: [StationName] = []

        // Step 4: fill blanks.
        for idx in blankIndices {
            if unused.isEmpty { break }
            let newIng = unused.removeFirst()
            finalArrayMapped[idx].ingredientName = newIng.name
            finalArrayMapped[idx].ingredientQuantity = newIng.quantity
            finalArrayMapped[idx].category = newIng.source.category
                ?? IngredientCategory(primary: newIng.primary,
                                      secondary: newIng.secondary,
                                      flavourTags: [])
            finalArrayMapped[idx].isPerishable = newIng.source.perishable ?? false
            // UIKit L146-148: when ALL six stations were blank, still
            // track every filled station in `changedStations` — the
            // setup flow uses this to decide whether to gate on a
            // confirmation alert.
            if blankIndices.count == 6 {
                changedStations.append(finalArrayMapped[idx].station)
            }
        }

        // Step 5: replace mismatched existing ingredients.
        for i in 0..<finalArrayMapped.count {
            let station = finalArrayMapped[i]
            guard !station.ingredientName.isEmpty,
                  station.ingredientName != Constants.emptyDoubleDash
            else { continue }
            let current = TempIngredient(
                name: station.ingredientName,
                quantity: station.ingredientQuantity,
                primary: (station.category?.primary ?? "").lowercased(),
                secondary: (station.category?.secondary ?? "").lowercased(),
                source: Ingredient(name: station.ingredientName)
            )
            let matchesMixlist = mixlistTemps.contains { Self.isSameIngredient($0, current) }
            if !matchesMixlist, let newIng = unused.first {
                finalArrayMapped[i].ingredientName = newIng.name
                finalArrayMapped[i].ingredientQuantity = newIng.quantity
                finalArrayMapped[i].category = newIng.source.category
                    ?? IngredientCategory(primary: newIng.primary,
                                          secondary: newIng.secondary,
                                          flavourTags: [])
                finalArrayMapped[i].isPerishable = newIng.source.perishable ?? false
                changedStations.append(finalArrayMapped[i].station)
                unused.removeFirst()
            }
        }

        // Step 6: stations that need cleaning = stations that changed
        // AND previously held a real ingredient (UIKit L184-192).
        let stationsToClean: [StationSlot] = changedStations.compactMap { name in
            guard let prev = stationsArrPrevious.first(where: { $0.station == name })
            else { return nil }
            return prev.ingredientName.isEmpty ? nil : prev
        }

        return Result(
            mappedSlots: finalArrayMapped,
            stationsToClean: stationsToClean
        )
    }

    /// 1:1 port of UIKit `isSameIngredient(_:_:)`. Primary+secondary
    /// (lowercase) compare first. Falls back to ingredient-name
    /// equality in two cases:
    ///   1. BOTH sides have blank categories (UIKit's documented
    ///      behaviour — supports legacy recipes without categories).
    ///   2. ONE side has blank categories AND the names match
    ///      (compatibility with stations PATCHed before the
    ///      `category` field was included in the payload — see
    ///      `patchAllStations` for the historical bug where the
    ///      server lost category data on every Setup-Stations
    ///      round-trip). Without this fallback the auto-map would
    ///      misread the half-populated server state as "station
    ///      holds a non-recipe ingredient" and route the user back
    ///      into cleaning even though the ingredient names match
    ///      perfectly — the user-reported "re-setup same mixlist
    ///      keeps taking me to clean stations" regression.
    private static func isSameIngredient(_ a: TempIngredient,
                                         _ b: TempIngredient) -> Bool {
        let ap = a.primary.trimmingCharacters(in: .whitespaces)
        let as_ = a.secondary.trimmingCharacters(in: .whitespaces)
        let bp = b.primary.trimmingCharacters(in: .whitespaces)
        let bs = b.secondary.trimmingCharacters(in: .whitespaces)
        let aHasCategory = !ap.isEmpty || !as_.isEmpty
        let bHasCategory = !bp.isEmpty || !bs.isEmpty
        let nameA = a.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nameB = b.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if aHasCategory && bHasCategory {
            // Both sides carry category info → strict compare (UIKit's
            // primary branch). Category mismatch here means genuinely
            // different ingredients (e.g. "Vodka (base/clear)" vs
            // "Triple Sec (liqueur/citrus)").
            return ap == bp && as_ == bs
        }
        if !aHasCategory && !bHasCategory {
            // UIKit's documented fallback — both sides blank, compare
            // names. Covers legacy user-created recipes / manually
            // added ingredients that never had categories assigned.
            return nameA == nameB && !nameA.isEmpty
        }
        // Asymmetric case — one side has category, the other doesn't.
        // Accept the match when names agree. Prevents the SAME
        // ingredient (same name) from being flagged as different just
        // because one storage layer preserved categories while the
        // other dropped them.
        return nameA == nameB && !nameA.isEmpty
    }
}

