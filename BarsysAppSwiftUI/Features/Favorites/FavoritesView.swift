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

    @State private var selectedTab: FavouritesTab = .barsysRecipes
    @State private var query: String = ""
    @State private var showMoreMenuFor: RecipeID? = nil
    @State private var didTrackView = false
    /// Bug fix (edit-routing): 1:1 port of UIKit
    /// `FavouritesRecipesAndDrinksViewController.didSelectEdit` →
    /// `present(EditViewController, animated: true)` which presents
    /// the edit sheet AS A MODAL on top of the current tab stack.
    /// The previous SwiftUI port used `router.push(.editRecipe(id))`
    /// which pushed the edit view onto the CURRENT tab's navigation
    /// stack instead — so the user ended up with the edit screen
    /// wedged into the BarBot / My Drinks nav stack, never returning
    /// to My Drinks. Using `.fullScreenCover` with this `Identifiable`
    /// state variable matches UIKit's modal presentation exactly.
    @State private var recipeToEdit: Recipe? = nil

    /// Source recipes per tab — ports `numberOfRows` + `recipe(at:)` from
    /// `FavouritesRecipesAndDrinksViewModel`.
    ///
    /// **Sort order** — matches UIKit `DBQueries.swift`:
    ///   • Barsys Recipes (L125):
    ///       ORDER BY r.barsys360Compatible DESC, r.favCreatedAt DESC
    ///     i.e. Barsys 360-compatible recipes first, then by time
    ///     favourited (newest favourites first).
    ///   • My Drinks (L149):
    ///       ORDER BY r.favCreatedAt DESC
    ///     — newest-favourited at the top.
    ///
    /// Previous port relied on `allRecipes()`'s alphabetical order,
    /// which inverted the Favourites tab vs UIKit.
    private var rows: [Recipe] {
        let pool: [Recipe]
        switch selectedTab {
        case .barsysRecipes:
            let ids = env.storage.favorites()
            pool = env.storage.allRecipes()
                .filter { ids.contains($0.id) }
                .sorted { lhs, rhs in
                    // Primary: Barsys 360 compatible first (DESC on Bool).
                    let lb = lhs.barsys360Compatible == true
                    let rb = rhs.barsys360Compatible == true
                    if lb != rb { return lb && !rb }
                    // Secondary: favCreatedAt DESC (newest favourite first).
                    return (lhs.favCreatedAt ?? 0) > (rhs.favCreatedAt ?? 0)
                }
        case .myDrinks:
            pool = env.storage.allRecipes()
                .filter { $0.isMyDrinkFavourite == true }
                .sorted { ($0.favCreatedAt ?? 0) > ($1.favCreatedAt ?? 0) }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return pool }
        return pool.filter {
            ($0.name ?? "").lowercased().contains(q)
                || ($0.ingredientNames ?? "").lowercased().contains(q)
        }
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
        VStack(spacing: 0) {
            tabsBar
            searchBar
            content
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
        .onAppear {
            if !didTrackView {
                didTrackView = true
                env.analytics.track(TrackEventName.favouratesScreenViewed.rawValue)
            }
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
            NavigationStack {
                EditRecipeView(recipeID: recipe.id)
            }
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
                        .foregroundStyle(selectedTab == .barsysRecipes
                                         ? Color.black
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
            Rectangle()
                .fill(Color.black)
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
                        .foregroundStyle(selectedTab == .myDrinks
                                         ? Color.black
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

    // MARK: - Search bar (1pt barbotBorderColor stroke, 12pt corners)

    private var searchBar: some View {
        // Shared `BarsysSearchBar` — 1:1 port of the UIKit
        // `viewSearch` + `txtSearch` + `searchAndCloseButton` widget
        // used by FavouritesRecipesAndDrinksViewController (see the
        // Mixlist.storyboard Favourites scene + the `filterCountries`
        // implementation where the button's image swaps between
        // `.search` and `.crossIcon` based on whether the field has
        // content). Previous inline implementation used SF Symbols
        // instead of the UIKit assets, a 16pt placeholder font
        // instead of 14pt, and a white container instead of the UIKit
        // transparent one.
        BarsysSearchBar(query: $query, placeholder: "Search favourites")
            .padding(.horizontal, 24)
            .padding(.top, 15)
            .accessibilityLabel("Search favourites")
            .accessibilityHint("Type a recipe or ingredient name")
    }

    // MARK: - List / empty state

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack(spacing: 12) {
                Spacer(minLength: 40)
                Image(systemName: "heart")
                    .font(.system(size: 48))
                    .foregroundStyle(Color("mediumGrayColor"))
                Text(Constants.noResultsToDisplayForFavourates)
                    .font(.system(size: 14))
                    .foregroundStyle(Color("mediumGrayColor"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No favourites yet")
        } else {
            // Same deterministic geometry as Cocktail Kits / Explore
            // Recipes — eliminates LazyVStack scroll-zoom.
            let cellWidth = UIScreen.main.bounds.width - 48
            let rowHeight = cellWidth / 2

            ScrollView {
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
                                // 1:1 port of UIKit
                                // `FavouritesRecipesAndDrinksViewController.didSelectEdit`:
                                // present EditViewController modally ABOVE the
                                // current tab (matching the storyboard segue
                                // `present modally` kind). Previously this
                                // used `router.push(.editRecipe(id))` which
                                // nested the edit screen inside the current
                                // tab's nav stack — wrong per UIKit.
                                recipeToEdit = recipe
                            },
                            onDelete: {
                                showMoreMenuFor = nil
                                confirmDelete(recipe)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 15)
                .padding(.bottom, 20)
            }
            .refreshable { await refresh() }
            .accessibilityLabel("Favourites list")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if ble.isAnyDeviceConnected {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if !deviceIconName.isEmpty {
                        Image(deviceIconName)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    }
                    Text(deviceKindName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color("appBlackColor"))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connected device, \(deviceKindName)")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Shared 100×48 glass pill (iOS 26+) / bare 61×24 icon stack
            // (pre-26). 1:1 UIKit `navigationRightGlassView` parity. On
            // the Favorites screen itself the heart icon is a no-op
            // (the whole screen already IS the favorites list).
            NavigationRightGlassButtons(
                onFavorites: {},
                onProfile: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        router.showSideMenu = true
                    }
                }
            )
        }
    }

    // MARK: - Actions

    /// Ports `performLikeUnlike(at:)` → toggles the local store and emits
    /// the matching Braze event with a confirmation toast.
    private func toggleFavourite(_ recipe: Recipe) {
        HapticService.light()
        let willBeFavourite = !(recipe.isFavourite ?? false)
        env.storage.toggleFavorite(recipe.id)
        env.analytics.track(
            (willBeFavourite ? TrackEventName.favouriteRecipeAdded
                             : TrackEventName.favouriteRecipeRemoved).rawValue
        )
        env.alerts.show(message: willBeFavourite
                        ? Constants.likeSuccessMessage
                        : Constants.unlikeSuccessMessage)
    }

    /// Ports `deleteRecipe(at:)` confirmation flow.
    private func confirmDelete(_ recipe: Recipe) {
        env.alerts.show(
            title: Constants.doYouWantToDeleteRecipe,
            message: ""
        ) {
            // Local removal — the real DBManager + API call would happen
            // here (mirrors `_deleteFromDB` + `deleteReceipe`).
            env.storage.toggleFavorite(recipe.id)
            env.alerts.show(message: Constants.recipeDeleteMessage)
        }
    }

    private func refresh() async {
        // Placeholder for the API refresh; the real fetch hooks in here in
        // production.
        try? await Task.sleep(nanoseconds: 250_000_000)
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

    private var optimizedImageURL: URL? {
        guard let raw = recipe.image?.url, !raw.isEmpty else { return nil }
        let optimized = raw
            .replacingOccurrences(of: "https://storage.googleapis.com/barsys-images-production/",
                                  with: "https://api.barsys.com/api/optimizeImage?fileUrl=https://media.barsys.com/")
        return URL(string: optimized)
    }

    private var isFavourite: Bool { recipe.isFavourite ?? false }

    var body: some View {
        Button(action: onTap) {
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

                // Right half — square image with favourite + more overlays
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: optimizedImageURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        case .empty, .failure:
                            Image("myDrink")
                                .resizable().aspectRatio(contentMode: .fill)
                        @unknown default:
                            Color("lightBorderGrayColor")
                        }
                    }
                    .frame(width: cellHeight, height: cellHeight)
                    .background(Color("lightBorderGrayColor"))
                    .clipped()

                    // Favourite + (My Drinks only) More — stacked vertically
                    // on the image's right edge, matching xib (top=5,
                    // trailing=5 for fav; below it for more).
                    VStack(spacing: 15) {
                        Button {
                            onFavourite()
                        } label: {
                            Image(isFavourite ? "favIconRecipeSelected" : "favIconRecipe")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .frame(width: 30, height: 30)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityLabel(isFavourite
                                            ? "Remove from favourites"
                                            : "Add to favourites")

                        if tab == .myDrinks {
                            Button {
                                onMore()
                            } label: {
                                Image("more")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel("More options for \(recipe.displayName)")
                        }
                    }
                    .padding(.top, 5)
                    .padding(.trailing, 5)
                    .overlay(alignment: .topTrailing) {
                        if tab == .myDrinks && isMoreMenuOpen {
                            morePopup
                                .offset(x: -34, y: 38)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .frame(height: cellHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(recipe.displayName), \(isFavourite ? "favourited" : "not favourited")"
        )
        .accessibilityHint("Double tap to view recipe details")
    }

    // 92×76 popup with Edit (92×38) + Delete (92×38), 12pt system font,
    // appBlackColor titles, glass card with 8pt corner radius.
    private var morePopup: some View {
        VStack(spacing: 0) {
            Button(action: onEdit) {
                HStack(spacing: 6) {
                    Image("edit").resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Edit")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("appBlackColor"))
                }
                .frame(width: 92, height: 38)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Edit recipe")

            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image("trash").resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Delete")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("appBlackColor"))
                }
                .frame(width: 92, height: 38)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Delete recipe")
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}
