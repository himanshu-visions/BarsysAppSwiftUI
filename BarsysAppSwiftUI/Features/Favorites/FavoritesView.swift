//
//  FavoritesView.swift
//  BarsysAppSwiftUI
//
//  1:1 port of `FavouritesRecipesAndDrinksViewController` and its
//  +TableView / +Accessibility extensions.
//
//  UIKit hierarchy reproduced here:
//   • 60pt custom nav (back chevron, device-info principal, favourites
//     button + glass profile circle trailing).
//   • Two-tab segmented selector "Barsys Recipes" / "My Drinks" — bold
//     14pt, active=appBlackColor, inactive=unSelectedColor, with the
//     active tab underlined by a 2pt rule (matches the storyboard
//     separator imageView between the buttons).
//   • Search bar (44pt, 12pt corners, `barbotBorderColor` 1pt stroke,
//     toggleable search↔cross icon).
//   • TableView of `BarsysRecipeTableViewCell` rows; cell layout matches
//     the xib's runtime constraints exactly:
//       — innerView (`beM-9Q-oNs`) glass card, 16pt corners
//       — drinkThumbImage = 50% of cell width (constraint VKZ-2m-DkK,
//         multiplier=0.5) + 1:1 aspect (AZv-Tk-EK2), full inner-card
//         height. Placeholder `myDrink`, bg `lightBorderGrayColor`.
//       — drinkLabel system 16pt charcoal, top=16, leading=16, lines=4
//       — drinkInfoLabel system 10pt mediumLightGray, lines=0
//       — favouriteButton 30×30 top-right (top=5, trailing=5)
//       — moreButton 30×30 below favourite (top=50, trailing=5) — visible
//         on My Drinks only (`tab == .myDrinks`)
//       — moreView popup 92×76 with Edit (92×38) + Delete (92×38), each
//         12pt system font, appBlackColor titles, glass effect with
//         `BarsysCornerRadius.small` (8pt)
//       — bottom 12pt spacer image (`r8k-xs-Rck`)
//   • Pull-to-refresh, "no data found" empty state, glass loader on the
//     favourite-toggle in-flight callback.
//
//  Functional parity:
//   • Favourite toggle goes through `env.storage.toggleFavorite(_:)` and
//     emits the matching Braze event (favouriteRecipeAdded / Removed).
//   • Tap on a row → `router.push(.recipeDetail(...))`.
//   • My Drinks "Edit" → `router.push(.editRecipe(...))`.
//   • My Drinks "Delete" → confirmation alert → local removal.
//   • Search filters by recipe name + ingredientNames (matches UIKit
//     `cacheRecipesSearchResults`).
//   • Tracking: `favouratesScreenViewed` on first appear.
//   • Accessibility labels/hints on every interactive control + the row.
//

import SwiftUI

// MARK: - MyDrinksCache
//
// Persistent cache for My Drinks data — ports the UIKit `cocktails_recipes`
// + `cocktails_ingredients` SQLite tables (DBHelper.swift L387-432).
//
// UIKit defines _insertMyDrinksData / _fetchDataForMyDrinks in
// DBManager+Favourites.swift but never calls them — My Drinks are always
// fetched fresh from the API on every viewWillAppear. However the DB
// infrastructure exists for offline/restart resilience.
//
// We implement actual persistence via UserDefaults+JSON so My Drinks
// survive app restarts. The flow mirrors UIKit's intended design:
//   • After successful API fetch → save to cache
//   • On app restart / API failure → load from cache
//   • After delete → remove from cache

enum MyDrinksCache {
    private static let recipesKey = "barsys_cachedMyDrinksRecipes"

    /// Ports UIKit `_insertMyDrinksData(_ myDrinks: [Recipe])` —
    /// INSERT OR REPLACE into cocktails_recipes + cocktails_ingredients.
    static func save(_ recipes: [Recipe]) {
        guard let data = try? JSONEncoder().encode(recipes) else { return }
        UserDefaults.standard.set(data, forKey: recipesKey)
    }

    /// Ports UIKit `_fetchDataForMyDrinks() -> [Recipe]` —
    /// SELECT * FROM cocktails_recipes.
    static func load() -> [Recipe] {
        guard let data = UserDefaults.standard.data(forKey: recipesKey),
              let recipes = try? JSONDecoder().decode([Recipe].self, from: data) else {
            return []
        }
        return recipes
    }

    /// Ports UIKit `_deleteRecipe(byId:)` for cocktails_recipes —
    /// DELETE FROM cocktails_recipes WHERE id = ?.
    static func remove(recipeId: RecipeID) {
        var cached = load()
        cached.removeAll { $0.id == recipeId }
        save(cached)
    }

    /// Clear all cached My Drinks.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: recipesKey)
    }
}

// MARK: - Tab enum

enum FavouritesTab: Int, Hashable, CaseIterable, Identifiable {
    case barsysRecipes = 0
    case myDrinks = 1
    var id: Self { self }
    var title: String { self == .barsysRecipes ? "Barsys Recipes" : "My Drinks" }
}

// MARK: - Root screen

struct FavoritesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    @Environment(\.dismiss) private var dismiss
    /// Reactive theme awareness — used to tint the top-right profile
    /// icon to near-white ONLY in dark mode (light mode keeps the
    /// raw PNG so pixels stay bit-identical to the existing design).
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: FavouritesTab = .barsysRecipes
    @State private var showMoreMenuFor: RecipeID? = nil
    @State private var didTrackView = false
    @State private var recipeToEdit: Recipe? = nil

    /// Forces `rows` to re-evaluate after a mutation that doesn't go
    /// through a `@Published` source. `MockStorageService` is plain
    /// (not `ObservableObject`) so calls to `env.storage.toggleFavorite`
    /// don't broadcast — without this trigger the heart-tap on the
    /// Barsys Recipes tab would update storage but the row would stay
    /// on screen until the user navigated away and back. UIKit
    /// `getMyFavouritesDataToShow(indexToLike:)` re-fetches the
    /// favourites array after the success alert is dismissed; this
    /// trigger plays the same role for the SwiftUI port.
    @State private var favouritesRefreshTick: Int = 0

    // MARK: - My Drinks Pagination State
    // 1:1 port of UIKit FavouritesRecipesAndDrinksViewModel pagination:
    //   var myDrinksResponseModel: MyDrinksDataModel? = nil
    //   var paginationState: PaginationState = .idle
    //
    // PaginationState: idle → loadingMore, triggered when scroll reaches
    // within 20pt of bottom (scrollViewDidEndDecelerating check).
    // Data concatenation: new API page data appended to existing array.

    @State private var myDrinksResponseModel: MyDrinksDataModel? = nil
    @State private var myDrinksLoaded: [Recipe] = []
    @State private var isLoadingMyDrinks = false
    @State private var isLoadingMoreMyDrinks = false
    @State private var myDrinksInitialLoadDone = false

    /// Whether more My Drinks pages are available.
    /// UIKit: `canLoadMoreMyDrinks` → offset != 0 && offset < total.
    private var canLoadMoreMyDrinks: Bool {
        guard let model = myDrinksResponseModel else { return false }
        let currentCount = model.data?.count ?? 0
        let total = model.total ?? 0
        return currentCount > 0 && currentCount < total
    }

    /// Source recipes per tab — ports `numberOfRows` + `recipe(at:)` from
    /// `FavouritesRecipesAndDrinksViewModel`.
    ///
    /// **Sort order** — matches UIKit `DBQueries.swift`:
    ///   • Barsys Recipes (L125):
    ///       ORDER BY r.barsys360Compatible DESC, r.favCreatedAt DESC
    ///   • My Drinks: uses API response order (server-sorted)
    private var rows: [Recipe] {
        // Reading `favouritesRefreshTick` here forces SwiftUI to re-evaluate
        // this computed property whenever the tick changes — required
        // because `env.storage.favorites()` reads from a non-observable
        // service (`MockStorageService` isn't an ObservableObject), so
        // the toggle would otherwise leave the row visible until the
        // next external trigger. This is the SwiftUI equivalent of
        // UIKit's explicit `tblFavouritesRecipesAndDrinks.reloadData()`
        // call after `applyLikeResult`.
        _ = favouritesRefreshTick
        let pool: [Recipe]
        switch selectedTab {
        case .barsysRecipes:
            let ids = env.storage.favorites()
            pool = env.storage.allRecipes()
                .filter { ids.contains($0.id) }
                .sorted { lhs, rhs in
                    let lb = lhs.barsys360Compatible == true
                    let rb = rhs.barsys360Compatible == true
                    if lb != rb { return lb && !rb }
                    return (lhs.favCreatedAt ?? 0) > (rhs.favCreatedAt ?? 0)
                }
        case .myDrinks:
            // Use API-loaded data when available, fallback to local storage
            if myDrinksInitialLoadDone {
                pool = myDrinksLoaded
            } else {
                pool = env.storage.allRecipes()
                    .filter { $0.isMyDrinkFavourite == true }
                    .sorted { ($0.favCreatedAt ?? 0) > ($1.favCreatedAt ?? 0) }
            }
        }
        return pool
    }

    // Toolbar device helpers.
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
        // tabsBar + recipe rows are now hosted INSIDE the
        // outer ScrollView — same structural pattern that fixed the
        // right-pill chrome on HomeView / Cocktail Kits / Pair Your
        // Device / Preferences. iOS 26's nav-bar Liquid Glass auto-wrap
        // relies on having scrollable material directly under the bar
        // to render the silvery-frosted right-pill the user sees on
        // MyBar / DevicePairedView / RecipeDetail; without it the bar
        // falls back to the thinner "black transparent" pill in dark
        // mode.
        //
        // The inner ScrollView in `content` (rows-non-empty branch) is
        // removed since nesting two ScrollViews would double-handle
        // bounce / pagination. Pull-to-refresh, infinite-scroll
        // pagination trigger, and bottom inset all stay intact — the
        // refreshable now hangs off the outer ScrollView and the
        // pagination `.onAppear` trigger on the last row still fires
        // when the row scrolls into view.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                tabsBar
                content
            }
        }
        .refreshable { await refresh() }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
        // Publish "we're on Favourites" so the side menu can skip a
        // duplicate `router.push(.favorites)` when the user taps the
        // Favourites row while this screen is already on-screen.
        .onAppear { router.isShowingFavorites = true }
        .onDisappear { router.isShowingFavorites = false }
        .onAppear {
            if !didTrackView {
                didTrackView = true
                env.analytics.track(TrackEventName.favouratesScreenViewed.rawValue)
            }
            // 1:1 port of UIKit viewWillAppear (L153-169):
            //   viewModel.resetMyDrinksForRefresh()
            //   getMyDrinksApi(isInitialDataLoading: true)
            //   getMyFavouritesDataToShow(isInitialDataLoading: true)
            //
            // UIKit ALWAYS resets + re-fetches on every screen appear so
            // the list reflects any edits/deletes made on other screens.
            // We mirror this by resetting and loading fresh every time.
            resetMyDrinksForRefresh()

            // Honor the deep-link / save-success preselected tab. UIKit
            // `BarBotCoordinator.showFavourites(tabSelected: 1)` opens
            // FavouritesRecipesAndDrinksViewController on the My Drinks
            // tab; we mirror that by reading
            // `router.pendingFavoritesTabIndex` set by the EditRecipe
            // save flow and clearing it after consumption.
            if let idx = router.pendingFavoritesTabIndex,
               let tab = FavouritesTab(rawValue: idx) {
                selectedTab = tab
                router.pendingFavoritesTabIndex = nil
                if tab == .myDrinks {
                    loadMyDrinksInitially()
                }
            }
        }
        .onChange(of: selectedTab) { newTab in
            // Reload My Drinks when switching to the tab if not yet loaded
            if newTab == .myDrinks && !myDrinksInitialLoadDone {
                loadMyDrinksInitially()
            }
        }
        // Refresh My Drinks when the EditRecipe save-success flow
        // signals a tick. Fires when the user saved an edit while
        // Favorites was already on-screen — we skip the redundant
        // `router.push(.favorites)` and just re-run the My Drinks fetch
        // in-place so the edited drink appears immediately.
        .onChange(of: router.myDrinksRefreshTick) { _ in
            // Also honour the pre-selected tab index the edit flow set,
            // so the user lands on My Drinks if they were on Barsys
            // Recipes when they edited.
            if let idx = router.pendingFavoritesTabIndex,
               let tab = FavouritesTab(rawValue: idx) {
                selectedTab = tab
                router.pendingFavoritesTabIndex = nil
            }
            resetMyDrinksForRefresh()
        }
        .simultaneousGesture(
            // Tapping anywhere outside a more-menu dismisses it (mirrors
            // UIKit's tap-away behaviour).
            TapGesture().onEnded { showMoreMenuFor = nil }
        )
        // 1:1 port of UIKit
        // `FavouritesRecipesAndDrinksViewController.didSelectEdit`:
        // the Edit button in the 3-dot "more" menu on a My-Drinks row
        // PRESENTS EditViewController modally — it does NOT push it
        // onto the current tab's nav stack.
        //
        // `.fullScreenCover(item:)` binds to the `Identifiable`
        // `recipeToEdit` state variable — setting it to a Recipe
        // presents the edit sheet full-screen above whatever tab is
        // currently visible. On dismiss the state clears and user
        // returns to the My Drinks list exactly where they left off.
        .fullScreenCover(item: $recipeToEdit) { recipe in
            // `EditRecipeCoverContent` owns a local NavigationPath and
            // publishes it via `\.editCoverPath` so Craft pushes inside
            // this cover rather than onto the parent tab's stack (which
            // would render Crafting under the cover, invisibly).
            //
            // `onClose` is the direct close action the cross button
            // uses — it sets `recipeToEdit = nil` so the cover
            // dismisses reliably on iPad too.
            EditRecipeCoverContent(onClose: { recipeToEdit = nil }) {
                // isCustomizing: false — editing an EXISTING My Drink
                // (UIKit: isCustomizingRecipe = false → PATCH /my/recipes/{id})
                //
                // We pass the FULL recipe object (not just the id) because
                // My Drinks live in `myDrinksLoaded`, NOT in `env.storage`.
                // Without this the EditRecipeView's storage lookup would
                // return nil and the save would fall through to POST,
                // surfacing as the "Unable to save recipe" error.
                EditRecipeView(
                    recipeID: recipe.id,
                    existingRecipe: recipe,
                    isCustomizing: false,
                    // Signal that Edit was opened from Favorites — after
                    // save-success the view model will refresh the
                    // current list in-place instead of pushing a brand
                    // new Favorites route (which would stack a second
                    // copy of this very screen).
                    openedFromFavorites: true
                )
            }
            // Mount the alert overlay INSIDE the fullScreenCover so the
            // success popup renders ABOVE the EditRecipeView. Without
            // this re-mount, `env.alerts.show(...)` only renders on the
            // RootView level which sits BENEATH the cover — exactly the
            // "popup appears behind EditViewController" bug the user
            // reported.
            .appAlert(env.alerts)
            // UIKit `EditViewController` is a child VC overlay — its
            // `mainView` has `addGlassEffect()` which clears the view's
            // backgroundColor AND its superview's backgroundColor so the
            // `UIGlassEffect(.regular)` composites against the live
            // FavoritesVC behind it. `.fullScreenCover` defaults to an
            // opaque container which blocks that compositing entirely.
            // `.presentationBackground(.clear)` makes the cover's own
            // container transparent, so the panel's `.regularMaterial`
            // blurs the actual FavoritesView exactly like UIKit.
            //
            // Only available on iOS 16.4+. Glass materials themselves
            // are gated to iOS 26+ elsewhere, so on any OS where the
            // glass path runs, this modifier is also available.
            .modifier(ClearPresentationBackgroundModifier())
            // Inherit environment objects so the modal can access the
            // same storage / analytics / BLE services as its parent.
        }
    }

    // MARK: - Tabs
    //
    // 1:1 port of the storyboard HStack (x=24, y=62, w=345, h=30):
    //   • BarsysRecipes button: right-aligned, titleEdgeInsets maxX=30,
    //     bold 14pt, storyboard default `.black`, runtime swap to `.gray`
    //     when inactive via `selectTab(_:)`.
    //   • Vertical separator: 1pt × 16pt, black (fRu-Zk-Dvg).
    //   • MyDrinks button: left-aligned, titleEdgeInsets minX=30,
    //     bold 14pt, storyboard default `unSelectedColor`, runtime swap
    //     to `.black` / `.gray` via `selectTab(_:)`.
    //   • No underline (UIKit has no indicator — `hideTabBarSelectionView()`
    //     is unrelated; it hides the bottom tab bar selector).
    //
    // UIKit applies `.addBounceEffect()` to both buttons → we match with
    // `BounceButtonStyle()`.  iOS 26+ the overall nav bar / side-menu
    // button get a liquid-glass treatment (see `btnSideMenu` in
    // viewDidLoad), but the TAB BUTTONS THEMSELVES remain plain text on
    // every iOS version — so no glass here, only the branch on available
    // APIs for anything nav-chrome adjacent.

    private var tabsBar: some View {
        HStack(spacing: 0) {
            // Barsys Recipes — right-aligned text within its half
            Button {
                HapticService.selection()
                selectedTab = .barsysRecipes
                showMoreMenuFor = nil
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    Text(FavouritesTab.barsysRecipes.title)
                        .font(.system(size: 14, weight: .bold))
                        // Trait-resolved at draw time: light branch is
                        // EXACT pure black (`UIColor.black`) — bit-
                        // identical to the previous hard-coded
                        // `Color.black`; dark branch is near-white so
                        // the selected tab label stays legible on the
                        // dark Favourites page. Unselected uses
                        // `UIColor.gray` (system grey) which is bit-
                        // identical to `Color.gray` in light and the
                        // same fixed system grey in dark (already
                        // adaptive enough for an unselected state).
                        .foregroundStyle(selectedTab == .barsysRecipes
                                         ? Color(UIColor { trait in
                                             trait.userInterfaceStyle == .dark
                                                 ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                                                 : UIColor.black // EXACT historical
                                         })
                                         : Color.gray)
                }
                .padding(.trailing, 30)     // titleEdgeInsets maxX=30
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(FavouritesTab.barsysRecipes.title)
            .accessibilityHint("Switch to Barsys Recipes tab")
            .accessibilityAddTraits(selectedTab == .barsysRecipes ? [.isSelected] : [])

            // 1 × 16 vertical separator (fRu-Zk-Dvg).
            // Trait-resolved at draw time so the separator is the
            // EXACT historical `Color.black` in light (bit-identical
            // pixels) and a softened off-white (`softWhiteTextColor`
            // = #EBEBEB) in dark for visibility without OLED glare.
            Rectangle()
                .fill(Color(UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? (UIColor(named: "softWhiteTextColor") ?? .white)
                        : UIColor.black // EXACT historical
                }))
                .frame(width: 1, height: 16)

            // My Drinks — left-aligned text within its half
            Button {
                HapticService.selection()
                selectedTab = .myDrinks
                showMoreMenuFor = nil
            } label: {
                HStack {
                    Text(FavouritesTab.myDrinks.title)
                        .font(.system(size: 14, weight: .bold))
                        // Same adaptive treatment as the Barsys Recipes
                        // tab label above — exact pure black in light
                        // (bit-identical), near-white in dark.
                        .foregroundStyle(selectedTab == .myDrinks
                                         ? Color(UIColor { trait in
                                             trait.userInterfaceStyle == .dark
                                                 ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                                                 : UIColor.black // EXACT historical
                                         })
                                         : Color.gray)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 30)      // titleEdgeInsets minX=30
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(FavouritesTab.myDrinks.title)
            .accessibilityHint("Switch to My Drinks tab")
            .accessibilityAddTraits(selectedTab == .myDrinks ? [.isSelected] : [])
        }
        .frame(height: 30)
        .padding(.horizontal, 24)           // storyboard outer HStack x=24
        .padding(.top, 10)
        .background(Color("primaryBackgroundColor"))
    }

    // MARK: - List / empty state

    @ViewBuilder
    private var content: some View {
        // Inner `ScrollView` was removed (the outer body-level
        // ScrollView now scrolls everything) — see body comment for
        // the iOS 26 right-pill rationale.
        //
        // Loading / empty states keep the ORIGINAL centred-in-viewport
        // appearance by sizing the wrapper VStack to a viewport-sized
        // minimum height (`UIScreen.main.bounds.height - 200` ≈
        // available area after status bar + nav bar + tabs bar +
        // search bar + tab bar). Inside that fixed height, the leading
        // + trailing `Spacer()`s centre the indicator / "No results"
        // text exactly as the previous `.frame(maxHeight: .infinity)`
        // VStack layout did — so this is purely structural plumbing
        // to satisfy iOS 26's nav-bar auto-glass requirement that the
        // outer container be a ScrollView, with zero visual change to
        // the loading / empty states.
        if isLoadingMyDrinks && selectedTab == .myDrinks && !myDrinksInitialLoadDone {
            VStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
        } else if rows.isEmpty {
            VStack {
                Spacer()
                Text(Constants.noResultsToDisplayForFavourates)
                    .font(.system(size: 17))
                    // Trait-resolved at draw time so the light value
                    // is the EXACT historical `Color.primary` (pure
                    // black on iOS, bit-identical to the previous
                    // pixels), and the dark variant is the same
                    // softer near-white tone (#E5E5EA) that the rest
                    // of the app's body text (`appBlackColor`) uses
                    // in dark mode — keeps the "no favourites yet"
                    // copy visually consistent with every other label
                    // on the screen instead of stark pure white.
                    .foregroundStyle(Color(UIColor { trait in
                        trait.userInterfaceStyle == .dark
                            ? UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1.0) // #E5E5EA
                            : UIColor.label // EXACT historical `Color.primary` (pure black in light)
                    }))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No results message")
        } else {
            let cellWidth = UIScreen.main.bounds.width - 48
            let rowHeight = cellWidth / 2

            LazyVStack(spacing: 0) {
                ForEach(rows) { recipe in
                    BarsysRecipeRow(
                        recipe: recipe,
                        cellHeight: rowHeight,
                        tab: selectedTab,
                        isMoreMenuOpen: showMoreMenuFor == recipe.id,
                        onTap: {
                            showMoreMenuFor = nil
                            router.push(.recipeDetail(recipe.id))
                        },
                        onFavourite: { toggleFavourite(recipe) },
                        onMore: {
                            showMoreMenuFor =
                                showMoreMenuFor == recipe.id ? nil : recipe.id
                        },
                        onEdit: {
                            showMoreMenuFor = nil
                            recipeToEdit = recipe
                        },
                        onDelete: {
                            showMoreMenuFor = nil
                            confirmDelete(recipe)
                        }
                    )
                    // Pagination trigger — 1:1 port of UIKit
                    // scrollViewDidEndDecelerating → shouldLoadMore.
                    // When the last visible row appears, load more
                    // if pagination has more pages available.
                    .onAppear {
                        if selectedTab == .myDrinks,
                           recipe.id == rows.last?.id,
                           canLoadMoreMyDrinks,
                           !isLoadingMoreMyDrinks {
                            loadMoreMyDrinks()
                        }
                    }
                }

                // Loading indicator at bottom during pagination
                if selectedTab == .myDrinks && isLoadingMoreMyDrinks {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 16)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 15)
            // Pre-iOS 26 has a solid tab bar + hairline that sits
            // on top of the scrollable content — the previous flat
            // 20pt bottom meant the last recipe row was visually
            // grazing the tab bar. iOS 26+ glass tab bar blurs over
            // content so a smaller 12pt inset is enough. Mirrors
            // the `bottomBarBottomInset` pattern used by MyBar /
            // HomeView so all tab-root screens have consistent
            // breathing room above the tab bar.
            .padding(.bottom, favouritesBottomInset)
            .accessibilityLabel("Favourites list")
        }
    }

    /// Bottom breathing room above the tab bar. iOS 26+ has a glass
    /// tab bar that blurs over content (12pt is enough); pre-iOS 26's
    /// opaque tab bar needs ~37pt so the last list row doesn't sit on
    /// the hairline. Mirrors `MyBarView.bottomBarBottomInset` so every
    /// tab-root screen uses the same scale.
    private var favouritesBottomInset: CGFloat {
        if #available(iOS 26.0, *) { 12 } else { 37 }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading: custom 15×15 `back` chevron — same styling used on
        // MyProfile / Preferences / PairYourDevice / Cocktail Kits /
        // ExploreRecipes / Crafting.
        ToolbarItem(placement: .topBarLeading) {
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
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Back")
        }

        // UIKit parity — icon only, 25×25, name label hidden
        // (FavouritesRecipesAndDrinksViewController.swift:207 sets
        // `lblDeviceName.isHidden = true` in `setupView()` and never
        // reverses it).
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                DevicePrincipalIcon(assetName: deviceIconName,
                                    accessibilityLabel: "Connected device, \(deviceKindName)")
            }
        }
        // Single profile button — 1:1 port of UIKit
        // `FavouritesRecipesAndDrinksViewController` (storyboard
        // `yH3-J7-7bh`, L16-305): the top bar has a back chevron on
        // the left and ONLY the profile button on the right. UIKit's
        // `btnSideMenu.addGlassEffectToUIButton(cornerRadius: height/2)`
        // produces a circular Liquid Glass chip — the SAME shape the
        // system applies to its native back button. By using a plain
        // `Button` inside `ToolbarItem(.topBarTrailing)` with an
        // icon-only label, iOS 26 renders the trailing item with the
        // same native back-button-style Liquid Glass chip — matching
        // the left-hand back chevron without any custom drawing.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HapticService.light()
                withAnimation(.easeInOut(duration: 0.4)) {
                    router.showSideMenu = true
                }
            } label: {
                // DARK MODE ONLY template-tint so the profile glyph
                // matches the system back chevron's near-white stroke.
                // Light mode keeps the raw PNG unchanged (no
                // `.renderingMode`, no `.foregroundStyle`) so light-
                // mode pixels stay bit-identical to the existing
                // UIKit-parity design.
                if colorScheme == .dark {
                    Image("profileIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Theme.Color.softWhiteText)
                } else {
                    Image("profileIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
            }
            .accessibilityLabel("Side menu")
        }
    }

    // MARK: - Actions

    /// Ports `FavouritesRecipesAndDrinksViewModel.performLikeUnlike(at:)` +
    /// `applyLikeResult(at:isLike:)`.
    ///
    /// UIKit behavior per tab (L331-376):
    ///   **Tab 0 (Barsys Recipes)**: `isLike` is ALWAYS `false` — tapping
    ///     the heart on a favourited recipe ONLY unlikes it (you can't
    ///     re-like from the favourites list). After unlike, DB is updated
    ///     (`updateFavouriteStatus(isFavourite: false)`) and the favourites
    ///     list is re-fetched from API so the row disappears.
    ///
    ///   **Tab 1 (My Drinks)**: `isLike` TOGGLES the `isMyDrinkFavourite`
    ///     flag. Only the in-memory response model is updated — NO DB
    ///     write (unlike Tab 0).
    /// 1:1 port of UIKit `favouriteAction(_ sender:)`
    /// (FavouritesRecipesAndDrinksViewController+TableView.swift L55-108)
    /// chained with `viewModel.performLikeUnlike` +
    /// `viewModel.applyLikeResult` + `getMyFavouritesDataToShow(indexToLike:)`.
    ///
    /// UIKit sequence:
    ///   1. Haptic .light(); disable user interaction.
    ///   2. Check connectivity → show offline alert if needed.
    ///   3. Call API likeUnlikeApi (Tab 0 always isLike=false; Tab 1 toggles).
    ///   4. On API success → showDefaultAlert(message: ..., okTitle: "OK")
    ///      → on OK callback:
    ///        a. applyLikeResult — Tab 0: DB update remove from favourites;
    ///                              Tab 1: flip `isMyDrinkFavourite` in-memory.
    ///        b. Tab 0 → getMyFavouritesDataToShow(indexToLike: index) — RE-FETCH
    ///                    the favourites array so the unfavourited row drops out.
    ///        c. Tab 1 → reloadData() (no re-fetch — local toggle suffices).
    ///   5. On API failure → showDefaultAlert("Operation failed").
    ///
    /// **Bug fixed**: previously the storage toggle ran BEFORE the alert
    /// and the row stayed visible because `MockStorageService` is not
    /// observable. Now the toggle runs INSIDE the alert's OK callback
    /// AND `favouritesRefreshTick` is incremented to force `rows` to
    /// re-evaluate — exactly mirroring UIKit's "alert OK → reload"
    /// sequence so the row disappears on the same gesture as in UIKit.
    private func toggleFavourite(_ recipe: Recipe) {
        HapticService.light()

        if selectedTab == .barsysRecipes {
            // ── Tab 0: UNLIKE (UIKit L342: isLike = false) ──
            // Fire the API request first, then defer the local mutation
            // until the user dismisses the success alert. Optimistic
            // local removal is intentionally avoided so the user sees
            // the row disappear AS THEY DISMISS the alert (matches UIKit
            // exactly, where the row stays visible during the OK alert
            // and only drops out when getMyFavouritesDataToShow runs).
            Task { @MainActor in
                do {
                    _ = try await env.api.likeUnlike(recipeId: recipe.id.value, isLike: false)
                    env.analytics.track(TrackEventName.favouriteRecipeRemoved.rawValue)
                    // UIKit: showDefaultAlert(message: responseMessage,
                    //                         okTitle: "OK") { okAction in ... }
                    env.alerts.show(message: Constants.unlikeSuccessMessage) {
                        // applyLikeResult (UIKit L370-372 Tab 0):
                        //   storage.updateFavouriteStatus(forRecipeId: recipeId, isFavourite: false)
                        // Use explicit `setFavorite(id, false)` instead of
                        // `toggleFavorite` — Tab 0 always unfavourites, so
                        // we should commit the EXACT direction. `toggle`
                        // would re-add the favourite if storage somehow
                        // already had it removed (e.g. an earlier preload
                        // raced ahead).
                        env.storage.setFavorite(recipe.id, isFavorite: false)
                        // getMyFavouritesDataToShow(indexToLike: index)
                        //   — re-fetch the favourites listing so the
                        //   removed row drops out. SwiftUI parity:
                        //   bump the refresh tick to force `rows` to
                        //   re-evaluate against the now-updated storage.
                        favouritesRefreshTick &+= 1
                    }
                } catch {
                    // UIKit failure path — generic error alert.
                    env.alerts.show(message: Constants.recipeFavouriteError)
                }
            }
        } else {
            // ── Tab 1: TOGGLE isMyDrinkFavourite (UIKit L344-352) ──
            let willBeFav: Bool
            if let idx = myDrinksLoaded.firstIndex(where: { $0.id == recipe.id }) {
                willBeFav = !(myDrinksLoaded[idx].isMyDrinkFavourite ?? false)
            } else {
                willBeFav = true
            }
            Task { @MainActor in
                do {
                    _ = try await env.api.likeUnlike(recipeId: recipe.id.value, isLike: willBeFav)
                    env.analytics.track(
                        (willBeFav ? TrackEventName.favouriteRecipeAdded
                                   : TrackEventName.favouriteRecipeRemoved).rawValue
                    )
                    env.alerts.show(message: willBeFav
                                    ? Constants.likeSuccessMessage
                                    : Constants.unlikeSuccessMessage) {
                        // applyLikeResult (UIKit L373-374 Tab 1):
                        //   myDrinksResponseModel.data[index].isMyDrinkFavourite = isLike
                        //   (in-memory only, no DB write)
                        if let idx = myDrinksLoaded.firstIndex(where: { $0.id == recipe.id }) {
                            myDrinksLoaded[idx].isMyDrinkFavourite = willBeFav
                            myDrinksLoaded[idx].isFavourite = willBeFav
                        }
                        if var model = myDrinksResponseModel {
                            if let idx = model.data?.firstIndex(where: { $0.id == recipe.id }) {
                                model.data?[idx].isMyDrinkFavourite = willBeFav
                                myDrinksResponseModel = model
                            }
                        }
                        // UIKit Tab 1: tblFavouritesRecipesAndDrinks.reloadData()
                        // — local @State writes already trigger SwiftUI re-render.
                    }
                } catch {
                    env.alerts.show(message: Constants.recipeFavouriteError)
                }
            }
        }
    }

    /// Ports `deleteRecipe(at:)` confirmation flow.
    /// UIKit (FavouritesRecipesAndDrinksViewController+TableView.swift L145-162):
    ///   1. Two-button confirmation ("Yes" / "No")
    ///   2. On "Yes" → deleteReceipe API → DBManager.deleteRecipe(byId:)
    ///   3. On success → success alert (Constants.recipeDeleteMessage)
    ///   4. On success alert dismiss (onComplete) →
    ///        resetMyDrinksForRefresh() + getMyDrinksApi(isInitialDataLoading:true)
    ///        + tblFavouritesRecipesAndDrinks.reloadData()
    ///
    /// UIKit `DBManager._deleteRecipe(byId:)` does:
    ///   DELETE FROM mixlistrecipes WHERE recipeId = ?;
    ///   DELETE FROM recipes WHERE id = ?;  -- cascades to ingredients
    /// Our `env.storage.delete(recipe:)` mirrors this: removes from recipes
    /// dict, favs set, and mixlist→recipe references.
    private func confirmDelete(_ recipe: Recipe) {
        env.alerts.show(
            title: Constants.doYouWantToDeleteRecipe,
            message: "",
            primaryTitle: ConstantButtonsTitle.yesButtonTitle,
            secondaryTitle: ConstantButtonsTitle.noButtonTitle,
            onPrimary: {
                Task { @MainActor in
                    do {
                        // 1. API DELETE — UIKit: FavoriteRecipeApiService.deleteReceipe()
                        try await env.api.deleteMyDrink(recipeId: recipe.id.value)

                        // 2. Local DB delete — UIKit: DBManager.shared.deleteRecipe(byId:)
                        //    Removes from recipes dict, favs set, and mixlist references.
                        env.storage.delete(recipe: recipe.id)
                        // Also remove from persistent cache (cocktails_recipes)
                        MyDrinksCache.remove(recipeId: recipe.id)

                        // 3. Immediately remove from @State arrays so the UI
                        //    updates BEFORE the success alert is shown. Without
                        //    this the row stays visible behind the alert overlay.
                        myDrinksLoaded.removeAll { $0.id == recipe.id }
                        if var model = myDrinksResponseModel {
                            model.data?.removeAll { $0.id == recipe.id }
                            if let total = model.total { model.total = total - 1 }
                            myDrinksResponseModel = model
                        }
                        // Persist the trimmed list to disk now that local
                        // state is correct — survives a cold launch even
                        // if the user closes the app before any background
                        // re-sync runs.
                        MyDrinksCache.save(myDrinksLoaded)

                        // 4. Success alert — DON'T re-fetch on dismiss.
                        // UIKit's `resetMyDrinksForRefresh + getMyDrinksApi
                        // + reloadData` chain was an imperative-table-view
                        // workaround; in SwiftUI the @State arrays already
                        // drive the UI and were updated atomically in step
                        // 3, so a full reset (`myDrinksLoaded = []` →
                        // refetch) just causes a visible empty-state flash
                        // and a re-render fluctuation. Local state is
                        // authoritative; the server already accepted the
                        // delete in step 1, so a re-fetch can only return
                        // the same trimmed list.
                        env.alerts.show(message: Constants.recipeDeleteMessage)
                    } catch {
                        env.alerts.show(message: Constants.recipeSaveError)
                    }
                }
            }
        )
    }

    /// 1:1 port of UIKit `FavouritesRecipesAndDrinksViewModel.resetMyDrinksForRefresh()`
    /// (L193-196) followed by `getMyDrinksApi(isInitialDataLoading: true)`.
    /// Clears cached response model + pagination state, then re-fetches the
    /// full My Drinks list from the API so the list rebuilds with fresh
    /// server data (matching UIKit's `tblFavouritesRecipesAndDrinks.reloadData()`).
    private func resetMyDrinksForRefresh() {
        myDrinksResponseModel = nil
        myDrinksLoaded = []
        myDrinksInitialLoadDone = false
        isLoadingMyDrinks = false   // ensure guard in loadMyDrinksInitially passes
        loadMyDrinksInitially()
    }

    // MARK: - My Drinks API (1:1 port of UIKit getMyDrinksApi)

    /// Initial load or full refresh of My Drinks from API.
    /// UIKit: `getMyDrinksApi(isInitialDataLoading: true)` →
    /// `viewModel.fetchMyDrinks(offset: 0)` → reloadTableForMyDrinks
    ///
    /// Persistence layer (ports UIKit's cocktails_recipes DB infra):
    ///   • On success → save to MyDrinksCache (INSERT OR REPLACE)
    ///   • On failure → load from MyDrinksCache (SELECT * FROM cocktails_recipes)
    ///   • This ensures My Drinks survive app restarts even if the API
    ///     is unreachable on next launch.
    private func loadMyDrinksInitially() {
        guard !isLoadingMyDrinks else { return }
        isLoadingMyDrinks = true

        // Show cached data immediately while API loads (like UIKit shows
        // DB data while network request is in-flight).
        let cached = MyDrinksCache.load()
        if !cached.isEmpty && myDrinksLoaded.isEmpty {
            myDrinksLoaded = cached
            // Also upsert cached recipes into in-memory storage so other
            // screens (RecipeDetail, etc.) can find them by ID.
            for recipe in cached {
                env.storage.upsert(recipe: recipe)
            }
        }

        Task {
            do {
                let response = try await env.api.fetchMyDrinks(
                    offset: 0,
                    isBarsys360Connected: ble.isBarsys360Connected()
                )
                myDrinksResponseModel = response
                myDrinksLoaded = response.data ?? []
                // Upsert into in-memory storage so other screens see them
                for recipe in myDrinksLoaded {
                    env.storage.upsert(recipe: recipe)
                }
                // Persist to disk (ports _insertMyDrinksData)
                MyDrinksCache.save(myDrinksLoaded)
                myDrinksInitialLoadDone = true
            } catch {
                // Fallback: use persisted cache (ports _fetchDataForMyDrinks)
                if myDrinksLoaded.isEmpty {
                    let cached = MyDrinksCache.load()
                    myDrinksLoaded = cached
                    for recipe in cached {
                        env.storage.upsert(recipe: recipe)
                    }
                }
                myDrinksInitialLoadDone = true
            }
            isLoadingMyDrinks = false
        }
    }

    /// Pagination — loads next page of My Drinks.
    /// UIKit: scrollViewDidEndDecelerating → shouldLoadMore →
    /// getMyDrinksApi(offset: currentCount) → append to data array.
    private func loadMoreMyDrinks() {
        guard !isLoadingMoreMyDrinks, canLoadMoreMyDrinks else { return }
        isLoadingMoreMyDrinks = true
        let currentCount = myDrinksResponseModel?.data?.count ?? 0
        Task {
            do {
                let response = try await env.api.fetchMyDrinks(
                    offset: currentCount,
                    isBarsys360Connected: ble.isBarsys360Connected()
                )
                // Append new data (1:1 with UIKit pagination concatenation)
                if let newData = response.data {
                    myDrinksLoaded.append(contentsOf: newData)
                    if var model = myDrinksResponseModel {
                        model.data?.append(contentsOf: newData)
                        model.offset = response.offset
                        model.limit = response.limit
                        myDrinksResponseModel = model
                    }
                    for recipe in newData {
                        env.storage.upsert(recipe: recipe)
                    }
                    // Update persistent cache with full list
                    MyDrinksCache.save(myDrinksLoaded)
                }
            } catch {
                // Silently fail pagination — user can scroll again
            }
            isLoadingMoreMyDrinks = false
        }
    }

    /// Pull-to-refresh handler.
    /// UIKit: refresh(_ sender:) → selectedTabIndex == 1 ? refreshMyDrinks : getMyFavouritesDataToShow
    private func refresh() async {
        if selectedTab == .myDrinks {
            // Reset and reload My Drinks from API
            myDrinksResponseModel = nil
            myDrinksLoaded = []
            myDrinksInitialLoadDone = false
            loadMyDrinksInitially()
            // Wait for the load to complete
            while isLoadingMyDrinks {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        } else {
            // Barsys Recipes: refresh favourites from local DB
            // (in production this would call getFavouritesListApi)
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}

// MARK: - BarsysRecipeRow (1:1 port of BarsysRecipeTableViewCell.xib)

struct BarsysRecipeRow: View {
    let recipe: Recipe
    let cellHeight: CGFloat
    let tab: FavouritesTab
    let isMoreMenuOpen: Bool
    let onTap: () -> Void
    let onFavourite: () -> Void
    let onMore: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Drives dark-mode template-tinting of the Edit/Trash glyphs in
    /// the more-menu popup so they stay legible against the dark
    /// `systemBackground` / `.ultraThinMaterial` popup surface.
    /// Light mode keeps the original PNG (bit-identical UIKit-parity).
    @Environment(\.colorScheme) private var colorScheme

    private var optimizedImageURL: URL? {
        // Match UIKit `BarsysRecipeTableViewCell` exactly:
        //   imgStr = data.image?.url
        //   imgUrl = imgStr?.getImageUrl()
        //   sd_setImage(with: imgUrl, …)
        // The helper percent-encodes the inner `fileUrl=…` query
        // value of optimizeImage URLs; without it the row falls
        // through to the `myDrink` placeholder.
        guard let raw = recipe.image?.url, !raw.isEmpty else { return nil }
        return raw.getImageUrl()
    }

    private var isFavourite: Bool { recipe.isFavourite ?? false }

    /// UIKit BarsysRecipeTableViewCell L63-77: iOS 26 uses 40×40 glass buttons
    /// with black@0.3 tint; pre-26 uses 30×30 plain buttons with white tint.
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

    /// On iPad + pre-iOS-26, SwiftUI's hit-test routing swallows nested
    /// `Button` taps inside an outer `Button` — the row's own `onTap`
    /// absorbed every press on the overlay Favourite / More icon. The
    /// outer Button is replaced by a `.contentShape + .onTapGesture`
    /// wrapper ONLY on that platform combination, which lets the inner
    /// Buttons receive their taps directly. iPhone (any iOS) and iPad
    /// iOS 26+ keep the original outer Button layout bit-identical.
    private var isIPadPre26: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        if #available(iOS 26.0, *) { return false } else { return true }
    }

    var body: some View {
        if isIPadPre26 {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
                .accessibilityAddTraits(.isButton)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(recipe.displayName), \(isFavourite ? "favourited" : "not favourited")"
                )
                .accessibilityHint("Double tap to view recipe details")
        } else {
            Button(action: onTap) { rowContent }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(recipe.displayName), \(isFavourite ? "favourited" : "not favourited")"
                )
                .accessibilityHint("Double tap to view recipe details")
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 0) {
                // Left half — title + ingredients
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
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Right half — square image with favourite + more overlays.
                //
                // 1:1 port of UIKit `BarsysRecipeTableViewCell.xib`
                // (BarsysApp/Controllers/Favourites/BarsysRecipeTableViewCell.xib):
                //
                //   • drinkThumbImage `byK-qQ-ugc` — 50% of card width,
                //     pinned trailing/top/bottom (constraints `JMo-d6-A5O`,
                //     `csz-Rp-gF7`, `jzg-xz-a3q`, width = card.width × 0.5
                //     via `VKZ-2m-DkK`).
                //   • favouriteButton `aHb-2f-Xkm` — 30×30 at TOP-RIGHT,
                //     top=5pt (`8Rd-hA-Zko`), trailing=5pt (`BRq-QH-nkH`).
                //   • moreButton `dZv-df-fwc` — 30×30 at BOTTOM-RIGHT,
                //     bottom=5pt (`jOe-iK-8I2`), trailing=5pt (`aMH-N5-tLB`).
                //
                // The UIKit buttons sit at OPPOSITE CORNERS of the card
                // (favourite top-right, more bottom-right) — NOT stacked
                // together. The previous SwiftUI port used a single
                // `VStack` which placed the more icon DIRECTLY BELOW the
                // favourite button (only 15pt apart) — visually wrong vs.
                // UIKit. Now `.overlay(alignment:)` pins each button to
                // its own corner so the visual matches the storyboard.
                //
                // UIKit BarsysRecipeTableViewCell.configure() L63-77:
                // iOS 26: 40×40 glass buttons, tint black@0.3
                // Pre-26: 30×30 plain buttons, tint white
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
                // Favourite button — TOP-RIGHT corner of the image
                // (UIKit `aHb-2f-Xkm` constraints: top=5, trailing=5).
                .overlay(alignment: .topTrailing) {
                    Button {
                        onFavourite()
                    } label: {
                        Image(isFavourite ? "favIconRecipeSelected" : "favIconRecipe")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .frame(width: favButtonSize, height: favButtonSize)
                            .foregroundStyle(favButtonTint)
                    }
                    .glassButtonIfAvailable(size: favButtonSize)
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel(isFavourite
                                        ? "Remove from favourites"
                                        : "Add to favourites")
                    .padding(.top, 5)
                    .padding(.trailing, 5)
                }
                // More (info) button — BOTTOM-RIGHT corner of the image,
                // visible only on the My Drinks tab (UIKit
                // `dZv-df-fwc` constraints: bottom=5, trailing=5;
                // visibility gated by `data.isMoreButtonHidden` which is
                // false only for My Drinks rows).
                .overlay(alignment: .bottomTrailing) {
                    if tab == .myDrinks {
                        Button {
                            onMore()
                        } label: {
                            Image("more")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .frame(width: favButtonSize, height: favButtonSize)
                                .foregroundStyle(favButtonTint)
                        }
                        .glassButtonIfAvailable(size: favButtonSize)
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityLabel("More options for \(recipe.displayName)")
                        .padding(.bottom, 5)
                        .padding(.trailing, 5)
                    }
                }
                // Edit / Delete popup — UIKit `3gv-w4-LyK` (moreView)
                // anchored bottom=10pt, trailing=8pt of the card. Now
                // hangs from the moreButton (which lives at the same
                // bottom-right corner).
                .overlay(alignment: .bottomTrailing) {
                    if tab == .myDrinks && isMoreMenuOpen {
                        morePopup
                            .padding(.bottom, 10)
                            .padding(.trailing, 8)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: cellHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial.opacity(0.7))
            )
            // UIKit addGlassEffect border: white@0.15, 0.5pt width
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 12)
    }

    // 92×76 popup with Edit (92×38) + Delete (92×38).
    //
    // 1:1 with UIKit `BarsysRecipeTableViewCell.xib` `moreView` (id `3gv-w4-LyK`):
    //   • Outer view  : 92×76, `roundCorners = 8` (BarsysCornerRadius.small).
    //   • Vertical stackView (`PCD-Gr-eJU`): fillEqually → two 92×38 cells.
    //   • Edit cell `LMv-Za-JFL`:
    //       - title "Edit", image "edit", font system 12pt, title color
    //         `appBlackColor`.
    //       - contentHorizontalAlignment: leading.
    //       - contentEdgeInsets: minX=16, minY=8, maxX=0, maxY=0 →
    //         16pt leading + 8pt top inset (top button gets extra top
    //         breathing room).
    //       - titleEdgeInsets: minX=8 → 8pt gap between image and title.
    //   • Delete cell `DC3-xs-NMc`:
    //       - title "Delete", image "trash", font/colour identical.
    //       - contentEdgeInsets: minX=16, minY=0, maxX=0, maxY=8 →
    //         16pt leading + 8pt bottom inset (bottom button gets extra
    //         bottom breathing room).
    //
    // The previous SwiftUI port centered the HStack inside each 92×38
    // cell with a 6pt spacing — that visually pushed the Edit/Delete
    // labels toward the middle of the popup and used the wrong gap
    // between icon and title. The corrected version uses leading
    // alignment + 16pt leading inset + asymmetric top/bottom 8pt insets
    // (Edit pinned to top, Delete pinned to bottom) so the two rows
    // sit at the corners of the popup like the storyboard, with the
    // 8pt icon→title gap matching `titleEdgeInsets`.
    private var morePopup: some View {
        VStack(spacing: 0) {
            Button(action: onEdit) {
                HStack(spacing: 8) {
                    morePopupGlyph(name: "edit")
                    Text("Edit")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("appBlackColor"))
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 0))
                .frame(width: 92, height: 38, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Edit recipe")

            Button(action: onDelete) {
                HStack(spacing: 8) {
                    morePopupGlyph(name: "trash")
                    Text("Delete")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("appBlackColor"))
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 0))
                .frame(width: 92, height: 38, alignment: .bottomLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Delete recipe")
        }
        .frame(width: 92, height: 76)
        .background(morePopupBackground)
        .overlay(morePopupBorder)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    /// 16×16 glyph for the Edit / Trash rows in the more-menu popup.
    /// Light mode keeps the original PNG (bit-identical UIKit-parity).
    /// Dark mode template-tints with `appBlackColor` (which resolves to
    /// near-white #E5E5EA in dark) so the dark glyph isn't invisible
    /// against the dark popup surface.
    @ViewBuilder
    private func morePopupGlyph(name: String) -> some View {
        if colorScheme == .dark {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color("appBlackColor"))
                .frame(width: 16, height: 16)
        } else {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        }
    }

    /// UIKit BarsysRecipeTableViewCell L75-79:
    /// iOS 26: moreView.backgroundColor = .clear + addGlassEffect(cornerRadius: 8, effect: "clear")
    /// Pre-26: moreView.backgroundColor = .systemBackground
    /// `.ultraThinMaterial` is the SwiftUI equivalent of UIGlassEffect(style: .clear)
    @ViewBuilder
    private var morePopupBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.systemBackground))
        }
    }

    @ViewBuilder
    private var morePopupBorder: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Glass button modifier for iOS 26+ (ports .prominentGlass() config)

extension View {
    /// On iOS 26+, wraps the view in a glass-effect background circle
    /// (ports UIKit `.prominentGlass()` button configuration).
    /// Pre-26: no-op (buttons remain flat on the image).
    @ViewBuilder
    func glassButtonIfAvailable(size: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
            )
        } else {
            self
        }
    }
}

/// Applies `.presentationBackground(.clear)` on iOS 16.4+ and is a
/// no-op on earlier versions. Needed because the modifier itself is
/// only available from iOS 16.4 (ErrorFix for build error).
/// Shared between `FavoritesView` and `RecipePage` — both present
/// `EditRecipeView` as a `.fullScreenCover` and need the cover's
/// backdrop to be transparent so the panel's glass composites
/// against the parent VC.
struct ClearPresentationBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }
}
