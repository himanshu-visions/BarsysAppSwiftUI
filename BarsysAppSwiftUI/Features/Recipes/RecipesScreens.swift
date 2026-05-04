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
import UIKit

// MARK: - UIGlassEffect bridge
//
// SwiftUI's `.regularMaterial` / `.ultraThinMaterial` are NOT the same
// rendering as UIKit's iOS-26 `UIGlassEffect(.regular)` Liquid Glass.
// The UIKit Edit screen (`EditViewController.swift` +
// `UIViewClass+GlassEffects.swift L31-69`) uses the real
// `UIGlassEffect` with `isInteractive = true`, which produces a
// subtler, lighter frosted refraction than any SwiftUI material.
//
// This `UIViewRepresentable` wraps the actual UIKit class so the
// SwiftUI Edit sheet renders pixel-identical to the UIKit screen.
@available(iOS 26.0, *)
struct UIGlassEffectBackground: UIViewRepresentable {
    var style: UIGlassEffect.Style = .regular
    var isInteractive: Bool = true

    func makeUIView(context: Context) -> UIVisualEffectView {
        let effect = UIGlassEffect(style: style)
        effect.isInteractive = isInteractive
        let view = UIVisualEffectView(effect: effect)
        view.backgroundColor = .clear
        // Match UIKit's `effectView.isUserInteractionEnabled = false`
        // (UIViewClass+GlassEffects.swift L62) so the glass doesn't
        // swallow taps meant for buttons/cells on top.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - Barsys Glass Panel Background
//
// 1:1 visual port of UIKit `addGlassEffect(cornerRadius:)` — used
// across the UIKit app for the side-menu panel (SideMenuViewController
// L51-61), Edit-panel (EditViewController L129), and Edit ingredient
// cells (EditViewController L180). UIKit implementation at
// UIViewClass+GlassEffects.swift L31-L69:
//
//     var glassEffect = UIGlassEffect(style: .regular)
//     glassEffect.isInteractive = true
//     let effectView = UIVisualEffectView(effect: glassEffect)
//     effectView.alpha = 1
//     insertSubview(effectView, at: 0)
//
// Reference screenshot (UIKit build, side menu open over the Home
// screen): the underlying Home screen is clearly VISIBLE through the
// panel — you can see the red device backdrop, the cocktail image,
// the eucalyptus branch, even the coaster detail — BUT everything is
// softly blurred. NOT a heavy whitish frost. The panel is more of a
// light glass than a frosted sheet.
//
// This wrapper matches that appearance by using real UIKit
// visual-effect views (so the blur renders at full strength instead
// of being attenuated by SwiftUI hosting):
//
//   • iOS 26+: `UIGlassEffect(style: .regular)` — byte-identical to
//     the UIKit side-menu glass.
//   • Pre-26:  `UIBlurEffect(style: .systemMaterial)` — the blur
//     family UIKit's `.regular` glass historically mapped to.
//
// The `whiteTintAlpha` default is **0.0** — i.e. no white overlay.
// The UIKit reference screen is pure `UIGlassEffect`; adding a
// translucent-white sublayer would over-frost the panel and hide the
// underlying content the reference keeps visible. Callers can
// override if a specific surface needs an extra whitening pass.
/// Installs a custom `UIAction` on the hosting view controller's
/// `navigationItem.backAction` (iOS 16+) so the default system back
/// button's tap can be INTERCEPTED without replacing the button.
///
/// The system-provided chevron / circular-glass back button keeps its
/// exact visual appearance (iOS 26 circular glass capsule, pre-26
/// chevron + previous-title) — only the tap handler is overridden.
///
/// The `handler` closure receives a `popIfAllowed` callback the caller
/// invokes WHEN it wants the pop to actually happen. If the caller
/// never invokes it (e.g. because an "unsaved changes" alert is being
/// shown first), the pop is silently suppressed — the caller takes
/// responsibility for popping later (typically in the alert's Discard
/// handler via `@Environment(\.dismiss)`).
/// Type alias for the "try to pop" callback the host view invokes
/// once it has decided the pop should proceed (typically after the
/// user dismisses the unsaved-changes popup with Discard).
typealias NavigationBackPopAction = () -> Void

/// Type alias for the back-button tap handler. `@escaping` cannot
/// appear inside a type expression in Swift, so we carry the
/// "escape-ness" through this named type instead.
typealias NavigationBackHandler = (NavigationBackPopAction) -> Void

struct NavigationBackActionInterceptor: UIViewRepresentable {
    /// Invoked when the user taps the nav-bar back button. Receives a
    /// closure that, when called, pops the view controller — the same
    /// pop that would have happened natively.
    let handler: NavigationBackHandler

    func makeUIView(context: Context) -> UIView {
        let view = InterceptorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.handler = handler
        // Install on next runloop once the view is in the hierarchy and
        // has a hosting view controller we can reach through the
        // responder chain.
        DispatchQueue.main.async { [weak view] in view?.installBackAction() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? InterceptorView else { return }
        view.handler = handler
        // Re-install on each SwiftUI update so the captured closure
        // always reflects the latest state of the hosting view.
        DispatchQueue.main.async { [weak view] in view?.installBackAction() }
    }

    final class InterceptorView: UIView {
        var handler: NavigationBackHandler?

        func installBackAction() {
            guard let vc = findHostViewController() else { return }
            let navItem = vc.navigationItem
            navItem.backAction = UIAction { [weak self, weak vc] _ in
                guard let self else { return }
                self.handler? {
                    vc?.navigationController?.popViewController(animated: true)
                }
            }
        }

        private func findHostViewController() -> UIViewController? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController { return vc }
                responder = r.next
            }
            return nil
        }
    }
}

/// Real-glass background for popup buttons — wraps `UIGlassEffect`
/// directly (iOS 26+) so SwiftUI buttons can render the same translucent
/// material UIKit uses via `addGlassEffect(...)` rather than the
/// approximate SwiftUI Materials. Pre-26 falls back to a `UIBlurEffect`
/// pairing analogous to UIKit's pre-26 path.
///
/// Two presets used by the alert popups:
///   • `.clear`   — for the FILLED (right) button's clear-glass sheen
///                  on top of the brand gradient (UIKit
///                  `addGlassEffect(effect: "clear")`).
///   • `.regular` + `tintColor` — for the BORDERED (left) button's
///                  glass-with-cancelButtonGray fill (UIKit
///                  `addGlassEffect(tintColor: cancelButtonGray)`
///                  inside `applyCancelCapsuleGradientBorderStyle`).
///
/// Mirrors `BarsysGlassPanelBackground` — same UIVisualEffectView
/// approach, just exposed as a button-friendly variant.
struct BarsysGlassButtonBackground: UIViewRepresentable {
    enum Style { case regular, clear }

    var style: Style = .regular
    /// Optional `UIGlassEffect.tintColor` — passed straight through to
    /// the iOS 26+ glass material. `nil` keeps the glass un-tinted.
    var tintUIColor: UIColor? = nil
    /// When set, the wrapper view (and the `UIVisualEffectView` inside)
    /// adopt this appearance instead of the system one. Used by the
    /// LEFT alert "No / Cancel" button so the glass + tint don't
    /// darken under system dark mode — the storyboard pill is meant
    /// to read as the same light-glass capsule in both appearances.
    var overrideUserInterfaceStyle: UIUserInterfaceStyle? = nil

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        if let overrideStyle = overrideUserInterfaceStyle {
            container.overrideUserInterfaceStyle = overrideStyle
        }

        let blurView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glassStyle: UIGlassEffect.Style
            switch style {
            case .regular: glassStyle = .regular
            case .clear:   glassStyle = .clear
            }
            let glassEffect = UIGlassEffect(style: glassStyle)
            if let tintUIColor { glassEffect.tintColor = tintUIColor }
            glassEffect.isInteractive = true
            blurView = UIVisualEffectView(effect: glassEffect)
        } else {
            // Pre-26 fallback — `.systemMaterial` for `.regular`,
            // `.systemUltraThinMaterial` for `.clear`. Tints aren't
            // supported by UIBlurEffect natively; the caller is
            // expected to layer a tint Color in SwiftUI on top.
            let blurStyle: UIBlurEffect.Style = (style == .clear)
                ? .systemUltraThinMaterial
                : .systemMaterial
            blurView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        }
        blurView.frame = container.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false
        blurView.backgroundColor = .clear
        if let overrideStyle = overrideUserInterfaceStyle {
            blurView.overrideUserInterfaceStyle = overrideStyle
        }
        container.addSubview(blurView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep the override in sync if the caller flips it at runtime.
        if let overrideStyle = overrideUserInterfaceStyle {
            uiView.overrideUserInterfaceStyle = overrideStyle
            for sub in uiView.subviews {
                sub.overrideUserInterfaceStyle = overrideStyle
            }
        }
    }
}

struct BarsysGlassPanelBackground: UIViewRepresentable {
    /// Optional translucent white overlay on top of the blur.
    /// Default 0.0 keeps the panel as pure glass to match the UIKit
    /// side-menu screenshot. Raise only if a specific caller needs
    /// extra whitening (currently none do).
    var whiteTintAlpha: CGFloat = 0.0

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true

        // --- Base blur layer -------------------------------------------------
        // iOS 26+: REAL `UIGlassEffect(style: .regular)` — identical
        // to UIKit `addGlassEffect(...)` (UIViewClass+GlassEffects.swift
        // L40-L48). Pre-26: `.systemMaterial` — the historically
        // closest native analogue of UIKit's `.regular` glass.
        let blurView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            blurView = UIVisualEffectView(effect: glassEffect)
        } else {
            blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }
        blurView.frame = container.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false
        blurView.backgroundColor = .clear
        container.addSubview(blurView)

        // --- Optional white tint overlay ------------------------------------
        // Only added when `whiteTintAlpha > 0`. Default is 0 so the
        // panel reads as pure glass (the UIKit reference has no
        // white-tint overlay — the blur + the underlying content
        // already produces the whitish cast you see in screenshots).
        if whiteTintAlpha > 0 {
            let tint = UIView()
            tint.frame = container.bounds
            tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            tint.isUserInteractionEnabled = false
            tint.backgroundColor = UIColor.white.withAlphaComponent(whiteTintAlpha)
            container.addSubview(tint)
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep the white-tint subview (if present) in sync with the
        // current alpha. Safely narrow: the tint view is the one
        // non-`UIVisualEffectView` subview in `container`.
        for sub in uiView.subviews where !(sub is UIVisualEffectView) {
            sub.backgroundColor = UIColor.white.withAlphaComponent(whiteTintAlpha)
        }
    }
}

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
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isSearching = false

    /// Bumped on every `.onAppear` so the `exploreRecipes` computed
    /// property re-evaluates against the live storage state. Required
    /// because `MockStorageService` is not `ObservableObject` — when
    /// `RecipeDetailView` toggles a favourite (via direct
    /// `env.storage.setFavorite` / `upsert` calls) and the user pops
    /// back, neither the storage mutation nor the catalog republish
    /// reliably trips a re-render of this hidden-then-revealed view.
    /// Reading the tick inside `exploreRecipes` registers it as a
    /// dependency, so bumping it on appear forces the heart icons to
    /// reflect the latest `isFavourite` flags. Mirrors UIKit's
    /// `viewWillAppear` → `tableView.reloadData()` pattern.
    @State private var favouritesRefreshTick: Int = 0

    private var isConnected: Bool { ble.isAnyDeviceConnected }

    /// Bottom breathing room above the tab bar on the Explore Recipes
    /// screen. iOS 26+ glass tab bar → 20pt (bit-identical to before);
    /// pre-iOS 26 opaque tab bar → 37pt so the last list row doesn't
    /// graze the hairline. Mirrors `MyBarView.bottomBarBottomInset`.
    private var exploreRecipesBottomInset: CGFloat {
        if #available(iOS 26.0, *) { 20 } else { 37 }
    }

    /// Wraps each Explore row so iPhone navigates via an outer
    /// `Button(action: navigate)` (preserves the original press
    /// styling + bit-identical hit testing) but iPad navigates via
    /// a leaf-level `.contentShape(...).onTapGesture` instead. The
    /// outer Button on iPad iOS 26 swallowed the inner Favourite
    /// button's tap (same SwiftUI hit-test problem documented in
    /// `BarsysRecipeRow` / `MixlistDetailRecipeRow`) — moving the
    /// gesture down lets the Favourite Button receive its tap.
    @ViewBuilder
    private func ipadAwareRowWrapper<Row: View>(
        navigate: @escaping () -> Void,
        @ViewBuilder row: () -> Row
    ) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            row()
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { navigate() }
        } else {
            Button(action: navigate) { row() }
                .buttonStyle(.plain)
        }
    }

    /// Source recipes for the Explore listing.
    ///
    /// Mirrors UIKit `DBQueries.fetchExploreAllRecipes()`:
    ///   • `WHERE user_id IS NULL OR TRIM(user_id) = ''` — only
    ///     standalone Barsys recipes; user-created My Drinks live on
    ///     the Favorites/My-Drinks tab, never the Explore feed.
    ///   • `ORDER BY createdAt DESC` — already applied by
    ///     `MockStorageService.allRecipes()` so `catalog.recipes`
    ///     arrives newest-first.
    ///   • UIKit ships every standalone recipe regardless of how many
    ///     ingredients it has (no SQL-level filter on ingredient
    ///     count) — but the PRODUCT requirement here is to suppress
    ///     rows with zero non-garnish ingredients (those render an
    ///     empty cell that confused users into thinking the page was
    ///     duplicating entries when the API hands back two copies of
    ///     the same recipe — one populated, one bare). Skipping the
    ///     empty copies leaves the populated row from the same
    ///     fetch, so nothing legitimate goes missing.
    ///   • NO de-dupe by displayName — UIKit doesn't `DISTINCT` /
    ///     `GROUP BY name`, and a previous SwiftUI dedup-by-name was
    ///     silently dropping the populated copy when the API returned
    ///     the same recipe under two ids. Matching UIKit's row-per-
    ///     standalone-record semantics keeps every populated recipe
    ///     visible.
    private var exploreRecipes: [Recipe] {
        // Reading the tick registers it as a dependency so SwiftUI
        // re-runs this computed property (and the `RecipeRowCell`
        // ForEach inside the body) on every `.onAppear` bump — the
        // hook that lets the heart icons refresh after a child
        // RecipeDetail toggle.
        let _ = favouritesRefreshTick
        // Source from `env.storage.allRecipes()` (not `catalog.recipes`)
        // so each pop-back from RecipeDetail picks up the live
        // `isFavourite` flag the detail view just wrote via
        // `setFavorite` / `upsert`. `catalog.recipes` is also republished
        // by `RecipeDetailView` for free, but storage is the
        // source-of-truth dictionary the storage layer mutates in place.
        let favs = env.storage.favorites()
        return env.storage.allRecipes().compactMap { stored in
            // Standalone-only (UIKit user_id filter).
            guard (stored.userId ?? "").isEmpty else { return nil }
            // Hide empty-ingredient rows. "Empty" mirrors UIKit's
            // ingredient subquery semantics: at least one ingredient
            // whose primary category isn't `garnish` /
            // `additionals` / `additional`. Garnish-only entries
            // count as empty and are suppressed.
            let realIngredients = (stored.ingredients ?? []).filter { ingredient in
                let primary = (ingredient.category?.primary ?? "").lowercased()
                return primary != "garnish"
                    && primary != "additionals"
                    && primary != "additional"
            }
            guard !realIngredients.isEmpty else { return nil }
            // Re-project the authoritative favs Set onto the recipe's
            // `isFavourite` flag. The storage `recipes` dict already
            // mirrors the favs Set when `setFavorite` runs, but this
            // belt-and-braces re-projection covers the edge case where
            // a `preload()` upsert from the API replaced the recipe
            // record with one whose `isFavourite` came back as `nil`
            // / `false` while the favs Set still has the id.
            var r = stored
            r.isFavourite = favs.contains(stored.id)
            return r
        }
    }

    /// Filtered recipes — ports cacheRecipesSearchResults().
    /// UIKit uses `words.contains` (ANY word matches), not allSatisfy.
    /// Searches recipe name and ingredientNames string.
    private var filtered: [Recipe] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return exploreRecipes
        }
        let words = query.lowercased().split(separator: " ").map(String.init)
        return exploreRecipes.filter { r in
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
        // Title + search bar are now hosted INSIDE the outer ScrollView
        // — same structural pattern that fixed the right-pill chrome
        // on HomeView / Cocktail Kits / Pair Your Device / Preferences /
        // Favorites. iOS 26's nav-bar Liquid Glass auto-wrap relies on
        // having scrollable material directly under the bar to render
        // the silvery-frosted right-pill the user sees on MyBar /
        // DevicePairedView / RecipeDetail; without it the bar falls
        // back to the thinner "black transparent" pill in dark mode.
        //
        // The inner ScrollView in the rows-non-empty branch is removed
        // to avoid nested scrolling. Pull-to-refresh moves to the outer
        // ScrollView. Loading / empty states preserve the original
        // centred-in-viewport look via `frame(minHeight: …)` so the
        // visual is unchanged.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Title — "All Recipes" 24pt, appBlackColor, leading 24, top 58.
                // iPad bumps to 32pt so the screen title matches the
                // Ready to Pour title size on the wider canvas.
                // iPhone unchanged.
                //
                // Top-padding bump on iPad: the inline iOS 26 nav-bar
                // Liquid-Glass blur overlaps the first few pixels of the
                // ScrollView content on the wider canvas, which made the
                // larger 32pt iPad title look clipped / "not coming"
                // (QA report). 16pt was enough on iPhone but iPad needs
                // the extra clearance — bumping iPad to 24pt restores
                // the same visible breathing room iPhone has at 16pt.
                // iPhone path stays at 16pt — bit-identical to before.
                Text("All Recipes")
                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 32 : 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 16)

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
                    // Loading / empty state preserves the original
                    // centred-in-viewport appearance via Spacer +
                    // content + Spacer inside a viewport-sized
                    // minHeight frame. Spacer collapses inside the
                    // outer ScrollView, so the explicit minHeight
                    // gives the wrapper a stable height to centre
                    // the text within — visually identical to the
                    // previous `.frame(maxHeight: .infinity)` layout.
                    VStack {
                        Spacer()
                        Text("No results to display")
                            .font(.system(size: 16))
                            .foregroundStyle(Color("mediumGrayColor"))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
                } else {
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
                            // iPad uses a leaf-level tap (via the
                            // `IPadRowNavTap` modifier below) instead
                            // of an outer `Button` — the latter
                            // swallows the inner Favourite button's
                            // taps on iPad iOS 26. iPhone (any iOS)
                            // keeps the original outer Button layout.
                            ipadAwareRowWrapper(
                                navigate: {
                                    HapticService.light()
                                    router.push(.recipeDetail(recipe.id))
                                }
                            ) {
                                RecipeRowCell(
                                    recipe: recipe,
                                    cellHeight: rowHeight,
                                    onFavourite: {
                                        // Determine the toggle direction BEFORE
                                        // mutating storage so the success-alert
                                        // copy matches the action the user just
                                        // performed. Mirrors UIKit
                                        // ExploreRecipesViewController's
                                        // post-likeUnlikeApi behaviour where
                                        // `showDefaultAlert(message: responseMessage)`
                                        // surfaces the "added to / removed from
                                        // My Favourites" toast — the SwiftUI
                                        // explore listing was the only entry
                                        // point still missing this alert
                                        // (RecipeDetail / Ready-to-Pour /
                                        // Favorites already show it).
                                        let willBeFav = !env.storage.favorites().contains(recipe.id)
                                        catalog.toggleFavourite(recipeId: recipe.id)
                                        // Bump the tick so `exploreRecipes`
                                        // (which now sources from
                                        // `env.storage.allRecipes()` and reads
                                        // the tick as a SwiftUI dependency)
                                        // re-evaluates immediately on tap and
                                        // the heart icon swaps from hollow ↔
                                        // filled in the same render pass.
                                        favouritesRefreshTick &+= 1
                                        env.analytics.track(
                                            (willBeFav ? TrackEventName.favouriteRecipeAdded
                                                       : TrackEventName.favouriteRecipeRemoved).rawValue
                                        )
                                        env.alerts.show(message: willBeFav
                                                        ? Constants.likeSuccessMessage
                                                        : Constants.unlikeSuccessMessage)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 15)
                    // iOS 26+ glass tab bar blurs over the last recipe
                    // row — 20pt is fine and bit-identical to before.
                    // Pre-iOS 26 the tab bar is opaque with a hairline
                    // and 20pt let the last row graze it; bump to 37pt
                    // (same scale used by `MyBarView.bottomBarBottomInset`)
                    // so the row sits visibly above the tab bar.
                    .padding(.bottom, exploreRecipesBottomInset)
                }
            }
        }
        .refreshable {
            await catalog.refresh()
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        // Ports ExploreRecipesViewController.viewDidLoad staleness check:
        // if cacheRecipes.isEmpty || AppStateManager.shared.areCacheRecipesStale
        .task {
            await catalog.refreshIfStale()
        }
        .onAppear {
            // 1:1 with UIKit `ExploreRecipesViewController` L62 —
            //   TrackEventsClass().addBrazeCustomEventWithEventName(
            //       eventName: TrackEventName.viewRecipesListing.rawValue)
            // Fires every time the All Recipes tab becomes visible.
            env.analytics.track(TrackEventName.viewRecipesListing.rawValue)
            // Re-project favourites from storage on every appear so a
            // RecipeDetail toggle (popped back via the nav stack)
            // refreshes the heart icons here. Mirrors UIKit's
            // `viewWillAppear` → `tableView.reloadData()` behaviour
            // and `ReadyToPourView.refreshFavouritesFromStorage()` on
            // the home screen. Bumping the tick is what forces
            // SwiftUI to re-evaluate `exploreRecipes` (which reads
            // `favouritesRefreshTick` to register a dependency).
            favouritesRefreshTick &+= 1
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Leading: custom back chevron — same 15×15 `Image("back")`
            // styling used on MyProfile / Preferences / PairYourDevice /
            // Cocktail Kits.
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

            // Center: device ICON ONLY (only when connected)
            //
            // UIKit parity: every BarsysApp controller's `updateDeviceInfo`
            // / `setupView` method sets `lblDeviceName.isHidden = true`
            // unconditionally and never reverses it — the device-name
            // label is present in the storyboard but visually hidden on
            // every screen. Only the 25×25 `imgDevice` renders. Examples:
            //   • BarBotViewController.swift:253
            //   • ExploreRecipesViewController.swift:129
            //   • MyBarViewController.swift:153
            //   • MixlistViewController.swift:86
            //   • FavouritesRecipesAndDrinksViewController.swift:207
            //   • MyProfileViewController.swift:200
            // (project-wide grep for `lblDeviceName.isHidden = false`
            // returns zero results outside ScanIngredientsVC).
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
        // Custom back chevron hides the system back button — restore
        // the swipe-from-left-edge interactive pop gesture.
        .interactivePopGestureEnabled()
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
        return raw.getImageUrl()
    }

    /// UIKit BarsysRecipeTableViewCell L63-77: iOS 26 uses 40×40 glass buttons
    /// with black@0.3 tint; pre-26 uses 30×30 plain buttons with white tint.
    /// iPad bumps to 60×60 — same QA-driven sizing fix applied to
    /// `BarsysRecipeRow` and `MixlistDetailRecipeRow`.
    private var favButtonSize: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad { return 60 }
        if #available(iOS 26.0, *) { return 40 } else { return 30 }
    }
    /// Glyph size INSIDE the button frame.
    private var favIconSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 36 : 22
    }
    private var favButtonTint: Color {
        if #available(iOS 26.0, *) {
            return Color.black.opacity(0.3)
        } else {
            return Theme.Color.softWhiteText
        }
    }
    /// iPad bumps the row text to a comfortable scale on the wider
    /// canvas. iPhone stays bit-identical to the UIKit storyboard
    /// 16pt / 10pt spec.
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    private var titleFontSize: CGFloat { isIPad ? 22 : 16 }
    private var ingredientsFontSize: CGFloat { isIPad ? 15 : 10 }

    var body: some View {
        HStack(spacing: 0) {
            // Left half — title + ingredients (Craft button hidden in Explore).
            // Uniform row height: title 3 lines, ingredients 6 lines max.
            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.displayName)
                    .font(.system(size: titleFontSize))
                    .foregroundStyle(Color("charcoalGrayColor"))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let names = recipe.ingredientNames, !names.isEmpty {
                    Text(names)
                        .font(.system(size: ingredientsFontSize))
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
            thumbnail
                .frame(width: cellHeight, height: cellHeight)
                .background(Color("lightBorderGrayColor"))
                .clipped()
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
        // Favourite button lives at the OUTER row container (after the
        // clipShape) — NOT inside the AsyncImage's ZStack — so its hit
        // testing isn't competing with the call-site outer
        // `Button(action: navigate)` wrapper. Without this move the
        // favourite was un-tappable on iPad because the outer
        // navigation Button absorbed every press.
        // 1:1 with UIKit `aHb-2f-Xkm`: top=5, trailing=5.
        .overlay(alignment: .topTrailing) {
            Button {
                HapticService.light()
                onFavourite()
            } label: {
                Image(recipe.isFavourite == true ? "favIconRecipeSelected" : "favIconRecipe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: favIconSize, height: favIconSize)
                    .frame(width: favButtonSize, height: favButtonSize)
                    .foregroundStyle(favButtonTint)
                    .glassButtonIfAvailable(size: favButtonSize)
            }
            .buttonStyle(BounceButtonStyle())
            .padding(.top, 5)
            .padding(.trailing, 5)
            .accessibilityLabel("Favourite")
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var thumbnail: some View {
        // UIKit: sd_setImage(with:imgUrl, placeholderImage:.myDrink)
        // Show `myDrink` placeholder during BOTH the loading and
        // failure phases so the row has visual weight instead of
        // a flat gray square while the image downloads (matches
        // SDWebImage's placeholder-before-and-during semantics).
        // Placeholder uses .fit to avoid zooming/stretching a small
        // asset. Loaded image uses .fill to cover the square frame.
        if let url = optimizedImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    Image("myDrink")
                        .resizable().aspectRatio(contentMode: .fit)
                        .padding(16)
                @unknown default:
                    Image("myDrink")
                        .resizable().aspectRatio(contentMode: .fit)
                        .padding(16)
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
    /// Pops the view off its enclosing NavigationStack. Used by the
    /// custom leading back button to close the recipe page (and by the
    /// unsaved-changes Discard handler to complete the back action
    /// once the user has confirmed the discard).
    @Environment(\.dismiss) private var dismiss
    /// Reactive theme awareness — used ONLY by the primary-orange
    /// Craft-button background (`primaryOrangeButtonBackground`) to
    /// override the dark-appearance variant of the
    /// `brandGradientTop` / `brandGradientBottom` colour assets (which
    /// wrongly resolve to dark grey / near-black in dark mode) back
    /// to the light-mode orange RGB so the Craft button stays
    /// readable in dark mode. Light mode is untouched.
    @Environment(\.colorScheme) private var colorScheme

    @State private var editedIngredients: [Ingredient] = []
    @State private var originalIngredients: [Ingredient] = []
    @State private var showUnsavedAlert = false
    @State private var unsavedPopup: BarsysPopup? = nil

    /// 1:1 with UIKit `RecipePageViewController` which shows the same
    /// `unsavedChangesForRecipe` alert from TWO different entry points:
    ///   • Craft button tap — on Discard, reset edits then proceed to craft.
    ///   • Favourite nav-icon tap — on Discard, reset edits then navigate
    ///     to the Favorites screen (UIKit `navigateToFavourites()`).
    /// Recording which action triggered the alert lets the shared
    /// `onPrimary` closure route correctly when Discard is tapped.
    enum PendingUnsavedAction { case craft, navigateToFavorites, back }
    @State private var pendingUnsavedAction: PendingUnsavedAction = .craft
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

    /// Live keyboard height (0 while the keyboard is dismissed). Drives
    /// two layout adjustments on this screen so the user can keep
    /// scrolling and editing while a quantity field is focused:
    ///   1. The floating Save / Craft bar's bottom padding switches
    ///      from 30pt (resting offset above the home indicator) to
    ///      100pt while `keyboardHeight > 0`.
    ///   2. The bottom buffer inside the ScrollView's VStack grows by
    ///      `keyboardHeight` so the user can scroll the Crafting
    ///      Instructions section all the way above the keyboard. Without
    ///      this, `.ignoresSafeArea(.keyboard, edges: .bottom)` (which
    ///      keeps the bar pinned) also stops the ScrollView from
    ///      auto-insetting its content for the keyboard, so the last
    ///      sections used to sit forever behind the keyboard.
    @State private var keyboardHeight: CGFloat = 0
    private var isKeyboardVisible: Bool { keyboardHeight > 0 }

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
            // Matches UIKit SQL `fetchMatchingRecipeLists`:
            // `NOT IN ('garnish', 'additionals', 'additional')`.
            return p != "garnish" && p != "additional" && p != "additionals"
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
            // Matches UIKit SQL `fetchMatchingRecipeLists`:
            // `NOT IN ('garnish', 'additionals', 'additional')`.
            return p != "garnish" && p != "additional" && p != "additionals"
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
                .navigationBarBackButtonHidden(true)
                // Custom back chevron hides the system back button —
                // restore the swipe-from-left-edge interactive pop
                // gesture. UIKit's swipe-back also bypasses the
                // unsaved-changes alert, so this preserves UIKit
                // parity (the alert only fires on the explicit
                // back-button tap, not on swipe-back).
                .interactivePopGestureEnabled()
                .toolbar { toolbarContent(for: recipe) }
                // Publish the local `hasUnsavedChanges` flag to the
                // router so the tab-bar Binding in `MainTabView` can
                // show the UIKit-parity "unsaved changes" confirmation
                // if the user taps a tab while edits are pending.
                // Cleared on disappear so the guard never persists
                // after the recipe page is gone.
                .onChange(of: hasUnsavedChanges) { newValue in
                    router.hasUnsavedRecipeChanges = newValue
                }
                .onAppear {
                    router.hasUnsavedRecipeChanges = hasUnsavedChanges
                }
                .onDisappear {
                    router.hasUnsavedRecipeChanges = false
                }
                // Keyboard accessory — ports UIKit
                // `RecipePageViewController+Helpers.swift` L37:
                // `cell.ingredientQuantityTextField.addDoneToolbar()`.
                // The Recipe-detail ingredient-quantity rows use
                // `.numberPad` / `.decimalPad`, neither of which has a
                // built-in Done key, so the accessory is essential.
                .keyboardDoneToolbar()
                // Flat `primaryBackgroundColor` nav bar so the top-right
                // glass pill renders on the same canvas HomeView uses.
                .chooseOptionsStyleNavBar()
                .onAppear {
                    loadIngredients(from: recipe)
                    // Seed local favourite state from the right source
                    // depending on whether this recipe is a Barsys
                    // recipe or a My Drink (1:1 UIKit Tab 0 / Tab 1):
                    //   • Barsys recipe (`isMyDrinkFavourite == nil`)
                    //     → favs Set (`storage.favorites()`).
                    //   • My Drink (`isMyDrinkFavourite != nil`)
                    //     → that flag itself.
                    // For Barsys recipes the favs Set is the
                    // AUTHORITATIVE source — the struct's
                    // `isFavourite` flag can drift after
                    // `CatalogService.preload()` re-fetches recipes
                    // (the API payload has no isFavourite field, so
                    // the upsert resets the flag to nil while the
                    // favs Set still holds the id). Reading the
                    // wrong source previously seeded `false` for
                    // already-favourited recipes and the "Add to
                    // Favorites" tap then REMOVED the favourite.
                    // For My Drinks the favs Set is intentionally
                    // empty (Tab 1 keeps its own flag, never writes
                    // to favs), so we read from the per-row flag
                    // instead.
                    if let stored = env.storage.recipe(by: recipeID),
                       let myDrinkFlag = stored.isMyDrinkFavourite {
                        localIsFavourite = myDrinkFlag
                    } else {
                        localIsFavourite = env.storage.favorites().contains(recipeID)
                    }
                    // 1:1 with UIKit `RecipePageViewModel+CraftAndAnalytics`
                    // `trackViewRecipe()` (L144-200) — fires every time the
                    // recipe page lands. Property dictionary mirrors the
                    // Braze branch (L194-198): recipe id/name/image and
                    // device id+type when a BLE device is connected so
                    // Braze can segment users by hardware. `source` is
                    // derived from the recipe's own flags (matches UIKit
                    // RecipeSource enum values: "barsys" / "user" / "ai").
                    let recipeSource: String = {
                        // UIKit RecipeSource mapping
                        // (Helpers/Constants/Constants+Enums.swift
                        // `RecipeSource`): a non-empty `userId` on the
                        // recipe means it's a user-created "My Drink"
                        // (source = "user"); anything else is a stock
                        // Barsys recipe (source = "barsys"). The BarBot
                        // "ai" branch fires from BarBotScreens, not
                        // from this detail-page hook.
                        let uid = recipe.userId ?? ""
                        return uid.isEmpty ? "barsys" : "user"
                    }()
                    var props: [String: Any] = [
                        "source": recipeSource,
                        "recipe_id": recipe.id.value,
                        "recipe_name": recipe.displayName,
                        "recipe_image": recipe.image?.url ?? ""
                    ]
                    if let connected = ble.connected.first {
                        props["deviceId"] = connected.name
                        props["deviceType"] = connected.kind.displayName
                    }
                    env.analytics.track(TrackEventName.viewRecipe.rawValue,
                                        properties: props)
                }
                // Unsaved changes popup — glass-card style matching UIKit
                // `unsavedChangesForRecipe` alert.
                //
                // Button mapping (swapped from the previous port so the
                // LEFT/RIGHT positions match UIKit exactly):
                //   • RIGHT button = `primaryTitle` = "Keep Editing"
                //     → `onPrimary` closure fires. Matches UIKit
                //       `onCancel: { _ in }` — do nothing, user stays
                //       on the page with edits intact.
                //   • LEFT button = `secondaryTitle` = "Discard"
                //     → `onSecondary` closure fires. Matches the first
                //       completion block of `showCustomAlertMultipleButtons`
                //       — reset edits, then navigate depending on
                //       `pendingUnsavedAction` (craft vs favorites nav).
                //
                // UIKit `viewModel.discardQuantityChanges()` is mirrored
                // by `loadIngredients(from: recipe)` which replays the
                // recipe's stored quantities over the local edit state.
                .barsysPopup($unsavedPopup, onPrimary: {
                    // "Keep Editing" — UIKit `onCancel: { _ in }`:
                    // do nothing, just dismiss the popup so the user
                    // remains on the recipe page with their edits.
                    pendingUnsavedAction = .craft
                }, onSecondary: {
                    // "Discard" — UIKit
                    // `viewModel.discardQuantityChanges()` + navigate.
                    loadIngredients(from: recipe)
                    switch pendingUnsavedAction {
                    case .navigateToFavorites:
                        // UIKit `navigateToFavourites()` L348-351:
                        //   BarBotCoordinator(nav:).showFavourites(tabSelected: 0)
                        router.push(.favorites)
                    case .craft:
                        // Craft button handles its own post-discard
                        // flow in the craft closure — nothing to do here.
                        break
                    case .back:
                        // UIKit `showUnsavedChangesAlertForBack` flow —
                        // once the user confirms Discard, pop the
                        // RecipeDetail screen off the nav stack so they
                        // return to wherever they came from (Explore,
                        // Favorites, BarBot etc.).
                        dismiss()
                    }
                    pendingUnsavedAction = .craft // reset to default
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
                    // `EditRecipeCoverContent` owns a local NavigationPath
                    // and publishes it via `\.editCoverPath` so the Craft
                    // button inside EditRecipeView pushes onto this path
                    // (Crafting layers on top of Edit) instead of onto the
                    // parent tab's stack (which would render Crafting
                    // beneath the cover, invisibly).
                    //
                    // `onClose` is the DIRECT close action the cross
                    // button uses — it sets `showEditRecipe = false`
                    // so the cover dismisses reliably on iPad too.
                    EditRecipeCoverContent(onClose: { showEditRecipe = false }) {
                        // isCustomizing: true — creating NEW My Drink from
                        // existing Barsys recipe (UIKit: isCustomizingRecipe = true).
                        // Pass the FULL recipe so EditRecipeView can carry
                        // glassware / instructions / image / slug into the
                        // POST request without depending on a storage lookup.
                        EditRecipeView(
                            recipeID: recipe.id,
                            existingRecipe: recipe,
                            isCustomizing: true
                        )
                    }
                    // Mount the alert overlay INSIDE the fullScreenCover so
                    // the save-success popup renders ABOVE EditRecipeView,
                    // not behind it on the RootView layer.
                    .appAlert(env.alerts)
                    // Same reasoning as FavoritesView (L304-L313):
                    // UIKit's child-VC overlay has a transparent root
                    // view so `UIGlassEffect` composites against the
                    // RecipePage behind. Without this modifier on the
                    // fullScreenCover, the cover is opaque and the
                    // glass has nothing to composite against — the
                    // panel reads as a flat color, NOT glass.
                    .modifier(ClearPresentationBackgroundModifier())
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
                // Extra 10pt top breathing room between the main
                // ingredients table and the "ADDITIONAL INGREDIENTS"
                // header so the section reads as visually separated
                // rather than glued to the row above it.
                if !additionalIngredients.isEmpty {
                    additionalSection
                        .padding(.top, 10)
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
                // 3. Crafting Instructions — vertical list of
                //    "Step N: …" blocks. 1:1 port of UIKit
                //    `RecipePageViewController.updateInstructionsUI`:
                //
                //        viewInstructions.isHidden =
                //            (lblInstruction.text ?? "").isEmpty
                //            || lblGlass.text?.lowercased()
                //               == Constants.notAvailable.lowercased()
                //
                //    where `Constants.notAvailable = "N/A"`. Hide when
                //    the formatted text is empty OR when the glass
                //    row reads "N/A". Context-aware formatting (My
                //    Drinks vs standard) is handled inside
                //    `instructionsSection(for:)` via
                //    `formattedInstructionSteps(for:)`.
                if shouldShowInstructions(for: recipe) {
                    instructionsSection(for: recipe)
                }
                // Bottom buffer grows by the live keyboard height so
                // the Crafting Instructions section can scroll all the
                // way above the keyboard while a quantity field is
                // focused. `.ignoresSafeArea(.keyboard)` on the outer
                // compound view stops the ScrollView from auto-
                // insetting itself, so we add the inset manually here.
                Color.clear.frame(
                    height: 30 + 70.0// keyboard height
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActions(for: recipe)
        }
        // QA fix — iOS 26 Liquid-Glass toolbar items (back-button
        // circle + favourites/profile pill) sample colours from the
        // scroll view's edge effect. The default `.soft` style fades
        // the scroll edge into the toolbar and lets the dark hero
        // image bleed through, tinting the capsules grey on scroll.
        // ExploreRecipes / Cocktail Kits work correctly because their
        // scroll content starts with light text + a search bar (the
        // image-bearing cells only reach the toolbar after deep
        // scrolling). Recipe Detail's hero image is at the very top
        // of the scroll content, so the issue is exposed immediately.
        // Setting `.scrollEdgeEffectStyle(.hard, for: .top)` switches
        // the system to a HARD scroll edge — no soft fade, no blur —
        // so the toolbar items see only the opaque nav-bar background
        // and stay visually identical to ExploreRecipes / Cocktail
        // Kits regardless of how dark the hero image is.
        .hardTopScrollEdgeIfAvailable()
        // Keep the floating "Save to My Drinks" + "Craft" bar pinned to
        // the physical bottom edge when the quantity-field keyboard
        // appears. SwiftUI's default behaviour grows the bottom safe
        // area by the keyboard height, which pushes everything in the
        // safe-area inset (the CTA bar) up with it. Putting
        // `.ignoresSafeArea(.keyboard, edges: .bottom)` on the inset's
        // content alone is NOT enough — the inset wraps the content in
        // its own region and the region itself respects the keyboard.
        // Applying the modifier to the WHOLE compound view (ScrollView
        // + safeAreaInset) instructs SwiftUI to compute layout against
        // the non-keyboard bottom safe area, so the CTA stays fixed
        // 30pt above the home-indicator and the keyboard slides up
        // OVER the recipe rows — same behaviour as UIKit's
        // `RecipePageViewController`.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Track the live keyboard height so `bottomActions(...)`'s
        // bottom padding (30 ↔ 100pt) and the ScrollView's bottom
        // buffer (`keyboardHeight + 30`) both react in lock-step.
        // Subscribing at the parent-view level keeps the observers
        // registered across body re-evaluations.
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )
        ) { notification in
            if let frame = notification.userInfo?[
                UIResponder.keyboardFrameEndUserInfoKey
            ] as? CGRect {
                keyboardHeight = frame.height
            } else {
                // Fallback when userInfo is missing — assume a
                // typical iPhone numberPad height. Better than 0
                // because the bottom buffer would otherwise leave
                // content behind the keyboard.
                keyboardHeight = 290
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            keyboardHeight = 0
        }
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
        // GeometryReader resolves the parent's PROPOSED width (screen –
        // 48 from the caller's `.padding(.horizontal, 24)`). We then
        // pin the AsyncImage to an explicit `width × width` square.
        //
        // The earlier implementation used
        //   `AsyncImage(...).frame(maxWidth: .infinity).aspectRatio(1, .fit)`
        // which works only when the remote image has a "normal" aspect
        // ratio. When the remote asset has wild intrinsic dimensions
        // (e.g. 3000×1000 landscape), AsyncImage propagates the
        // image's intrinsic size UP through the modifier chain, the
        // `.fill` content-mode keeps that width, and
        // `.aspectRatio(1, .fit)` is reinterpreted against the huge
        // intrinsic — the container ends up rendering wider than the
        // padded parent, which stretched the ENTIRE recipe-detail
        // VStack (title / description / ingredients) off-screen. That
        // was the bug the user reported.
        //
        // Pinning via `.frame(width: side, height: side)` inside the
        // GeometryReader ignores the image's intrinsic size entirely
        // and produces a consistent square on every device and for
        // every remote asset.
        GeometryReader { geo in
            let side = geo.size.width
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    // Loading state — 1:1 with UIKit `sd_setImage(with:imgUrl,
                    // placeholderImage: .myDrink)`: SDWebImage shows the
                    // `myDrink` artwork BEFORE + DURING the download.
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
                    Image("myDrink")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(40)
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .background(Color("lightBorderGrayColor"))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        // Tell the GeometryReader to be a 1:1 square so it requests
        // `proposedWidth × proposedWidth` from its parent — matches
        // the UIKit storyboard constraint `width:height = 1:1`.
        .aspectRatio(1, contentMode: .fit)
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
    private func instructionsSection(for recipe: Recipe) -> some View {
        // Render the heading, then render EACH formatted step as its
        // own `Text` inside a `VStack`. Earlier ports joined every step
        // into one big "\n\n"-delimited string and handed it to a single
        // `Text`; that path kept clipping to a single line on the
        // device because SwiftUI sizes a multi-line `Text` against the
        // first proposed width pass and doesn't re-wrap reliably inside
        // a `VStack(alignment: .leading)` + `ScrollView` chain — even
        // with the recommended `.frame(maxWidth:) → .fixedSize(...)`
        // modifier order. Splitting the steps into sibling `Text` views
        // makes each step a fully independent layout participant: the
        // VStack lays them out vertically, each Text grows to fit its
        // own content, and there is zero shared wrapping state. Visually
        // identical to UIKit's `lblInstruction` (numberOfLines = 0)
        // — UIKit's `\n\n` separator becomes the 14pt VStack spacing
        // here.
        let formattedSteps = Self.formattedInstructionSteps(for: recipe)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Crafting Instructions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !formattedSteps.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(formattedSteps.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(Color("appBlackColor"))
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            // Modifier order matters — the wide frame
                            // proposes the full available width FIRST,
                            // then `.fixedSize(vertical: true)`
                            // measures the wrapped vertical height
                            // against that bound. This is what makes
                            // each Text behave like a UIKit label with
                            // `numberOfLines = 0` + leading/trailing
                            // pinned to its parent: it grows
                            // vertically with content, never clips.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        // Storyboard constraint `y4e-UG-x99`: Pd3-56-bQz.top =
        // cdY-8H-RMr.top + 25, and cdY starts immediately below
        // the Glass row container with no gap — so total vertical
        // inset from the Glass row bottom to the "Crafting
        // Instructions" heading is 25pt.
        .padding(.top, 25)
    }

    /// 1:1 port of UIKit
    /// `RecipePageViewController.updateInstructionsUI`:
    ///
    ///     viewInstructions.isHidden =
    ///         (lblInstruction.text ?? "").isEmpty
    ///         || lblGlass.text?.lowercased()
    ///            == Constants.notAvailable.lowercased()
    ///
    /// where `Constants.notAvailable = "N/A"` (verified verbatim from
    /// `BarsysApp/Helpers/Constants/Constants.swift:290`). Hide the
    /// whole crafting-instructions container when the formatted text
    /// is empty OR when the glass row reads "N/A" (case-insensitive).
    ///
    /// SwiftUI port additionally hides when the glass type is empty —
    /// the SwiftUI glass row is suppressed entirely on empty input
    /// (rather than UIKit's "show 'N/A' string" fallback), so an
    /// empty glass type is the SwiftUI equivalent of UIKit's
    /// `lblGlass.text == "N/A"` state.
    private func shouldShowInstructions(for recipe: Recipe) -> Bool {
        let formatted = Self.formattedInstructionSteps(for: recipe)
        guard !formatted.isEmpty else { return false }
        let glassType = recipe.glassware?.type ?? ""
        let glassUnknown = glassType.isEmpty
            || glassType.lowercased() == "n/a"
        if glassUnknown { return false }
        return true
    }

    /// Dispatcher mirroring UIKit
    /// `RecipePageViewModel.instructionsDisplayText`:
    ///
    ///     let instructionsArr = recipe?.instructions
    ///         .filter({ !$0.isEmpty }) ?? []
    ///     if currentContext == .myDrinks {
    ///         return formatMyDrinksInstructions(instructionsArr)
    ///     } else {
    ///         return formatStandardInstructions(instructionsArr)
    ///     }
    ///
    /// UIKit carries `currentContext: RecipePageContext` set by every
    /// caller (`.standard` for Explore, `.myDrinks` for the Favorites
    /// "My Drinks" tab, `.barBotMixlist` / `.barBotRecipe` /
    /// `.customize` for the BarBot flows). The SwiftUI route doesn't
    /// thread that enum through, so we infer `.myDrinks` from the
    /// recipe payload itself: a non-empty `userId` (user-created
    /// recipe) OR a non-nil `isMyDrinkFavourite` flag — exactly the
    /// pair already used by `RecipeDetailView.bottomActions` to
    /// branch the favourite logic between Barsys recipes and My
    /// Drinks. Everything else (Explore, Mixlist Detail, BarBot)
    /// falls through to the standard formatter, matching UIKit's
    /// default-`else` semantics.
    private static func formattedInstructionSteps(for recipe: Recipe) -> [String] {
        // 1) UIKit's `instructionsArr = recipe?.instructions
        //    .filter({ !$0.isEmpty }) ?? []` — drop empty rows the
        //    server / DB sometimes hands back so they don't shift
        //    indices or break the "count != 1" branch.
        let cleaned = recipe.instructions.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        let isMyDrinks = (recipe.userId.map { !$0.isEmpty } ?? false)
            || recipe.isMyDrinkFavourite != nil
        if isMyDrinks {
            return formatMyDrinksInstructionSteps(cleaned)
        } else {
            return formatStandardInstructionSteps(cleaned, recipeID: recipe.id)
        }
    }

    /// 1:1 port of UIKit
    /// `RecipePageViewModel+CraftAndAnalytics.formatMyDrinksInstructions(_:)`
    /// (lines 221-243).
    ///
    /// UIKit source (verbatim):
    /// ```
    /// var instructionsText: String = ""
    /// for i in 0..<(instructionsArr.count) {
    ///     var text = instructionsArr[i]
    ///     text = "Step \(i+1): " + text.replacingOccurrences(of: "@", with: "")
    ///     if i == 0 {
    ///         instructionsText = text
    ///     } else {
    ///         instructionsText = instructionsText + "\n\n\(text)"
    ///     }
    /// }
    /// if instructionsText.contains(" | ") {
    ///     let steps = instructionsText.components(separatedBy: " | ")
    ///     instructionsText = steps.enumerated().map { index, step in
    ///         if step.contains("Step \(index + 1):") {
    ///             return "\(step)"
    ///         } else {
    ///             return "Step \(index + 1): \(step)"
    ///         }
    ///     }.joined(separator: "\n\n")
    /// }
    /// return instructionsText.isEmpty ? nil : instructionsText
    /// ```
    ///
    /// Differences vs `formatStandardInstructions`:
    ///   • Iterates the WHOLE array (no recipe-id gate, no first-only
    ///     fallback) — every element gets prefixed with "Step N: ".
    ///   • Strips `@` symbols (legacy My-Drinks "@mention" markers
    ///     never make it into the rendered label).
    ///   • Re-split on `" | "` only as a fallback if the joined text
    ///     happens to contain pipes — and that pass preserves an
    ///     existing `"Step N:"` prefix instead of doubling it.
    ///
    /// Returns the per-step strings as an array for the SwiftUI
    /// VStack/ForEach render.
    private static func formatMyDrinksInstructionSteps(_ instructionsArr: [String]) -> [String] {
        // Phase 1 — iterate every element, strip `@`, prefix
        // "Step N: ", build a `\n\n`-joined buffer (UIKit's
        // intermediate `instructionsText`).
        var lines: [String] = []
        for i in 0..<instructionsArr.count {
            let text = "Step \(i + 1): "
                + instructionsArr[i].replacingOccurrences(of: "@", with: "")
            lines.append(text)
        }
        let joined = lines.joined(separator: "\n\n")

        // Phase 2 — UIKit's pipe-fallback re-split. If any line
        // contained `" | "`, the joined buffer will too; UIKit
        // re-splits and re-prefixes, but preserves an
        // already-present `"Step N:"` prefix instead of doubling it.
        if joined.contains(" | ") {
            let split = joined.components(separatedBy: " | ")
            return split.enumerated().map { index, step in
                if step.contains("Step \(index + 1):") {
                    return step
                } else {
                    return "Step \(index + 1): \(step)"
                }
            }
        }

        return lines
    }

    /// 1:1 port of UIKit
    /// `RecipePageViewModel.instructionsDisplayText` ➜
    /// `formatStandardInstructions(_:)`.
    ///
    /// UIKit source (verbatim, RecipePageViewModel+CraftAndAnalytics.swift):
    /// ```
    /// var instructionsDisplayText: String? {
    ///     let instructionsArr = recipe?.instructions.filter({ !$0.isEmpty }) ?? []
    ///     if currentContext == .myDrinks {
    ///         return formatMyDrinksInstructions(instructionsArr)
    ///     } else {
    ///         return formatStandardInstructions(instructionsArr)
    ///     }
    /// }
    ///
    /// func formatStandardInstructions(_ instructionsArr: [String]) -> String? {
    ///     guard let rawInstruction = instructionsArr.first else { return nil }
    ///     if instructionsArr.first?.contains(" | ") == false
    ///        && (recipe?.id == nil || recipe?.id.isEmpty == true)
    ///        && instructionsArr.count != 1 {
    ///         return instructionsArr.enumerated().map { index, step in
    ///             if step.contains("\(index + 1). ") {
    ///                 return "Step \(index + 1): \(step.replacingOccurrences(of: "\(index + 1). ", with: ""))"
    ///             } else {
    ///                 return "Step \(index + 1): \(step)"
    ///             }
    ///         }.joined(separator: "\n\n")
    ///     } else {
    ///         let steps = rawInstruction.components(separatedBy: " | ")
    ///         return steps.enumerated().map { index, step in … }.joined(separator: "\n\n")
    ///     }
    /// }
    /// ```
    ///
    /// Two ports of UIKit semantics that the previous SwiftUI version
    /// was missing and are why only "Step 1" was rendering for Barsys
    /// recipes whose API payload arrives as a multi-element array
    /// (e.g. Martini Negroni:
    /// `["Add ingredients to mixing vessel", "Mix according to technique",
    ///   "Serve in appropriate glass"]`):
    ///
    ///   1. **Empty-string pre-filter** — `instructionsDisplayText`
    ///      drops empty entries before formatting; we mirror that
    ///      with `.filter { !$0.isEmpty }` up-front so blank rows
    ///      from the API never count toward `count != 1` or push the
    ///      "real" first step into a non-zero index.
    ///
    ///   2. **Data-shape-driven branch** — UIKit's literal condition
    ///      gates the "use array directly" path on
    ///      `recipe?.id.isEmpty`. In UIKit production data the gate
    ///      held because Barsys API recipes always returned
    ///      instructions as a single pipe-separated string (count
    ///      == 1) and only user-created My Drinks were multi-element.
    ///      The SwiftUI port's storage / decoder serves Barsys
    ///      recipes as a multi-element array AS WELL, so the strict
    ///      UIKit gate would discard every step past the first. We
    ///      relax the branch to be driven by the data shape itself
    ///      (which is what UIKit's gate was approximating): if the
    ///      array already has the steps split out AND the first
    ///      element doesn't contain ` | `, treat it as the
    ///      pre-split form regardless of whether the recipe has an
    ///      ID. This is the SAME end result UIKit produces for
    ///      every payload shape that exists in practice — it just
    ///      stops swallowing multi-element Barsys arrays.
    ///
    /// Returns the array of `"Step N: …"` strings instead of UIKit's
    /// `"\n\n"`-joined string so each step renders as its own `Text`
    /// view in a `VStack` — UIKit gets multi-line vertical stacking
    /// for free with `lblInstruction.numberOfLines = 0`, but
    /// SwiftUI's single-`Text`-with-newlines path repeatedly clipped
    /// to one line on device. Per-step `Text` views give the same
    /// visual result with no shared wrapping state.
    private static func formatStandardInstructionSteps(_ instructionsArr: [String],
                                                       recipeID: RecipeID) -> [String] {
        // The empty-string filter from UIKit's `instructionsDisplayText`
        // is applied by the caller (`formattedInstructionSteps(for:)`)
        // before this function runs — so `instructionsArr` is already
        // free of empty entries.
        guard let rawInstruction = instructionsArr.first else { return [] }

        // Data-shape-driven branch (relaxes UIKit's
        // `recipe?.id.isEmpty` gate — see method docs above).
        // Treat as a pre-split array when we already have multiple
        // non-empty elements AND the first element isn't itself a
        // pipe-separated payload.
        let stepsToFormat: [String]
        if instructionsArr.count > 1 && rawInstruction.contains(" | ") == false {
            stepsToFormat = instructionsArr
        } else {
            // Single-element / pipe-separated payload — split on
            // ` | ` exactly as UIKit's `components(separatedBy:)`
            // does. For a count-1 array with no pipe this returns
            // `[rawInstruction]` unchanged, preserving UIKit's
            // single-step rendering.
            stepsToFormat = rawInstruction.components(separatedBy: " | ")
        }

        return stepsToFormat.enumerated().map { index, step in
            // Strip an inline "N. " marker (UIKit's
            // `replacingOccurrences(of: "\(index + 1). ", with: "")`)
            // so legacy data like "1. Mix the gin" doesn't render
            // as the duplicated "Step 1: 1. Mix the gin".
            let inlineMarker = "\(index + 1). "
            if step.contains(inlineMarker) {
                return "Step \(index + 1): \(step.replacingOccurrences(of: inlineMarker, with: ""))"
            } else {
                return "Step \(index + 1): \(step)"
            }
        }
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
                    // Branch on the data source so the two listings
                    // stay completely separate (1:1 UIKit Tabs 0/1):
                    //   • Barsys recipe → write to favs Set ONLY.
                    //   • My Drink (`isMyDrinkFavourite` non-nil) →
                    //     update `isMyDrinkFavourite` ONLY, leave the
                    //     favs Set alone so it never appears in
                    //     "Barsys Recipes" tab.
                    //
                    // `setFavorite(_:isFavorite:)` is preferred over
                    // `toggleFavorite` so the optimistic UI direction
                    // always matches storage, even if storage drifted
                    // from a recent preload re-fetch.
                    let isMyDrink: Bool = {
                        if let s = env.storage.recipe(by: recipe.id) {
                            return s.isMyDrinkFavourite != nil
                        }
                        return false
                    }()
                    if isMyDrink {
                        if let stored = env.storage.recipe(by: recipe.id) {
                            var u = stored
                            u.isMyDrinkFavourite = true
                            u.isFavourite = true
                            env.storage.upsert(recipe: u)
                        }
                    } else {
                        env.storage.setFavorite(recipe.id, isFavorite: true)
                    }
                    // Republish `catalog.recipes` from storage so any
                    // listing screen the user pops back to (Explore
                    // Recipes, Mixlist Detail's recipes list, etc.)
                    // re-renders the heart icon with the fresh state.
                    // `MockStorageService` is not `ObservableObject`, so
                    // its dictionary mutations don't broadcast on their
                    // own — without this, the parent listings still
                    // show the pre-tap heart on pop-back.
                    env.catalog.reloadRecipesFromStorage()
                    Task {
                        do {
                            _ = try await env.api.likeUnlike(
                                recipeId: recipe.id.value, isLike: true)
                        } catch {
                            localIsFavourite = false
                            if isMyDrink {
                                if let stored = env.storage.recipe(by: recipe.id) {
                                    var u = stored
                                    u.isMyDrinkFavourite = false
                                    u.isFavourite = false
                                    env.storage.upsert(recipe: u)
                                }
                            } else {
                                env.storage.setFavorite(recipe.id, isFavorite: false)
                            }
                            // Mirror the optimistic-write republish on
                            // the revert path so listings observing
                            // `catalog.recipes` reflect the rolled-back
                            // state too.
                            await MainActor.run { env.catalog.reloadRecipesFromStorage() }
                        }
                    }
                    env.analytics.track(TrackEventName.favouriteRecipeAdded.rawValue)
                    env.alerts.show(message: Constants.likeSuccessMessage)
                case .unfavourite:
                    localIsFavourite = false
                    // Same Tab 0 / Tab 1 split as `.addToFavourites`
                    // — only the data source that owns this recipe's
                    // favourite state gets updated.
                    let isMyDrink: Bool = {
                        if let s = env.storage.recipe(by: recipe.id) {
                            return s.isMyDrinkFavourite != nil
                        }
                        return false
                    }()
                    if isMyDrink {
                        if let stored = env.storage.recipe(by: recipe.id) {
                            var u = stored
                            u.isMyDrinkFavourite = false
                            u.isFavourite = false
                            env.storage.upsert(recipe: u)
                        }
                    } else {
                        env.storage.setFavorite(recipe.id, isFavorite: false)
                    }
                    // Republish `catalog.recipes` so listings that
                    // observe it (Explore Recipes, Mixlist Detail's
                    // recipes list) re-render with the unfavourited
                    // state on pop-back. See matching comment in the
                    // `.addToFavourites` branch above.
                    env.catalog.reloadRecipesFromStorage()
                    Task {
                        do {
                            _ = try await env.api.likeUnlike(
                                recipeId: recipe.id.value, isLike: false)
                        } catch {
                            localIsFavourite = true
                            if isMyDrink {
                                if let stored = env.storage.recipe(by: recipe.id) {
                                    var u = stored
                                    u.isMyDrinkFavourite = true
                                    u.isFavourite = true
                                    env.storage.upsert(recipe: u)
                                }
                            } else {
                                env.storage.setFavorite(recipe.id, isFavorite: true)
                            }
                            await MainActor.run { env.catalog.reloadRecipesFromStorage() }
                        }
                    }
                    env.analytics.track(TrackEventName.favouriteRecipeRemoved.rawValue)
                    env.alerts.show(message: Constants.unlikeSuccessMessage)
                }
            } label: {
                // UIKit: applyCancelCapsuleGradientBorderStyle() — capsule
                // glass with 1.5pt gradient border (white@95% highlights).
                // Pre-26 fallback: craftButtonBorderColor 1pt stroke.
                //
                // Text is pinned to `.black` (not `appBlackColor`) because
                // the capsule background is forced white-glass in BOTH
                // color schemes for UIKit parity. `appBlackColor` would
                // resolve to near-white in dark mode and the label would
                // disappear against the white fill.
                Text(favouriteButtonTitle(for: recipe))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black)
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
                    // 1:1 port of UIKit
                    // `RecipePageViewController.showUnsavedChangesAlertForBack`
                    // / `showUnsavedChangesAlertForFavourites` /
                    // `showUnsavedChangesAlertForSideMenu`
                    // (RecipePageViewController.swift L301-384):
                    //
                    //   showCustomAlertMultipleButtons(
                    //       title: Constants.unsavedChangesForRecipe,
                    //       cancelButtonTitle: keepEditingButtonTitle,   ← RIGHT, FILLED
                    //       continueButtonTitle: discardButtonTitle,     ← LEFT, BORDERED
                    //       cancelButtonColor: .segmentSelectionColor,   ← orange fill on Keep
                    //       isCloseButtonHidden: true)
                    //
                    // BarsysPopup mapping:
                    //   primaryTitle   → RIGHT button (UIKit "cancelButton")
                    //   secondaryTitle → LEFT  button (UIKit "continueButton")
                    //
                    // So "Keep Editing" is `primaryTitle` (right-side
                    // orange-filled pill via default `primaryFillColor =
                    // "segmentSelectionColor"`) and "Discard" is
                    // `secondaryTitle` (left-side bordered pill).
                    // `isDestructive: false` — UIKit NEVER renders the
                    // Discard button as a red destructive CTA here; it's
                    // always the neutral bordered capsule.
                    unsavedPopup = .confirm(
                        title: Constants.unsavedChangesForRecipe,
                        message: nil,
                        primaryTitle: ConstantButtonsTitle.keepEditingButtonTitle,
                        secondaryTitle: ConstantButtonsTitle.discardButtonTitle,
                        isDestructive: false,
                        // UIKit `EditViewController.swift:353` shows the X
                        // here (`isCloseButtonHidden: false`).
                        isCloseHidden: false
                    )
                } else {
                    craft(recipe)
                }
            } label: {
                // UIKit makeOrangeStyle(): iOS 26+ → capsule with brand
                // gradient (#FAE0CC → #F2C2A1). Pre-26 → flat segmentSelectionColor.
                //
                // Text colour:
                //   • Light mode — `appBlackColor` asset (resolves to
                //     `#4C4D4F`), bit-identical to the existing
                //     UIKit-parity rendering.
                //   • Dark mode — force `Color.black`. The Craft
                //     button's gradient is pinned to the light-mode
                //     orange RGB in dark mode (see
                //     `primaryOrangeButtonBackground` above), so the
                //     pill stays orange in both appearances. If we
                //     kept `appBlackColor` in dark mode it would
                //     resolve to the adaptive near-white `#E5E5EA`,
                //     turning the text into low-contrast white text
                //     on an orange pill. Hard-coding black only in
                //     dark mode restores UIKit's readability without
                //     touching light-mode pixels.
                Text("Craft")
                    .font(.system(size: 15))
                    .foregroundStyle(colorScheme == .dark
                                     ? Color.black
                                     : Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(primaryOrangeButtonBackground)
            }
            .buttonStyle(BounceButtonStyle())
        }
        // 1:1 with UIKit `Mixlist.storyboard` `Seh-le-otk` stack
        // constraints `4p8-cd-X5a` (leading=24) and `pdu-H2-8V5`
        // (trailing=24). Matches the recipe-image horizontal inset
        // (`heroImage` is rendered with `.padding(.horizontal, 24)` at
        // the caller) so the Add-to-Favourites pill's leading edge and
        // the Craft pill's trailing edge align vertically with the
        // image's left and right edges. Was 16pt — visibly tighter
        // than the image, breaking the storyboard's intended column
        // grid.
        .padding(.horizontal, 24)
        .padding(.top, 10)
        // Bottom offset between the action pills and the physical
        // bottom edge:
        //   • 10pt when keyboard is closed — symmetric resting offset
        //     matching the 10pt top inset inside the glass container.
        //   • 100pt when keyboard is open — lifts the bar up so it
        //     reads as floating clear of the keyboard accessory
        //     toolbar instead of glued to the bottom edge.
        // Toggled by the keyboard show/hide notification observers
        // wired below at the safeAreaInset call site, so the bar
        // animates between the two values whenever a quantity field
        // is focused or dismissed.
        .padding(.bottom, isKeyboardVisible ? 100 : 10)
        .animation(.easeInOut(duration: 0.25), value: isKeyboardVisible)
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
    ///
    /// DARK MODE ONLY: the `brandGradientTop` / `brandGradientBottom`
    /// colour assets have a dark-appearance variant that resolves to
    /// dark grey / near-black — which would render the Recipe Craft
    /// button as an invisible dark pill in dark mode. UIKit's
    /// `PrimaryOrangeButton.makeOrangeStyle()` always uses the brand
    /// orange gradient regardless of appearance, so we bypass the
    /// asset resolution in dark mode and hard-code the LIGHT-mode
    /// orange RGB values (`#FAE0CC` / `#F2C2A1`). Light-mode pixels
    /// stay bit-identical to the existing rendering.
    @ViewBuilder
    private var primaryOrangeButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                // Explicit LIGHT-mode brand-orange RGB
                                // so dark mode still shows the intended
                                // peach → tan gradient instead of the
                                // asset's dark-grey dark-appearance
                                // variant. Values match the light
                                // entries in
                                // `brandGradientTop.colorset` /
                                // `brandGradientBottom.colorset`.
                                Color(red: 0.980, green: 0.878, blue: 0.800),
                                Color(red: 0.949, green: 0.761, blue: 0.631)
                            ]
                            : [
                                // Light mode — unchanged, resolves via
                                // the existing asset catalog so
                                // pixels stay bit-identical.
                                Color("brandGradientTop"),
                                Color("brandGradientBottom")
                            ],
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
            // Force the light-mode white-glass pill in BOTH color
            // schemes. Using `.ultraThinMaterial` here flipped the
            // button to a dark adaptive material in dark mode — the
            // cancel-capsule gradient border lost its contrast and
            // the "Save to My Drinks" / "Add to Favourites" label
            // read as dim black text on a dark blob. Explicit white
            // tint matches the Save button in EditRecipeView
            // (RecipesScreens.swift:3319) and the popup secondary
            // button at Theme.swift:1396 — same white-glass capsule
            // in every color scheme.
            Capsule(style: .continuous)
                .fill(SwiftUI.Color.white.opacity(0.85))
        } else {
            // `Theme.Color.surface` light = pure white sRGB(1, 1, 1) —
            // bit-identical to the previous hard-coded `Color.white`,
            // so light mode renders the EXACT same cancel capsule.
            // Dark mode picks up the elevated dark surface (#2C2C2E)
            // so the pre-iOS 26 cancel button stops being a stark
            // white slab on the dark recipe page.
            RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                .fill(Theme.Color.surface)
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
        // Leading: custom 15×15 `back` chevron — same styling used on
        // MyProfile / Preferences / PairYourDevice / Cocktail Kits /
        // ExploreRecipes / Crafting / Favorites.
        //
        // Tapping runs the UIKit-parity unsaved-changes guard
        // (`RecipePageViewController.showUnsavedChangesAlertForBack`):
        //   • hasUnsavedChanges → set `pendingUnsavedAction = .back`
        //     and surface the `unsavedChangesForRecipe` popup. The
        //     popup's Discard handler (in `.barsysPopup(... onSecondary:)`)
        //     resets edits then calls `dismiss()`.
        //   • else → dismiss immediately.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticService.light()
                if hasUnsavedChanges {
                    pendingUnsavedAction = .back
                    unsavedPopup = .confirm(
                        title: Constants.unsavedChangesForRecipe,
                        message: nil,
                        primaryTitle: ConstantButtonsTitle.keepEditingButtonTitle,
                        secondaryTitle: ConstantButtonsTitle.discardButtonTitle,
                        isDestructive: false,
                        isCloseHidden: false
                    )
                } else {
                    dismiss()
                }
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
        // (RecipePageViewController.swift:228 sets
        // `lblDeviceName.isHidden = true` in `updateDeviceNameAndImage`
        // and never reverses it).
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                DevicePrincipalIcon(assetName: deviceIconName,
                                    accessibilityLabel: deviceKindName)
            }
        }
        // Shared 100×48 glass pill (iOS 26+) / bare 61×24 icon stack
        // (pre-26) — 1:1 with UIKit `RecipePageViewController` top-right
        // nav container.
        //
        // IMPORTANT — UIKit semantics for the leading favorite icon:
        //
        //   `didPressFavouriteButton` (RecipePageViewController.swift
        //    L322-351) does NOT toggle the recipe's like state. It
        //    **navigates to the Favorites screen** via
        //    `BarBotCoordinator(navigationController:).showFavourites(tabSelected: 0)`.
        //
        //   Toggling the per-recipe "like" state in UIKit is done by
        //   the BOTTOM button `btnAddToFavourites` (the "Add to
        //   Favourites" / "Remove from Favourites" action in the
        //   recipe-page footer) — a separate control with its own
        //   `likeUnlikeApi` call path.
        //
        //   The previous SwiftUI port wired the top-right icon to the
        //   toggle behaviour, which conflated the two. Now the
        //   top-right icon matches UIKit — a navigation shortcut to
        //   the Favorites tab (which is the same shortcut Home /
        //   MyBar / ControlCenter / Explore already ship).
        //
        //   Guard: if the user has unsaved quantity edits, UIKit shows
        //   the `unsavedChangesForRecipe` confirmation alert before
        //   navigating (L333-346). SwiftUI mirrors the same guard via
        //   the existing `unsavedPopup` state.
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationRightGlassButtons(
                onFavorites: { handleFavoritesNavTap() },
                onProfile: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        router.showSideMenu = true
                    }
                }
            )
        }
    }

    /// 1:1 with UIKit `didPressFavouriteButton` + `showUnsavedChangesAlertForFavourites`
    /// (RecipePageViewController.swift L322-346).
    ///   1. HapticService.light()
    ///   2. If the user has unsaved quantity edits → show
    ///      `unsavedChangesForRecipe` alert with Keep Editing / Discard.
    ///      On Discard → revert edits + navigate to Favorites.
    ///      On Keep Editing → cancel silently.
    ///   3. Else → navigate straight to Favorites.
    private func handleFavoritesNavTap() {
        HapticService.light()
        if hasUnsavedChanges {
            // 1:1 with UIKit
            // `RecipePageViewController.showUnsavedChangesAlertForFavourites`
            // (RecipePageViewController.swift L333-346). Discard is
            // LEFT + bordered (secondaryTitle), Keep Editing is RIGHT
            // + orange-filled (primaryTitle) — same mapping as the
            // craft-button variant above; see comment there.
            unsavedPopup = .confirm(
                title: Constants.unsavedChangesForRecipe,
                message: nil,
                primaryTitle: ConstantButtonsTitle.keepEditingButtonTitle,
                secondaryTitle: ConstantButtonsTitle.discardButtonTitle,
                isDestructive: false,
                // UIKit `EditViewController.swift:353` shows the X here
                // (`isCloseButtonHidden: false`).
                isCloseHidden: false
            )
            // Tag the pending action so the Discard handler routes to
            // Favorites instead of starting a craft. Reuses the same
            // `unsavedPopup` binding; the discard handler (now
            // `onSecondary` after the LEFT/RIGHT swap) restores
            // `editedIngredients` from the backing recipe — after that
            // we push Favorites.
            pendingUnsavedAction = .navigateToFavorites
        } else {
            router.push(.favorites)
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
            // UIKit `RecipePageViewController+Actions.swift` L61 —
            // sets `pendingConnectionSource = .recipeCrafting` so
            // the connect callback pops back to the recipe page.
            router.promptPairDevice(isConnected: ble.isAnyDeviceConnected,
                                    source: .recipeCrafting)
            return
        }
        // 1:1 port of UIKit
        // `RecipePageViewController+Actions.didPressCraftButton` +
        // `checkBarsys360Craftability` preflight pipeline. UIKit
        // routes the button through `performBarsys360CraftCheck`
        // which:
        //   1. getStationsHere → stationsArray
        //   2. Build `recipeIngredientsWithStationName` from
        //      baseAndMixer with 5 ml minimum clamp.
        //   3. For each ingredient: match station by
        //      primary+secondary category. No match →
        //      `ingredientDoesNotExistInStation` alert + return.
        //   4. If station matches and
        //      `station.ingredientQuantity < recipe.quantity` →
        //      `insufficientIngredientQuantityFor360` alert + return.
        //   5. `getPerishableArrayFromIngredientsArr(arrStations)` —
        //      if any perishable-expired, show the
        //      `perishableDescriptionTitle` popup with Clean → cleaning
        //      and Okay → no-op (stay on recipe page). Do NOT push
        //      crafting screen.
        //   6. Only after all checks pass → push CraftingVC.
        //
        // Without this preflight the SwiftUI port let the user tap
        // Craft → push CraftingView → dispatch-time validation → show
        // error alert → dismiss. UIKit never lets the user land on
        // the crafting screen in an invalid state, so the feedback
        // is clearer and the user stays on the recipe page to fix
        // the stations.
        //
        // Coaster / Shaker keep the simpler UIKit path
        // (craftCoasterRecipeWithUpdatedQuantity) — which only
        // enforces the 5 ml minimum before pushing. The
        // `CraftingViewModel.start(…)` preamble handles that
        // downstream, so we can go straight to push here.
        if ble.isBarsys360Connected() {
            Task { @MainActor in
                await validateAndPushBarsys360Craft(recipe)
            }
            return
        }
        router.push(.crafting(recipe.id))
    }

    /// Ports the Barsys-360 branch of UIKit
    /// `RecipePageViewController+Actions.performBarsys360CraftCheck` +
    /// `RecipeCraftingClass+StationSetup.craft360RecipeForUpdatedQuantity`.
    /// Fetches live stations, runs the full validation chain, and
    /// either surfaces the matching alert or pushes `.crafting`.
    @MainActor
    private func validateAndPushBarsys360Craft(_ recipe: Recipe) async {
        let deviceName = ble.getConnectedDeviceName()
        guard !deviceName.isEmpty else {
            env.alerts.show(title: Constants.deviceNotConnected)
            return
        }
        env.loading.show("Checking stations…")
        let stations = await StationsAPIService.loadStations(deviceName: deviceName)
        env.loading.hide()

        // Extract base/mixer (non-garnish, non-additional), unique by
        // lowercased name — matches UIKit
        // `RecipePageViewModel+DataLoading.swift` L27-28 +
        // `.unique(by: { $0.name.lowercased() })`.
        let rawBaseAndMixer = (recipe.ingredients ?? []).filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            // Matches UIKit SQL `fetchMatchingRecipeLists`:
            // `NOT IN ('garnish', 'additionals', 'additional')`.
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        var seen = Set<String>()
        var baseAndMixer: [Ingredient] = []
        for ing in rawBaseAndMixer {
            let key = ing.name.lowercased()
            if key.isEmpty { continue }
            if seen.insert(key).inserted { baseAndMixer.append(ing) }
        }

        // 5 ml minimum — UIKit
        // `MainBarBotCell+Actions.craftAction` L25-29 clamps instead
        // of alerts, but Recipe Page uses the stricter check in
        // `craft360RecipeForUpdatedQuantity` (any < 5 ml triggers
        // `lowIngredientQty` alert).
        for ing in baseAndMixer {
            if (ing.quantity ?? 0) < 5.0 {
                env.alerts.show(title: Constants.lowIngredientQty)
                return
            }
        }

        // All-6-empty guard — UIKit
        // `MainBarBotCell+Actions.craftAction` L62-70. Recipe Page
        // takes the same path through `checkBarsys360Craftability`.
        let emptyCount = stations.filter {
            $0.ingredientName.isEmpty || $0.ingredientName == Constants.emptyDoubleDash
        }.count
        if emptyCount == 6 {
            env.alerts.show(title: Constants.ingredientDoesNotExistInStation)
            return
        }

        // Per-ingredient station match + quantity check — UIKit
        // `RecipeCraftingClass+StationSetup.craft360RecipeForUpdatedQuantity`
        // L42-65. Primary+secondary (lowercase) comparison; no match
        // fires `ingredientDoesNotExistInStation`; station holding
        // an ingredient with insufficient quantity fires
        // `insufficientIngredientQuantityFor360`.
        for ing in baseAndMixer {
            let rp = (ing.category?.primary ?? "").lowercased()
            let rs = (ing.category?.secondary ?? "").lowercased()
            let matching = stations.first { slot in
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
        // `RecipePageViewController+Actions` L90-99: show
        // `perishableDescriptionTitle` alert with Clean/Okay. Clean
        // routes to the cleaning flow (control-center origin — NOT
        // setup, so we clear the setup context); Okay is a no-op
        // (user stays on recipe page, can't craft until they clean).
        // Use `isPerishableExpired` (computed from raw flag +
        // updatedAt >24h check), NOT the raw `isPerishable` which
        // is true for every perishable ingredient regardless of age.
        let expiredPerishables = stations.filter { $0.isPerishableExpired }
        if !expiredPerishables.isEmpty {
            env.alerts.show(
                title: Constants.perishableDescriptionTitle,
                primaryTitle: Constants.cleanAlertTitle,
                secondaryTitle: Constants.okayButtonTitle,
                onPrimary: {
                    router.setupStationsContext = nil
                    router.push(.stationCleaning)
                },
                onSecondary: {
                    // UIKit "Okay" primary closure is explicit `{ _ in return }` —
                    // user stays on the recipe page and must clean
                    // before retrying craft. No state change.
                }
            )
            return
        }

        // All checks pass → push the crafting screen.
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
                // Stepper cluster — matches storyboard stack `NEL-QM-2aY`:
                //   [ 30×30 minus btn ] [ qty field + unit ] [ 30×30 plus btn ]
                //
                // Spacing tightened so the row reads as a compact stepper:
                //   • outer HStack `spacing: 5` → 5pt between the minus
                //     button and the quantity, and between the unit
                //     label and the plus button.
                //   • inner HStack `spacing: 0` → quantity touches the
                //     "ml" / "oz" label with no horizontal gap.
                //   • TextField pinned to a fixed 28pt width so the
                //     column lines up across rows regardless of digit
                //     count (replaces the storyboard's 70pt centring
                //     container, which produced ~22pt visible gaps on
                //     either side of the qty content).
                HStack(spacing: 0) {
                    Button {
                        HapticService.light()
                        onMinus()
                    } label: {
                        // UIKit: `state.image = newMinus` with
                        // `tintColor = grayBorderColor`. Template render
                        // so the asset tints to match the UIKit grey.
                        // Dark mode tints to pure white so the glyph
                        // reads with high contrast against the dark
                        // glass pill (the `grayBorderColor` asset
                        // resolved to a near-invisible mid-grey on the
                        // dark canvas). Light mode keeps the historical
                        // `grayBorderColor` value bit-identical.
                        Image("newMinus")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color(UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                    ? (UIColor(named: "softWhiteTextColor") ?? .white)
                                    : UIColor(named: "grayBorderColor") ?? .gray
                            }))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Decrease \(ingredient.name)")

                    // Quantity + unit cluster.
                    HStack(spacing: 0) {
                        TextField("", text: $editingText)
                            .keyboardType(unit == .ml ? .numberPad : .decimalPad)
                            .multilineTextAlignment(.center)
                            // Storyboard `m1H-Gu-dS6` — system 11pt,
                            // `mediumLightGrayColor`.
                            .font(.system(size: 11))
                            .foregroundStyle(Color("mediumLightGrayColor"))
                            // Fixed quantity-field width so all rows
                            // align under each other regardless of
                            // digit count ("52" / "1.76" / "5"). Replaces
                            // the 70pt centring container which spread
                            // the qty + unit into the middle of the cell.
                            .frame(width: 28, height: 30)
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
                            // Re-sync editingText whenever the parent
                            // mutates the bound `ingredient.quantity` —
                            // mirrors UIKit
                            // `RecipePageViewController+Helpers.swift`
                            // L65 (`tblIngredient.reloadRows(...)`) and
                            // L412 (`tblIngredient.reloadData()` after
                            // plus/minus). UIKit reloads the whole cell
                            // on every change, which always rewrites
                            // `cell.ingredientQuantityTextField.text =
                            // displayData.quantityText` — even while
                            // the field is the first responder.
                            //
                            // Use the `newValue` from the change
                            // parameter directly instead of going
                            // through `displayText`. `displayText`
                            // reads `self.ingredient.quantity`, which
                            // can briefly lag behind the actual change
                            // because SwiftUI sometimes invokes the
                            // `.onChange` closure before the captured
                            // `self` snapshot is replaced. That stale
                            // read was leaving the field showing the
                            // PREVIOUS value (e.g. type 22 + Done →
                            // field still showed 30) until the user
                            // re-tapped the field. Reformatting from
                            // `newValue` removes the dependency on the
                            // stale snapshot.
                            .onChange(of: ingredient.quantity) { newValue in
                                let q = newValue ?? 0
                                switch unit {
                                case .ml: editingText = String(format: "%.0f", q)
                                case .oz: editingText = String(format: "%.2f", q / 29.5735)
                                }
                            }
                            .onChange(of: unit) { newUnit in
                                let q = ingredient.quantity ?? 0
                                switch newUnit {
                                case .ml: editingText = String(format: "%.0f", q)
                                case .oz: editingText = String(format: "%.2f", q / 29.5735)
                                }
                            }
                        Text(unitLabel)
                            // Storyboard `Q8p-KS-sM8` — system 11pt,
                            // `mediumLightGrayColor`.
                            .font(.system(size: 11))
                            .foregroundStyle(Color("mediumLightGrayColor"))
                    }
                    .frame(height: 30)

                    Button {
                        HapticService.light()
                        onPlus()
                    } label: {
                        // Dark mode → white; light mode → `grayBorderColor`
                        // (bit-identical to the historical light pixels).
                        // Same rationale as the minus button above.
                        Image("newPlus")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color(UIColor { trait in
                                trait.userInterfaceStyle == .dark
                                    ? (UIColor(named: "softWhiteTextColor") ?? .white)
                                    : UIColor(named: "grayBorderColor") ?? .gray
                            }))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Increase \(ingredient.name)")
                }
                .padding(.trailing, 24) // matches `Kzt-lz-F4P` trailing 24
            } else {
                // Read-only quantity + unit on the Recipe Page rows.
                // Split into an HStack with 2pt spacing so the unit label
                // sits tight against the quantity (UIKit storyboard has
                // ≤2pt leading between the two labels). The previous
                // "\(displayText) \(unitLabel)" rendered the literal
                // space-character glyph (~3-4pt at 11pt system), which
                // read as too wide a gap on the recipe-page ingredients
                // and additional-ingredients tables.
                HStack(spacing: 2) {
                    Text(displayText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                    Text(unitLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                }
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
                // Pre-iOS 26 fallback for the glass pill: trait-resolved
                // closure preserves the EXACT historical pure-white@0.7
                // capsule fill in light mode (bit-identical pixels), and
                // returns a near-clear capsule in dark so the pill blends
                // with the dark page instead of looking like a stark
                // semi-opaque white slab over `primaryBackgroundColor`.
                .background(
                    Color(UIColor { trait in
                        trait.userInterfaceStyle == .dark
                            ? UIColor(white: 1.0, alpha: 0.10)
                            : UIColor(white: 1.0, alpha: 0.7) // EXACT historical
                    }),
                    in: Capsule(style: .continuous)
                )
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
        // Show the clamped value RIGHT AWAY in the field. Previously
        // this line set `editingText = displayText`, which reads from
        // `ingredient.quantity` — but at this point the parent's
        // `onEdit(...)` mutation has only just been scheduled, so
        // `ingredient` still holds the OLD value and the field would
        // briefly snap back to the previous quantity (e.g. type 30,
        // press Done → field shows 20). Re-formatting `clamped`
        // directly bypasses the stale snapshot and matches UIKit's
        // `EditViewModel.validateAndUpdateQuantity(...)` which writes
        // the validated value back to the cell synchronously.
        switch unit {
        case .ml: editingText = String(format: "%.0f", clamped)
        case .oz: editingText = String(format: "%.2f", clamped / 29.5735)
        }
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
        let recipe = Recipe(name: name.isEmpty ? "My Custom Drink" : name,
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
        // Keyboard accessory — ports UIKit
        // `MakeMyOwnViewController+TableView.swift` L36/L44:
        // `cell.ingredientQuantityTextField.addDoneToolbar()`. The
        // drink-name field is default keyboard (has Return), but the
        // ingredient-quantity fields (numberPad/decimalPad) inside
        // the picker sheet need this accessory to dismiss.
        .keyboardDoneToolbar()
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

/// Identifiable wrapper around `UIImagePickerController.SourceType` so
/// it can drive `.sheet(item:)`. Mirrors `MyBarView.PickerPresentation`
/// (MyBarScreens.swift L179-182). The `id` changes on every new
/// presentation, forcing SwiftUI to rebuild the sheet body with the
/// fresh `source` value — fixes the camera-first-tap race where the
/// previous two-step `pickerSource = .camera; showPicker = true`
/// pattern captured the stale default `.photoLibrary`.
fileprivate struct EditRecipePickerPresentation: Identifiable, Equatable {
    let id = UUID()
    let source: UIImagePickerController.SourceType
}

struct EditRecipeView: View {
    let recipeID: RecipeID?
    /// When set, the EditRecipeView uses this recipe DIRECTLY as the
    /// initial state and (for edits) as the patch target — no `env.storage`
    /// lookup needed. This is critical when editing a My Drink because
    /// My Drinks live in `myDrinksLoaded` (FavoritesView state), NOT in
    /// `env.storage`, so a lookup-by-id would return nil and the save
    /// would mistakenly POST a brand-new recipe instead of PATCHing the
    /// existing one — surfacing as the "Unable to save recipe" error.
    var existingRecipe: Recipe? = nil
    /// Ports UIKit `EditViewController.isCustomizingRecipe`.
    /// - `true`  → creating a NEW My Drink from an existing Barsys recipe
    ///   (RecipeDetailView "Save to My Drinks"). API: POST /my/recipes.
    /// - `false` → editing an EXISTING My Drink
    ///   (FavoritesView My Drinks tab "Edit"). API: PATCH /my/recipes/{id}.
    var isCustomizing: Bool = false
    /// When `true`, the edit screen was opened from within FavoritesView
    /// (edit existing My Drink). After save-success, we just dismiss the
    /// cover — FavoritesView is already on-screen and will refresh via
    /// its own `.onChange(of: router.myDrinksRefreshTick)` observer
    /// (UIKit parity: FavouritesVC.viewWillAppear re-runs its fetch).
    ///
    /// Prevents the "already on Favorites, but we pushed a new Favorites
    /// screen on top of it" stack bug. When `false` (the RecipeDetail
    /// customise flow), we keep the UIKit-parity push to Favorites +
    /// pre-select the My Drinks tab.
    var openedFromFavorites: Bool = false
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var ble: BLEService    // hide-add row depends on Barsys 360 connection
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// When EditRecipeView is hosted by an `EditRecipeCoverContent`
    /// fullScreenCover, this binding points at the cover's local
    /// `NavigationPath`. `craft()` appends there so Crafting pushes
    /// INSIDE the cover (on top of Edit) instead of onto the parent
    /// tab's stack (where it would render underneath the cover,
    /// invisibly). Nil when Edit was pushed directly onto a tab stack
    /// via `Route.editRecipe` — in that case we fall back to
    /// `router.push`.
    @Environment(\.editCoverPath) private var editCoverPath

    @State private var name: String = ""
    @State private var ingredients: [Ingredient] = []
    /// 1:1 with UIKit `EditViewController.garnishIngredientsArr`
    /// (EditViewController.swift L40 + L69-71). The editable
    /// `ingredients` array above only carries BASE / MIXER rows; garnish
    /// and additional are stored separately so they survive the save
    /// round-trip. UIKit re-injects them into `recipe.ingredients` on
    /// save (L204-211: remove base/mixer → append garnish/additional →
    /// append edited base/mixer). Without this snapshot the SwiftUI
    /// port was overwriting `recipe.ingredients` with just the edited
    /// base/mixer rows on save, silently losing every garnish and
    /// optional-additional ingredient the recipe originally had.
    @State private var savedGarnishIngredients: [Ingredient] = []
    /// 1:1 with UIKit `EditViewController.additionalIngredientsArr`
    /// (EditViewController.swift L41 + L70-72). UIKit treats Additional
    /// Ingredients as `category.primary == "garnish" &&
    /// ingredientOptional == true` (NOT a separate primary). Tracked
    /// here so save can re-inject them alongside garnishes.
    @State private var savedAdditionalIngredients: [Ingredient] = []
    /// Locally-picked image — set when user chooses a photo from the
    /// picker. Takes precedence over `remoteImageURL` for display.
    /// 1:1 with UIKit `EditViewModel.selectedImageForRecipe`.
    @State private var selectedImage: UIImage?
    /// Existing remote image URL for recipes that already have an
    /// image (e.g. editing a My Drink with a previously-uploaded
    /// image, or customizing a Barsys recipe that ships with artwork).
    /// Populated from `existingRecipe.image?.url` on `.onAppear`.
    /// Cleared when the user taps the delete button, mirroring UIKit
    /// `EditViewModel.deleteImage()` which sets `recipe?.image?.url = ""`.
    /// The display rule matches UIKit `viewSetup` L131-146:
    ///   `hasImage == !(image.url isEmpty || nil)` → show the image
    ///   view, hide the Add Image button.
    @State private var remoteImageURL: URL?
    /// Controls the Camera / Photos / Cancel action sheet for adding
    /// or replacing the recipe image — 1:1 with UIKit
    /// `showActionSheetForImagePicker()` invoked from
    /// `didPressAddImageButton` (EditViewController.swift L219-226).
    @State private var showAddImageActionSheet = false
    /// Identifiable wrapper that drives the recipe-image
    /// `UIImagePickerController` sheet via `.sheet(item:)`.
    ///
    /// The previous two-step `addImagePickerSource = .camera;
    /// showPhotoPicker = true` pattern raced on first tap: SwiftUI
    /// coalesced the mutations into a single render pass and the
    /// `.sheet(isPresented:)` body captured the STALE default
    /// `.photoLibrary` source, opening Photos instead of the camera.
    /// Same bug MyBarScreens.swift L165-182 documents and fixes via
    /// `PickerPresentation` — porting that fix here so Camera works
    /// on the very first tap. Subsequent presentations get a fresh
    /// UUID, forcing SwiftUI to rebuild the sheet body with the new
    /// source value every time.
    @State private var recipeImagePicker: EditRecipePickerPresentation?
    @State private var nameHasError = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    // MARK: - Add-Ingredient image-detection state (1:1 UIKit parity)
    //
    // UIKit `didPressAddIngredientButton` →
    //   showActionSheetForImagePicker(isImageCroppingDisabled: true) →
    //   uploadIngredientImage(...) → processUploadedIngredients →
    //   addIngredient(ingredient).
    //
    // SwiftUI mirrors the same finite-state machine:
    //   1. Tap → `showAddIngredientActionSheet` (Camera / Photos / Cancel).
    //   2. Pick → `ingredientImagePicker` opens the chosen source via
    //      `.sheet(item:)` so the source value is captured atomically
    //      (see `recipeImagePicker` doc above for the race-condition
    //      rationale that motivated this pattern).
    //   3. After pick → `uploadAndProcessIngredient(image:)` runs the
    //      AI-detection request and either appends a row or surfaces
    //      one of the four UIKit error messages
    //      (Constants.ingredientUnableToAddError, ingredientCannotBeUsedHere,
    //      moreThanOneIngredientIdentified, hasSameIngredientInDrink).
    @State private var showAddIngredientActionSheet = false
    @State private var ingredientImagePicker: EditRecipePickerPresentation?
    @State private var pickedIngredientImage: UIImage?
    // Loader for `uploadIngredientImage` is now the shared
    // `env.loading` overlay (`LoadingOverlayModifier` in
    // DesignSystem/Components.swift) — that's the canonical SwiftUI
    // port of UIKit `showGlassLoader(message:)` and matches the UIKit
    // dimensions exactly (200×150pt card, 20pt corners, BarsysLoader
    // GIF, SFProDisplay-Medium 15pt label, black@0.30 backdrop). The
    // previous local `@State isUploadingIngredient` overlay used a
    // smaller ProgressView + 16pt-corner card with `.regularMaterial`
    // and 14pt label — visually off from the UIKit reference.

    /// Ports UIKit `EditViewModel.validateForSave()` — must have a name
    /// and at least one ingredient with a non-zero quantity.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !ingredients.isEmpty
            && ingredients.contains { ($0.quantity ?? 0) > 0 }
    }

    var body: some View {
        // 1:1 port of UIKit `EditViewController` layout. BarBot.storyboard
        // scene `ub5-ev-1ng`:
        //
        //   • Root view `dYz-iY-rsl`: (0, 0, 393, 852), TRANSPARENT
        //   • mainView `9FU-1Q-j4b`: (0, 356.33, 393, 427.67) — bottom
        //     58% of the screen, storyboard white, runtime
        //     `mainView.addGlassEffect()` (EditViewController.swift L129)
        //     with top-only corner mask (12pt)
        //   • Top 42% of the screen (y=0 to 356.33) is root-view
        //     transparent → FavoritesVC / RecipeDetailsVC visible
        //     directly, NO glass overlay there
        //   • Outer tap view `FKS-QG-YGV` catches taps in the top strip
        //     to dismiss (`didPressOuterView:`)
        //
        // SwiftUI layout mirrors UIKit's storyboard: a VStack with a
        // transparent tap-dismiss region sized to 41.8% of the screen
        // (matching mainView's y=356 on 852pt), and the glass
        // `mainView` pinned to the bottom 58.2%. Combined with
        // `.presentationBackground(.clear)` on the `.fullScreenCover`
        // (see FavoritesView AND RecipePage call sites), the parent
        // screen (FavoritesView / RecipeDetails) stays visible across
        // the top 42% and blurs through the panel's `.regularMaterial`
        // glass on the bottom 58%.
        VStack(spacing: 0) {
            // Top transparent tap-dismiss region.
            //
            // 1:1 with UIKit storyboard constraints on `mainView`
            // (BarBot.storyboard scene `ub5-ev-1ng`):
            //   • `EbN-xa-swC`: mainView.bottom = safeArea.bottom
            //   • `K0K-OI-fZd`: mainView.top    >= safeArea.top + 100
            //
            // So mainView's HEIGHT is NOT fixed — it is driven by the
            // intrinsic size of its contents (title + name + image +
            // dynamic table + pill + buttons). When the user adds
            // ingredients the table grows (via UIKit
            // `tblDrinksHeightConstraints.constant`) up to the 150pt
            // cap set in `EditViewModel.tableHeightForContentSize`
            // (EditViewModel.swift L312-320), and mainView grows
            // right along with it — the storyboard frame (y=356.33,
            // h=427.67) is just the default that auto-layout overrides
            // at runtime.
            //
            // Previously the SwiftUI port used a FIXED
            // `UIScreen.main.bounds.height * 0.418` for this top
            // region, which pinned the panel start at ~41.8% of the
            // screen regardless of content. That didn't match UIKit:
            // a panel with 1 ingredient had the same y-offset as one
            // with 6 ingredients.
            //
            // Flex-fill the top region with `maxHeight: .infinity` so
            // the panel below naturally sizes to its content and pushes
            // up as the ingredient list grows — matching UIKit.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // mainView — glass panel, bottom ~58% of the screen.
            // Contains BOTH the ScrollView content AND the Save/Craft
            // button stack so a SINGLE `panelBackground` glass layer
            // covers everything. The previous split layout
            // (ScrollView panel + separate `safeAreaInset` button bar
            // with its own `bottomButtonBarBackground`) produced a
            // visible seam / color break between the two `.regularMaterial`
            // surfaces — exactly the "underline / different color below
            // Add Ingredient" the user reported.
            // 1:1 with UIKit `EditViewController` storyboard hierarchy
            // (BarBot.storyboard scene `ub5-ev-1ng`):
            //
            //   mainView (9FU-1Q-j4b) — glass panel pinned bottom
            //     ├── [STICKY TOP]
            //     │    ├── "Edit" title + cross button (y=24, y=21)
            //     │    ├── Recipe name textView + underline (y=61)
            //     │    └── Add Image stackView (y=125, h=152)
            //     │
            //     ├── [SCROLLABLE MIDDLE]
            //     │    └── tblDrinks (y=292) — dynamic height,
            //     │         capped at 150pt via `tableHeightForContentSize`
            //     │         (EditViewModel.swift L312-320); when content
            //     │         exceeds 150pt the table scrolls INTERNALLY.
            //     │
            //     ├── viewAddIngredients pill (A4B-bI-6Jh, h=52)
            //     │    pinned 5pt below tblDrinks
            //     │
            //     └── [STICKY BOTTOM]
            //          └── Save + Craft buttons (xzw-6X-XYP, h=57)
            //              pinned to mainView.bottom with 20pt gap
            //              above from the pill
            //
            // The previous SwiftUI port wrapped EVERYTHING in one
            // `ScrollView`, which scrolled the recipe name + image
            // block together with the ingredients — breaking parity
            // with the UIKit design where only the ingredient table
            // scrolls.
            VStack(spacing: 0) {

                // -- STICKY TOP BLOCK ----------------------------------------
                // Title + cross + name + image. Never scrolls.
                VStack(alignment: .leading, spacing: 24) {
                    header
                    nameField
                    imagePickerBlock
                }
                .padding(.top, 24)
                // 15pt gap to the ingredients table — matches UIKit
                // constraint `UOt-L3-Vxv: tblDrinks.top = rQQ-0k-gay.bottom + 15`.
                .padding(.bottom, 15)

                // -- SCROLLABLE INGREDIENTS LIST -----------------------------
                // Only this section scrolls. Height clamped by
                // `tableHeightForEditList` — 1:1 with UIKit
                // `EditViewModel.tableHeightForContentSize` L312-320:
                //   0          → 0    (empty, list collapses)
                //   1…59pt     → 100  (stretched minimum)
                //   60…150pt   → height (exact content height)
                //   > 150pt    → 150  (cap, internal scroll kicks in)
                // So the panel GROWS with the table up to the 150pt
                // cap — this is what causes the panel to size to its
                // contents (same as UIKit `mainView` with its
                // `tblDrinksHeightConstraints` observer).
                ingredientsList
                    .frame(height: tableHeightForEditList)
                    .padding(.horizontal, 24)

                // -- Add Ingredient pill (fixed position) --------------------
                // 5pt gap below table — UIKit
                // `rKW-ci-7cL: A4B-bI-6Jh.top = tblDrinks.bottom + 5`.
                if !shouldHideAddIngredientRow {
                    addIngredientPill
                        .padding(.horizontal, 24)
                        .padding(.top, 5)
                }

                // Error message (hidden by default).
                if let msg = errorMessage {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(Color("errorLabelColor"))
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                // 20pt FIXED gap between `viewAddIngredients` and the
                // Save/Craft stack — UIKit constraint
                // `Fmu-lM-w5w: xzw-6X-XYP.top = A4B-bI-6Jh.bottom + 20`.
                // (Not a flexible Spacer — UIKit uses an exact 20pt
                // gap, and the panel sizes to content above/below.)
                Color.clear.frame(height: 20)

                // -- STICKY BOTTOM — Save + Craft buttons --------------------
                bottomButtons
            }
            .background(panelBackground)
            .clipShape(panelShape)
            // 1:1 with UIKit `addGlassStyleShadow()`
            // (UIViewClass+GlassEffects.swift L160-174):
            //   shadowColor   = UIColor.black.withAlphaComponent(0.15)
            //   shadowOpacity = 0.35  → effective ≈ 0.0525
            //   shadowOffset  = (0, 4)
            //   shadowRadius  = 12
            .shadow(color: .black.opacity(0.0525), radius: 12, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only ignore CONTAINER safe areas (status bar, home indicator)
        // so the panel still extends edge-to-edge — but DO respect the
        // keyboard safe area so the panel lifts above the keyboard
        // when a quantity field is focused. Default `.all` regions
        // (the previous behaviour) was eating the keyboard inset, which
        // left focused fields hidden behind the keyboard.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .navigationBarTitleDisplayMode(.inline)
        // Hide ONLY the navigation bar — the modern API
        // `toolbar(.hidden, for: .navigationBar)` is scoped to the
        // navigation bar and leaves other toolbar item groups (notably
        // `ToolbarItemGroup(placement: .keyboard)` from
        // `keyboardDoneToolbar()` below) intact. The deprecated
        // `.navigationBarHidden(true)` previously used here also
        // suppressed the keyboard accessory toolbar on iOS 16+, so
        // the Done button never appeared above the numberPad keyboard
        // when a quantity field was focused.
        .toolbar(.hidden, for: .navigationBar)
        // Keyboard accessory — ports UIKit
        // `EditViewController+TableView.swift` L23:
        // `cell.textFieldQuantity.addDoneToolbar()`.
        // Edit-recipe ingredient-quantity fields use `.numberPad` /
        // `.decimalPad`, so the Done accessory is required to dismiss.
        .keyboardDoneToolbar()
        // 1:1 with UIKit `showActionSheetForImagePicker`
        // (ImagePickerViewController.swift L45-89): Camera / Photos /
        // Cancel alert. SwiftUI `confirmationDialog` renders the same
        // iOS action sheet. Title matches `Constants.pleaseSelectAnOption`.
        .confirmationDialog(
            "Please Select an Option",
            isPresented: $showAddImageActionSheet,
            titleVisibility: .visible
        ) {
            // Single atomic state mutation — replaces the old two-step
            // `addImagePickerSource = …; showPhotoPicker = true` that
            // raced on first tap and opened Photos when Camera was
            // requested. See `recipeImagePicker` declaration for the
            // SwiftUI race-condition rationale.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    recipeImagePicker = EditRecipePickerPresentation(source: .camera)
                }
            }
            Button("Photos") {
                recipeImagePicker = EditRecipePickerPresentation(source: .photoLibrary)
            }
            Button("Cancel", role: .cancel) { }
        }
        // 1:1 with UIKit post-action-sheet flow: picking Camera or
        // Photos presents a `UIImagePickerController` with the
        // corresponding `sourceType`. `.fullScreenCover(item:)` is
        // required (instead of `.sheet`) because SwiftUI's sheet uses
        // `pageSheet` presentation on iOS 13+, which inset-crops the
        // camera UI and HIDES the bottom capture button — UIKit
        // presents `UIImagePickerController` with `.fullScreen` style
        // (the default), so we mirror that here. Photo library works
        // fine in fullScreenCover too. The `(item:)` variant rebuilds
        // the body with the fresh `presentation.source` on every
        // present, so Camera works on the very first tap.
        .fullScreenCover(item: $recipeImagePicker) { presentation in
            BarBotImagePicker(image: $selectedImage, source: presentation.source)
                .ignoresSafeArea()
        }
        // 1:1 port of UIKit `showActionSheetForImagePicker(isImageCroppingDisabled: true)`
        // (ImagePickerViewController.swift L45-89). UIKit shows exactly
        // three actions: Camera / Photos / Cancel — no manual-entry path.
        .confirmationDialog(
            Constants.pleaseSelectAnOption,
            isPresented: $showAddIngredientActionSheet,
            titleVisibility: .visible
        ) {
            // Atomic mutation — see `recipeImagePicker` doc above.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    ingredientImagePicker = EditRecipePickerPresentation(source: .camera)
                }
            }
            Button("Photos") {
                ingredientImagePicker = EditRecipePickerPresentation(source: .photoLibrary)
            }
            Button(ConstantButtonsTitle.cancelButtonTitle, role: .cancel) { }
        }
        // Image picker for the AI ingredient detection flow. UIKit pipes
        // the chosen image through `uploadIngredientImage(...)` —
        // SwiftUI does the same via `uploadAndProcessIngredient(image:)`.
        // `.fullScreenCover(item:)` for the same two reasons spelled
        // out on the recipe-image picker above:
        //   1. Camera needs full-screen presentation; SwiftUI's
        //      `.sheet` uses `pageSheet` which crops the bottom and
        //      hides the camera capture button.
        //   2. `(item:)` rebuilds the body with the fresh
        //      `presentation.source` on every present, so Camera
        //      works on the very first tap.
        .fullScreenCover(item: $ingredientImagePicker) { presentation in
            BarBotImagePicker(image: $pickedIngredientImage,
                              source: presentation.source)
                .ignoresSafeArea()
        }
        .onChange(of: pickedIngredientImage) { newImage in
            guard let image = newImage else { return }
            // UIKit parity: defer the upload until after the picker has
            // dismissed — mirrors `picker.dismiss(animated: true) { ... }`
            // in `imagePickerController(_:didFinishPickingMediaWithInfo:)`.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                uploadAndProcessIngredient(image: image)
                pickedIngredientImage = nil
            }
        }
        // The "Adding ingredients" glass loader is rendered by the
        // shared `LoadingOverlayModifier` (applied at the app root via
        // `.loadingOverlay(env.loading)`) — driven by
        // `env.loading.show/hide` in `uploadAndProcessIngredient`. This
        // matches UIKit's `showGlassLoader(message:)` dimensions
        // (200×150pt card, 20pt corners, BarsysLoader GIF) instead of
        // the previous undersized inline ProgressView card.
        .onAppear {
            // Prefer the recipe passed in directly. Fallback to storage
            // lookup so RouteView's id-only `.editRecipe(id)` path keeps
            // working for Barsys catalog recipes.
            let source: Recipe?
            if let recipe = existingRecipe {
                source = recipe
            } else if let id = recipeID {
                source = env.storage.recipe(by: id)
            } else {
                source = nil
            }
            if let recipe = source {
                name = recipe.name ?? ""

                // QA: edit-recipe was showing garnish + additional rows
                // in the editable ingredients table because the previous
                // port did `ingredients = recipe.ingredients ?? []` —
                // ALL ingredients dumped into the editable list. UIKit
                // `EditViewController.viewSetup` (L68-103) splits the
                // recipe's ingredients into THREE arrays:
                //
                //   • baseAndMixer (recipeIngredientsArrayToShow):
                //       primary != "garnish" && primary != "additional",
                //       deduped by lowercased name. THIS is what fills
                //       the editable table.
                //   • garnishIngredientsArr:
                //       primary == "garnish" && ingredientOptional == false,
                //       deduped by lowercased name. Read-only — preserved
                //       for the save round-trip.
                //   • additionalIngredientsArr:
                //       primary == "garnish" && ingredientOptional == true,
                //       deduped by lowercased name. Read-only — preserved
                //       for the save round-trip.
                //
                // Note: UIKit treats "Additional Ingredients" as a SUBSET
                // of garnish (same primary, distinguished by the
                // `ingredientOptional` flag), NOT as a separate primary.
                // The base/mixer filter still excludes both "additional"
                // strings defensively because some legacy server
                // payloads use `primary == "additional"` directly.
                let allIngredients = recipe.ingredients ?? []

                let baseAndMixerFiltered = allIngredients.filter { ing in
                    let p = (ing.category?.primary ?? "").lowercased()
                    return p != "garnish" && p != "additional" && p != "additionals"
                }
                var seenBase = Set<String>()
                ingredients = baseAndMixerFiltered.filter {
                    seenBase.insert($0.name.lowercased()).inserted
                }

                // 1:1 with UIKit's exact comparison semantics
                // (EditViewController.swift L69-70):
                //   `$0.ingredientOptional == false`  → garnish only
                //   `$0.ingredientOptional == true`   → additional only
                // The Optional<Bool> direct equality means a `nil`
                // `ingredientOptional` is NEITHER garnish NOR additional
                // and is silently dropped — same as UIKit. The
                // RecipePageView read-only sections (lines 925-942) use
                // this same pattern so the edit / view paths stay
                // consistent.
                let garnishFiltered = allIngredients.filter { ing in
                    let p = (ing.category?.primary ?? "").lowercased()
                    return p == "garnish" && ing.ingredientOptional == false
                }
                var seenGarnish = Set<String>()
                savedGarnishIngredients = garnishFiltered.filter {
                    seenGarnish.insert($0.name.lowercased()).inserted
                }

                let additionalFiltered = allIngredients.filter { ing in
                    let p = (ing.category?.primary ?? "").lowercased()
                    return p == "garnish" && ing.ingredientOptional == true
                }
                var seenAdditional = Set<String>()
                savedAdditionalIngredients = additionalFiltered.filter {
                    seenAdditional.insert($0.name.lowercased()).inserted
                }

                // 1:1 with UIKit `viewSetup` L131-146:
                //   hasImage = !(image.url isEmpty || nil)
                //   recipeImageUrl = image.url.getImageUrl()
                // Initialize the remote URL so the thumbnail displays
                // the existing recipe image instead of the Add Image
                // placeholder button. User can then tap delete or pick
                // a new image to replace it.
                if let urlString = recipe.image?.url,
                   !urlString.isEmpty,
                   let url = urlString.getImageUrl() {
                    remoteImageURL = url
                }
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
                // UIKit storyboard (EditViewController scene ub5-ev-1ng):
                //   • Button frame 24×24 (id nw9-fs-LNG width constraint)
                //   • Image `crossIcon` at its natural 12×11.67 size,
                //     NOT stretched (UIButton default, no imageEdgeInsets)
                // SwiftUI match: image rendered at native 12pt, centered
                // inside a 24pt tap-target frame.
                Image("crossIcon")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(width: 24, height: 24)
                    // The inner 12pt icon left an empty 6pt margin
                    // inside the 24pt tap-target. `contentShape` makes
                    // the whole 24×24 frame hit-testable so the close
                    // button works anywhere inside the visible area.
                    .contentShape(Rectangle())
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
            // 1:1 with UIKit `viewSetup` L131-146:
            //   if viewModel.hasImage {
            //       showImageViewSuperView.isHidden = false
            //       // sd_setImage(with: recipeImageUrl, placeholder: .myDrink)
            //   } else {
            //       addImageViewSuperView.isHidden = false
            //   }
            // Display priority:
            //   1. selectedImage (locally picked UIImage) — takes precedence
            //   2. remoteImageURL (existing recipe image URL)
            //   3. Add Image button (no image)
            if let image = selectedImage {
                imageThumbnail(localImage: image)
            } else if let url = remoteImageURL {
                imageThumbnail(remoteURL: url)
            } else {
                // 1:1 with UIKit `didPressAddImageButton` L219-226:
                //   showActionSheetForImagePicker() — Camera/Photos/Cancel
                Button {
                    HapticService.light()
                    showAddImageActionSheet = true
                } label: {
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

    /// 120×120 thumbnail for a locally-picked UIImage — 1:1 with UIKit
    /// `showImgView` post-pick (`didSelectImagesFromPhotos` L382-386).
    @ViewBuilder
    private func imageThumbnail(localImage: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: localImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            imageDeleteButton
        }
    }

    /// 120×120 thumbnail for a remote URL — 1:1 with UIKit
    /// `showImgView.sd_setImage(with: imgUrl, placeholderImage: .myDrink)`
    /// at `EditViewController` L133-141.
    @ViewBuilder
    private func imageThumbnail(remoteURL: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    Image("myDrink")
                        .resizable().aspectRatio(contentMode: .fit)
                        .padding(16)
                case .failure:
                    Image("myDrink")
                        .resizable().aspectRatio(contentMode: .fit)
                        .padding(16)
                @unknown default:
                    Color("lightBorderGrayColor")
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            imageDeleteButton
        }
    }

    /// Delete overlay button — `whiteDeleteImage` asset at 30×30,
    /// `charcoalGrayColor` tint, 2pt from the top-right
    /// (storyboard `Mqn-Av-Zo2`). 1:1 with UIKit
    /// `EditViewModel.deleteImage()` which clears both
    /// `selectedImageForRecipe` AND `recipe?.image?.url`.
    private var imageDeleteButton: some View {
        Button {
            selectedImage = nil
            remoteImageURL = nil
        } label: {
            Image("whiteDeleteImage")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .foregroundStyle(Color("charcoalGrayColor"))
        }
        .offset(x: -2, y: 2)
        .accessibilityLabel("Remove image")
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

    /// The SCROLLABLE ingredients list — 1:1 with UIKit `tblDrinks`
    /// (BarBot.storyboard id `6YO-Ic-WDI`). Displays the editable
    /// ingredient rows inside a `ScrollView` so the caller can cap its
    /// frame to 150pt (matching `EditViewModel.tableHeightForContentSize`
    /// L312-320). When content exceeds the cap, the list scrolls
    /// internally — EXACTLY like the UIKit table with its dynamic
    /// `tblDrinksHeightConstraints.constant`.
    private var ingredientsList: some View {
        // ScrollViewReader so a focused row inside the 150pt-clamped
        // inner scroll can be brought into view when the keyboard
        // appears — without it, fields in lower rows stay hidden
        // behind the keyboard accessory bar.
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                // UIKit cell is 64pt tall (6pt top pad + 52pt inner glass +
                // 6pt bottom pad) with no table separator, so adjacent rows
                // have a 12pt gap. Matching that keeps the row rhythm
                // identical to UIKit.
                VStack(spacing: 12) {
                    ForEach($ingredients) { $ing in
                        EditIngredientRow(
                            ingredient: $ing,
                            unit: env.preferences.measurementUnit,
                            onDelete: {
                                ingredients.removeAll { $0.id == ing.id }
                            },
                            onFocus: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(ing.id, anchor: .center)
                                }
                            }
                        )
                        .id(ing.id)
                    }
                }
            }
        }
    }

    /// The FIXED Add Ingredient pill — 1:1 with UIKit
    /// `viewAddIngredients` (A4B-bI-6Jh, 52pt tall, full width, "+ Add
    /// Ingredient"). UIKit applies `applyCellGlassStyle(view)`:
    ///   iOS 26+ → `addGlassEffect(cornerRadius: xlarge=20, alpha: 1)`
    ///   pre-26  → `roundCorners = pill(24)`, borderWidth = 1,
    ///             gradient [black@10%, white@10%], border color #F2F2F2
    ///             (EditViewController.swift L234-243).
    /// Hidden when Barsys 360 is connected and the user has hit the
    /// 6-ingredient cap — matches UIKit `hideUnhideAddIngredientButton`
    /// (EditViewController.swift L169-176).
    private var addIngredientPill: some View {
        Button {
            HapticService.light()
            // 1:1 with UIKit `didPressAddIngredientButton` →
            // `showActionSheetForImagePicker(isImageCroppingDisabled: true)`.
            showAddIngredientActionSheet = true
        } label: {
            HStack(spacing: 12) {
                Image("newPlus")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(width: 30, height: 30)
                Text("Add Ingredient")
                    .font(.system(size: 14))
                    .foregroundStyle(Color("appBlackColor"))
                Spacer()
            }
            .padding(.leading, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(addIngredientBackground)
            .overlay(addIngredientBorder)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel("Add Ingredient")
        .accessibilityHint("Add another ingredient to the recipe")
    }

    /// Ports UIKit `EditViewModel.shouldHideAddIngredientRow`: a recipe
    /// for the Barsys 360 device caps at 6 ingredients.
    private var shouldHideAddIngredientRow: Bool {
        ingredients.count >= 6 && ble.isBarsys360Connected()
    }

    /// Rendered height of the scrollable ingredients list — 1:1 port of
    /// UIKit `EditViewModel.tableHeightForContentSize(_:)`
    /// (EditViewModel.swift L312-320):
    ///
    ///     if height > 150        { return 150.0 }      // cap
    ///     else if height < 60 && height != 0 { return 100.0 }  // min
    ///     else                   { return height }     // exact
    ///
    /// The SwiftUI port estimates the intrinsic content height from
    /// the ingredient count and each row's fixed height (UIKit
    /// `EditTableViewCell` is 64pt: 6pt top + 52pt glass pill + 6pt
    /// bottom = 64pt). Spacing between rows in SwiftUI is 12pt
    /// (`VStack(spacing: 12)` in `ingredientsList`), so the total
    /// intrinsic content height is:
    ///
    ///     count = 0     → 0
    ///     count >= 1    → count * 64 + (count - 1) * 12
    ///
    /// Clamped to match UIKit's min-100 / max-150 rules so the panel
    /// grows/shrinks with content up to the same ceiling.
    private var tableHeightForEditList: CGFloat {
        let count = CGFloat(ingredients.count)
        guard count > 0 else { return 0 }
        // Row is 64pt tall (6pt top pad + 52pt glass pill + 6pt bottom
        // pad); 12pt VStack spacing between rows.
        let rowHeight: CGFloat = 64
        let spacing: CGFloat = 12
        let contentHeight = count * rowHeight + max(0, count - 1) * spacing
        if contentHeight > 150 {
            return 150.0
        } else if contentHeight < 60 {
            // UIKit: `height < 60 && height != 0` → 100
            return 100.0
        } else {
            return contentHeight
        }
    }

    // MARK: - Upload + AI detection (UIKit didSelectImagesFromPhotos parity)
    //
    // Faithful port of `EditViewController.didSelectImagesFromPhotos`
    // (EditViewController.swift L379-418) for the ingredient branch:
    //   1. Show glass loader "Adding ingredients".
    //   2. POST image to `image/multipart` via APIClient.
    //   3. Map response to [Ingredient] (unit "ml", quantity 0.0,
    //      ingredientOptional false) — UIKit
    //      `EditViewModel+API.uploadIngredientImage` L66-69.
    //   4. Run `processUploadedIngredients` validation chain — UIKit
    //      `EditViewModel+API.processUploadedIngredients` L77-121:
    //        • nil response          → ingredientUnableToAddError
    //        • empty array           → ingredientCannotBeUsedHere
    //        • base/mixer count == 0 (only garnish/additional present)
    //                                → ingredientCannotBeUsedHere
    //        • base/mixer count > 1  → moreThanOneIngredientIdentified
    //        • category primary or secondary missing
    //                                → ingredientCannotBeUsedHere
    //        • duplicate by primary+secondary
    //                                → hasSameIngredientInDrink
    //        • all pass → append Ingredient(quantity: minimumQtyDouble = 5.0).
    //   5. On any failure, surface the message via env.alerts.
    private func uploadAndProcessIngredient(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            env.alerts.show(message: Constants.ingredientUnableToAddError)
            return
        }

        env.loading.show(Constants.addingIngredientLoaderText)
        Task { @MainActor in
            defer { env.loading.hide() }
            do {
                let detected = try await env.api.uploadIngredientImage(data)
                let result = processUploadedIngredients(detected)
                if let ingredient = result.ingredient {
                    HapticService.success()
                    ingredients.append(ingredient)
                } else if let message = result.message {
                    env.alerts.show(message: message)
                }
            } catch {
                env.alerts.show(message: Constants.recipeSaveError)
            }
        }
    }

    /// 1:1 port of UIKit `EditViewModel+API.processUploadedIngredients`
    /// — same five validation branches in the same order, with the
    /// same Constants strings. Returns either a validated Ingredient or
    /// the message to show the user.
    private func processUploadedIngredients(
        _ detected: [IngredientFromImage]?
    ) -> (ingredient: Ingredient?, message: String?) {
        guard let detected = detected else {
            return (nil, Constants.ingredientUnableToAddError)
        }
        if detected.isEmpty {
            return (nil, Constants.ingredientCannotBeUsedHere)
        }

        // Filter to base/mixer (exclude garnish + additional).
        let baseAndMixer = detected.filter {
            let p = ($0.category?.primary ?? "").lowercased()
            // Matches UIKit SQL `fetchMatchingRecipeLists`:
            // `NOT IN ('garnish', 'additionals', 'additional')`.
            return p != "garnish" && p != "additional" && p != "additionals"
        }

        if baseAndMixer.isEmpty {
            // The image only contained garnish/additional ingredients —
            // not allowed in EditRecipe (UIKit L91-93).
            return (nil, Constants.ingredientCannotBeUsedHere)
        }
        if baseAndMixer.count > 1 {
            return (nil, Constants.moreThanOneIngredientIdentified)
        }

        let first = baseAndMixer[0]
        let primary = first.category?.primary ?? ""
        let secondary = first.category?.secondary ?? ""
        if primary.isEmpty || secondary.isEmpty {
            return (nil, Constants.ingredientCannotBeUsedHere)
        }

        // Duplicate check — UIKit `hasDuplicateIngredient(primary:secondary:)`
        // matches by primary AND secondary, lowercased.
        let isDuplicate = ingredients.contains { existing in
            (existing.category?.primary?.lowercased() ?? "") == primary.lowercased()
                && (existing.category?.secondary?.lowercased() ?? "") == secondary.lowercased()
        }
        if isDuplicate {
            return (nil, Constants.hasSameIngredientInDrink)
        }

        // Build the Ingredient with the same defaults as UIKit
        // (`Ingredient.init(...)` in EditViewModel+API L105-114):
        //   unit: "ml" (lowercased), quantity: 5.0, ingredientOptional: false.
        let ing = Ingredient(
            name: first.name ?? "",
            unit: Constants.mlText.lowercased(),
            notes: "",
            category: first.category,
            quantity: 5.0,
            perishable: first.perishable,
            substitutes: [],
            ingredientOptional: false
        )
        return (ing, nil)
    }

    // 1:1 with UIKit `applyCellGlassStyle(viewAddIngredients)` —
    // EditViewController.swift L90/L93/L178-187.
    //
    // IMPORTANT: UIKit calls the SAME `applyCellGlassStyle` helper on
    // both the ingredient cells (`cell.viewGlass` in
    // EditViewController+TableView.swift L17) AND the Add Ingredient
    // pill (`viewAddIngredients` in EditViewController.swift L90/93).
    // So the two surfaces MUST render identically in SwiftUI too — the
    // earlier port had the pill using SwiftUI `.regularMaterial` while
    // the cells used `BarsysGlassPanelBackground` (real UIGlassEffect),
    // which is why the user saw a visible mismatch.
    //
    // Both paths now share the same SwiftUI recipe:
    //   • iOS 26+: `BarsysGlassPanelBackground()` clipped to a 20pt
    //     rounded rect — byte-identical to UIKit
    //     `addGlassEffect(cornerRadius: xlarge=20, alpha: 1)`.
    //   • Pre-26: Capsule (`roundCorners = pill = 24`) with a solid
    //     white fill plus the UIKit black@10% → white@10% vertical
    //     gradient overlay and the 1pt `#F2F2F2` border.
    @ViewBuilder
    private var addIngredientBackground: some View {
        if #available(iOS 26.0, *) {
            BarsysGlassPanelBackground()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            // Pre-iOS 26 fallback — `Theme.Color.surface` light value
            // is sRGB(1, 1, 1), bit-identical to the previous hard-coded
            // `Color.white`, so light mode renders the EXACT same Add
            // Ingredient pill capsule. Dark mode picks up the elevated
            // dark surface (#2C2C2E) so the pill stops being a stark
            // white slab on the dark Edit Recipe panel.
            Capsule()
                .fill(Theme.Color.surface)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.10), Color.white.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                )
        }
    }

    @ViewBuilder
    private var addIngredientBorder: some View {
        if #available(iOS 26.0, *) {
            // Matches `editCellBorder` — faint sheen stroke so the
            // pill has the same edge definition over the panel glass
            // as an ingredient row.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        } else {
            // UIKit `applyCellGlassStyle` pre-26 border — #F2F2F2, 1pt.
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
            // Save — 1:1 with UIKit `addToFavouritesButton`
            // (EditViewController.swift L88-94):
            //   iOS 26+ → applyCancelCapsuleGradientBorderStyle()
            //             — capsule (height/2 corner) + glass + 1.5pt
            //               cancel-gradient border (white/cancelBorderGray
            //               alternating sheen).
            //   Pre-26  → makeBorder(width: 1, color: .craftButtonBorderColor)
            //             — white background + plain 1pt border, 8pt corner.
            //   Title font: storyboard default (matches body 14pt).
            //   Title color: black (storyboard normal title color).
            Button {
                HapticService.light()
                save()
            } label: {
                // Label pinned to `.black` (not `appBlackColor`) because
                // the capsule background is forced white-glass in BOTH
                // color schemes — `appBlackColor` resolves to near-white
                // in dark mode and the "Save" text would disappear.
                Text(ConstantButtonsTitle.saveButtonTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(editCancelCapsuleBackground)
                    .overlay(editCancelCapsuleBorder)
                    .clipShape(editButtonShape)
                    .opacity(canSave ? 1.0 : 0.5)
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Save to My Drinks")
            .accessibilityHint("Saves the recipe to your drinks list")

            // Craft — 1:1 with UIKit `craftButton: PrimaryOrangeButton`
            // (EditViewController.swift L89, L95):
            //   iOS 26+ → makeOrangeStyle() — capsule (height/2 corner) +
            //             vertical brand gradient (brandGradientTop=#FAE0CC →
            //             brandGradientBottom=#F2C2A1).
            //   Pre-26  → backgroundColor = .segmentSelectionColor (#E0B392),
            //             8pt corner.
            //   Title font + color match Save button.
            Button {
                HapticService.light()
                craft()
            } label: {
                Text("Craft")
                    .font(.system(size: 14))
                    .foregroundStyle(colorScheme == .dark
                                     ? Color.black
                                     : Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(editOrangeButtonBackground)
                    .clipShape(editButtonShape)
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
        // Add bottom safe area (~34pt on notched iPhones) since the
        // parent VStack `ignoresSafeArea(.bottom)` and the button bar
        // is now in the main content flow (no safeAreaInset wrapper).
        .padding(.bottom, iOS26BottomInset + 34)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        // No separate background — the Save/Craft stack lives INSIDE
        // the panel's `.background(panelBackground)` VStack in `body`,
        // so a single continuous glass surface covers everything.
        // Previously a separate `bottomButtonBarBackground` produced
        // a visible seam between the panel and the button bar.
    }

    /// Glass continuation for the Save/Craft button-bar inset.
    /// Matches `panelBackground` — `.regularMaterial` on iOS 15+,
    /// solid white pre-15. The panel above provides the rounded top
    /// edge; here we extend past the bottom safe area so the glass
    /// meets the screen edge like UIKit `mainView`'s bottom constraint.
    @ViewBuilder
    private var bottomButtonBarBackground: some View {
        if #available(iOS 15.0, *) {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        } else {
            Rectangle()
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// 1:1 with UIKit button `roundCorners` runtime attribute on
    /// `addToFavouritesButton` / `craftButton`:
    ///   iOS 26+ → capsule (height/2 = 22.5 for our 45pt buttons)
    ///   Pre-26  → 8pt rounded rect (BarsysCornerRadius.small)
    private var editButtonShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// 1:1 with UIKit `mainView.addGlassEffect()`.
    ///
    /// UIKit code path (UIViewClass+GlassEffects.swift L31-69):
    ///   • iOS 26+: `UIGlassEffect(style: .regular)` with
    ///     `isInteractive = true`, inserted at z-index 0, `alpha = 1`,
    ///     clears `backgroundColor` and `superview?.backgroundColor`.
    ///   • Pre-26: `addGlassEffect` is guarded by `#available(iOS 26.0, *)`
    ///     and does NOTHING — the `mainView` keeps its storyboard fill
    ///     (solid white).
    ///
    /// The UIKit reference screenshot shows a HEAVY whitish frosted
    /// glass where the underlying FavoritesVC / RecipeDetailsVC is
    /// visibly muted to a near-white pastel. SwiftUI's
    /// `.regularMaterial.opacity(0.95)` reads as clear by contrast.
    /// Use `BarsysGlassPanelBackground` — a real
    /// `UIVisualEffectView(.systemMaterial)` blur plus a subtle white
    /// tint — so the Edit panel matches the UIKit visual output.
    @ViewBuilder
    private var panelBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 12,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 12,
            style: .continuous
        )
        // Pure glass — no white-tint overlay — so the underlying
        // FavoritesVC / RecipeDetailsVC shows through the panel
        // softly blurred, matching the UIKit Edit-screen reference
        // where `mainView.addGlassEffect()` renders as `UIGlassEffect
        // (.regular)` alone with no extra whitening layer.
        BarsysGlassPanelBackground()
            .clipShape(shape)
    }

    /// Top-only rounded clipping shape — 1:1 with UIKit storyboard
    /// `mainView.layer.maskedCorners = [.layerMaxXMinYCorner,
    ///                                   .layerMinXMinYCorner]` (top
    /// corners only, bottom flush with safe area).
    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 12,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 12,
            style: .continuous
        )
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

        // UIKit EditViewModel+API.saveRecipe L26-28: filter base/mixer
        // ingredients with quantity > 0 before sending to API.
        let filteredBaseAndMixer = ingredients.filter { ($0.quantity ?? 0) > 0 }

        // 1:1 with UIKit `EditViewController.didPressAddToFavouriteButton`
        // L203-211 — re-assemble the recipe ingredients in this order:
        //   1. retained garnish entries (primary == "garnish",
        //      ingredientOptional == false)
        //   2. retained additional entries (primary == "garnish",
        //      ingredientOptional == true)
        //   3. edited base/mixer entries with quantity > 0
        // The previous SwiftUI port wrote `recipeToSave.ingredients =
        // filteredIngredients` directly, which silently DROPPED every
        // garnish and additional ingredient on save — surfacing as
        // "ingredients come wrong" once the user edited a recipe with
        // a non-empty garnish or additional list.
        var filteredIngredients: [Ingredient] = []
        filteredIngredients.append(contentsOf: savedGarnishIngredients)
        filteredIngredients.append(contentsOf: savedAdditionalIngredients)
        filteredIngredients.append(contentsOf: filteredBaseAndMixer)

        // Build the recipe to send to API.
        //
        // Resolve the source recipe in this priority order:
        //   1. `existingRecipe` parameter — passed in directly from
        //      FavoritesView's My-Drinks "Edit" button (the one place
        //      a recipe lives outside `env.storage`).
        //   2. `env.storage.recipe(by: id)` — Barsys catalog recipes
        //      and locally-upserted My Drinks.
        //   3. nil — a brand-new recipe with no template.
        let sourceRecipe: Recipe? = existingRecipe
            ?? recipeID.flatMap { env.storage.recipe(by: $0) }

        var recipeToSave: Recipe
        if !isCustomizing, let source = sourceRecipe, !source.id.value.isEmpty {
            // EDIT existing My Drink — PATCH /my/recipes/{id}
            //
            // Crucially we KEEP `source.id` (was previously lost when the
            // storage lookup failed because My Drinks aren't in env.storage,
            // which forced us into the create path with an empty id and
            // produced "Unable to save recipe").
            recipeToSave = source
            recipeToSave.name = trimmed
            recipeToSave.ingredients = filteredIngredients
            recipeToSave.isMyDrinkFavourite = true
        } else if let source = sourceRecipe {
            // CUSTOMIZE existing Barsys recipe → POST new My Drink with
            // empty id so the server generates a fresh one. Carry over
            // metadata so the new drink keeps glassware / instructions /
            // image etc.
            recipeToSave = Recipe(
                id: RecipeID(""),
                name: trimmed,
                description: source.description,
                image: source.image,
                ice: source.ice,
                ingredients: filteredIngredients,
                instructions: source.instructions,
                glassware: source.glassware,
                tags: source.tags,
                ingredientNames: source.ingredientNames,
                barsys360Compatible: source.barsys360Compatible,
                isMyDrinkFavourite: true,
                slug: source.slug
            )
        } else {
            // BRAND-NEW My Drink — no source recipe available.
            recipeToSave = Recipe(
                id: RecipeID(""),
                name: trimmed,
                ingredients: filteredIngredients,
                instructions: ["Add all ingredients in order.", "Stir or shake to taste."],
                isMyDrinkFavourite: true
            )
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
                // — fixes "Edit shows stale data" by mirroring the saved
                // recipe into env.storage the same way My Drinks would
                // be after a fresh API fetch.
                if !isCustomizing {
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

                // 1:1 port of UIKit
                // `EditViewController.didPressAddToFavouriteButton`
                // L271-289 success branch:
                //
                //   showCustomAlertMultipleButtons(
                //       title: message, subTitleStr: nil,
                //       cancelButtonTitle: nil,
                //       continueButtonTitle: "OK",
                //       continueButtonColor: .segmentSelectionColor,
                //       isCloseButtonHidden: true) { okAction in
                //
                //     // Refresh My Drinks if the parent screen is the
                //     // favourites controller, otherwise navigate to it.
                //     hideEditButtonFromFavScreen(isNeedRefresh: true)
                //     DelayedAction.afterAnimation {
                //         if topVC is FavouritesRecipesAndDrinksViewController {
                //             controller.getMyDrinksApi(isInitialDataLoading: true)
                //         } else {
                //             BarBotCoordinator(navigationController: navVc)
                //                 .showFavourites(tabSelected: 1)
                //         }
                //     }
                //     removeFromParent(); view.removeFromSuperview()
                //   } onCancel: { _ in }
                //
                // SwiftUI translation:
                //   • showSuccess → renders the orange-fill OK popup with
                //     no close-X (matches UIKit storyboard exactly).
                //   • OK callback dismisses the EditRecipeView cover
                //     first, then asks AppRouter to push `.favorites`
                //     with `pendingFavoritesTabIndex = 1` so
                //     FavoritesView lands on My Drinks (parity with
                //     `tabSelected: 1` UIKit forwards).
                env.alerts.showSuccess(message: successMsg) {
                    // Step 1 — dismiss the edit cover (UIKit `removeFromParent` +
                    // `view.removeFromSuperview()`).
                    dismiss()
                    // Step 2 — route behaviour:
                    //   • If the user opened Edit FROM Favorites, they
                    //     are already on that screen. Don't stack a new
                    //     `.favorites` route on top — just bump the
                    //     refresh tick so FavoritesView re-pulls the My
                    //     Drinks list (UIKit parity:
                    //     `FavouritesVC.viewWillAppear → refreshData()`).
                    //     Also pre-select the My Drinks tab index so
                    //     the user sees their saved edit straight away.
                    //   • Otherwise (RecipeDetail → Customize flow),
                    //     push to Favorites with `My Drinks` preselected —
                    //     matches UIKit
                    //     `BarBotCoordinator.showFavourites(tabSelected: 1)`.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        router.pendingFavoritesTabIndex = 1   // My Drinks
                        if openedFromFavorites {
                            router.myDrinksRefreshTick &+= 1
                        } else {
                            router.push(.favorites)
                        }
                    }
                }
            } catch {
                isSaving = false
                env.alerts.show(message: Constants.recipeSaveError)
            }
        }
    }

    /// 1:1 port of UIKit `EditViewController.didPressCraftButton(_:)`
    /// (EditViewController.swift L332-368) chained with
    /// `EditViewModel.validateForCraft(recipeName:)` and
    /// `craftActionInEditScreen()`.
    ///
    /// Validation cascade (matches UIKit `CraftValidationResult` enum
    /// and switch on it L336-367):
    ///   1. recipeIngredientsArrayToShow.count == 0
    ///        → showDefaultAlert("Please add ingredients")
    ///   2. base/mixer with quantity > 0 count == 0
    ///        → showDefaultAlert("Ingredient quantity cannot be zero")
    ///   3. !isDeviceConnected (BLE Barsys360 / Coaster / Shaker all off)
    ///        → AppNavigationState.pendingConnectionSource = .recipeCrafting
    ///          openPairYourDeviceWhenNotConnected() (push pair device)
    ///   4. determineCraftTarget == .barsys360 && ingredientCount > 6
    ///        → showDefaultAlert("Maximum ingredients allowed are 6")
    ///   5. Has unsaved changes (name/ingredients/image differ from initial)
    ///        → showCustomAlertMultipleButtons(
    ///             title: "Your changes will not be saved...",
    ///             cancelButtonTitle: "Save", continueButtonTitle: "Continue"
    ///          ) → onSave: didPressAddToFavouriteButton (save first),
    ///              onContinue: craftActionInEditScreen() (discard + craft)
    ///   6. No unsaved changes → craftActionInEditScreen() → push crafting.
    private func craft() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let baseAndMixerWithQty = ingredients.filter { ($0.quantity ?? 0) > 0 }

        // Step 1 — validate ingredient set (UIKit
        // EditViewModel.validateForCraft L257-264).
        if ingredients.isEmpty {
            env.alerts.show(message: Constants.pleaseAddIngredients)
            return
        }
        if baseAndMixerWithQty.isEmpty {
            env.alerts.show(message: Constants.ingredientsCantBeZero)
            return
        }

        // Step 2 — device gate (UIKit L270-272). When no Barsys device is
        // connected, route the user to the pair-device flow with the
        // "recipeCrafting" source flag set. Without a connected device
        // there's nothing to craft on.
        let deviceConnected = ble.isAnyDeviceConnected
            || ble.isBarsys360Connected()
            || ble.isCoasterConnected()
            || ble.isBarsysShakerConnected()
        guard deviceConnected else {
            // UIKit `EditViewController.swift` L345 — sets
            // `pendingConnectionSource = .recipeCrafting` so the BLE
            // connect callback pops back to the edit source (not
            // Explore). Dismiss the edit sheet FIRST so the pair push
            // lands on the underlying nav stack, then trigger the
            // alert on the router.
            router.promptPairDevice(isConnected: deviceConnected,
                                    source: .recipeCrafting)
            dismiss()
            return
        }

        // Step 3 — Barsys 360 ingredient cap (UIKit
        // EditViewModel.validate360IngredientCount L286-291 + the
        // craftActionInEditScreen branch L312).
        if ble.isBarsys360Connected() && baseAndMixerWithQty.count > 6 {
            env.alerts.show(message: Constants.maximumQtyIs6)
            return
        }

        // Step 4 — unsaved-changes gate (UIKit L274-282). When the user
        // has touched name / ingredients / image, ask before committing
        // to craft (which would discard the changes by default).
        if hasUnsavedChanges(currentName: trimmed) {
            // 1:1 with UIKit `showCustomAlertMultipleButtons(
            //     title: yourChangesWillNotSavedAlert,
            //     cancelButtonTitle: "Save",
            //     continueButtonTitle: "Continue",
            //     cancelButtonColor: .segmentSelectionColor,
            //     isCloseButtonHidden: false)`
            //
            // primaryTitle = "Save" (orange, fires save flow)
            // secondaryTitle = "Continue" (neutral, discards + crafts)
            env.alerts.show(
                title: Constants.yourChangesWillNotSavedAlert,
                message: "",
                primaryTitle: ConstantButtonsTitle.saveButtonTitle,
                secondaryTitle: ConstantButtonsTitle.continueButtonTitle,
                onPrimary: { [weak env] in
                    _ = env
                    save()                               // Save first, then craft from favorites
                },
                onSecondary: {
                    proceedToCraft()                    // Discard + craft
                }
            )
            return
        }

        // Step 5 — no unsaved changes, craft directly.
        proceedToCraft()
    }

    /// Pushes the crafting screen — UIKit `craftActionInEditScreen()`
    /// (L304-326) → `RecipeCraftingClass.craftCoasterRecipeWithUpdatedQuantity`
    /// or `craft360RecipeForUpdatedQuantity`. The SwiftUI `CraftingView`
    /// route handles the device-specific dispatch internally.
    private func proceedToCraft() {
        // 1:1 UIKit parity — `EditViewController.craftActionInEditScreen`
        // pushes CraftingVC on top of the nav stack WITHOUT popping itself
        // (RecipeCraftingClass.swift L28 does
        // `fromController?.navigationController?.pushViewController(…)`).
        //
        // When Edit is hosted in the `EditRecipeCoverContent`
        // fullScreenCover, push onto THAT cover's local NavigationPath
        // so Crafting layers on top of Edit inside the cover. Pushing
        // onto `router` (a tab path) would place Crafting below the
        // cover and it would render invisibly behind Edit. When Edit
        // was pushed directly via `Route.editRecipe`, fall back to the
        // router path (the test for that is `editCoverPath == nil`).
        let id = recipeID ?? RecipeID()
        if let localPath = editCoverPath {
            localPath.wrappedValue.append(Route.crafting(id))
        } else {
            router.push(.crafting(id))
        }
    }

    /// 1:1 port of UIKit `EditViewModel.hasUnsavedChanges(currentName:)`
    /// (EditViewModel.swift L337-346): compares ingredient name + rounded
    /// quantity against the initial snapshot, plus checks the recipe
    /// name and image URL.
    private func hasUnsavedChanges(currentName: String) -> Bool {
        guard let original = existingRecipe else {
            // Brand-new recipe — anything entered counts as a change.
            return !currentName.isEmpty || !ingredients.isEmpty
        }
        let originalName = (original.name ?? "").trimmingCharacters(in: .whitespaces)
        if currentName != originalName { return true }

        // Compare only the BASE / MIXER slice of the original recipe,
        // because `ingredients` (the editable @State) was scoped to
        // base/mixer in `.onAppear` per UIKit parity. Comparing against
        // the unfiltered `original.ingredients ?? []` would always
        // report the count mismatch as a change whenever the recipe
        // had any garnish or additional entries — falsely triggering
        // the "Your changes will not be saved" alert on craft / close
        // even when the user touched nothing. Same dedupe rules used
        // in `.onAppear` so the snapshots line up.
        let originalAll = original.ingredients ?? []
        let originalBaseAndMixerFiltered = originalAll.filter { ing in
            let p = (ing.category?.primary ?? "").lowercased()
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        var seenBase = Set<String>()
        let originalBaseAndMixer = originalBaseAndMixerFiltered.filter {
            seenBase.insert($0.name.lowercased()).inserted
        }

        if ingredients.count != originalBaseAndMixer.count { return true }
        // Compare by name + rounded ml (matches UIKit's loose equality).
        for (idx, ing) in ingredients.enumerated() {
            let other = originalBaseAndMixer[idx]
            if ing.name != other.name { return true }
            let lhsQty = Int((ing.quantity ?? 0).rounded())
            let rhsQty = Int((other.quantity ?? 0).rounded())
            if lhsQty != rhsQty { return true }
        }
        // Image change — a newly picked `selectedImage` always counts,
        // AND deleting an existing remote image (`remoteImageURL` cleared
        // while the original recipe had a non-empty `image.url`) also
        // counts as a change. 1:1 with UIKit
        // `EditViewModel.hasUnsavedChanges` which compares the recipe
        // snapshot's `image.url` to the current value.
        if selectedImage != nil { return true }
        let originalHasImage = !(original.image?.url?.isEmpty ?? true)
        if originalHasImage && remoteImageURL == nil { return true }
        return false
    }

    // MARK: - Button style helpers (ports PrimaryOrangeButton + applyCancelCapsuleGradientBorderStyle)

    @ViewBuilder
    private var editOrangeButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(
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
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("segmentSelectionColor"))
        }
    }

    @ViewBuilder
    private var editCancelCapsuleBackground: some View {
        if #available(iOS 26.0, *) {
            // Force the light-mode wet-glass look in BOTH color schemes.
            // `.regularMaterial` flipped to a dark pill in dark mode which
            // swallowed the cancel-border gradient overlay — the button
            // read as a dark blob with a faint rim instead of the crisp
            // white-glass capsule UIKit shows. Explicit white tint +
            // cancelButtonGray wash preserves the light-mode pixels and
            // gives dark mode the same white-glass "Save" pill the user
            // sees in light mode (matches the popup secondary-button fix
            // at Theme.swift:1396).
            Capsule(style: .continuous)
                .fill(SwiftUI.Color.white.opacity(0.85))
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Theme.Color.cancelButtonGray.opacity(0.12))
                )
        } else {
            // Pre-iOS 26 fallback — `Theme.Color.surface` light value
            // is sRGB(1, 1, 1), bit-identical to the previous hard-coded
            // `Color.white`, so light mode renders the EXACT same edit
            // cancel capsule. Dark mode picks up elevated dark surface
            // (#2C2C2E) for visual consistency on the dark Edit panel.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Color.surface)
        }
    }

    @ViewBuilder
    private var editCancelCapsuleBorder: some View {
        if #available(iOS 26.0, *) {
            // 1:1 with UIKit `applyCancelCapsuleGradientBorderStyle(borderColors:)`
            // (UIViewClass+GradientStyles.swift L92-110): 8-stop alternating
            // white(@0.95) ↔ cancelBorderGray(@0.9) sheen on a diagonal,
            // 1.5pt line width. Reproduces the etched-glass border effect
            // UIKit applies to the Save / Cancel capsule on iOS 26+.
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.95),                       location: 0.00),
                            .init(color: Theme.Color.cancelBorderGray.opacity(0.9),  location: 0.20),
                            .init(color: .white.opacity(0.95),                       location: 0.40),
                            .init(color: .white.opacity(0.95),                       location: 0.60),
                            .init(color: Theme.Color.cancelBorderGray.opacity(0.9),  location: 0.80),
                            .init(color: .white.opacity(0.95),                       location: 1.00)
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
    /// Fired when the quantity field gains focus. The parent uses this
    /// to scroll the ingredients ScrollView so the focused row stays
    /// visible above the keyboard.
    var onFocus: (() -> Void)? = nil

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
                Image("deleteImg")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
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
                    HapticService.light()
                    adjust(by: -10)   // UIKit maxIncrementDecrementValueForMl
                } label: {
                    Image("newMinus")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color("grayBorderColor"))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Decrease \(ingredient.name)")

                // Quantity field + unit — matches RecipeIngredientRow stepper:
                // spacing 0 so the qty digits sit tight against the unit
                // label, fixed 28pt qty width so columns line up across
                // rows regardless of digit count, height pinned to 30pt.
                HStack(spacing: 0) {
                    TextField("", text: $editingText)
                        .keyboardType(unit == .ml ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("mediumLightGrayColor"))
                        .frame(width: 28, height: 30)
                        .focused($isFocused)
                        .onChange(of: isFocused) { focused in
                            if focused {
                                editingText = displayQty
                                onFocus?()
                            } else { commitEdit() }
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
                .frame(height: 30)

                // Plus button — 30×30, `grayBorderColor` tint.
                Button {
                    HapticService.light()
                    adjust(by: +10)
                } label: {
                    Image("newPlus")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
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

    /// UIKit `applyCellGlassStyle()` from EditViewController.swift L178-187:
    ///   iOS 26+: view.addGlassEffect(cornerRadius: xlarge=20, alpha: 1.0)
    ///            → real `UIGlassEffect(style: .regular)` UIVisualEffectView
    ///   Pre-26: roundCorners = pill(24), borderWidth=1,
    ///           gradientLayer [black@10%, white@10%], borderColor = #F2F2F2
    @ViewBuilder
    private var editCellBackground: some View {
        if #available(iOS 26.0, *) {
            // UIKit iOS 26 branch — cell gets the same `UIGlassEffect
            // (.regular)` the UIKit side-menu / Edit-panel helper
            // installs. Pure glass (no whitening overlay) so the
            // cell stays semi-transparent over the panel's own glass,
            // exactly like UIKit's nested `addGlassEffect` surfaces.
            BarsysGlassPanelBackground()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            // UIKit pre-26 branch: solid white + vertical gradient
            // overlay on a capsule (radius = pill = 24).
            // `Theme.Color.surface` light value is sRGB(1, 1, 1),
            // bit-identical to the previous hard-coded `Color.white`,
            // so light mode renders the EXACT same edit cell capsule.
            // Dark mode picks up the elevated dark surface (#2C2C2E)
            // so ingredient cells inside the dark Edit panel read as
            // raised cards instead of stark white slabs.
            Capsule()
                .fill(Theme.Color.surface)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.10), Color.white.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                )
        }
    }

    @ViewBuilder
    private var editCellBorder: some View {
        if #available(iOS 26.0, *) {
            // UIKit `addGlassEffect(...)` doesn't add a border
            // (`isBorderEnabled` is a dead parameter — see
            // UIViewClass+GlassEffects.swift L31-68). Keep a very
            // faint sheen stroke only for slight edge definition so
            // cells don't visually dissolve into the panel glass.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        } else {
            // UIKit pre-26 `applyCellGlassStyle` border: 1pt #F2F2F2
            // on a pill (radius 24).
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

// MARK: - AddIngredientSheet
//
// 1:1 with UIKit `EditViewModel.processUploadedIngredients` post-effect:
// adds an `Ingredient` (unit ml, quantity ≥ 5, ingredientOptional false,
// non-empty name, no duplicate by lowercased name) to the recipe.
//
// UIKit gets the name from the AI ingredient-detection backend; SwiftUI
// surfaces a tiny entry sheet so the user can still produce the same
// downstream effect without the backend dependency. Validation matches
// `EditViewModel+API.processUploadedIngredients` exactly:
//   • Trimmed name must be non-empty
//   • Quantity must parse and be >= 5 ml (`NumericConstants.minimumQtyDouble`)
//   • Reject duplicates (by lowercased name) — same check as
//     `hasDuplicateIngredient(primary:secondary:)` but on name.
struct AddIngredientSheet: View {
    let unit: MeasurementUnit
    let existingNames: [String]
    let onAdd: (Ingredient) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var quantityText: String = ""
    @State private var errorMessage: String?

    private var unitLabel: String { unit == .ml ? "ml" : "oz" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("primaryBackgroundColor").ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    // Name field — same underline + 12pt placeholder as the
                    // EditRecipe name field.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredient Name")
                            .font(.system(size: 12))
                            .foregroundStyle(Color("charcoalGrayColor").opacity(0.7))
                        TextField("e.g. Vodka", text: $name)
                            .font(.system(size: 14))
                            .foregroundStyle(Color("appBlackColor"))
                            .textInputAutocapitalization(.words)
                            .frame(height: 40)
                        Rectangle()
                            .fill(Color("veryDarkGrayColor"))
                            .frame(height: 1)
                    }

                    // Quantity field — keyboard matches the unit
                    // (numberPad for ml, decimalPad for oz) just like
                    // `IngredientDisplayData.keyboardType`.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quantity (\(unitLabel))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color("charcoalGrayColor").opacity(0.7))
                        TextField(unit == .ml ? "30" : "1", text: $quantityText)
                            .font(.system(size: 14))
                            .foregroundStyle(Color("appBlackColor"))
                            .keyboardType(unit == .ml ? .numberPad : .decimalPad)
                            .frame(height: 40)
                        Rectangle()
                            .fill(Color("veryDarkGrayColor"))
                            .frame(height: 1)
                    }

                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(Color("errorLabelColor"))
                    }

                    Spacer()

                    // Add button — same orange/glass capsule treatment as
                    // the Edit screen's Craft button (PrimaryOrangeButton +
                    // makeOrangeStyle / segmentSelectionColor fallback).
                    Button {
                        HapticService.light()
                        addIngredient()
                    } label: {
                        Text("Add Ingredient")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color("appBlackColor"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background(addButtonBackground)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Add ingredient to recipe")
                }
                .padding(24)
            }
            .navigationTitle("New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticService.light()
                        dismiss()
                    } label: {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "xmark")
                        } else {
                            Text("Cancel")
                        }
                    }
                    .tint(Color("appBlackColor"))
                }
            }
        }
    }

    @ViewBuilder
    private var addButtonBackground: some View {
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

    private func addIngredient() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter an ingredient name."
            return
        }
        if existingNames.contains(trimmedName.lowercased()) {
            // Mirrors UIKit `processUploadedIngredients` duplicate check.
            errorMessage = Constants.hasSameIngredientInDrink
            return
        }
        let parsed = Double(quantityText.replacingOccurrences(of: ",", with: "."))
        let qtyInput = parsed ?? 0
        // Convert oz input to ml (canonical storage) using same constant
        // as `EditIngredientRow.commitEdit` (29.5735 ml/oz).
        let ml = (unit == .oz) ? qtyInput * 29.5735 : qtyInput
        // Clamp to the same min/max range as the UIKit slider:
        //   floor   = 5 ml  (NumericConstants.minimumQtyDouble)
        //   ceiling = 750 ml (NumericConstants.maximumQuantityDoubleMLFor360)
        let clamped = max(5, min(750, ml > 0 ? ml : 30))
        let ing = Ingredient(
            name: trimmedName,
            unit: Constants.mlText,
            quantity: clamped
        )
        onAdd(ing)
        dismiss()
    }
}
