//
//  SideMenuView.swift
//  BarsysAppSwiftUI
//
//  Direct 1:1 port of:
//    - BarsysApp/Controllers/SideMenu/SideMenuViewController.swift (345 lines)
//    - BarsysApp/StoryBoards/Base.lproj/SideMenu.storyboard scene "XDb-u3-YWN"
//    - BarsysApp/Helpers/Constants/Constants+UI.swift::SideMenuConstants.arraySideMenu
//    - BarsysApp/Helpers/CustomViews/UIViewController+Navigation.swift::setupSideMenuForSwipe / openSideMenu
//    - SideMenuNavigationController configuration:
//          leftSide = false                    (presents from the RIGHT)
//          presentationStyle = .menuSlideIn    (slide-in over content)
//          menuWidth = UIScreen.main.bounds.width (per UIKit code; storyboard width is 279)
//          presentDuration = 0.4, dismissDuration = 0.3
//          addScreenEdgePanGesturesToPresent(forMenu: .right) — right-edge swipe
//          addPanGestureToPresent — full-screen pan
//
//  ============== STORYBOARD LAYOUT ==============
//
//  Full-screen TR6-cr-hHT (393×852), backgroundColor clear (dismisses on tap)
//    └ dismissButton 1nV-WA-K3C (full-screen invisible button, tap → dismiss)
//    └ menuView lsy-m6-wis (279×726, trailing:0, top:8 from safeArea, bottom:0, rounded 8)
//         ├ header view gND-Tg-GnT (279×158)
//         │     ├ "My Account" label 7Wm-yA-doy (system 24pt appBlackColor, x:24, y:48)
//         │     ├ crossIcon button Qpu-iw-ryO (40×45, trailing:13, centerY with title)
//         │     ├ profileIcon image Uq9-vB-KWi (24×24, leading:24, top:31.33 from title bottom)
//         │     ├ lblName xK2-Mh-81R (boldSystem 17pt, 3 lines, leading:10 from profile trailing)
//         │     └ "Edit Profile" button Ans-0g-jJo (70×28, sys 13pt appBlackColor, below name)
//         └ tableView wnQ-Pw-bOP (279×568, insetGrouped, sectionHeaderHeight 50, rowHeight 50)
//
//  Glass effect (iOS 26+):
//    - visualEffectView apH-Xf-zT8 (blurEffect style="regular", rounded 8)
//    - sized identically to menuView, hidden in storyboard
//    - addGlassEffect(cornerRadius: 8) runtime
//
//  ============== MENU ITEMS (SideMenuConstants.arraySideMenu) ==============
//
//    0  Device            (no sub-rows → direct action: openDeviceConnectedPopUp / showPairYourDevice)
//    1  Favourites        (no sub-rows → push Favourites)
//    2  Help              (sub-rows: FAQs, Contact us)
//    3  Preferences       (no sub-rows → push UnitPreferences)
//    4  Privacy and Legal (sub-rows: Privacy Policy, Terms of Service)
//    5  About Barsys      (sub-rows: About Us, Version 1.0.0)
//    6  Review the App    (confirm alert → App Store URL)
//    7  Logout            (confirm alert → logout + clearAll)
//
//  SpeakEasy case (`AppStateManager.shared.isSpeakEasyCase == true`):
//    - Favourites row is removed from the array
//

import SwiftUI

// MARK: - Models (ports SideMenuSections / SideMenuRows)

struct SideMenuSection: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subRows: [SideMenuRow]
}

struct SideMenuRow: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

enum SideMenuConstants {
    static let arraySideMenu: [SideMenuSection] = [
        .init(name: "Device",           subRows: []),
        .init(name: "Favourites",       subRows: []),
        .init(name: "Help",             subRows: [.init(name: "FAQs"), .init(name: "Contact us")]),
        .init(name: "Preferences",      subRows: []),
        .init(name: "Privacy and Legal",subRows: [.init(name: "Privacy Policy"), .init(name: "Terms of Service")]),
        .init(name: "About Barsys",     subRows: [.init(name: "About Us"), .init(name: "Version 1.0.0")]),
        .init(name: "Review the App",   subRows: []),
        .init(name: "Logout",           subRows: [])
    ]
}

// MARK: - SideMenuOverlay
//
// Top-level container. Rendered as the last child of MainTabView so it can
// cover the entire screen including the tab bar. Drives its presentation
// from `router.showSideMenu`.

struct SideMenuOverlay: View {
    @EnvironmentObject private var router: AppRouter

    // MARK: - State

    /// Live x-offset of the panel while a drag is in progress.
    ///   0           → fully visible (flush right edge)
    ///   panelWidth  → fully offscreen (shifted right one panel-width)
    ///   nil         → no drag in progress; fall back to rest position
    @State private var liveDragOffset: CGFloat? = nil
    @State private var pendingOpen: Bool = false

    // MARK: - Layout constants

    /// Visible panel width (matches storyboard menuView frame).
    private let panelWidth: CGFloat = 279

    /// Gesture normalization distance. UIKit SideMenuSwift uses
    /// `menu.menuWidth = UIScreen.main.bounds.width`, so a full
    /// screen-width finger travel maps to 0→100% progress.
    /// This makes the gesture feel **gradual** (not jumpy).
    private var gestureWidth: CGFloat { UIScreen.main.bounds.width }

    /// Returns `true` on every iPad, regardless of iOS version.
    /// Used to swap the full-screen `ScreenEdgePanGesture` representable
    /// for a narrow edge-only strip — the full-screen variant produces
    /// a hit-test collision on iPad (both pre-iOS-26 and iOS 26+) that
    /// swallows every tap in the content below (tab bar, back, card
    /// buttons). iPhone (any version) always returns `false` so the
    /// full-screen representable stays in place there — behaviour on
    /// iPhone is preserved bit-for-bit.
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // MARK: - Critically-damped spring (matches UIKit SideMenuSwift)
    //
    // UIKit uses `usingSpringWithDamping: 1.0, initialSpringVelocity: V`
    // with `completeGestureDuration ≈ 0.35s`. An interpolating spring with
    // stiffness 300 / damping 30 settles in ~0.35s with no overshoot —
    // the same critically-damped behavior.

    private func commitSpring(velocity: CGFloat) -> Animation {
        .interpolatingSpring(stiffness: 300, damping: 30, initialVelocity: velocity)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .trailing) {

            // Full-screen sizing proxy. Never blocks touches.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            // ---- Scrim ----
            // ALWAYS mounted. Opacity is 0 when the panel is offscreen, so
            // there's no pop from SwiftUI's insert/remove transition.
            // Supports BOTH tap-to-close AND swipe-right-to-close, matching
            // UIKit SideMenuSwift where `addPanGestureToPresent` is installed
            // on the full presenting view (scrim + panel).
            Color.black
                // Scrim is invisible (opacity 0) when fully closed.
                // Adding an explicit `opacity(isVisible ? ...)` gate
                // prevents sub-pixel artifacts from the always-mounted
                // Color.black compositing at opacity ≈ 0.
                .opacity(isVisible ? scrimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissMenu(velocity: 0) }
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard router.showSideMenu else { return }
                            let tx = max(0, min(panelWidth, value.translation.width))
                            liveDragOffset = tx
                        }
                        .onEnded { value in
                            guard router.showSideMenu else { return }
                            let travelled = max(0, value.translation.width)
                            let past = travelled > panelWidth * 0.35
                            let fast = value.predictedEndTranslation.width > panelWidth * 0.6
                            let overshoot = max(0, value.predictedEndTranslation.width - value.translation.width)
                            let vel = overshoot / panelWidth
                            if past || fast {
                                dismissMenu(velocity: vel)
                            } else {
                                cancelClose(velocity: vel)
                            }
                        }
                )
                .allowsHitTesting(isVisible)

            // ---- Panel ----
            // ALWAYS mounted, positioned offscreen via offset when closed.
            // No `if isVisible` / `.transition()` — those caused jank
            // because SwiftUI ran an insertion animation that fought the
            // live finger-tracked offset during interactive open.
            SideMenuPanel(onDismiss: { dismissMenu() })
                .frame(width: panelWidth)
                .offset(x: panelOffsetX)
                // Fully transparent when closed — prevents the panel edge
                // from flashing due to safe-area rounding when it sits at
                // offset == panelWidth (exactly at the screen edge).
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .zIndex(1)
                // Interactive close: rightward drag on the open panel.
                // Uses SwiftUI DragGesture (works fine here because the
                // panel sits above TabView). Cells still receive taps
                // because minimumDistance > 0.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard router.showSideMenu else { return }
                            let tx = max(0, min(panelWidth, value.translation.width))
                            liveDragOffset = tx
                        }
                        .onEnded { value in
                            guard router.showSideMenu else { return }
                            let travelled = max(0, value.translation.width)
                            let past = travelled > panelWidth * 0.35
                            let fast = value.predictedEndTranslation.width > panelWidth * 0.6
                            // Derive velocity from predicted overshoot.
                            // `predictedEndTranslation - translation` approximates
                            // how far the finger would coast, which is proportional
                            // to velocity. Normalize by panelWidth.
                            let overshoot = max(0, value.predictedEndTranslation.width - value.translation.width)
                            let vel = overshoot / panelWidth
                            if past || fast {
                                dismissMenu(velocity: vel)
                            } else {
                                cancelClose(velocity: vel)
                            }
                        }
                )

            // ---- Edge-pan to open ----
            // UIKit `SideMenuManager.addScreenEdgePanGesturesToPresent(forMenu: .right)`
            // Uses `gestureWidth` (screen width) so sensitivity matches UIKit exactly.
            //
            // On iPad + iOS 26, the SwiftUI/UIKit bridge captures the
            // first-touch event on a `.zIndex(2)` top-level
            // `UIViewRepresentable` that has `maxWidth: .infinity` —
            // even though `PassthroughView.hitTest` returns `nil`
            // outside the 40pt right-edge zone. That swallowed every
            // tap in the content below (tab bar, back button, toolbar
            // buttons, card buttons) while swipes still fired.
            //
            // Fix: on iPad + iOS 26 we confine the representable to a
            // narrow 60pt strip pinned to the right edge via an HStack
            // (Spacer on the left is marked non-interactive so it
            // can't eat taps). The `UIScreenEdgePanGestureRecognizer`
            // is already filtered to the rightmost 40pt by UIKit, so
            // a 60pt representable gives the gesture everything it
            // needs without sitting over the rest of the screen. On
            // iPhone (any version) and iPad pre-iOS-26 we keep the
            // original full-screen representable — behaviour there
            // is untouched and known-good.
            Group {
                if Self.isIPad {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                        ScreenEdgePanGesture(
                            mode: .openFromRightEdge,
                            onProgress: { progress in
                                if !pendingOpen && !router.showSideMenu {
                                    pendingOpen = true
                                    HapticService.light()
                                }
                                liveDragOffset = panelWidth * (1 - progress)
                            },
                            onEnded: { committed, velocity in
                                guard pendingOpen else { return }
                                if committed {
                                    completeOpen(velocity: velocity)
                                } else {
                                    cancelOpen(velocity: velocity)
                                }
                            },
                            totalWidth: gestureWidth
                        )
                        .frame(width: 60)
                        .frame(maxHeight: .infinity)
                    }
                    .ignoresSafeArea()
                } else {
                    ScreenEdgePanGesture(
                        mode: .openFromRightEdge,
                        onProgress: { progress in
                            if !pendingOpen && !router.showSideMenu {
                                pendingOpen = true
                                HapticService.light()
                            }
                            // progress ∈ [0, 1] normalized by screen width.
                            // Map to panel offset: 0 = fully offscreen, 1 = fully visible.
                            liveDragOffset = panelWidth * (1 - progress)
                        },
                        onEnded: { committed, velocity in
                            guard pendingOpen else { return }
                            if committed {
                                completeOpen(velocity: velocity)
                            } else {
                                cancelOpen(velocity: velocity)
                            }
                        },
                        totalWidth: gestureWidth
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }
            }
            // Right-edge swipe is BLOCKED while:
            //   • the right side menu is already open, OR
            //   • the BarBot history (left menu) is open.
            //
            // UIKit SideMenuManager only allows one menu at a time; when
            // the LEFT menu is on screen, swiping the right edge does
            // NOT open the right menu — the user must dismiss the left
            // panel first (by swiping left or tapping the dead-zone),
            // and only then can a fresh right-edge swipe open the right
            // menu. Mirroring that here so users can't end up with both
            // panels mid-animation.
            .allowsHitTesting(!router.showSideMenu && !router.showBarBotHistory)
            .zIndex(2)
        }
        // Zero implicit animation on the ZStack — all animations are
        // explicit via `withAnimation` in the commit helpers. An ambient
        // `.animation(_:value:)` fought the interactive drag.
        .onChange(of: router.showSideMenu) { _ in
            liveDragOffset = nil
        }
    }

    // MARK: - Derived state

    private var isVisible: Bool {
        router.showSideMenu || pendingOpen
    }

    private var panelOffsetX: CGFloat {
        if let live = liveDragOffset { return live }
        return router.showSideMenu ? 0 : panelWidth
    }

    private var scrimOpacity: Double {
        let fraction = 1.0 - Double(panelOffsetX / panelWidth)
        return max(0, min(0.35, 0.35 * fraction))
    }

    // MARK: - Commit helpers
    //
    // Each receives the gesture velocity so the animation starts at the
    // finger's speed and decelerates naturally — matching UIKit's
    // `UIView.animate(usingSpringWithDamping: 1.0, initialSpringVelocity: V)`.

    /// Interactive open committed. Animate from current offset → 0 (fully open).
    /// UIKit SideMenuManager mutex (BarBot history auto-dismiss) is now
    /// enforced by `AppRouter.showSideMenu.didSet`, so we don't have to
    /// clear `showBarBotHistory` explicitly here.
    private func completeOpen(velocity: CGFloat = 0) {
        HapticService.light()
        withAnimation(commitSpring(velocity: velocity)) {
            router.showSideMenu = true
            liveDragOffset = nil
            pendingOpen = false
        }
    }

    /// Interactive open cancelled. Snap back to closed (offset = panelWidth).
    private func cancelOpen(velocity: CGFloat = 0) {
        withAnimation(commitSpring(velocity: velocity)) {
            liveDragOffset = nil
            pendingOpen = false
        }
    }

    /// Close the menu — called from gesture commit, scrim tap, or cross button.
    private func cancelClose(velocity: CGFloat = 0) {
        withAnimation(commitSpring(velocity: velocity)) {
            liveDragOffset = nil
        }
    }

    /// Dismiss the menu (committed close gesture, scrim tap, or button).
    private func dismissMenu(velocity: CGFloat = 0) {
        withAnimation(commitSpring(velocity: velocity)) {
            router.showSideMenu = false
            liveDragOffset = nil
            pendingOpen = false
        }
    }

    /// Programmatic open from the hamburger button (no gesture velocity).
    /// Uses UIKit-matched `presentDuration = 0.4, curveEaseInOut`.
    /// SideMenuManager mutex (BarBot history dismiss) is enforced by
    /// `AppRouter.showSideMenu.didSet`.
    static func openMenu(router: AppRouter) {
        withAnimation(.easeInOut(duration: 0.4)) {
            router.showSideMenu = true
        }
    }
}

// MARK: - SideMenuPanel
//
// The actual 279pt-wide panel. Ports the menuView (lsy-m6-wis) from the
// storyboard with its header (gND-Tg-GnT) + inset-grouped table.

private struct SideMenuPanel: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var userStore: UserProfileStore

    let onDismiss: () -> Void

    /// Ports `selectedSection` — only one section is expanded at a time.
    @State private var selectedSection: Int? = nil

    /// Shows DeviceConnectedPopup when tapping "Device" while connected.
    /// Ports UIKit `openDeviceConnectedPopUp()`.
    @State private var showDeviceConnectedPopup = false

    private var arrMenu: [SideMenuSection] {
        // Matches `SideMenuViewController.viewDidAppear` SpeakEasy branch:
        //   if isSpeakEasyCase && arrMenu[1].name == "Favourites" {
        //       arrMenu.remove(at: 1)
        //   }
        if AppStateManager.shared.isSpeakEasyCase {
            return SideMenuConstants.arraySideMenu.filter { $0.name != "Favourites" }
        }
        return SideMenuConstants.arraySideMenu
    }

    /// Live user name — reads from the observable `UserProfileStore` so the
    /// label re-renders automatically when login completes. Falls back to
    /// `auth.profile.firstName` (also observed) then to an empty string.
    private var displayName: String {
        if !userStore.name.isEmpty { return userStore.name }
        if !auth.profile.firstName.isEmpty { return auth.profile.firstName }
        return ""
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            // Background — 1:1 port of UIKit `SideMenuViewController.swift` L51-61:
            //
            //   if #available(iOS 26.0, *) {
            //       menuView.backgroundColor = .clear
            //       menuView.addGlassEffect(cornerRadius: BarsysCornerRadius.small) // 8pt
            //       tblMenu.backgroundColor   = .clear
            //   } else {
            //       menuView.backgroundColor = .white
            //       tblMenu.backgroundColor  = .white
            //   }
            //
            // `menuView.addGlassEffect(cornerRadius: 8)` inserts a real
            // `UIVisualEffectView(effect: UIGlassEffect(style: .regular))`
            // at z-index 0 (UIViewClass+GlassEffects.swift L31-68).
            //
            // The UIKit reference screenshot (side menu open over the
            // Home screen) shows the red device backdrop, cocktail
            // image, eucalyptus branch, and coaster all clearly
            // recognisable THROUGH the panel — softly blurred but NOT
            // heavily whitened. So the port uses pure
            // `UIGlassEffect(.regular)` on iOS 26 and
            // `UIBlurEffect(.systemMaterial)` pre-26, with NO
            // additional white-tint overlay (white overlay would hide
            // the content the UIKit reference keeps visible).
            //
            // `BarsysGlassPanelBackground` is declared in
            // RecipesScreens.swift.
            BarsysGlassPanelBackground()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Foreground content — header grows intrinsically with the
            // user-name length (UIKit autolayout does the same via the
            // `gND-Tg-GnT.bottom = Ans-0g-jJo.bottom` constraint); the
            // menu list starts immediately below the Edit Profile
            // button. The old hard-coded 158pt cap was the cause of
            // the name-label / Edit Profile button OVERLAP bug on
            // users whose full name wraps to a second or third line.
            VStack(spacing: 0) {
                headerOverlay
                    .frame(maxWidth: .infinity, alignment: .leading)

                menuList
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Outer drop-shadow on the left edge of the panel (so the content
        // behind it gets a subtle shaded border on the hinge side).
        .shadow(color: .black.opacity(0.22), radius: 22, x: -6, y: 0)
        .padding(.top, 8) // matches `lsy-m6-wis` top:8 from safeArea top
        .padding(.bottom, 0)
    }

    // MARK: - Header overlay (ports gND-Tg-GnT — 279pt wide, INTRINSIC height)
    //
    // UIKit autolayout (SideMenu.storyboard — constraints on lblName,
    // btnEditProfile, and the profile avatar):
    //
    //   • `7Wm-yA-doy`  My Account           top = gND.top + 48,   leading = 24
    //   • `Qpu-iw-ryO`  crossIcon dismiss    centerY = 7Wm.centerY, trailing = 13
    //   • `Uq9-vB-KWi`  profileIcon avatar   24×24, leading = 24 (= 7Wm.leading),
    //                                        top = 7Wm.bottom + 31.33
    //   • `xK2-Mh-81R`  lblName (3 lines)    leading = avatar.trailing + 10,
    //                                        centerY = avatar.centerY,
    //                                        trailing = gND.trailing − 15
    //   • `Ans-0g-jJo`  Edit Profile btn     70×28, leading = lblName.leading,
    //                                        top    = lblName.bottom + 10,
    //                                        bottom = gND.bottom
    //
    // **Critical**: the storyboard anchors the BOTTOM of the header to
    // the Edit Profile button's BOTTOM — so the header GROWS as the
    // user name wraps from 1 → 2 → 3 lines. The previous port used
    // absolute `.position(x:y:)` with hard-coded coordinates (lblName
    // y=120, btn y=144), which worked only for single-line names.
    // Long names wrap into the button causing the visible overlap bug.
    //
    // Re-implemented as a pair of VStacks so SwiftUI's layout engine
    // intrinsically sizes both the label (up to 3 lines) and pushes
    // the Edit Profile button below it — no overlap possible.

    private var headerOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1 — "My Account" title (y=48, h=28.67)
            // and the cross dismiss button, vertically centered on the
            // title (storyboard `dk6-jo-0dC`: Qpu.centerY = 7Wm.centerY).
            HStack(alignment: .center, spacing: 0) {
                Text("My Account")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    // 40×45 hit target (Qpu-iw-ryO frame); 13×12 icon
                    // (crossIcon image intrinsic size). ZStack so the
                    // extra padding stays tappable.
                    ZStack {
                        Color.clear.frame(width: 40, height: 45)
                        Image("crossIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13, height: 12)
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
                .accessibilityHint("Double tap to close the side menu")
            }
            .padding(.top, 48)                       // 8mo-QR-unJ: title top=48
            .padding(.leading, 24)                   // vvp-Jn-SJe: title leading=24
            .padding(.trailing, 13)                  // cdZ-yj-PCa: Qpu trailing=13

            // Row 2 — avatar on the left, name + Edit Profile stacked
            // on the right.
            //
            // UIKit constraint `Emx-R3-Bhf`:
            //   xK2-Mh-81R.centerY = Uq9-vB-KWi.centerY
            // i.e. the user-name label's vertical centre is pinned to
            // the avatar's vertical centre. As the name wraps from
            // 1 → 2 → 3 lines, the avatar visually sits in the MIDDLE
            // of the label block (the label grows both upward and
            // downward around its centre).
            //
            // SwiftUI mirrors that with `HStack(alignment: .center)`
            // across the avatar + the name/edit-button VStack. The
            // avatar's small fixed size means the VStack drives the
            // row height — which is exactly what UIKit autolayout
            // produces at runtime.
            HStack(alignment: .center, spacing: 10) {
                profileAvatar

                // VStack spacing tuned for visual parity with UIKit's
                // `gVk-Ao-Hw7` constraint (`Edit Profile.top = lblName.bottom + 10`).
                //
                // SwiftUI's `Text` frame includes line-height + descender
                // padding (~3-4pt past the visible baseline) AND the
                // 70×28 Button frame centers its 13pt text vertically
                // (≈ 7.5pt empty above the glyphs). With a literal
                // `spacing: 10` the apparent gap measures ≈ 20pt — a
                // few points wider than UIKit's tighter ≈ 17pt visual.
                //
                // Tightening the SwiftUI spacing to **4pt** restores the
                // UIKit visual rhythm (Text descender + 4 + button top
                // padding ≈ 14-15pt — matches what users see in the
                // storyboard preview).
                VStack(alignment: .leading, spacing: 4) {
                    // lblName — boldSystem 17pt, up to 3 lines,
                    // trailing = gND.trailing − 15 (iDc-ap-JHv).
                    //
                    // `.lineSpacing(0)` clamps any extra line-spacing
                    // SwiftUI may add for multi-line wraps so the bottom
                    // of the visible glyph block sits where UIKit's
                    // `lblName.bottom` constraint anchor sits.
                    Text(displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color("appBlackColor"))
                        .lineLimit(3)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("User name")

                    // Edit Profile button — leading aligned with lblName
                    // (ZOv-t3-Hts), 70×28 fixed size (storyboard frame).
                    // Internal text padding centered (UIButton default).
                    Button {
                        HapticService.light()
                        onDismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            router.push(.myProfile)
                        }
                    } label: {
                        Text("Edit Profile")
                            .font(.system(size: 13))
                            .foregroundStyle(Color("appBlackColor"))
                            .frame(width: 70, height: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 24)                   // avatar.leading = 24
            .padding(.trailing, 15)                  // lblName.trailing = 15 from gND
            .padding(.top, 31.33)                    // kx7-en-hLr: avatar.top = title.bottom + 31.33

            // Bottom spacer — mirrors the UIKit constraint
            // `gND-Tg-GnT.bottom = Ans-0g-jJo.bottom` (rjb-tJ-Xnj).
            // No fixed header height; parent VStack lets the menu list
            // sit directly underneath.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Avatar view for the side menu header — reads the profile image URL
    /// from the observable `UserProfileStore` which mirrors
    /// `UserDefaultsClass.getProfileImage()` (same key the UIKit
    /// `MyProfileApiService.getProfile()` writes to). Falls back to the
    /// static `profileIcon` asset if no URL is present or the image fails
    /// to load.
    @ViewBuilder
    private var profileAvatar: some View {
        if !userStore.profileImageURL.isEmpty,
           let url = URL(string: userStore.profileImageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                case .empty, .failure:
                    fallbackProfileIcon
                @unknown default:
                    fallbackProfileIcon
                }
            }
        } else {
            fallbackProfileIcon
        }
    }

    private var fallbackProfileIcon: some View {
        Image("profileIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .foregroundStyle(Color("appBlackColor"))
    }

    // MARK: - Menu list (ports the inset-grouped tableView)
    //
    // Storyboard heights:
    //   heightForHeaderInSection = 60   (SideMenuViewController.swift line 278)
    //   heightForRowAt           = UITableView.automaticDimension (expanded)
    //                              0 (collapsed)
    //
    // SideMenuHeaderView.xib frames:
    //   btnImage           x=24, y=16.67, w=19,  h=18   (section icon)
    //   lblSection (stack) x=53, y=10.67, w=289, h=30   (system 17pt appBlackColor)
    //   btndropDownArrow   stack.trailing, 30×30
    //
    // SideMenuTableViewCell.xib frames:
    //   lblSection (stack) x=38, y=0,  w=266, h=35       (leading 38 indent)

    private var menuList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(arrMenu.enumerated()), id: \.element.id) { index, section in
                    VStack(spacing: 0) {
                        sectionHeader(section: section, index: index)
                            .frame(height: 60) // matches heightForHeaderInSection = 60
                            .frame(maxWidth: .infinity)

                        if selectedSection == index && !section.subRows.isEmpty {
                            ForEach(section.subRows) { row in
                                subRow(row: row)
                                    .frame(minHeight: 35) // matches xib cell height 35
                                    .frame(maxWidth: .infinity)
                            }
                            .transition(.opacity)
                        }
                    }
                }
                Spacer(minLength: 24)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedSection)
        }
        // Logout confirmation popup — surfaced through `env.alerts` so it
        // renders via `BarsysAlertOverlay`, which is the direct SwiftUI
        // port of UIKit `AlertPopUpHorizontalStackController`
        // (orange-filled primary on the right, bordered neutral on the
        // left, no close X). The previous `.confirmationDialog` path
        // rendered a native iOS action sheet and didn't match the
        // UIKit custom popup visuals or button labels (UIKit uses
        // "No", not "Cancel"). Triggered from `handleSectionTap` via
        // `presentLogoutConfirmation()` below.
        // Rating popup is now shown at the MainTabView level via
        // router.pendingRatingPopup — see handleSectionTap "Review the App".
        // Device Connected Popup — shown when tapping "Device" while connected.
        // Ports UIKit `openDeviceConnectedPopUp()` which presents
        // DeviceConnectedController modally with .overFullScreen.
        .fullScreenCover(isPresented: $showDeviceConnectedPopup) {
            DeviceConnectedPopup(isPresented: $showDeviceConnectedPopup)
                .background(ClearBackgroundViewForSideMenu())
        }
        // 1:1 with UIKit `SideMenuViewController.viewWillAppear`:
        //   selectedSection = nil
        //   tblMenu.reloadData()
        // — every time the side menu opens, all expanded section rows
        // collapse so the user starts from a clean state.
        //
        // SideMenuPanel is ALWAYS-mounted (not conditionally rendered)
        // so its `@State selectedSection` would otherwise persist across
        // open/close cycles. Observing `router.showSideMenu` and
        // resetting on EVERY transition (open AND close) guarantees the
        // collapsed state on re-open even if the user never went through
        // the dismiss callback (e.g. swipe-to-close, scrim tap, mutex
        // auto-dismiss when BarBot history opens).
        .onChange(of: router.showSideMenu) { _ in
            selectedSection = nil
        }
    }

    // MARK: - Section header row (tap → expand or direct action)
    //
    // Ports `SideMenuHeaderView.xib` exactly:
    //   Icon   : leading 24,  19×18   (contentMode scaleAspectFill)
    //   Title  : leading 53,  system 17pt appBlackColor
    //            (53 = 24 icon leading + 19 icon width + 10 gap)
    //   Chevron: trailing ≈13, 30×30

    @ViewBuilder
    private func sectionHeader(section: SideMenuSection, index: Int) -> some View {
        Button {
            HapticService.light()
            handleSectionTap(section: section, index: index)
        } label: {
            ZStack(alignment: .leading) {
                Color.clear // hit-test area spanning the whole row

                // Leading icon — 19×18 at leading 24, vertically centred.
                // Uses `systemName:` so SwiftUI looks the glyph up in the
                // SF Symbol library instead of the asset catalog —
                // `systemImageFor(_:)` returns SF Symbol names (e.g.
                // `heart.fill`), so the previous bare `Image(name:)`
                // call was logging "No image named X found in asset
                // catalog" for every menu row on every render.
                Image(systemName: systemImageFor(section.name))
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 19, height: 18)
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.leading, 24)

                // Section title — leading 53, 17pt.
                HStack(spacing: 0) {
                    Text(section.name)
                        .font(.system(size: 17,
                                      weight: selectedSection == index ? .bold : .regular))
                        .foregroundStyle(Color("appBlackColor"))
                        .padding(.leading, 53)

                    Spacer(minLength: 0)

                    // Down arrow — only when section has sub-rows.
                    // Rotates 180° on expand (matches UIKit's upArrowSmall image swap).
                    if !section.subRows.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color("appBlackColor"))
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(selectedSection == index ? 180 : 0))
                            .animation(.easeInOut(duration: 0.2), value: selectedSection)
                            .padding(.trailing, 13)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Sub-row under an expanded section.
    ///
    /// Ports `SideMenuTableViewCell.xib` — label inside a stackView at x=38
    /// within the cell content view. For SwiftUI we also align the sub-row
    /// text directly under the section title (leading 53) for a cleaner
    /// hierarchical read, and add trailing padding to prevent "Privacy Policy"
    /// and "Terms of Service" from clipping on narrower devices.
    private func subRow(row: SideMenuRow) -> some View {
        Button {
            HapticService.light()
            handleRowTap(row: row)
        } label: {
            HStack(spacing: 0) {
                Text(row.name)
                    .font(.system(size: 17))
                    .foregroundStyle(Color("appBlackColor"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .padding(.leading, 53) // aligned with section title
                    .padding(.trailing, 20)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section tap handler (ports openSelectedSection)

    private func handleSectionTap(section: SideMenuSection, index: Int) {
        switch section.name {
        case "Logout":
            presentLogoutConfirmation()
            return

        case "Device":
            // If the user is already on Pair Your Device AND no device is
            // connected (so the menu row would have pushed that same
            // screen again), just dismiss the side menu. UIKit never
            // double-pushed the same VC because `SideMenuViewController`
            // checked the top of the nav stack before presenting.
            if !ble.isAnyDeviceConnected && router.isShowingPairDevice {
                onDismiss()
                return
            }
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                // UIKit: if connected → openDeviceConnectedPopUp(), else → showPairYourDevice()
                if ble.isAnyDeviceConnected {
                    showDeviceConnectedPopup = true
                } else {
                    router.push(.pairDevice)
                }
            }
            return

        case "Preferences":
            // Already on Preferences → just close the side menu, no push.
            if router.isShowingPreferences {
                onDismiss()
                return
            }
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                router.push(.preferences)
            }
            return

        case "Favourites":
            // Already on Favourites → just close the side menu, no push.
            if router.isShowingFavorites {
                onDismiss()
                return
            }
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                router.push(.favorites)
            }
            return

        case "Review the App":
            // UIKit: dismissSideMenu(isAnimated: false) FIRST, THEN shows
            // the rating popup on UIApplication.shared.topViewController().
            // We dismiss the side menu and set a pending popup on the router
            // so MainTabView shows it on the full screen.
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                router.pendingRatingPopup = .confirm(
                    title: Constants.wouldYouLikeRatingTextForSideMenu,
                    message: nil,
                    primaryTitle: ConstantButtonsTitle.yesPleaseButtonTitle,
                    secondaryTitle: ConstantButtonsTitle.noStayInAppButtonTitle,
                    primaryFillColor: "segmentSelectionColor",
                    isCloseHidden: true
                )
            }
            return

        default:
            // Expandable sections (Help, Privacy and Legal, About Barsys).
            if section.subRows.isEmpty { return }
            if selectedSection == index {
                selectedSection = nil
            } else {
                selectedSection = index
            }
        }
    }

    /// Sub-row tap — opens WebView for Privacy Policy / Terms of Service / FAQs / Contact us / About Us.
    /// Mirrors the `tableView(_:didSelectRowAt:)` switch in SideMenuViewController.
    private func handleRowTap(row: SideMenuRow) {
        let name = row.name.lowercased()
        // 1:1 port of UIKit `UIViewController+DeepLinks.swift` L214-260.
        // All URLs come from the shared `WebViewURLs` enum so any
        // future URL change only needs to touch one place (matching
        // UIKit `ApiConstants.swift`).
        let destination: (url: URL, title: String)? = {
            switch name {
            case "faqs":
                return (URL(string: WebViewURLs.faqWebURL)!, "FAQs")
            case "contact us":
                return (URL(string: WebViewURLs.contactUsWebUrl)!, "Contact us")
            case "privacy policy":
                return (URL(string: WebViewURLs.privacyWebUrl)!, "Privacy Policy")
            case "terms of service":
                return (URL(string: WebViewURLs.termsOfUseWebUrl)!, "Terms of Service")
            case "about us":
                return (URL(string: WebViewURLs.aboutUsWebUrl)!, "About Us")
            default:
                return nil
            }
        }()

        // Matching analytics events from SideMenuViewController:
        switch name {
        case "faqs":            env.analytics.track("faq")
        case "contact us":      env.analytics.track("contact_us")
        case "privacy policy":  env.analytics.track("privacy_policy")
        case "terms of service":env.analytics.track("terms_of_service")
        case "about us":        env.analytics.track("about_us")
        default: break
        }

        onDismiss()
        if let destination {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                router.push(.web(destination.url, destination.title))
            }
        }
    }

    // MARK: - Logout

    /// 1:1 with UIKit `UIViewController+Navigation.logoutActionWithMessage(
    ///     reason: .userInitiated, ...)` manual branch (L54-74):
    ///
    ///     showCustomAlertMultipleButtons(
    ///         title: Constants.doYouWantToLogout,
    ///         subTitleStr: nil,
    ///         cancelButtonTitle: ConstantButtonsTitle.logoutButtonTitle,   // "Log out" — TINTED
    ///         continueButtonTitle: ConstantButtonsTitle.noButtonTitle,    // "No"     — NEUTRAL
    ///         cancelButtonColor: .segmentSelectionColor,
    ///         isCloseButtonHidden: true)
    ///
    /// The UIKit `cancelButton` becomes the SwiftUI **primary** slot
    /// (right-hand tinted orange button) and fires the destructive
    /// action; `continueButton` is the **secondary** slot (left-hand
    /// neutral bordered button) and is a pure no-op.
    private func presentLogoutConfirmation() {
        env.alerts.show(
            title: Constants.doYouWantToLogout,
            primaryTitle: ConstantButtonsTitle.logoutButtonTitle,
            secondaryTitle: ConstantButtonsTitle.noButtonTitle,
            onPrimary: { performLogout() },
            onSecondary: nil,
            hideClose: true
        )
    }

    private func performLogout() {
        // Ports `logoutAction()` from SideMenuViewController exactly:
        //   1. Dismiss side menu
        //   2. Show glass loader "Logging Out"
        //   3. Disconnect BLE + set disconnectedState = .manuallyDisconnected
        //   4. Remove device data from UserDefaults
        //   5. Clear all UserDefaults
        //   6. After 1.5s delay: hide loader → navigate to auth
        onDismiss()

        // Show loading indicator
        env.loading.show("Logging Out")

        // Disconnect BLE SILENTLY — the normal `disconnectAll()` fires
        // the `onDeviceDisconnected` callback which shows a red toast
        // ("{device} is Disconnected") and an alert. During a user-
        // initiated logout that noise chases the user onto the Login
        // screen and looks like an error; UIKit's `logoutAction()`
        // branch runs `clearPeripheral()` instead of the alert-showing
        // disconnect handler — `disconnectAllSilently()` matches that.
        ble.disconnectAllSilently()

        // Remove device data immediately
        UserDefaultsClass.removeLastConnectedDevice()
        UserDefaultsClass.removeLastConnectedDeviceTime()

        // Clear ALL UserDefaults (ports UserDefaultsClass.clearAll)
        UserDefaultsClass.clearAll()

        // Reset the in-memory `@Published var hasSeenTutorial` so it
        // tracks the just-cleared UserDefaults key. The flag no longer
        // gates post-login routing (UIKit never auto-presented a
        // tutorial after login — that's handled per-device in the
        // pairing flow), but keep the reset for parity until the
        // preference is removed.
        env.preferences.hasSeenTutorial = false

        // Clear cached recipes/mixlists timestamps so next login does fresh fetch
        UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForCacheRecipeData")
        UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForMixlistData")
        UserDefaults.standard.removeObject(forKey: "updatedDataTimeStampForFavourites")
        UserDefaults.standard.removeObject(forKey: "coreDataMixlistCount")

        // Track analytics
        env.analytics.track(TrackEventName.logoutEvent.rawValue)

        // Delay for UI transition (UIKit: 1.5s DelayedAction.afterTransition)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            env.loading.hide()
            auth.logout()
            router.logout()
        }
    }

    // MARK: - Icons

    /// The UIKit menu uses asset-catalog images named after each section
    /// (e.g. `UIImage(named: "Device")`). Several of those are missing from
    /// the SwiftUI project, so we fall back to SF Symbols that visually
    /// match each section's semantic.
    private func systemImageFor(_ sectionName: String) -> String {
        switch sectionName {
        case "Device":            return "externaldrive.fill.badge.wifi"
        case "Favourites":        return "heart.fill"
        case "Help":              return "questionmark.circle"
        case "Preferences":       return "slider.horizontal.3"
        case "Privacy and Legal": return "lock.doc"
        case "About Barsys":      return "info.circle"
        case "Review the App":    return "star.fill"
        case "Logout":            return "rectangle.portrait.and.arrow.right"
        default:                  return "line.3.horizontal"
        }
    }
}

// MARK: - BLEService convenience

extension BLEService {
    /// Matches `BleManager.disconnectedTypeState = .manuallyDisconnected` +
    /// `clearPeripheral()` sequence from `logoutAction()`.
    func disconnectAll() {
        for device in connected {
            disconnect(device)
        }
        disconnectedState = .manuallyDisconnected
        reconnectionState = .idle
    }

    /// Same as `disconnectAll()` but SUPPRESSES the
    /// `onDeviceDisconnected` toast + "Device disconnected" alert.
    /// Used by the logout / session-expired / delete-account flows —
    /// UIKit fires a soft `clearPeripheral()` on these paths WITHOUT
    /// running the alert-showing disconnect handler, so the user
    /// sees a clean transition to Login instead of a stale
    /// "{device} is Disconnected" toast chasing them onto the Auth
    /// screen. Other entry points (Control Center "Disconnect"
    /// button, unexpected peripheral drop) continue to call the
    /// standard `disconnectAll()` so the user still gets the alert.
    ///
    /// Implementation: save + null the `onDeviceDisconnected` closure
    /// across the disconnect loop so each peripheral teardown runs
    /// silently, then restore the closure in case the app is
    /// reopened (the auth flow tears down `BLEService` anyway, but
    /// restoring is defensive against future refactors).
    func disconnectAllSilently() {
        let savedHandler = onDeviceDisconnected
        onDeviceDisconnected = nil
        defer { onDeviceDisconnected = savedHandler }
        for device in connected {
            disconnect(device)
        }
        disconnectedState = .manuallyDisconnected
        reconnectionState = .idle
    }
}

// MARK: - ClearBackgroundViewForSideMenu

private struct ClearBackgroundViewForSideMenu: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Device Connected Popup
//
// 1:1 port of UIKit `DeviceConnectedController`
// (Controllers/DeviceConnected/DeviceConnectedController.swift +
//  StoryBoards/Base.lproj/Device.storyboard scene `dPi-fR-1YI`).
//
// Presented when the user taps "Device" in the side menu while a
// device is already connected. UIKit presents `.overFullScreen`
// with `backgroundColor = .clear`, so the underlying screen shows
// through and the popup's own `prominent` blur backdrop provides
// the frosted veil.
//
// ------------------- EXACT STORYBOARD LAYOUT -----------------------
//
//   root view `Pqp-LM-rcF` (393×852, bg CLEAR)
//     ├── visualEffectView `jVb-RO-feQ` (393×852, blur="prominent",
//     │       initial alpha=0.0) — backdrop that frosts the entire
//     │       underlying screen.
//     │       contains nested `b3t-O0-SEI` (153×724 leading, vibrancy
//     │       + blur="regular") — a decorative vibrancy pass layered
//     │       over the left strip of the backdrop. Purely cosmetic,
//     │       renders as a soft light column on one side of the blur.
//     │
//     ├── full-screen tap-dismiss button `Zj9-2g-TnC` (393×852, clear)
//     │       NOTE: this button has NO action wired in the storyboard —
//     │       it exists but is inert. UIKit does NOT dismiss on tapping
//     │       the backdrop; the user must hit the cross button or the
//     │       Disconnect button. SwiftUI reproduces the inert behaviour.
//     │
//     ├── glassBackgroundView `ELw-dL-uZx` (49-trailing, 49-leading, 295×337,
//     │       centerY centered, bg CLEAR in storyboard)
//     │       In code `viewWillAppear`:
//     │           glassBackgroundView.alertPopUpBackgroundStyle(
//     │               cornerRadius: BarsysCornerRadius.medium = 12)
//     │       Which resolves (UIViewClass+GradientStyles.swift L13-22) to:
//     │           iOS 26+ → addGlassEffect(cornerRadius: 12)
//     │                     (UIGlassEffect(.regular), alpha=1, isInteractive=true)
//     │           pre-26  → backgroundColor = white@0.95,
//     │                     roundCorners = 12, masksToBounds = true
//     │
//     └── popupContainerView `ASv-0m-OLs` (295×337, bg CLEAR, cornerRadius=12)
//           • pinned sibling of glassBackgroundView at IDENTICAL frame via
//             constraints ILM-cq-gRe / OQs-KP-N3m / tok-Go-mFe / ueA-Ya-rpg.
//             UIKit layers the card glass BEHIND the content so taps still
//             go through to the content's buttons.
//           ├── cross button `wcP-Xk-wlX`
//           │     50×50, top=0, trailing=0 of card,
//           │     image="crossIcon", tintColor=appBlackColor,
//           │     bg=clear. action: crossButtonClicked:
//           │
//           └── inner content `SDQ-Vi-uWQ` (247×277,
//                 top=30 leading=24 trailing=24 bottom=30 of card)
//                 ├── "Connected" label `aim-QZ-wXu`
//                 │     18pt system LIGHT, veryDarkGrayColor, centered,
//                 │     top=0 of SDQ.
//                 ├── device image `Yh9-Ww-vUh`
//                 │     FIXED 101×100, top=Connected.bottom+24,
//                 │     centerX=SDQ.centerX, image="barsys_360" /
//                 │     "barsys_coaster" / "barsys_shaker" chosen in code.
//                 ├── device type label `TXK-kT-ate`
//                 │     18pt system REGULAR, veryDarkGrayColor, centered,
//                 │     top=image.bottom+24.
//                 ├── device name label `ODO-1m-a1Y`
//                 │     14pt system LIGHT, veryDarkGrayColor, centered,
//                 │     top=type.bottom+7. Initially 0×0 (empty), grown by
//                 │     the text the code assigns (BLE name / SpeakEasy name).
//                 └── disconnect button `bKu-Ut-zme`
//                       184×40, top=name.bottom+40, centerX=SDQ.centerX,
//                       storyboard font: system 16pt, title="Disconnect",
//                       titleColor=black, cornerRadius=8
//                       (userDefinedRuntimeAttribute). bg CLEAR in storyboard.
//                       In code `viewSetup` L36-37:
//                           btnDisconnect.layer.borderColor = UIColor.borderColor.cgColor
//                           btnDisconnect.layer.borderWidth = 1.0
//                       → no fill, just a 1pt borderColor stroke over the
//                         glass card showing through. The earlier SwiftUI
//                         port filled it with pure white, which incorrectly
//                         broke the glass continuity visible in UIKit.
//
// ------------------- RUNTIME BEHAVIOUR -----------------------------
//
//   viewDidLoad  → addBounceEffect() on disconnect; HapticService.success()
//   viewWillAppear → glassBackgroundView.alertPopUpBackgroundStyle(12)
//   crossButtonClicked(_:) → HapticService.light(); dismiss(animated: true)
//   disconnectAction(_:)   → HapticService.light();
//                            DelayedAction.afterBleResponse(0.5) {
//                                dismiss(animated: false)
//                                if SpeakEasy {
//                                    toast "X is Disconnected", clear socket,
//                                    AppStateManager.setSpeakEasyCaseState(false),
//                                    coordinator.handleDisconnect(),
//                                    analytics event
//                                } else {
//                                    showGlassLoader("Disconnecting")
//                                    BleManager.disconnect() + clearPeripheral()
//                                    + disconnectedTypeState = .manuallyDisconnected
//                                    DelayedAction.afterBleResponse(0.4) {
//                                        UserDefaultsClass.removeLastConnectedDevice()
//                                    }
//                                }
//                            }
//
// ------------------- FIXES vs PRIOR PORT ---------------------------
//
//   1. ADDED the prominent-blur full-screen backdrop (`jVb-RO-feQ`) —
//      previously the SwiftUI port used `Color.black.opacity(0.001)`,
//      so the home screen behind the popup stayed completely sharp. The
//      UIKit reference frosts the entire screen behind the card.
//   2. DROPPED the glass-sheen gradient + white-border overlays on the
//      card — UIKit's `alertPopUpBackgroundStyle` applies the glass
//      effect alone without sheen or stroke. Extra overlays made the
//      SwiftUI card visibly "busier" than UIKit.
//   3. MADE the Disconnect button transparent — UIKit has NO background
//      fill on the button, only a 1pt borderColor stroke. The earlier
//      white-fill broke the glass continuity.
//   4. ENFORCED the inert backdrop — UIKit does not dismiss on tap
//      outside the card. SwiftUI now matches.

// MARK: - ProminentBlurBackdrop
//
// Wraps `UIVisualEffectView(UIBlurEffect(style: .prominent))` in a
// `UIViewRepresentable` so SwiftUI can use it as a full-screen
// backdrop. Matches UIKit `jVb-RO-feQ` — the top blur layer only.
// The nested vibrancy view (`b3t-O0-SEI`) is cosmetic and unusual
// enough (fixed 153×724 strip) that it is NOT re-created here; its
// visual contribution on top of a full prominent blur is negligible.

private struct ProminentBlurBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct DeviceConnectedPopup: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var env: AppEnvironment
    /// Reactive color scheme — drives the dark-mode-only gradient border
    /// overlay on the glass card so the popup has a clearly-defined edge
    /// against the dark backdrop (light mode stays unchanged).
    @Environment(\.colorScheme) private var colorScheme

    /// Storyboard popup card frame — constraints `dxF-oY-6Dw` (leading=49)
    /// / `eqc-th-bzO` (trailing=49) on the 393pt reference canvas yield
    /// a 295pt width. Height is fixed at 337pt.
    private let cardWidth: CGFloat = 295
    private let cardHeight: CGFloat = 337

    private var connectedDevice: BarsysDevice? {
        ble.connected.first
    }

    var body: some View {
        ZStack {
            // ---- Backdrop (`jVb-RO-feQ`) --------------------------------
            // UIKit storyboard ships this `UIVisualEffectView(.prominent)`
            // at `alpha="0.0"` and NO code path animates it up — so at
            // runtime the prominent blur is effectively INVISIBLE. The
            // user perceives the popup as sitting on top of the parent
            // screen with only the card's own glass frost visible (same
            // appearance as the side menu and edit panel).
            //
            // SwiftUI matches by keeping the backdrop blur but applying
            // a very low alpha so it contributes a barely-perceptible
            // tint without whitening the background the way a full
            // prominent blur would. The net look is the same "card over
            // a sharp screen" UIKit renders — noticeably more transparent
            // than a fully-opaque prominent backdrop.
            ProminentBlurBackdrop()
                .opacity(0.0)
                .ignoresSafeArea()

            // ---- Inert tap layer (`Zj9-2g-TnC`) ------------------------
            // UIKit's full-screen button has NO action wired — it is a
            // dead view. Reproduce that by attaching a subtle scrim that
            // absorbs taps outside the card WITHOUT dismissing. The 0.08
            // black opacity matches the visual weight of the side-menu
            // scrim at its lowest intensity, giving enough separation for
            // the card without whitening the underlying screen.
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .transition(.opacity)
                // iPad + iOS 26 only hit-test bypass — defensive fix for
                // the same hit-test collision documented on
                // `SideMenuOverlay.isIPad`. iPhone (any
                // version) and iPad pre-iOS-26 keep the absorber active
                // exactly as before, so the pre-existing behaviour is
                // preserved bit-for-bit on every platform the bug
                // doesn't affect.
                .allowsHitTesting(!SideMenuOverlay.isIPad)

            // ---- Glass card (layered `ELw-dL-uZx` + `ASv-0m-OLs`) ------
            ZStack(alignment: .topTrailing) {
                // `ELw-dL-uZx` — `alertPopUpBackgroundStyle(cornerRadius:12)`.
                //   iOS 26+ → real UIGlassEffect(.regular)
                //   pre-26  → white@0.95 fill
                Group {
                    if #available(iOS 26.0, *) {
                        BarsysGlassPanelBackground()
                    } else {
                        // Pre-iOS 26 fallback — trait-resolved closure
                        // preserves the EXACT historical white@0.95 fill
                        // in light mode (bit-identical pixels), and
                        // returns elevated dark surface @ 0.95 in dark
                        // so the device-connected popup card adapts
                        // naturally instead of being a stark white slab
                        // on the dark side menu glass.
                        Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 0.95)
                                : UIColor.white.withAlphaComponent(0.95) // EXACT historical
                        })
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Dark-mode-only etched-glass border. In light mode the
                // popup already separates from its backdrop via the
                // natural glass frost; in dark mode the `.regular`
                // `UIGlassEffect` darkens and the card's edge becomes
                // indistinct. A subtle 1pt white→transparent gradient
                // stroke (matches the DeviceListPopup fix at
                // DeviceScreens.swift:298 and `BarsysPopupCard` at
                // Theme.swift:1135) reads as a soft highlight rim,
                // defining the card without looking like a hard border.
                // Applied ONLY on dark mode per user request — light
                // mode pixels stay unchanged.
                .overlay(
                    Group {
                        if colorScheme == .dark {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.70),
                                            .white.opacity(0.20)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                )
                // UIKit `alertPopUpBackgroundStyle` applies NO drop
                // shadow — the popup's elevation is conveyed entirely
                // through the prominent blur contrast behind it. Match
                // by dropping the previously-added shadow.

                // ---- `SDQ-Vi-uWQ` inner content ----------------------
                // Spacing is EXACTLY: top=30, vertical stack with
                //   Connected → 24 → image → 24 → type → 7 → name → 40 → button
                // so the total content height is
                //   21 + 24 + 100 + 24 + 21 + 7 + 21 + 40 + 40 = 298pt
                // which leaves 37pt of slack that UIKit autolayout
                // distributes as bottom padding (card height 337 - SDQ
                // bottom 30 = 307pt; close enough given label wrap).
                VStack(spacing: 0) {
                    // "Connected" — system 18pt LIGHT, veryDarkGrayColor,
                    // centered. Storyboard `aim-QZ-wXu`.
                    Text("Connected")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color("veryDarkGrayColor"))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 30)

                    if let device = connectedDevice {
                        // Device image — 101×100 FIXED (`Xoh-hx-cns`
                        // / `zY1-DF-a6F`), top=Connected.bottom+24.
                        Image(deviceImageName(device.kind))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 101, height: 100)
                            .padding(.top, 24)
                            .accessibilityLabel("Connected device image")

                        // Device type — system 18pt REGULAR,
                        // veryDarkGrayColor, top=image.bottom+24.
                        Text(device.kind.displayName)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color("veryDarkGrayColor"))
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)

                        // Device name — system 14pt LIGHT,
                        // veryDarkGrayColor, top=type.bottom+7.
                        // UIKit label starts at 0×0 (empty) and grows
                        // to fit the assigned text; SwiftUI does the
                        // same via `fixedSize(vertical:)`.
                        Text(device.name)
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color("veryDarkGrayColor"))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 7)
                            .padding(.horizontal, 24)

                        Spacer(minLength: 0)

                        // Disconnect button — 184×40, 8pt corner,
                        // system 16pt BLACK title, **TRANSPARENT fill**,
                        // 1pt `borderColor` stroke (UIKit L36-37 in
                        // `viewSetup()`). No other effects.
                        Button {
                            HapticService.light()
                            ble.disconnect(device)
                            isPresented = false
                        } label: {
                            Text("Disconnect")
                                .font(.system(size: 16))
                                // Preserve EXACT pure black in light
                                // mode (bit-identical to the previous
                                // hard-coded `Color.black`); switch
                                // to a near-white tone in dark mode
                                // for legibility on the dark glass
                                // panel of the device-connected popup.
                                // Trait-resolved at draw time → light
                                // pixels are unchanged.
                                .foregroundStyle(Color(UIColor { trait in
                                    trait.userInterfaceStyle == .dark
                                        ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                                        : UIColor.black // EXACT historical
                                }))
                                .frame(width: 184, height: 40)
                                .background(
                                    // TRANSPARENT fill — the glass card
                                    // behind shows through, matching
                                    // UIKit's `backgroundColor=clear` +
                                    // layer stroke recipe.
                                    RoundedRectangle(cornerRadius: 8,
                                                     style: .continuous)
                                        .fill(Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8,
                                                     style: .continuous)
                                        .stroke(Color("borderColor"),
                                                lineWidth: 1)
                                )
                        }
                        .buttonStyle(BounceButtonStyle()) // UIKit addBounceEffect()
                        .accessibilityLabel("Disconnect device")
                        .accessibilityHint("Disconnects \(device.name)")
                        .padding(.bottom, 30)
                    } else {
                        Spacer()
                        Text("No device connected")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color("veryDarkGrayColor"))
                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .frame(width: cardWidth, height: cardHeight)

                // Cross button (`wcP-Xk-wlX`) — 50×50 top-right of card,
                // top=0 trailing=0. Uses the real `crossIcon` asset
                // tinted `appBlackColor` via template rendering. UIKit
                // does NOT specify a fixed icon size for the crossIcon
                // image — it scales to its intrinsic size inside a
                // 50×50 hit target. Previously SwiftUI hard-coded 12×12
                // which reads smaller than UIKit on device; switch to
                // the intrinsic asset size via `.fit` with a bounded
                // 14×14 so it matches the reference.
                Button {
                    HapticService.light()
                    isPresented = false
                } label: {
                    Image("crossIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss device connected popup")
            }
            .frame(width: cardWidth, height: cardHeight)
            // UIKit modal present animation — scale-up from ~0.9 + fade.
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        // UIKit `DeviceConnectedController.viewDidLoad()` L22 plays a
        // success haptic the moment the popup is shown.
        .onAppear { HapticService.success() }
    }

    /// Asset names match UIKit `UIImage.barsys360 / .barsysCoaster /
    /// .barsysShaker` already shipped in `Assets.xcassets/PairYourDevice`.
    private func deviceImageName(_ kind: DeviceKind) -> String {
        switch kind {
        case .shaker:    return "barsys_shaker"
        case .coaster:   return "barsys_coaster"
        case .barsys360: return "barsys_360"
        }
    }
}
