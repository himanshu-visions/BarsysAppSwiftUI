//
//  RecipesScreens.swift
//  BarsysAppSwiftUI
//
//  Full port of ExploreRecipesViewController + RecipePageViewController +
//  MakeMyOwnViewController + EditRecipeViewController.
//
//  ExploreRecipes: table of cached recipes with search, device icon in
//  top bar when connected, favourite toggle, glass-styled cells.
//  Storyboard: Mixlist.storyboard ExploreRecipesViewController scene.
//  Cell: MixlistDetailTableViewCell.xib — left image 47×47 + title 16pt +
//  ingredients 10pt + favourite heart 30×30.

import SwiftUI

// MARK: - Explore Recipes
//
// Full port of ExploreRecipesViewController.
// Layout: "All Recipes" title (24pt), search bar (44pt, 12pt corners),
// table of MixlistDetailTableViewCell rows.
// Device icon shown in top bar when connected, hidden when disconnected.

struct ExploreRecipesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var catalog: CatalogService
    @EnvironmentObject private var ble: BLEService

    @State private var query = ""
    @State private var isSearching = false

    private var isConnected: Bool { ble.isAnyDeviceConnected }

    /// Filtered recipes — ports cacheRecipesSearchResults().
    /// UIKit uses `words.contains` (ANY word matches), not allSatisfy.
    /// Searches recipe name and ingredientNames string.
    private var filtered: [Recipe] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return catalog.recipes
        }
        let words = query.lowercased().split(separator: " ").map(String.init)
        return catalog.recipes.filter { r in
            let name = r.displayName.lowercased()
            let ingredients = (r.ingredientNames ?? "").lowercased()
            return words.contains { word in
                name.contains(word) || ingredients.contains(word)
            }
        }
    }

    // Device info helpers (ports setupView device detection)
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
        VStack(spacing: 0) {
            // Title — "All Recipes" 24pt, appBlackColor, leading 24, top 58
            Text("All Recipes")
                .font(.system(size: 24))
                .foregroundStyle(Color("appBlackColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // Search bar — 1:1 port of UIKit `viewSearch` + `txtSearch` +
            // `searchAndCloseButton` from Mixlist.storyboard scene
            // `Zsc-V0-6RG`. The previous inline implementation drifted
            // from UIKit on several axes (system SF Symbols instead of
            // the `exploreSearch` / `crossIcon` assets, 16pt placeholder
            // font instead of 14pt, white backgroundColor instead of
            // clear, a duplicate "×" button glued to the trailing edge).
            // Factored into the shared `BarsysSearchBar` — same widget
            // used by ExploreRecipes / Cocktail Kits / Favorites so
            // every UIKit search bar is pixel-identical to UIKit.
            BarsysSearchBar(query: $query)
                .padding(.horizontal, 24)
                .padding(.top, 15)

            // Recipe list
            if filtered.isEmpty {
                Spacer()
                Text("No results to display")
                    .font(.system(size: 16))
                    .foregroundStyle(Color("mediumGrayColor"))
                Spacer()
            } else {
                ScrollView {
                    if catalog.isLoading && catalog.recipes.isEmpty {
                        ProgressView("Loading recipes...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    // Same deterministic geometry as Cocktail Kits so all
                    // listings feel identical and never re-measure on scroll.
                    let cellWidth = UIScreen.main.bounds.width - 48
                    let rowHeight = cellWidth / 2
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { recipe in
                            Button {
                                HapticService.light()
                                router.push(.recipeDetail(recipe.id))
                            } label: {
                                RecipeRowCell(
                                    recipe: recipe,
                                    cellHeight: rowHeight,
                                    onFavourite: {
                                        catalog.toggleFavourite(recipeId: recipe.id)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    await catalog.refresh()
                }
            }
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        // Ports ExploreRecipesViewController.viewDidLoad staleness check:
        // if cacheRecipes.isEmpty || AppStateManager.shared.areCacheRecipesStale
        .task {
            await catalog.refreshIfStale()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            // Center: device icon + name (only when connected)
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
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
    }
}

// MARK: - Recipe Row Cell
//
// Ports MixlistDetailTableViewCell.xib:
//   innerView: glass effect, 16pt corners
//   HStack: [image 47×47 1:1 | VStack: title 16pt + ingredients 10pt | heart 30×30]
//   Cell height: ~156pt auto-sized

/// 1:1 port of `MixlistDetailTableViewCell.xib` as used by
/// `ExploreRecipesViewController+TableView`.
///
/// **Critical constraint re-discovery** — the xib's image is NOT 47×47 at
/// runtime (that was IB's design-time snapshot). The actual constraints:
///   • `image.width = innerView.width × 0.5`           (id="VKZ-2m-DkK")
///   • `image.width = image.height`                    (id="2gl-fW-Dgu", 1:1)
///   • image top/trailing/bottom pinned to innerView   (full inner height)
/// → Image is **50% of cell width, square, full inner-card height**, exactly
///   like CocktailsForYouTableViewCell.
///
/// Other measurements (constraints, not snapshot frames):
///   • innerView glass: `addGlassEffect(isBorderEnabled: true,
///     cornerRadius: BarsysCornerRadius.large /* 16 */, alpha: 0.7)`
///     + `roundCorners=16` userDefinedRuntimeAttribute.
///   • drinkLabel:    top=16, leading=16, trailing=image.leading-16
///                    font system 16pt, lines=4 (set programmatically)
///   • drinkInfoLabel: top=drinkLabel.bottom+16, leading=16,
///                     trailing=image.leading-16, bottom=innerView.bottom-15
///                     font system 10pt, lines=0
///   • craftButton: leading=16, trailing=image.leading-16, height=29,
///                  bottom=innerView.bottom-10, title "Craft",
///                  roundCorners=8 — **HIDDEN in ExploreRecipes**.
///   • favouriteButton: 30×30 (40×40 on iOS 26+), top=innerView.top+5,
///                      trailing=innerView.trailing-5. Image is
///                      `favIconRecipe` (off) / `favIconRecipeSelected` (on).
///   • Bottom spacer image: height=12 fixed.
struct RecipeRowCell: View {
    let recipe: Recipe
    /// Deterministic side length of the square image / row height. Passed
    /// from the parent list so every row has identical geometry on first
    /// render — prevents the LazyVStack zoom-pop on scroll.
    let cellHeight: CGFloat
    let onFavourite: () -> Void

    /// Ports `getImageUrl()` URL optimization the UIKit cell pipes through.
    private var optimizedImageURL: URL? {
        guard let raw = recipe.image?.url, !raw.isEmpty else { return nil }
        let optimized = raw
            .replacingOccurrences(of: "https://storage.googleapis.com/barsys-images-production/",
                                  with: "https://api.barsys.com/api/optimizeImage?fileUrl=https://media.barsys.com/")
        return URL(string: optimized)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left half — title + ingredients (Craft button hidden in Explore).
            // Uniform row height: title 3 lines, ingredients 6 lines max.
            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let names = recipe.ingredientNames, !names.isEmpty {
                    Text(names)
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

            // Right half — explicit `cellHeight × cellHeight` square so the
            // row never re-measures on first appearance in LazyVStack.
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: cellHeight, height: cellHeight)
                    .background(Color("lightBorderGrayColor"))
                    .clipped()

                Button {
                    HapticService.light()
                    onFavourite()
                } label: {
                    Image(recipe.isFavourite == true ? "favIconRecipeSelected" : "favIconRecipe")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.001)) // ensures hit area
                }
                .buttonStyle(BounceButtonStyle())
                .padding(.top, 5)
                .padding(.trailing, 5)
                .accessibilityLabel("Favourite")
            }
        }
        // Lock the row to the deterministic height — single change that
        // removes the zoom/pop on scroll.
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
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var thumbnail: some View {
        // UIKit: sd_setImage(with:imgUrl, placeholderImage:.myDrink)
        // Placeholder uses .fit to avoid zooming/stretching a small asset.
        // Loaded image uses .fill to cover the square frame and clip.
        if let url = optimizedImageURL {
            AsyncImage(url: url) { phase in
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
        } else {
            Image("myDrink")
                .resizable().aspectRatio(contentMode: .fit)
                .padding(16)
        }
    }
}

// MARK: - Recipe detail

/// Ports `RecipePageViewController` end-to-end:
///   • 60pt custom nav bar (back chevron • device info principal •
///     favorite icon + glass profile trailing).
///   • Hero: recipe image 345×345, 12pt corner radius, `UIImage.myDrink`
///     placeholder fallback on load failure.
///   • Title (bold 16pt) + description (12pt) block.
///   • "The Recipe" underlined section header (bold 14pt).
///   • "INGREDIENTS (n)" heading + editable ingredient rows with − / + /
///     inline quantity field driven by `RecipePageViewModel` rules (min
///     0.5ml, max 1000ml / 33.8oz, 5-char limit).
///   • Conditional Glassware + Garnish rows.
///   • Instructions block rendered as "Step 1: … | Step 2: …" per UIKit.
///   • Additional (optional garnish) ingredients table when present.
///   • Bottom CTA stack: Craft Recipe (brand orange primary) + Add /
///     Remove Favorite (outlined, gradient stroke).
///   • Favorite action calls `env.storage.toggleFavorite(id)` and flashes
///     the UIKit-matched toast; Craft checks BLE connection and falls
///     back to `.pairDevice` when nothing is paired.
struct RecipeDetailView: View {
    let recipeID: RecipeID
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

    @State private var editedIngredients: [Ingredient] = []
    @State private var originalIngredients: [Ingredient] = []
    @State private var showUnsavedAlert = false
    @State private var unsavedPopup: BarsysPopup? = nil
    /// UIKit `RecipePageViewController.didPressAddToFavoriteButton` in
    /// the "Save to My Drinks" branch adds `editVc` as a CHILD view
    /// controller — `self.view.addSubview(editVc.view)` + `addChild` —
    /// so it overlays the RecipePage in place and pops back when done.
    /// In SwiftUI we mirror that by presenting `EditRecipeView` as a
    /// full-screen cover so it visually replaces RecipePage without
    /// navigating the parent tab stack (previously it was wrongly
    /// pushed into the BarBot tab via `router.push(in: .barBot)`).
    @State private var showEditRecipe = false
    /// Local favourite flag — drives the button text (Add to Favorites /
    /// Unfavourite) immediately on tap without waiting for `env.storage`
    /// to trigger a SwiftUI re-render (MockStorageService is NOT
    /// ObservableObject, so mutations to its internal dict are invisible
    /// to SwiftUI).  Matches UIKit `setLikeAndCraftButtonsUI()` which
    /// explicitly updates the button title after the API callback.
    @State private var localIsFavourite: Bool = false

    private var recipe: Recipe? { env.storage.recipe(by: recipeID) }

    // Splits ingredients exactly like `RecipePageViewModel+DataLoading`:
    //   baseAndMixer  = primary != "garnish" AND primary != "additional"
    //   garnish       = primary == "garnish" AND ingredientOptional == false  (unique by name)
    //   additional    = primary == "garnish" AND ingredientOptional == true   (unique by name)
    // This matches the UIKit code 1:1 — a "garnish" ingredient with
    // `ingredientOptional == true` is an Additional Ingredient (NOT a
    // garnish), and the read-only "ADDITIONAL INGREDIENTS (n)" section
    // only shows rows that live under the garnish category AND are
    // flagged optional.
    private var baseAndMixer: [Ingredient] {
        editedIngredients.filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            return p != "garnish" && p != "additional"
        }
    }
    private var garnishIngredients: [Ingredient] {
        let filtered = (recipe?.ingredients ?? []).filter {
            ($0.category?.primary ?? "").lowercased() == "garnish"
                && $0.ingredientOptional == false
        }
        // UIKit: `.unique(by: { $0.name.lowercased() })`
        var seen = Set<String>()
        return filtered.filter { seen.insert($0.name.lowercased()).inserted }
    }
    private var additionalIngredients: [Ingredient] {
        let filtered = (recipe?.ingredients ?? []).filter {
            ($0.category?.primary ?? "").lowercased() == "garnish"
                && $0.ingredientOptional == true
        }
        // UIKit: `.unique(by: { $0.name.lowercased() })`
        var seen = Set<String>()
        return filtered.filter { seen.insert($0.name.lowercased()).inserted }
    }

    private var hasUnsavedChanges: Bool {
        // Same filter as `baseAndMixer` (matches UIKit `RecipePageViewModel
        // +DataLoading.swift` — base/mixer excludes primary "garnish" AND
        // primary "additional"; the optional-garnish "additional
        // ingredients" are filtered out via the `"additional"` exclusion
        // because in UIKit they live under the garnish category with
        // `ingredientOptional == true` and never enter the base/mixer
        // pool).
        let originalBaseAndMixer = originalIngredients.filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            return p != "garnish" && p != "additional"
        }
        guard baseAndMixer.count == originalBaseAndMixer.count else { return false }
        for edited in baseAndMixer {
            if !originalIngredients.contains(where: { $0.name == edited.name && $0.quantity == edited.quantity }) {
                return true
            }
        }
        return false
    }

    private var isBarsys360Connected: Bool { ble.isBarsys360Connected() }
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
        if let recipe {
            content(recipe: recipe)
                .background(Theme.Color.background.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent(for: recipe) }
                // Flat `primaryBackgroundColor` nav bar so the top-right
                // glass pill renders on the same canvas HomeView uses.
                .chooseOptionsStyleNavBar()
                .onAppear {
                    loadIngredients(from: recipe)
                    // Seed local favourite state from storage so the
                    // button text + toolbar heart icon are correct on
                    // initial render. Subsequent toggles update
                    // localIsFavourite directly (instant UI feedback).
                    localIsFavourite = recipe.isFavourite ?? false
                }
                // Unsaved changes popup — glass-card style matching UIKit
                .barsysPopup($unsavedPopup, onPrimary: {
                    // "Discard" — dismiss handled by nav
                }, onSecondary: {
                    // "Keep editing" — stay on page
                })
                // 1:1 port of UIKit child-VC embed:
                //   editVc.presentedFromController = self
                //   self.view.addSubview(editVc.view)
                //   self.addChild(editVc)
                //   editVc.view.frame = self.view.frame
                // In SwiftUI the cleanest equivalent is a full-screen
                // cover so the EditRecipe experience replaces Recipe
                // Detail visually without affecting the parent tab's
                // navigation stack (prevents the BarBot/My Drinks tab
                // jump the previous port was causing).
                .fullScreenCover(isPresented: $showEditRecipe) {
                    NavigationStack {
                        // isCustomizing: true — creating NEW My Drink from
                        // existing Barsys recipe (UIKit: isCustomizingRecipe = true)
                        EditRecipeView(recipeID: recipe.id, isCustomizing: true)
                    }
                }
        } else {
            EmptyStateView(systemImage: "questionmark.circle",
                           title: "Recipe not found",
                           subtitle: "This recipe is no longer available.")
                .background(Theme.Color.background.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(recipe: Recipe) -> some View {
        ScrollView {
            // Parent VStack spacing 0 — UIKit stacks the hero, title,
            // subtitle, and the `fBc-sd-Chd` details container by
            // explicit autolayout constants (image top=0, title top=20
            // from image bottom, subtitle top=14 from title bottom,
            // `fBc-sd-Chd` top = WMC bottom with no extra gap). The
            // previous `spacing: 16` double-counted and pushed every
            // section down by 16pt relative to UIKit.
            VStack(alignment: .leading, spacing: 0) {
                // Hero image — storyboard `VN9-Mm-R3c`:
                //   leading:24, trailing:24, top=0 (pinned to WMC top),
                //   width:height=1:1, roundCorners:12.
                heroImage(recipe: recipe)
                    .padding(.horizontal, 24)

                // Title + description — matches storyboard
                //   `K2L-S7-8cr`: boldSystem 16pt, `appBlackColor`,
                //       leading/trailing:24, top = image.bottom + 20.
                //   `S8V-cr-6My`: system 12pt, `appBlackColor`, multi-line,
                //       leading/trailing:24, top = title.bottom + 14.
                VStack(alignment: .leading, spacing: 14) {
                    Text(recipe.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color("appBlackColor"))
                        .accessibilityAddTraits(.isHeader)
                    if !recipe.subtitle.isEmpty {
                        Text(recipe.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color("appBlackColor"))
                            .lineSpacing(2)
                    }
                }
                .padding(.horizontal, 24)
                // UIKit constraint `sH9-eg-yai`: K2L-S7-8cr.top =
                // VN9-Mm-R3c.bottom + 20. Previously 6pt — wrong.
                .padding(.top, 20)

                // "The Recipe" underlined header — storyboard `kqG-7l-90a`:
                //   boldSystem 14pt, `appBlackColor`, underlined attributed
                //   text set in `setupView()` via `.underline`.
                HStack {
                    Text("The Recipe")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color("appBlackColor"))
                        .underline()
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                // Section order (1:1 port of UIKit
                // `RecipePageViewController.swift` storyboard + runtime
                // visibility in `setupView`):
                //   1. INGREDIENTS (N) — main base + mixer table
                //   2. ADDITIONAL INGREDIENTS (N) — shown immediately
                //      below the main ingredients table when
                //      `viewModel.additionalIngredientsArr.count > 0`
                //      (UIKit `viewAdditionalIngredient` outlet is
                //      visible iff `isAdditionalIngredientsVisible`).
                //   3. Glass info row
                //   4. Garnish info row
                //   5. Crafting Instructions
                //
                // The previous SwiftUI order rendered Additional
                // Ingredients AFTER Instructions which didn't match
                // the UIKit layout — fixed here by moving it up
                // right after `ingredientsSection`.

                // INGREDIENTS (n)
                ingredientsSection

                // ADDITIONAL INGREDIENTS (n) — shown directly below
                // the main ingredients table (matches UIKit storyboard).
                if !additionalIngredients.isEmpty {
                    additionalSection
                }

                // Bh4-Tv-YEG (details stack `7Yu-k8-WvF`) — the UIKit
                // storyboard orders these three rows top-to-bottom as:
                //   1. Garnish   (Jef-JS-SvH, y=0,   50pt tall, label top=25)
                //   2. Glass     (g08-Lm-IC9, y=50,  50pt tall, label top=12)
                //   3. Crafting Instructions (cdY-8H-RMr, y=100,
                //                             label top=25, body top=12 from label)
                // The previous SwiftUI port inverted the first two so
                // "Glass" rendered above "Garnish" — fixed here.
                //
                // Runtime visibility in UIKit (`setupView()`):
                //   • lblGlass / lblGarnish / lblInstruction are always
                //     populated from `viewModel`. In SwiftUI we only
                //     render rows that actually have data so the layout
                //     never produces empty sections, matching UIKit
                //     `isHidden` toggling for missing values.

                // 1. Garnish (joined list, comma-separated capitalized)
                //    — UIKit Jef-JS-SvH label top = 25.
                if !garnishIngredients.isEmpty {
                    infoRow(title: "Garnish",
                            value: garnishIngredients.map { $0.name.capitalized }.joined(separator: ", "),
                            topInset: 25)
                }
                // 2. Glass — UIKit g08-Lm-IC9 label top = 12 (tighter
                //    than the first row because it sits inside the
                //    50pt row below Garnish with only the 12pt interior
                //    offset as visual separation).
                if let g = recipe.glassware?.type, !g.isEmpty {
                    infoRow(title: "Glass", value: g.capitalized,
                            topInset: 12)
                }
                // 3. Crafting Instructions — "Step 1: … | Step 2: …"
                //    (UIKit `formatStandardInstructions`).
                if !recipe.instructions.isEmpty {
                    instructionsSection(steps: recipe.instructions)
                }
                Color.clear.frame(height: 120) // room for the floating CTA
            }
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) { bottomActions(for: recipe) }
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroImage(recipe: Recipe) -> some View {
        // UIKit pipeline: `imgRecipe.sd_setImage(with: imgUrl,
        //   placeholderImage: .myDrink, options: [.scaleDownLargeImages, ...])`
        // → on failure or empty URL the `myDrink` artwork is shown.
        //
        // Storyboard (`VN9-Mm-R3c`) constraints:
        //   • leading = parent + 24
        //   • trailing = parent − 24
        //   • width:height multiplier = 1:1 (square)
        //   • roundCorners = 12
        //   • contentMode = scaleAspectFill (clips to rounded rect)
        //   • backgroundColor = `lightBorderGrayColor` (shows while
        //     SDWebImage is downloading / on missing artwork)
        //
        // The previous SwiftUI port hard-coded `.frame(width: 345,
        // height: 345)`, which only matched UIKit on a 393pt device
        // and visibly broke on iPhone SE / Mini widths. Re-expressed
        // as `maxWidth: .infinity` + 1:1 aspectRatio so the caller's
        // 24pt horizontal padding drives the final width, exactly
        // replicating the UIKit autolayout result on every device.
        let url = URL(string: recipe.imageURL)
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                // Remote image: .fill so it covers the full square,
                // clipped by the rounded rect below.
                img.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                // Loading state: show background color only
                Color("lightBorderGrayColor")
            case .failure:
                // Failed / no URL: show placeholder centered, NOT zoomed.
                // Using .fit prevents the small placeholder from
                // stretching to fill the entire square frame.
                Image("myDrink")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(40)
            @unknown default:
                Color("lightBorderGrayColor")
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color("lightBorderGrayColor"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ingredients

    // Storyboard `PsB-98-YZl`: boldSystem 11pt `appBlackColor`, text set
    // from `viewModel.ingredientHeadingText` → "INGREDIENTS (n)".
    // 14pt gap between heading and the table (`6VP-br-Hrm`).
    //
    // Position of the OGj-uC-sa2 stackView (this section's root) in
    // UIKit = `kqG-7l-90a.bottom + 20` (constraint `keD-en-qN9`).
    // Parent SwiftUI VStack uses `spacing: 0` so the 20pt gap from the
    // "The Recipe" header bottom is applied here directly.
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INGREDIENTS (\(baseAndMixer.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
                .kerning(0.5)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                ForEach(baseAndMixer) { ing in
                    RecipeIngredientRow(
                        ingredient: ing,
                        unit: env.preferences.measurementUnit,
                        onMinus: { adjustQuantity(for: ing, delta: -1) },
                        onPlus:  { adjustQuantity(for: ing, delta: +1) },
                        onEdit:  { newValue in overwriteQuantity(for: ing, toMl: newValue) }
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        // UIKit constraint `keD-en-qN9`: OGj-uC-sa2.top = kqG-7l-90a.bottom + 20.
        .padding(.top, 20)
    }

    // Storyboard row pattern — `Jef-JS-SvH` / `g08-Lm-IC9` containers
    // inside the `7Yu-k8-WvF` stackView:
    //   • Row container is fixed 50pt tall (no explicit height constraint,
    //     but derived from the stackView frame rects — Garnish y=0 h=50,
    //     Glass y=50 h=50).
    //   • Title label `Div-lf-S2f` / `iZE-WM-eLn` — boldSystem 11pt,
    //     width = parent × 0.28, top = 25 (Garnish) OR top = 12 (Glass).
    //   • Value label `2Dh-Md-BXw` / `kek-hZ-qpx` — system 11pt,
    //     leading = label.trailing + 5, trailing = 0, top matches label.
    //
    // Column width: `parent × 0.28` of a 345pt row = 96.6pt — rounded
    // to 97pt in the SwiftUI frame.
    //
    // The 25 vs 12 top inset is passed by caller so Garnish (first
    // row) can use the wider 25pt padding UIKit uses at the start of
    // the details stack, while Glass (second row) uses the 12pt
    // inset that leaves a uniform visual gap between rows.
    private func infoRow(title: String, value: String,
                         topInset: CGFloat = 25) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
                .frame(width: 97, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(Color("appBlackColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset)
    }

    // Crafting Instructions — storyboard `cdY-8H-RMr` container
    // inside the `7Yu-k8-WvF` stack:
    //   • Heading `Pd3-56-bQz`  — boldSystem 11pt, top = container + 25.
    //   • Body    `SUr-n2-AaT`  — system 11pt, top = heading.bottom + 12.
    //   • Container bottom constraint pushes 40pt of breathing room
    //     below the text (`K4f-LP-yt2` constant=40) — reproduced via
    //     the `Color.clear.frame(height: 120)` below the bottom CTA
    //     which owns the floating action bar clearance.
    private func instructionsSection(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crafting Instructions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
            // UIKit `formatStandardInstructions` — "Step 1: … | Step 2: …"
            let formatted = steps.enumerated()
                .map { "Step \($0.offset + 1): \($0.element)" }
                .joined(separator: " | ")
            Text(formatted)
                .font(.system(size: 11))
                .foregroundStyle(Color("appBlackColor"))
                .lineSpacing(2)
        }
        .padding(.horizontal, 24)
        // Storyboard constraint `y4e-UG-x99`: Pd3-56-bQz.top =
        // cdY-8H-RMr.top + 25, and cdY starts immediately below
        // the Glass row container with no gap — so total vertical
        // inset from the Glass row bottom to the "Crafting
        // Instructions" heading is 25pt.
        .padding(.top, 25)
    }

    // Storyboard `eH4-x3-txk`: boldSystem 11pt `appBlackColor`, text set
    // from `viewModel.additionalIngredientHeadingText`.
    //
    // Layout (Mixlist.storyboard — same layout that RecipePage uses):
    //   • Parent stackView `OGj-uC-sa2` is vertical, spacing=5  →
    //     the main "INGREDIENTS" block and the Additional block sit
    //     5pt apart (NOT 10 + 16 that the previous port produced).
    //   • Inside the Additional container `bLY-mz-NGy`:
    //       – Heading label top = 6pt from container top
    //       – Table top = 14pt from heading bottom
    //   • So the Additional block header effectively renders 5 + 6 = 11pt
    //     below the bottom of the main ingredients table. In SwiftUI we
    //     approximate that with a single 5pt top padding on the section
    //     (the parent ScrollView VStack contributes the rest).
    //   • The UIKit label has `numberOfLines="0"` — kerning matches the
    //     bold 11pt metrics applied uniformly to every other storyboard
    //     header in this scene (no explicit letter spacing is set).
    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ADDITIONAL INGREDIENTS (\(additionalIngredients.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
                .kerning(0.5)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 12) {
                ForEach(additionalIngredients) { ing in
                    RecipeIngredientRow(
                        ingredient: ing,
                        unit: env.preferences.measurementUnit,
                        readOnly: true,
                        onMinus: {}, onPlus: {}, onEdit: { _ in }
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        // 5pt — matches the parent stackView spacing (`OGj-uC-sa2`
        // vertical spacing="5") between the main Ingredients block and
        // the AdditionalIngredientsView container.
        .padding(.top, 5)
    }

    // MARK: - Bottom CTA
    //
    // 1:1 port of UIKit `setLikeAndCraftButtonsUI()` + the three-state
    // `FavouriteButtonState` enum (RecipePageViewModel.swift, lines 49-
    // 53, 156-188):
    //
    //   • shouldShowAddToMyDrinks → "Save to My Drinks"
    //     (triggered when the user has edited any quantity OR the recipe
    //      came from BarBot/mixlist/custom context — in SwiftUI we only
    //      have the "edited quantities" case so `hasUnsavedChanges` is
    //      the driver).
    //   • isFavourite  → "Remove from Favorites"
    //   • default       → "Add to Favorites"
    //
    // Tap handler mirrors UIKit `didPressAddToFavoriteButton`:
    //   • If hasUnsavedChanges → present unsaved-changes alert
    //     (Keep editing / Discard) instead of toggling favourites.
    //   • Otherwise, if shouldShowAddToMyDrinks → route to EditRecipe
    //     (mirrors the UIKit child-VC embed).
    //   • Otherwise → call the favourite-toggle API.

    private enum FavouriteButtonState { case addToMyDrinks, addToFavourites, unfavourite }

    private func favouriteButtonState(for recipe: Recipe) -> FavouriteButtonState {
        if hasUnsavedChanges { return .addToMyDrinks }
        // Read from local @State so SwiftUI re-renders immediately on tap.
        // `recipe.isFavourite` comes from env.storage which is NOT observable.
        return localIsFavourite ? .unfavourite : .addToFavourites
    }

    private func favouriteButtonTitle(for recipe: Recipe) -> String {
        switch favouriteButtonState(for: recipe) {
        case .addToMyDrinks:   return Constants.addToMyDrinksTitle
        case .addToFavourites: return Constants.addToFavTitle
        case .unfavourite:     return Constants.unFavouriteTitle
        }
    }

    // 1:1 port of the UIKit storyboard `bottomButtonStackView` (`pXo-0l-aPm`):
    //
    //   • Horizontal stack: [Favourite button] [Craft button] — EQUAL width.
    //   • Storyboard titles: "Add to Favourites" + "Craft". Favourite title
    //     is swapped at runtime by `setLikeAndCraftButtonsUI()` into one of
    //     three strings depending on `FavouriteButtonState`:
    //         - .addToMyDrinks   → Constants.addToMyDrinksTitle
    //         - .addToFavourites → Constants.addToFavTitle
    //         - .unfavourite     → Constants.unFavouriteTitle
    //   • Background: iOS 26+ → `bottomButtonStackView.addGlassEffect(
    //       isBorderEnabled: true, cornerRadius: BarsysCornerRadius.medium)`
    //     + `roundTopCorners(radius: 12)` (top corners rounded only).
    //     iOS < 26 → the stackView is HIDDEN entirely (each button renders
    //     its own flat style inline).
    //   • Craft button:        PrimaryOrangeButton (→ `makeOrangeStyle()`
    //                          on iOS 26; flat `segmentSelectionColor` on
    //                          earlier iOS).
    //   • Favourite button:    `applyCancelCapsuleGradientBorderStyle()` on
    //                          iOS 26 (white glass + gradient border);
    //                          `craftButtonBorderColor` 1pt border on
    //                          earlier iOS.
    @ViewBuilder
    private func bottomActions(for recipe: Recipe) -> some View {
        HStack(spacing: 14) {
            // Favourite — white bg, cancel-capsule border gradient on iOS 26.
            Button {
                HapticService.light()
                switch favouriteButtonState(for: recipe) {
                case .addToMyDrinks:
                    // UIKit embeds `EditViewController` as a child VC
                    // (`addSubview` + `addChild`) so it presents over
                    // RecipePage IN PLACE and stays in the SAME tab
                    // the user is currently on. SwiftUI equivalent:
                    // full-screen cover on the current view — NOT a
                    // tab-scoped `router.push(in: .barBot)` which was
                    // yanking the user into the BarBot + My Drinks
                    // tabs regardless of where they came from.
                    showEditRecipe = true
                case .addToFavourites:
                    localIsFavourite = true
                    env.storage.toggleFavorite(recipe.id)
                    // 1:1 port of UIKit RecipePageViewController+Actions
                    // performLikeUnlike: updates DB + calls likeUnlikeApi
                    // Revert on failure (matches FavoritesView pattern)
                    Task {
                        do {
                            _ = try await env.api.likeUnlike(
                                recipeId: recipe.id.value, isLike: true)
                        } catch {
                            localIsFavourite = false
                            env.storage.toggleFavorite(recipe.id)
                        }
                    }
                    env.analytics.track(TrackEventName.favouriteRecipeAdded.rawValue)
                    env.alerts.show(message: Constants.likeSuccessMessage)
                case .unfavourite:
                    localIsFavourite = false
                    env.storage.toggleFavorite(recipe.id)
                    Task {
                        do {
                            _ = try await env.api.likeUnlike(
                                recipeId: recipe.id.value, isLike: false)
                        } catch {
                            localIsFavourite = true
                            env.storage.toggleFavorite(recipe.id)
                        }
                    }
                    env.analytics.track(TrackEventName.favouriteRecipeRemoved.rawValue)
                    env.alerts.show(message: Constants.unlikeSuccessMessage)
                }
            } label: {
                // UIKit: applyCancelCapsuleGradientBorderStyle() — capsule
                // glass with 1.5pt gradient border (white@95% highlights).
                // Pre-26 fallback: craftButtonBorderColor 1pt stroke.
                Text(favouriteButtonTitle(for: recipe))
                    .font(.system(size: 15))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(cancelCapsuleBackground)
                    .overlay(cancelCapsuleBorder)
            }
            .buttonStyle(BounceButtonStyle())

            // Craft — PrimaryOrangeButton (brand gradient on iOS 26+,
            // flat segmentSelectionColor on pre-26).
            Button {
                HapticService.light()
                if hasUnsavedChanges {
                    unsavedPopup = .confirm(
                        title: "Unsaved changes",
                        message: "You've changed quantities. Discard your edits?",
                        primaryTitle: ConstantButtonsTitle.discardButtonTitle,
                        secondaryTitle: ConstantButtonsTitle.keepEditingButtonTitle,
                        isDestructive: true
                    )
                } else {
                    craft(recipe)
                }
            } label: {
                // UIKit makeOrangeStyle(): iOS 26+ → capsule with brand
                // gradient (#FAE0CC → #F2C2A1). Pre-26 → flat segmentSelectionColor.
                Text("Craft")
                    .font(.system(size: 15))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(primaryOrangeButtonBackground)
            }
            .buttonStyle(BounceButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(bottomContainerBackground)
    }

    /// iOS 26+ → glass background with border, rounded top corners only.
    /// iOS <26 → transparent (UIKit hides the whole stackView; we let the
    /// buttons float over the scroll view with just a slight scrim).
    @ViewBuilder private var bottomContainerBackground: some View {
        if #available(iOS 26.0, *) {
            UnevenRoundedRectangle(topLeadingRadius: 12,
                                   bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: 12,
                                   style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 12,
                                           bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0,
                                           topTrailingRadius: 12,
                                           style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        } else {
            Theme.Gradient.bottomScrim
        }
    }

    // MARK: - Shared button backgrounds (ports UIKit PrimaryOrangeButton + applyCancelCapsuleGradientBorderStyle)

    /// Ports UIKit `makeOrangeStyle()` — PrimaryOrangeButton.swift:
    ///   iOS 26+: Capsule with brand gradient #FAE0CC → #F2C2A1
    ///   Pre-26:  Flat segmentSelectionColor (#E0B392) with 8pt corners
    @ViewBuilder
    private var primaryOrangeButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color("brandGradientTop"), Color("brandGradientBottom")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("segmentSelectionColor"))
        }
    }

    /// Ports UIKit `applyCancelCapsuleGradientBorderStyle()` —
    /// UIViewClass+GradientStyles.swift:
    ///   iOS 26+: Capsule glass with cancelButtonGray tint + 1.5pt
    ///            gradient border (white@95% highlights)
    ///   Pre-26:  White bg with craftButtonBorderColor 1pt stroke
    @ViewBuilder
    private var cancelCapsuleBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                .fill(Color.white)
        }
    }

    @ViewBuilder
    private var cancelCapsuleBorder: some View {
        if #available(iOS 26.0, *) {
            // UIKit: 1.5pt gradient border with white@95% highlights
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color(white: 0.85).opacity(0.9),
                            Color.white.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
        }
    }

    // MARK: - Toolbar (60pt nav bar parity)

    @ToolbarContentBuilder
    private func toolbarContent(for recipe: Recipe) -> some ToolbarContent {
        if ble.isAnyDeviceConnected {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if !deviceIconName.isEmpty {
                        Image(deviceIconName).resizable().aspectRatio(contentMode: .fit).frame(width: 22, height: 22)
                    }
                    Text(deviceKindName)
                        .font(Theme.Font.of(.caption1, .medium))
                        .foregroundStyle(Color("appBlackColor"))
                }
            }
        }
        // Shared 100×48 glass pill (iOS 26+) / bare 61×24 icon stack
        // (pre-26) with a RECIPE-SPECIFIC heart as the leading icon.
        //
        // 1:1 UIKit parity: `RecipePageViewController` wraps the
        // per-recipe favorite button + side-menu button inside the
        // SAME `navigationRightGlassView` container used by every
        // other tab-level screen. The only thing that changes is the
        // leading icon's glyph (`heart.fill` when favourited, `heart`
        // otherwise) + the action (toggle recipe favorite + toast).
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationRightGlassButtons(
                leadingSystemImage: localIsFavourite
                    ? "heart.fill"
                    : "heart",
                leadingAccessibilityLabel: "Favourite",
                onFavorites: {
                    let willBeFav = !localIsFavourite
                    localIsFavourite = willBeFav
                    env.storage.toggleFavorite(recipe.id)
                    // 1:1 port of UIKit: likeUnlikeApi + revert on failure
                    Task {
                        do {
                            _ = try await env.api.likeUnlike(
                                recipeId: recipe.id.value, isLike: willBeFav)
                        } catch {
                            localIsFavourite = !willBeFav
                            env.storage.toggleFavorite(recipe.id)
                        }
                    }
                    env.analytics.track(
                        (willBeFav ? TrackEventName.favouriteRecipeAdded
                                   : TrackEventName.favouriteRecipeRemoved).rawValue
                    )
                    env.alerts.show(
                        message: willBeFav
                            ? Constants.likeSuccessMessage
                            : Constants.unlikeSuccessMessage
                    )
                },
                onProfile: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        router.showSideMenu = true
                    }
                }
            )
        }
    }

    // MARK: - Actions

    private func loadIngredients(from recipe: Recipe) {
        let all = recipe.ingredients ?? []
        originalIngredients = all
        editedIngredients = all
    }

    /// 1:1 port of `RecipePageViewModel.increase/decreaseQuantity` →
    /// `Quantity.increase/decreaseQuantityByUnit(_:unit:)`.
    ///
    /// **Exact UIKit constants** (`Constants.swift` + `Quantity.swift`):
    ///   • Step (ml unit):  `maxIncrementDecrementValueForMl = 10`
    ///   • Step (oz unit):  `maxIncrementDecrementValueForOz = 0.33814`
    ///                      (≈ 10 ml — the helper does the round-trip via
    ///                      ml then back to oz, so the visible jump is
    ///                      always one of these two values).
    ///   • Floor:           `minimumQtyDouble = 5`
    ///   • Ceiling:         `maximumQuantityDoubleMLFor360 = 750`
    ///   • Boundary snap:   when `value >= (max − step)`, UIKit snaps to
    ///                      `max` exactly so the user can land on 750ml
    ///                      with one tap from 745ml.
    private func adjustQuantity(for ing: Ingredient, delta: Int) {
        guard let idx = editedIngredients.firstIndex(where: { $0.id == ing.id }) else { return }
        let stepMl: Double = 10.0
        let minMl: Double = 5.0
        let maxMl: Double = 750.0
        var copy = editedIngredients[idx]
        var q = copy.quantity ?? 0
        if delta > 0 {
            // Increase — snap to ceiling when within one step of max.
            if q + stepMl > maxMl {
                q = maxMl
            } else {
                q += stepMl
            }
        } else {
            // Decrease — snap to floor when going below it.
            q -= stepMl
            if q < minMl { q = minMl }
        }
        copy.quantity = q
        editedIngredients[idx] = copy
    }

    /// Direct text-edit overwrite — clamps to UIKit's
    /// [`minimumQtyDouble`, `maximumQuantityDoubleMLFor360`] = [5, 750] ml.
    private func overwriteQuantity(for ing: Ingredient, toMl ml: Double) {
        guard let idx = editedIngredients.firstIndex(where: { $0.id == ing.id }) else { return }
        var copy = editedIngredients[idx]
        copy.quantity = max(5.0, min(750.0, ml))
        editedIngredients[idx] = copy
    }

    private func craft(_ recipe: Recipe) {
        guard ble.isAnyDeviceConnected else {
            router.push(.pairDevice)
            return
        }
        router.push(.crafting(recipe.id))
    }

    private func quantityString(_ ml: Double) -> String {
        switch env.preferences.measurementUnit {
        case .ml: return String(format: "%.0f ml", ml)
        case .oz: return String(format: "%.2f oz", ml / 29.5735)
        }
    }
}

// MARK: - Recipe ingredient row (ports RecipeIngredientTableViewCell)
//
// UIKit XIB dimensions:
//   • cell height: 61pt (49pt glass view + 6pt insets top/bottom)
//   • name label: 14pt, appBlackColor, up to 3 lines, left 24pt, w≥135
//   • quantity text field: 11pt, center aligned, 70pt wide, 5-char max
//   • unit label: 11pt, mediumLightGrayColor ("ml" / "oz")
//   • ± buttons: 30×30
//   • glass view: pill radius, iOS 26 glass OR iOS ≤25 gradient
//     (black 10% / white 10%) + 1pt #F2F2F2 border
struct RecipeIngredientRow: View {
    let ingredient: Ingredient
    let unit: MeasurementUnit
    var readOnly: Bool = false
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onEdit: (Double) -> Void

    @State private var editingText: String = ""
    @FocusState private var isFocused: Bool

    private var displayText: String {
        let ml = ingredient.quantity ?? 0
        switch unit {
        case .ml: return String(format: "%.0f", ml)
        case .oz: return String(format: "%.2f", ml / 29.5735)
        }
    }

    private var unitLabel: String {
        switch unit { case .ml: return "ml"; case .oz: return "oz" }
    }

    var body: some View {
        HStack(spacing: 5) {
            // Name label — system 14pt, `appBlackColor`, up to 3 lines,
            // 24pt leading inset matching storyboard constraint `kim-hJ-6Pi`.
            Text(ingredient.name)
                .font(.system(size: 14))
                .foregroundStyle(Color("appBlackColor"))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)

            if !readOnly {
                // Stepper cluster — 130pt wide, centered in the cell right
                // half. Matches storyboard stack `NEL-QM-2aY`:
                //   [ 30×30 minus btn ] [ 70×30 qty field + unit ] [ 30×30 plus btn ]
                HStack(spacing: 0) {
                    Button {
                        HapticService.light()
                        onMinus()
                    } label: {
                        // UIKit: `state.image = newMinus` with
                        // `tintColor = grayBorderColor`. Template render
                        // so the asset tints to match the UIKit grey.
                        Image("newMinus")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color("grayBorderColor"))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Decrease \(ingredient.name)")

                    // Quantity + unit — stackView inside a 70×30 container.
                    HStack(spacing: 5) {
                        TextField("", text: $editingText)
                            .keyboardType(unit == .ml ? .numberPad : .decimalPad)
                            .multilineTextAlignment(.center)
                            // Storyboard `m1H-Gu-dS6` — system 11pt,
                            // `mediumLightGrayColor`.
                            .font(.system(size: 11))
                            .foregroundStyle(Color("mediumLightGrayColor"))
                            .focused($isFocused)
                            .onChange(of: isFocused) { focused in
                                if focused {
                                    editingText = displayText
                                } else {
                                    commitEdit()
                                }
                            }
                            .onChange(of: editingText) { new in
                                // 5-char limit (UIKit `shouldAllowCharacterChange`).
                                if new.count > 5 { editingText = String(new.prefix(5)) }
                            }
                            // Re-sync editingText when parent mutates quantity
                            // (via +/- or unit toggle) — mirrors UIKit's
                            // `tblIngredient.reloadData()` after each tap.
                            .onChange(of: ingredient.quantity) { _ in
                                if !isFocused { editingText = displayText }
                            }
                            .onChange(of: unit) { _ in
                                if !isFocused { editingText = displayText }
                            }
                        Text(unitLabel)
                            // Storyboard `Q8p-KS-sM8` — system 11pt,
                            // `mediumLightGrayColor`.
                            .font(.system(size: 11))
                            .foregroundStyle(Color("mediumLightGrayColor"))
                    }
                    .frame(width: 70, height: 30)

                    Button {
                        HapticService.light()
                        onPlus()
                    } label: {
                        Image("newPlus")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color("grayBorderColor"))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Increase \(ingredient.name)")
                }
                .padding(.trailing, 24) // matches `Kzt-lz-F4P` trailing 24
            } else {
                Text("\(displayText) \(unitLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("mediumLightGrayColor"))
                    .padding(.trailing, 24)
            }
        }
        // Total cell height ≈ 49 (storyboard `s3S-ze-LXL` frame h=49).
        .frame(minHeight: 49)
        // Glass pill background:
        //   • iOS 26+ → `addGlassEffect(cornerRadius: 25, alpha: 1.0)`
        //   • iOS <26 → `roundCorners = pill`, gradient black 10% / white 10%,
        //              1pt #F2F2F2 border.
        .background(pillGlassBackground)
        .onAppear { editingText = displayText }
    }

    @ViewBuilder private var pillGlassBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(red: 0.949, green: 0.949, blue: 0.949),
                                lineWidth: 1)
                )
        } else {
            // Gradient fill — black 10% → white 10% (matches UIKit
            // `addGradientLayer(colors: [.black α0.1, .white α0.1])`).
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.1), Color.white.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(Color.white.opacity(0.7), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(red: 0.949, green: 0.949, blue: 0.949),
                                lineWidth: 1)
                )
        }
    }

    /// Direct text-edit commit — mirrors UIKit
    /// `validateAndUpdateQuantity(at:inputText:)` clamping rules:
    ///   • Floor: `minimumQtyDouble` = 5 ml
    ///   • Ceiling: `maximumQuantityDoubleMLFor360` = 750 ml
    private func commitEdit() {
        guard let v = Double(editingText) else {
            editingText = displayText
            return
        }
        let ml: Double = (unit == .oz) ? v * 29.5735 : v
        let clamped = max(5, min(750, ml))
        onEdit(clamped)
        editingText = displayText
    }
}

// MARK: - Make My Own

@MainActor
final class MakeMyOwnViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var items: [Ingredient] = []
    @Published var showPicker = false

    func addIngredient(_ i: Ingredient) { items.append(i) }
    func remove(_ i: Ingredient) { items.removeAll { $0.id == i.id } }

    /// Ports UIKit MakeMyOwnViewController+Actions.saveRecipeAfterAll() →
    /// FavoriteRecipeApiService.saveRecipe_Or_UpdateRecipe(mode: .create).
    /// Creates a new My Drink locally AND calls the POST /my/recipes API.
    func save(to storage: StorageService, api: APIClient) -> Recipe {
        var recipe = Recipe(name: name.isEmpty ? "My Custom Drink" : name,
                            description: "Custom creation",
                            ingredients: items,
                            instructions: ["Add all ingredients in order.", "Stir or shake to taste."],
                            tags: ["Custom"],
                            isMyDrinkFavourite: true)
        storage.upsert(recipe: recipe)
        // Fire-and-forget API call (UIKit: saveRecipeAfterAll → saveRecipe_Or_UpdateRecipe)
        let recipeToSend = recipe
        Task {
            try? await api.saveOrUpdateMyDrink(
                recipe: recipeToSend, image: nil, isCustomizing: false)
        }
        return recipe
    }
}

struct MakeMyOwnView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = MakeMyOwnViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                AppTextField(placeholder: "Drink name", text: $viewModel.name, systemImage: "textformat").pagePadding()

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack {
                        Text("Ingredients").font(Theme.Font.headline()).foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        Button { viewModel.showPicker = true } label: {
                            Label("Add", systemImage: "plus.circle.fill").foregroundStyle(Theme.Color.brand)
                        }
                    }
                    if viewModel.items.isEmpty {
                        Text("Tap + to add an ingredient.")
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Theme.Spacing.l)
                    } else {
                        ForEach(viewModel.items) { item in
                            HStack {
                                Text(item.name).foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                                Text("\(Int(item.quantityML)) ml").foregroundStyle(Theme.Color.textSecondary)
                                Button { viewModel.remove(item) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Color.danger)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.s)
                        }
                    }
                }
                .cardBackground()
                .pagePadding()

                PrimaryButton(title: "Save & craft") {
                    let recipe = viewModel.save(to: env.storage, api: env.api)
                    router.push(.crafting(recipe.id))
                }
                .pagePadding()
            }
            .padding(.top, Theme.Spacing.m)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Make my own")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .sheet(isPresented: $viewModel.showPicker) {
            IngredientPicker { viewModel.addIngredient($0); viewModel.showPicker = false }
        }
    }
}

private struct IngredientPicker: View {
    @EnvironmentObject private var env: AppEnvironment
    let onPick: (Ingredient) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(SampleData.ingredients.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { ing in
                    Button { onPick(ing) } label: {
                        HStack {
                            Text(ing.name).foregroundStyle(Theme.Color.textPrimary)
                            Spacer()
                            Text(ing.category?.primary ?? "").foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.Color.surface)
                }
            }
            .searchable(text: $query)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle(Constants.addIngredientTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Edit recipe
//
// 1:1 port of `EditViewController` + its `+TableView` / `+Accessibility`
// extensions. UIKit reference (BarBot.storyboard scene `ub5-ev-1ng`):
//
//   • Header row (y=24): "Edit" title (16pt system, appBlackColor) +
//     close-button (24×24, `crossIcon`, touchUpInside → dismiss).
//   • Cocktail-name row (y=62, h=40):
//       - UITextView 12pt system, sentences cap.
//       - Placeholder label "Cocktail name" at (5,9) 12pt placeholder grey.
//       - 1pt underline at y=39 in `veryDarkGrayColor` — turns red
//         (`errorLabelColor`) when the save-time validator fails.
//   • Add-image stack (y=125, h=152):
//       - "Add Image" button 92×32, 8pt corners, `charcoalGrayColor`
//         title, `craftButtonBorderColor` 1pt stroke.
//       - When an image is picked → 120×120 preview (8pt corners)
//         + 30×30 delete button (`whiteDeleteImage`) top-right.
//   • Ingredient table (y=292, dynamic height, cap 150pt).
//   • Bottom button row: "Cancel" (white) + "Save" (brand gradient) +
//     "Craft" (brand gradient, segmentSelectionColor).
//   • Presented as a child VC of RecipePage / Favourites (embedded),
//     dismissed via `removeFromParent()`.
//
// SwiftUI presentation is a full navigation-stack screen so we use
// `@Environment(\.dismiss)` instead of manual child-VC unwinding.

struct EditRecipeView: View {
    let recipeID: RecipeID?
    /// Ports UIKit `EditViewController.isCustomizingRecipe`.
    /// - `true`  → creating a NEW My Drink from an existing Barsys recipe
    ///   (RecipeDetailView "Save to My Drinks"). API: POST /my/recipes.
    /// - `false` → editing an EXISTING My Drink
    ///   (FavoritesView My Drinks tab "Edit"). API: PATCH /my/recipes/{id}.
    var isCustomizing: Bool = false
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService    // hide-add row depends on Barsys 360 connection
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var ingredients: [Ingredient] = []
    @State private var selectedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var nameHasError = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// Ports UIKit `EditViewModel.validateForSave()` — must have a name
    /// and at least one ingredient with a non-zero quantity.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !ingredients.isEmpty
            && ingredients.contains { ($0.quantity ?? 0) > 0 }
    }

    var body: some View {
        // Panel container mirrors UIKit EditViewController mainView:
        // top-rounded BarsysCornerRadius.medium (12pt) + `addGlassEffect()`
        // + shadow. The inner VStack holds the same Edit / cross / name /
        // image / ingredients / bottom-buttons hierarchy as the storyboard.
        ZStack {
            Color("primaryBackgroundColor").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    nameField
                    imagePickerBlock
                    ingredientsBlock
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(Color("errorLabelColor"))
                            .padding(.horizontal, 24)
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.top, 24)
            }
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
                .fill(.regularMaterial)
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
            )
            // Lifts the panel off the parent — maps the UIKit glass
            // `shadowColor=black@0.20, opacity 0.30, offset (0,10), radius 25`
            // (UIViewClass+GlassEffects.swift L137-140) to SwiftUI.
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom) { bottomButtons }
        .sheet(isPresented: $showPhotoPicker) {
            ImagePicker(image: $selectedImage)
        }
        .onAppear {
            if let id = recipeID, let recipe = env.storage.recipe(by: id) {
                name = recipe.name ?? ""
                ingredients = recipe.ingredients ?? []
            }
            env.analytics.track(TrackEventName.editRecipeBegin.rawValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        // Storyboard: "Edit" label x:24 y:24 size 16pt + cross 24×24 at x:345.
        // Cross uses the `crossIcon` asset (same visual as Recipe Detail).
        HStack {
            Text("Edit")
                .font(.system(size: 16))
                .foregroundStyle(Color("appBlackColor"))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                HapticService.light()
                dismiss()
            } label: {
                Image("crossIcon")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color("appBlackColor"))
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Close editor")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Name field with placeholder + underline

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if name.isEmpty {
                    Text("Cocktail name")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("charcoalGrayColor").opacity(0.6))
                        .padding(.leading, 5)
                        .padding(.top, 9)
                        .allowsHitTesting(false)
                }
                TextField("", text: $name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("appBlackColor"))
                    .textInputAutocapitalization(.sentences)
                    .frame(height: 40)
                    .padding(.leading, 5)
                    .onChange(of: name) { _ in
                        if nameHasError { nameHasError = false }
                    }
                    .accessibilityLabel("Cocktail name")
                    .accessibilityHint("Enter a name for your drink")
            }
            Rectangle()
                .fill(nameHasError ? Color("errorLabelColor") : Color("veryDarkGrayColor"))
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Image picker block

    @ViewBuilder
    private var imagePickerBlock: some View {
        HStack {
            if let image = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button { selectedImage = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.55))
                            )
                    }
                    .offset(x: -2, y: 2)
                    .accessibilityLabel("Remove image")
                }
            } else {
                Button { showPhotoPicker = true } label: {
                    Text("Add Image")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("charcoalGrayColor"))
                        .frame(width: 92, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Add recipe image")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Ingredients block — matches `EditViewController+TableView`
    //
    // UIKit hierarchy:
    //   • Editable rows (EditTableViewCell.xib) — 64pt tall.
    //   • A **separate** "viewAddIngredients" row (52pt glass pill,
    //     "+ Add Ingredient" centred) BELOW the list — NOT a small
    //     plus button next to a header. The pill is `applyCellGlassStyle`
    //     so it gets the iOS-26 glass effect or the iOS-25 gradient
    //     border on older OS.
    //   • `hideUnhideAddIngredientButton`: hides the pill when
    //     `recipeIngredientsArrayToShow.count == 6 && isBarsys360Connected()`
    //     — Barsys 360 maxes out at 6 ingredients per recipe.
    //
    // SwiftUI also drops the bold "INGREDIENTS (n)" header that the
    // earlier port had, since the UIKit storyboard never exposed one
    // (the count is communicated only by visible rows).

    private var ingredientsBlock: some View {
        VStack(spacing: 10) {
            // Editable ingredient rows.
            ForEach($ingredients) { $ing in
                EditIngredientRow(
                    ingredient: $ing,
                    unit: env.preferences.measurementUnit,
                    onDelete: {
                        ingredients.removeAll { $0.id == ing.id }
                    }
                )
            }

            // viewAddIngredients pill — 52pt tall, full width, "+ Add
            // Ingredient". UIKit applies `applyCellGlassStyle(view)`:
            //   iOS 26+ → addGlassEffect(cornerRadius: xlarge=20, alpha:1)
            //   pre-26  → roundCorners = pill(24), borderWidth = 1,
            //             gradient [black@10%, white@10%], border color
            //             #F2F2F2 (EditViewController.swift L234-L243).
            // Hidden when Barsys 360 is connected and the user has hit
            // the 6-ingredient cap.
            if !shouldHideAddIngredientRow {
                Button {
                    HapticService.light()
                    addPlaceholderIngredient()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color("appBlackColor"))
                        Text("Add Ingredient")
                            .font(.system(size: 14))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(addIngredientBackground)
                    .overlay(addIngredientBorder)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel("Add Ingredient")
                .accessibilityHint("Add another ingredient to the recipe")
            }
        }
        .padding(.horizontal, 24)
    }

    /// Ports UIKit `EditViewModel.shouldHideAddIngredientRow`: a recipe
    /// for the Barsys 360 device caps at 6 ingredients.
    private var shouldHideAddIngredientRow: Bool {
        ingredients.count >= 6 && ble.isBarsys360Connected()
    }

    /// 1:1 with UIKit `didPressAddIngredientButton` —
    /// `showActionSheetForImagePicker(isImageCroppingDisabled: true)`
    /// followed by `uploadIngredientImage(...)` ingredient detection.
    /// Local placeholder until the upload service is wired in.
    private func addPlaceholderIngredient() {
        ingredients.append(Ingredient(name: "New Ingredient",
                                      unit: Constants.mlText,
                                      quantity: 30))
    }

    // iOS 26: glass material at xlarge (20pt) radius; pre-26: pill (24pt)
    // with the UIKit black/white 10% gradient fill.
    @ViewBuilder
    private var addIngredientBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        } else {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(Capsule().fill(Color.white))
        }
    }

    @ViewBuilder
    private var addIngredientBorder: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        } else {
            // UIKit border color #F2F2F2, 1pt width.
            Capsule()
                .stroke(Color(red: 0.949, green: 0.949, blue: 0.949),
                        lineWidth: 1)
        }
    }

    // MARK: - Bottom actions — Cancel + Save + Craft (matches UIKit button stack)

    // MARK: - Bottom actions — UIKit stackView `dSR-2a-DVd`
    //
    // Storyboard frame: x:24 y:370.67 w:345 h:57, spacing 8pt.
    //   • addToFavouritesButton (`vUR-Kl-PyW`): 168.67 × 45, title "Save",
    //     black title, cornerRadius 8.
    //       iOS 26+ → `applyCancelCapsuleGradientBorderStyle()` — capsule
    //                 gradient stroke (same as UIKit Cancel capsule).
    //       pre-26  → `makeBorder(width:1, color: craftButtonBorderColor)`
    //                 — plain 1pt border, white bg, 8pt rounded.
    //   • craftButton (`qTT-Jo-wcp`): 168.33 × 45, title "Craft",
    //     black title, `makeOrangeStyle()` + segmentSelectionColor bg.
    //
    // Cancel is NOT a bottom button — dismiss is only via the cross
    // button at the top right (see `header`).
    //
    // Bottom constraint `Au6-gK-VHK`: iOS 26 → 12pt, pre-26 → 36pt
    // (`viewWillAppear` in EditViewController.swift L196-L200).
    private var bottomButtons: some View {
        HStack(spacing: 8) {
            // Save — ports applyCancelCapsuleGradientBorderStyle():
            //   iOS 26+: Capsule glass + 1.5pt gradient border
            //   Pre-26:  White bg + craftButtonBorderColor 1pt stroke
            Button {
                HapticService.light()
                save()
            } label: {
                Text(ConstantButtonsTitle.saveButtonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(editCancelCapsuleBackground)
                    .overlay(editCancelCapsuleBorder)
                    .opacity(canSave ? 1.0 : 0.5)
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Save to My Drinks")
            .accessibilityHint("Saves the recipe to your drinks list")

            // Craft — ports makeOrangeStyle():
            //   iOS 26+: Capsule with brand gradient #FAE0CC → #F2C2A1
            //   Pre-26:  Flat segmentSelectionColor, 8pt corners
            Button {
                HapticService.light()
                craft()
            } label: {
                Text("Craft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(editOrangeButtonBackground)
                    .opacity(canSave ? 1.0 : 0.5)
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Craft this recipe")
            .accessibilityHint("Pour this recipe on your connected device")
        }
        .padding(.horizontal, 24)
        // UIKit bottom constraint: iOS 26 → 12pt, pre-26 → 36pt
        // (plus 27pt if a custom tab-bar is visible; our SwiftUI tab bar
        // is already excluded from the inset stack so 12/36 is fine).
        .padding(.bottom, iOS26BottomInset)
        .padding(.top, 8)
        .background(Theme.Gradient.bottomScrim)
    }

    /// Mirrors `viewWillAppear` branch on `EditViewController.swift`
    /// (L196-L200): iOS 26 → 12pt, pre-26 → 36pt.
    private var iOS26BottomInset: CGFloat {
        if #available(iOS 26.0, *) { 12 } else { 36 }
    }

    // MARK: - Save / Craft handlers (ports EditViewModel+API.saveRecipe)

    /// Ports UIKit EditViewModel+API.saveRecipe() → FavoriteRecipeApiService.saveRecipe_Or_UpdateRecipe().
    ///
    /// Flow (matching UIKit EditViewController.didPressAddToFavouriteButton L238-293):
    ///   1. Validate name + ingredients
    ///   2. Show loader ("Saving Recipe")
    ///   3. Call API: POST (create) or PATCH (update)
    ///   4. On success → upsert to storage + cache, show alert, dismiss
    ///   5. FavoritesView.onAppear will re-fetch from API (resetMyDrinksForRefresh)
    private func save() {
        guard validate() else { return }
        guard !isSaving else { return }
        isSaving = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // UIKit EditViewModel+API.saveRecipe L26-28: filter ingredients
        // with quantity > 0 before sending to API.
        let filteredIngredients = ingredients.filter { ($0.quantity ?? 0) > 0 }

        // Build the recipe to send to API
        var recipeToSave: Recipe
        if let id = recipeID, let existing = env.storage.recipe(by: id), !isCustomizing {
            // EDIT existing My Drink — PATCH /my/recipes/{id}
            recipeToSave = existing
            recipeToSave.name = trimmed
            recipeToSave.ingredients = filteredIngredients
            recipeToSave.isMyDrinkFavourite = true
        } else {
            // CREATE new My Drink — POST /my/recipes
            // When customizing, use existing recipe data as template but
            // clear the ID so the server generates a new one.
            if let id = recipeID, let existing = env.storage.recipe(by: id) {
                recipeToSave = Recipe(
                    id: RecipeID(""),   // Server generates new ID
                    name: trimmed,
                    description: existing.description,
                    image: existing.image,
                    ice: existing.ice,
                    ingredients: filteredIngredients,
                    instructions: existing.instructions,
                    glassware: existing.glassware,
                    tags: existing.tags,
                    ingredientNames: existing.ingredientNames,
                    barsys360Compatible: existing.barsys360Compatible,
                    isMyDrinkFavourite: true,
                    slug: existing.slug
                )
            } else {
                recipeToSave = Recipe(
                    id: RecipeID(""),
                    name: trimmed,
                    ingredients: filteredIngredients,
                    instructions: ["Add all ingredients in order.", "Stir or shake to taste."],
                    isMyDrinkFavourite: true
                )
            }
        }

        // Encode image if user picked one (UIKit: base64 JPEG)
        let imageData = selectedImage?.jpegData(compressionQuality: 0.7)

        Task { @MainActor in
            do {
                // API call — POST or PATCH (matches UIKit L265-268)
                try await env.api.saveOrUpdateMyDrink(
                    recipe: recipeToSave,
                    image: imageData,
                    isCustomizing: isCustomizing
                )
                // Local upsert (for immediate visibility on other screens)
                if !isCustomizing, let id = recipeID {
                    // Update: keep the existing ID, upsert locally
                    var updated = recipeToSave
                    updated.isMyDrinkFavourite = true
                    env.storage.upsert(recipe: updated)
                }
                isSaving = false
                env.analytics.track(TrackEventName.editRecipeSuccessful.rawValue)
                // UIKit: isCustomizingRecipe || .create → recipeAddMessage,
                //        .update → recipeUpdateMessage (EditViewModel+API L53-55)
                let successMsg = isCustomizing
                    ? Constants.recipeAddMessage
                    : Constants.recipeUpdateMessage
                // UIKit (EditViewController L274-289):
                //   if topVC is FavouritesRecipesAndDrinksViewController:
                //     controller.getMyDrinksApi(isInitialDataLoading: true)
                //   else:
                //     BarBotCoordinator.showFavourites(tabSelected: 1)
                // We dismiss first (closes the fullScreenCover), then
                // navigate to favourites on the current tab so the user
                // lands on the My Drinks tab and sees the saved recipe.
                env.alerts.show(message: successMsg) {
                    dismiss()
                    // Navigate to favorites screen (My Drinks tab) after
                    // a short delay so the dismiss animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        router.push(.favorites)
                    }
                }
            } catch {
                isSaving = false
                env.alerts.show(message: Constants.recipeSaveError)
            }
        }
    }

    private func craft() {
        guard validate() else { return }
        if let id = recipeID { env.alerts.show(message: "Crafting \(name)…") ; _ = id }
        dismiss()
    }

    // MARK: - Button style helpers (ports PrimaryOrangeButton + applyCancelCapsuleGradientBorderStyle)

    @ViewBuilder
    private var editOrangeButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color("brandGradientTop"), Color("brandGradientBottom")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("segmentSelectionColor"))
        }
    }

    @ViewBuilder
    private var editCancelCapsuleBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        }
    }

    @ViewBuilder
    private var editCancelCapsuleBorder: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color(white: 0.85).opacity(0.9),
                            Color.white.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
        }
    }

    private func validate() -> Bool {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            nameHasError = true
            errorMessage = Constants.pleaseAddRecipeName
            return false
        }
        if ingredients.isEmpty {
            errorMessage = Constants.pleaseAddIngredients
            return false
        }
        if ingredients.allSatisfy({ ($0.quantity ?? 0) <= 0 }) {
            errorMessage = Constants.ingredientsCantBeZero
            return false
        }
        errorMessage = nil
        return true
    }
}

// MARK: - EditIngredientRow (ports EditViewController+TableView cell)

struct EditIngredientRow: View {
    @Binding var ingredient: Ingredient
    let unit: MeasurementUnit
    let onDelete: () -> Void

    @State private var editingText: String = ""
    @FocusState private var isFocused: Bool

    private var displayQty: String {
        let ml = ingredient.quantity ?? 0
        return unit == .ml ? String(format: "%.0f", ml)
                            : String(format: "%.2f", ml / 29.5735)
    }
    private var unitLabel: String { unit == .ml ? "ml" : "oz" }

    /// 1:1 port of UIKit `EditTableViewCell.xib` (rowHeight=48, cell
    /// 320×64, viewGlass y=6 h=52). Layout left-to-right:
    ///
    ///   • Delete button (`deleteImg` asset): 30×30 at x=20 (LEFT side)
    ///   • Ingredient name label: 14pt `appBlackColor`, x=55, w=106
    ///   • Quantity controls (right side, 130pt wide):
    ///       — Minus button (`newMinus` asset, `grayBorderColor` tint): 30×30
    ///       — Quantity field 11pt `mediumLightGrayColor` + unit label
    ///         11pt `mediumLightGrayColor`, total 70pt wide
    ///       — Plus button (`newPlus` asset, `grayBorderColor` tint): 30×30
    var body: some View {
        HStack(spacing: 0) {
            // Delete on the LEFT (xib `deleteImg` button at x=20, 30×30)
            Button(role: .destructive) {
                HapticService.light()
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Delete \(ingredient.name)")
            .padding(.leading, 20)

            // Name label — 14pt appBlackColor, leading=55-20=35 from delete
            Text(ingredient.name)
                .font(.system(size: 14))
                .foregroundStyle(Color("appBlackColor"))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)

            // Quantity controls — 130pt wide stack:
            HStack(spacing: 0) {
                // Minus button — 30×30, `grayBorderColor` tint.
                Button {
                    adjust(by: -10)   // UIKit maxIncrementDecrementValueForMl
                } label: {
                    Image(systemName: "minus.circle")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color("grayBorderColor"))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Decrease \(ingredient.name)")

                // Quantity field + unit — 70pt wide, both 11pt mediumLightGray.
                HStack(spacing: 4) {
                    TextField("", text: $editingText)
                        .keyboardType(unit == .ml ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .frame(width: 30)
                        .focused($isFocused)
                        .onChange(of: isFocused) { focused in
                            if focused { editingText = displayQty }
                            else { commitEdit() }
                        }
                        .onChange(of: editingText) { new in
                            if new.count > 5 { editingText = String(new.prefix(5)) }
                        }
                        // Re-sync after +/- mutations and ml↔oz preference
                        // changes so the textfield never displays a stale
                        // value (mirrors UIKit `tblIngredient.reloadData()`).
                        .onChange(of: ingredient.quantity) { _ in
                            if !isFocused { editingText = displayQty }
                        }
                        .onChange(of: unit) { _ in
                            if !isFocused { editingText = displayQty }
                        }
                    Text(unitLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                }
                .frame(width: 70)

                // Plus button — 30×30, `grayBorderColor` tint.
                Button {
                    adjust(by: +10)
                } label: {
                    Image(systemName: "plus.circle")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color("grayBorderColor"))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Increase \(ingredient.name)")
            }
            .padding(.trailing, 4)
        }
        .frame(height: 52)
        .background(editCellBackground)
        .overlay(editCellBorder)
        .onAppear { editingText = displayQty }
    }

    /// UIKit `applyCellGlassStyle()` from EditViewController.swift:
    ///   iOS 26+: addGlassEffect(cornerRadius: xlarge=20, alpha: 1.0)
    ///   Pre-26: roundCorners = pill(24), borderWidth=1, gradient [black@10%, white@10%],
    ///           borderColor = #F2F2F2
    @ViewBuilder
    private var editCellBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        } else {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.10), Color.white.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(Capsule().fill(Color.white.opacity(0.8)))
        }
    }

    @ViewBuilder
    private var editCellBorder: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        } else {
            Capsule()
                .stroke(Color(red: 0.949, green: 0.949, blue: 0.949), lineWidth: 1)
        }
    }

    /// Step + clamp logic — 1:1 with UIKit
    /// `Quantity.increase/decreaseQuantityByUnit`:
    ///   • Step ml: 10 (`maxIncrementDecrementValueForMl`)
    ///   • Floor:   5 ml (`minimumQtyDouble`)
    ///   • Ceiling: 750 ml (`maximumQuantityDoubleMLFor360`)
    ///   • Boundary snap: increase from 745→750 lands exactly on 750.
    private func adjust(by deltaMl: Double) {
        var q = ingredient.quantity ?? 0
        if deltaMl > 0 {
            q = (q + deltaMl > 750) ? 750 : q + deltaMl
        } else {
            q += deltaMl
            if q < 5 { q = 5 }
        }
        ingredient.quantity = q
    }

    private func commitEdit() {
        guard let v = Double(editingText) else {
            editingText = displayQty
            return
        }
        let ml = (unit == .oz) ? v * 29.5735 : v
        ingredient.quantity = max(5, min(750, ml))
        editingText = displayQty
    }
}
