//
//  ScreenEdgePanGesture.swift
//  BarsysAppSwiftUI
//
//  Native UIKit gesture host that mirrors what SideMenuSwift does in the
//  UIKit app (see `UIViewController+Navigation.setupSideMenuForSwipe`):
//
//      SideMenuManager.default.rightMenuNavigationController = menu
//      SideMenuManager.default.addScreenEdgePanGesturesToPresent(toView:, forMenu: .right)
//      SideMenuManager.default.addPanGestureToPresent(toView:)
//
//  SideMenuSwift attaches two UIKit recognizers to the host view:
//    1. `UIScreenEdgePanGestureRecognizer(edges: .right)` — grabs pans that
//       start on the right screen edge and drives the interactive presentation
//       of the menu (open-by-swipe).
//    2. `UIPanGestureRecognizer` — installed on the full container, used to
//       drive the interactive dismissal (close-by-swipe) once the menu is up.
//
//  This file ports BOTH behaviours into a single `UIViewRepresentable` so a
//  SwiftUI overlay can consume them. SwiftUI's own `DragGesture` cannot be
//  used here because it's eaten by `TabView` and the panel's own hit area;
//  UIKit's recognizers win because they're attached to a raw UIView on top
//  of the tab content.
//

import SwiftUI
import UIKit

/// Which of the four SideMenuSwift gestures this host should drive.
///
/// - `.openFromRightEdge`: installs `UIScreenEdgePanGestureRecognizer(.right)`
///   only. Used when the right menu is closed — a right-edge pan drags
///   the panel in from the right. Matches
///   `addScreenEdgePanGesturesToPresent(forMenu: .right)`.
///
/// - `.closeFromAnywhere`: installs a plain `UIPanGestureRecognizer` that
///   listens everywhere on its view. Used when the right menu is open —
///   a rightward pan anywhere on the panel drags it back offscreen.
///   Matches `addPanGestureToPresent` for the right-menu dismiss case.
///
/// - `.openFromLeftEdge`: installs `UIScreenEdgePanGestureRecognizer(.left)`.
///   Used when the BarBot history (LEFT-side menu) is closed — a left-edge
///   pan drags the history panel in from the left. Matches UIKit
///   `setupSideMenuForSwipeForBarBotHistory()` →
///   `SideMenuManager.default.addScreenEdgePanGesturesToPresent(toView: self.view, forMenu: .left)`.
///
/// - `.closeLeftFromAnywhere`: installs a `UIPanGestureRecognizer` that
///   listens everywhere on its view. Used when the BarBot history is
///   open — a LEFTWARD pan anywhere drags the panel back off-screen
///   to the left. Matches the SideMenuSwift dismiss-pan behaviour for
///   a LEFT menu (panel at x=0, swipe-left moves it to x=-panelWidth).
enum SideMenuGestureMode {
    case openFromRightEdge
    case closeFromAnywhere
    case openFromLeftEdge
    case closeLeftFromAnywhere
}

struct ScreenEdgePanGesture: UIViewRepresentable {

    /// Which of the two SideMenuSwift gestures this instance drives.
    let mode: SideMenuGestureMode

    /// Progress from 0 (finger at start position) to 1 (finger travelled
    /// the full `totalWidth`). Fired on every `.changed` event.
    let onProgress: (CGFloat) -> Void

    /// Called once on `.ended` or `.cancelled`.
    /// - `committed`: `true` when the pan crossed 40 % of `totalWidth`
    ///   OR the flick velocity exceeded 800 pts/sec in the commit direction.
    /// - `velocity`: the gesture's horizontal velocity in pts/sec at the
    ///   moment of release, normalized by `totalWidth`. Pass this into a
    ///   spring animation so the completion starts at the finger's speed.
    ///   Matches what UIKit's `UIPercentDrivenInteractiveTransition` feeds
    ///   into `UIView.animate(initialSpringVelocity:)` inside SideMenuSwift.
    let onEnded: (_ committed: Bool, _ velocity: CGFloat) -> Void

    /// The "full travel" distance used to normalize progress. Defaults to
    /// the side menu panel width in the storyboard (279pt). The UIKit app
    /// sets `menu.menuWidth = UIScreen.main.bounds.width`, but the actual
    /// visible content panel is 279pt — we mirror the visible content.
    var totalWidth: CGFloat = 279

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        view.mode = mode
        view.backgroundColor = .clear

        switch mode {
        case .openFromRightEdge:
            let recognizer = UIScreenEdgePanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            recognizer.edges = .right
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)

        case .openFromLeftEdge:
            // 1:1 with UIKit `addScreenEdgePanGesturesToPresent(forMenu: .left)`
            // — `UIScreenEdgePanGestureRecognizer(edges: .left)` filters to
            // touches that start within the system-defined left edge zone
            // and drives the BarBot history panel slide-in interactively.
            let recognizer = UIScreenEdgePanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            recognizer.edges = .left
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)

        case .closeFromAnywhere, .closeLeftFromAnywhere:
            let recognizer = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)
        }

        context.coordinator.owner = self
        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) {
        context.coordinator.owner = self
        uiView.mode = mode
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: ScreenEdgePanGesture

        init(owner: ScreenEdgePanGesture) {
            self.owner = owner
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)

            // Convert raw translation/velocity to a SIGNED quantity in the
            // direction that COMPLETES the gesture, so `progress == 1` always
            // means "fully committed" regardless of which edge the panel is on.
            //
            //   .openFromRightEdge:    finger moves LEFT  (translation.x < 0)
            //                          → travel = -translation.x
            //   .openFromLeftEdge:     finger moves RIGHT (translation.x > 0)
            //                          → travel = +translation.x
            //   .closeFromAnywhere:    right-menu dismiss = pan RIGHT (translation.x > 0)
            //                          → travel = +translation.x
            //   .closeLeftFromAnywhere: left-menu dismiss = pan LEFT (translation.x < 0)
            //                          → travel = -translation.x
            let signedTravel: CGFloat
            let signedVelocity: CGFloat
            switch owner.mode {
            case .openFromRightEdge:
                signedTravel = -translation.x
                signedVelocity = -velocity.x
            case .openFromLeftEdge:
                signedTravel = translation.x
                signedVelocity = velocity.x
            case .closeFromAnywhere:
                signedTravel = translation.x
                signedVelocity = velocity.x
            case .closeLeftFromAnywhere:
                signedTravel = -translation.x
                signedVelocity = -velocity.x
            }
            let travel = max(0, signedTravel)
            let progress = min(1, travel / owner.totalWidth)

            switch recognizer.state {
            case .began, .changed:
                owner.onProgress(progress)
            case .ended:
                // Match SideMenuSwift's commit heuristic: fire if the pan
                // crossed 40% of the menu width OR the flick velocity is
                // past 800 pts/sec in the commit direction.
                let committed = progress > 0.4 || signedVelocity > 800
                // Normalized velocity: pts/sec ÷ totalWidth. Matches what
                // UIKit feeds into UIView.animate(initialSpringVelocity:).
                let normalizedVelocity = signedVelocity / owner.totalWidth
                owner.onEnded(committed, normalizedVelocity)
            case .cancelled, .failed:
                owner.onEnded(false, 0)
            default:
                break
            }
        }

        // Allow this recognizer to fire alongside SwiftUI's internal
        // gestures — critical because TabView / ScrollView install their own
        // pan recognizers that would otherwise cancel ours. SideMenuSwift
        // does the same via its own UIGestureRecognizerDelegate.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }

        // Let UIKit's recognizers decide when to begin on their own:
        //
        // - `UIScreenEdgePanGestureRecognizer` ALREADY filters to touches
        //   that start on the configured edge and it discriminates against
        //   vertical pans internally. Adding a velocity-based filter on top
        //   rejected some pans at t=0 where velocity was near-zero, which
        //   caused the intermittent "sometimes behaves differently" issue
        //   the user reported.
        //
        // - For the close-from-anywhere mode we still want to enforce a
        //   "primarily rightward" direction so a downward scroll on the
        //   menu rows doesn't accidentally close it.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            switch owner.mode {
            case .openFromRightEdge, .openFromLeftEdge:
                // Trust UIKit — `UIScreenEdgePanGestureRecognizer` already
                // filters to its edge zone and discriminates against vertical
                // pans internally. Adding velocity gating on top causes
                // intermittent rejections at touch-down (velocity is ~0).
                return true
            case .closeFromAnywhere:
                // Right menu dismiss: must be primarily rightward.
                let v = pan.velocity(in: view)
                return abs(v.x) > abs(v.y) && v.x > 0
            case .closeLeftFromAnywhere:
                // Left menu dismiss: must be primarily LEFTWARD so a vertical
                // scroll on the history rows doesn't accidentally close it.
                let v = pan.velocity(in: view)
                return abs(v.x) > abs(v.y) && v.x < 0
            }
        }
    }

    // MARK: - PassthroughView

    /// A UIView that lets the attached recognizer receive touches while
    /// letting every OTHER touch fall through to the SwiftUI content below.
    ///
    /// - `.openFromRightEdge`: captures touches that START within the right
    ///   edge hit zone (40pt). Everywhere else passes through so the tab
    ///   bar, buttons, scroll views etc. keep working.
    /// - `.closeFromAnywhere`: captures every touch in its bounds. This is
    ///   only mounted while the menu is visible, so blocking the rest of
    ///   the screen is fine — that's exactly what the scrim does anyway.
    final class PassthroughView: UIView {
        var mode: SideMenuGestureMode = .openFromRightEdge
        /// How close to the right edge (in points) a touch must begin to
        /// be captured in `.openFromRightEdge` mode.
        var edgeHitWidth: CGFloat = 40

        /// Vertical strip at the TOP of the view that always passes
        /// through to whatever sits below — protects the navigation
        /// bar / toolbar trailing buttons (profile / side-menu) from
        /// being captured by the edge-pan recognizer.
        ///
        /// On iPad the toolbar's profile button sits at the right
        /// edge (trailing inset 8pt + 110pt pill = ~118pt wide) which
        /// overlaps the rightmost 40pt edge-hit zone. Without this
        /// top-inset guard `UIScreenEdgePanGestureRecognizer` claims
        /// the touch before the SwiftUI `Button` can fire its action,
        /// so the side-menu icon visually does nothing on tap.
        ///
        /// 110pt covers a typical iPad nav-bar height (50pt nav bar +
        /// up to ~60pt status bar / dynamic-island safe-area inset)
        /// with a few extra points of margin. iPhone keeps the same
        /// guard — it doesn't hurt there because the iPhone toolbar
        /// is also outside the swipe zone — but the previously known-
        /// good iPhone behaviour stays untouched (the guard lets
        /// touches FALL THROUGH, never blocks them).
        var topInsetSafeFromHitTest: CGFloat = 110

        /// Vertical strip at the BOTTOM of the view that always passes
        /// through — protects the BarBot chat input bar (the
        /// `barBotPlus` "+" attachment button at x≈12pt overlaps the
        /// leftmost 40pt edge-hit zone), the tab bar, and any other
        /// bottom-of-screen control from being captured by the edge-
        /// pan recognizer.
        ///
        /// On BarBot the chat input bar STACKS on top of the tab
        /// bar — the "+" button center sits roughly at:
        ///   tab_bar (≈50pt) + lift (≈15pt) + bottom safe area
        ///   (0–34pt) + input_bar_padding (~10pt) + input_bar_half_height
        ///   (~35pt) ≈ 110pt above the screen bottom.
        ///
        /// 200pt covers:
        ///   • Tab bar + lift     ≈ 64pt
        ///   • Chat input bar     ≈ 80pt (BarBot, sits ABOVE tab bar)
        ///   • Bottom safe area   ≈ 0–34pt (home indicator)
        ///   • Safety margin      ≈ 22pt
        /// — the union (≈200pt) is the safe lower bound that
        /// guarantees the BarBot "+" button at y≈(screen_height−110)
        /// lands inside the pass-through region. Like the top inset,
        /// this is a defensive PASS-THROUGH (returns nil for the
        /// bottom band) — it can never BLOCK a touch from reaching
        /// whatever sits below.
        var bottomInsetSafeFromHitTest: CGFloat = 200

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // Top-of-screen guard — any touch in the top
            // `topInsetSafeFromHitTest` points is passed through to the
            // SwiftUI content below (system toolbar, custom top bar,
            // back button, profile + favorites pill). This is the FIX
            // for "side menu button is not tappable on iPad" — the
            // edge-pan recognizer no longer competes with the toolbar
            // Button for the right-edge tap that lands on the profile
            // icon.
            if point.y < topInsetSafeFromHitTest {
                return nil
            }

            // Bottom-of-screen guard — any touch in the BOTTOM
            // `bottomInsetSafeFromHitTest` points is passed through to
            // the SwiftUI content below (BarBot chat input bar with
            // the `barBotPlus` "+" attachment button, tab bar, etc.).
            // FIX for "BarBot plus / photos / camera button not
            // working on iPad" — the left-edge recognizer was
            // claiming taps on the input bar's leading "+" icon
            // before the SwiftUI `Button` could fire its action.
            if point.y > bounds.height - bottomInsetSafeFromHitTest {
                return nil
            }

            switch mode {
            case .openFromRightEdge:
                if point.x >= bounds.width - edgeHitWidth {
                    return self
                }
                return nil
            case .openFromLeftEdge:
                // Mirror image of the right-edge hit zone — capture touches
                // that START within the leftmost `edgeHitWidth` points so
                // the rest of the screen (tab bar, scroll views, buttons)
                // stays interactive when the BarBot history is closed.
                if point.x <= edgeHitWidth {
                    return self
                }
                return nil
            case .closeFromAnywhere, .closeLeftFromAnywhere:
                // Capture everywhere — the overlay scrim sits under this
                // view and the panel sits above it in the z-order.
                return self
            }
        }
    }
}
