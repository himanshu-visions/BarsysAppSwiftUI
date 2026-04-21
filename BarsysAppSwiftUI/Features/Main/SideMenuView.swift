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

    @State private var showLogoutConfirm = false
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

            // Background — mirrors UIKit `SideMenuViewController.swift` L51-61:
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
            // So on iOS 26+ the panel uses the `.regular` glass blur that the
            // storyboard's `<blurEffect style="regular"/>` ships with (SwiftUI
            // `.regularMaterial`). On iOS < 26 it's a plain WHITE fill — no
            // glass, no blur, no highlight stroke — matching the UIKit code
            // path EXACTLY. The previous SwiftUI port used `.regularMaterial`
            // on every iOS version which was wrong on iOS 18/19 where the
            // UIKit build shows a solid white panel.
            Group {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                }
            }

            // Subtle specular-style highlight stroke — only on iOS 26+ where
            // the storyboard `addGlassEffect` produces a glass sheen. On
            // iOS < 26 the UIKit panel has no border (plain white view), so
            // we don't draw one either.
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }

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
        .confirmationDialog("", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(ConstantButtonsTitle.logoutButtonTitle, role: .destructive) {
                performLogout()
            }
            Button(ConstantButtonsTitle.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(Constants.doYouWantToLogout)
        }
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
                Image(systemImageFor(section.name))
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
            showLogoutConfirm = true
            return

        case "Device":
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
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                router.push(.preferences)
            }
            return

        case "Favourites":
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

        // Disconnect BLE (ports BleManager.disconnectedTypeState = .manuallyDisconnected)
        ble.disconnectAll()

        // Remove device data immediately
        UserDefaultsClass.removeLastConnectedDevice()
        UserDefaultsClass.removeLastConnectedDeviceTime()

        // Clear ALL UserDefaults (ports UserDefaultsClass.clearAll)
        UserDefaultsClass.clearAll()

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
// Ports DeviceConnectedController.swift — shown when user taps "Device"
// in the side menu while a device is connected. Modal popup with
// .overFullScreen presentation showing device image, type, name, and
// a Disconnect button.

/// 1:1 port of UIKit `DeviceConnectedController`
/// (BarsysApp/StoryBoards/Base.lproj/Device.storyboard scene
/// `dPi-fR-1YI`). EXACT storyboard measurements:
///
///   • Backdrop (`jVb-RO-feQ`) — full-screen `UIVisualEffectView` with
///     `prominent` blur. Frosts the entire underlying screen so the
///     scrim is luminous frosted glass, not flat black.
///   • Card (`ASv-0m-OLs` popupContainerView): **295 × 337**, centered
///     (49pt leading + 49pt trailing inset on a 393pt screen), 12pt
///     corner radius (`userDefinedRuntimeAttribute cornerRadius=12`).
///   • `glassBackgroundView` (`ELw-dL-uZx`) — same frame as the card,
///     adds `alertPopUpBackgroundStyle(cornerRadius: .medium)` =
///     iOS 26 `UIGlassEffect` glass fill + sheen.
///   • Cross button (`wcP-Xk-wlX`): **50 × 50** at top-right corner
///     (top=0, trailing=0 of card), `crossIcon` asset, `appBlackColor`
///     tint.
///   • Inner content frame (`SDQ-Vi-uWQ`): 247 × 277, top=30,
///     leading=24, trailing=24, bottom=30 of card.
///       — "Connected" label (`aim-QZ-wXu`): **18pt light**,
///         `veryDarkGrayColor`, centered.
///       — Device image (`Yh9-Ww-vUh`): **101 × 100 FIXED**, asset
///         `barsys_360` / `barsys_coaster` / `barsys_shaker`,
///         scaleAspectFit, centered, top = "Connected".bottom + 24.
///       — Device type label (`TXK-kT-ate`): **18pt regular**,
///         `veryDarkGrayColor`, centered, top = image.bottom + 24.
///       — Device name label (`ODO-1m-a1Y`): **14pt light**,
///         `veryDarkGrayColor`, centered, top = type.bottom + 7.
///       — Disconnect button (`bKu-Ut-zme`): **184 × 40**, system 16pt,
///         **black title**, **8pt corner radius (NOT capsule)**, 1pt
///         `borderColor` border, white fill, top = name.bottom + 40.
struct DeviceConnectedPopup: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var env: AppEnvironment

    /// Storyboard popup card: 295 × 337 (49pt L/R inset on a 393pt
    /// device width). Height is fixed in the xib.
    private let cardWidth: CGFloat = 295
    private let cardHeight: CGFloat = 337

    private var connectedDevice: BarsysDevice? {
        ble.connected.first
    }

    var body: some View {
        ZStack {
            // Backdrop — 1:1 with UIKit storyboard: `jVb-RO-feQ`
            // (UIVisualEffectView) ships with `alpha="0.0"` and the
            // full-screen button `Zj9-2g-TnC` has no action. The
            // presenting VC is shown with `.overFullScreen`
            // + `backgroundColor = .clear`, so the home screen stays
            // visible and UNBLURRED behind the popup. Only the popup
            // CARD itself carries the glass effect (its `.regularMaterial`
            // fill natively blurs what's beneath it in its bounds).
            //
            // Previously this layer filled the whole screen with
            // `.regularMaterial`, frosting the entire home screen —
            // which doesn't match the UIKit design. Now the layer is
            // an invisible tap-catcher only; the card provides the
            // glass effect exactly where UIKit puts it.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
                .transition(.opacity)

            // The 295×337 glass card.
            ZStack(alignment: .topTrailing) {
                // Glass fill of the card itself — `ELw-dL-uZx`
                // applies `alertPopUpBackgroundStyle(cornerRadius:
                // .medium)` (iOS 26 `UIGlassEffect`).
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        // White-sheen highlight overlay matching UIKit
                        // `addGlassEffect` second-layer gradient.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.6)
                            .blendMode(.plusLighter)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.7),
                                             .white.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    // UIKit `addBlurEffect` shadow values
                    // (UIViewClass+GlassEffects.swift L137-140):
                    //   color  = black @ 0.20 alpha
                    //   opacity = 0.3  (effective black @ 0.06)
                    //   radius  = 25
                    //   offset  = (0, 10)
                    // Wider, softer drop than `.barsysShadow(.glass)`
                    // — matches the diffuse halo around the popup in
                    // the UIKit reference screenshot.
                    .shadow(color: .black.opacity(0.06), radius: 25, x: 0, y: 10)

                // Inner content (`SDQ-Vi-uWQ`): 247 × 277, top=30,
                // leading=24, trailing=24, bottom=30 of card.
                VStack(spacing: 0) {
                    // "Connected" — system 18pt LIGHT, veryDarkGrayColor.
                    Text("Connected")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color("veryDarkGrayColor"))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 30)

                    if let device = connectedDevice {
                        // Device image — fixed 101 × 100
                        // (`Xoh-hx-cns` width=101, `zY1-DF-a6F` height=100).
                        Image(deviceImageName(device.kind))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 101, height: 100)
                            .padding(.top, 24)
                            .accessibilityLabel("Connected device image")

                        // Device type — system 18pt REGULAR, veryDarkGray.
                        Text(device.kind.displayName)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color("veryDarkGrayColor"))
                            .padding(.top, 24)

                        // Device name — system 14pt LIGHT, veryDarkGray.
                        Text(device.name)
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color("veryDarkGrayColor"))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 7)
                            .padding(.horizontal, 24)

                        Spacer(minLength: 0)

                        // Disconnect — 184 × 40, **8pt rounded
                        // rectangle (NOT capsule)**, white fill,
                        // 1pt borderColor stroke, black title 16pt.
                        Button {
                            HapticService.light()
                            ble.disconnect(device)
                            isPresented = false
                        } label: {
                            Text("Disconnect")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.black)
                                .frame(width: 184, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color("borderColor"), lineWidth: 1)
                                )
                        }
                        // UIKit `btnDisconnect.addBounceEffect()` —
                        // press-scale animation on touch. `BounceButtonStyle`
                        // (BarBotScreens.swift) is the shared 1:1 port.
                        .buttonStyle(BounceButtonStyle())
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

                // Cross button (`wcP-Xk-wlX`): 50 × 50 at top-right
                // (top=0, trailing=0 of card). Uses the shipped
                // `crossIcon` asset (UIKit storyboard image="crossIcon")
                // tinted `appBlackColor` via template rendering mode —
                // NOT an SF-symbol `xmark` which would look slightly
                // different than the UIKit popup.
                Button {
                    HapticService.light()
                    isPresented = false
                } label: {
                    Image("crossIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss device connected popup")
            }
            .frame(width: cardWidth, height: cardHeight)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        // UIKit `DeviceConnectedController.viewDidLoad()` plays a
        // success haptic the moment the popup is shown.
        .onAppear { HapticService.success() }
    }

    /// Asset names match UIKit `UIImage.barsys360 / .barsysCoaster /
    /// .barsysShaker` already shipped in
    /// `Assets.xcassets/PairYourDevice`.
    private func deviceImageName(_ kind: DeviceKind) -> String {
        switch kind {
        case .shaker:    return "barsys_shaker"
        case .coaster:   return "barsys_coaster"
        case .barsys360: return "barsys_360"
        }
    }
}
