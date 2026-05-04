//
//  Components.swift
//  BarsysAppSwiftUI
//
//  Reusable SwiftUI primitives matching the existing UIKit components.
//

import SwiftUI
import UIKit

// MARK: - Interactive pop gesture (swipe-from-left-edge to dismiss)

/// Re-enables the swipe-from-left-edge interactive pop gesture even
/// when the host view has set `navigationBarBackButtonHidden(true)`.
///
/// UIKit silently disables `interactivePopGestureRecognizer` when the
/// system back button is hidden — that's why every screen that swapped
/// to a custom back chevron in this app lost its swipe-back behaviour.
/// Setting the gesture's delegate to `nil` is Apple's documented
/// workaround: the gesture no longer asks the (now-stale) delegate
/// whether to recognise, so the swipe falls through to UIKit's default
/// pop machinery exactly like on screens that still ship the system
/// back button.
///
/// Apply via the `.interactivePopGestureEnabled()` `View` modifier on
/// any screen with a custom back button that should still support
/// swipe-back. Don't apply on screens that intentionally disable
/// back navigation (e.g. CraftingView, which already sets
/// `interactiveDismissDisabled()` to prevent accidental mid-pour
/// dismiss).
private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        ProbeController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// Hosting `UIViewController` whose only job is to walk to the
    /// nearest enclosing `UINavigationController` once it lands in
    /// the hierarchy and clear the interactive-pop delegate.
    final class ProbeController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableSwipeBack()
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // Re-arm on every appear in case another screen pushed in
            // between had its own delegate set, leaving the gesture
            // disabled when we come back to a screen that wants it.
            enableSwipeBack()
        }
        private func enableSwipeBack() {
            // `parent?.navigationController` is the standard climb;
            // SwiftUI sometimes hosts us inside a `UIHostingController`
            // whose `navigationController` is the SwiftUI-managed
            // `UINavigationController`. Both paths resolve to the same
            // recogniser.
            guard let nav = navigationController
                ?? parent?.navigationController
                ?? view.window?.rootViewController?.navigationController
            else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

extension View {
    /// Re-enables the swipe-from-left-edge interactive pop gesture on
    /// screens that have replaced the system back button with a custom
    /// chevron. See `InteractivePopGestureEnabler` for rationale.
    func interactivePopGestureEnabled() -> some View {
        background(InteractivePopGestureEnabler())
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if isLoading {
                    ProgressView().tint(.black)
                } else if let sys = systemImage {
                    Image(systemName: sys)
                }
                Text(title)
                    .font(Theme.Font.headline(17))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .fill(isEnabled ? Theme.Color.brand : Theme.Color.brand.opacity(0.35))
            )
        }
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(title))
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let sys = systemImage { Image(systemName: sys) }
                Text(title).font(Theme.Font.headline(17))
            }
            .foregroundStyle(Theme.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
        }
    }
}

struct IconButton: View {
    let systemImage: String
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.Color.surface)
                .clipShape(Circle())
        }
    }
}

// MARK: - Text fields

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let sys = systemImage {
                Image(systemName: sys).foregroundStyle(Theme.Color.textTertiary)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.Color.textTertiary))
                .keyboardType(keyboard)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .stroke(Theme.Color.border, lineWidth: 1)
        )
    }
}

struct SecureAppTextField: View {
    let placeholder: String
    @Binding var text: String
    @State private var reveal = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "lock.fill").foregroundStyle(Theme.Color.textTertiary)
            Group {
                if reveal {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.Color.textTertiary))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.Color.textTertiary))
                }
            }
            .foregroundStyle(Theme.Color.textPrimary)
            .textContentType(.password)
            Button { reveal.toggle() } label: {
                Image(systemName: reveal ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .stroke(Theme.Color.border, lineWidth: 1)
        )
    }
}

// MARK: - Search bar (1:1 port of viewSearch + txtSearch + searchAndCloseButton)
//
// Shared across ExploreRecipesViewController, MixlistViewController, and
// FavouritesRecipesAndDrinksViewController. All three screens use the
// IDENTICAL Mixlist.storyboard search widget:
//
//   viewSearch   (345×44, roundCorners=12, borderColor=barbotBorderColor 1pt,
//                 backgroundColor=clear)
//     ├─ searchAndCloseButton  (44×44, x=0, buttonType=system,
//                                tintColor=grayBorderColor,
//                                image="exploreSearch"  (default) /
//                                       "crossIcon"     (when text non-empty))
//     └─ txtSearch             (leading=8 trailing=10 → effectively full width,
//                                font system 14pt, textColor=appBlackColor,
//                                placeholder="Search",
//                                leftView = 30pt clear padding (always)
//                                clearButtonMode = .always)
//
// Runtime behavior (UIKit — see ExploreRecipesViewController
// `didPressSearchButton`, `textFieldDidChange`, and Favourites
// `filterCountries`):
//   • As soon as the user types any non-whitespace text, the search
//     button's image swaps from "exploreSearch" to "crossIcon". Tapping
//     when the image is the cross CLEARS the field and resets results;
//     tapping when it's the glass ACTIVATES the field (becomeFirstResponder).
//   • `clearButtonMode = .always` means iOS also shows its own right-side
//     clear "×" while editing, so the user has two ways to wipe the field.
//   • Filtering itself runs off-main and uses word-splitting so "rum lemon"
//     matches any ingredient or recipe that contains "rum" OR "lemon".
//     (That search helper is per-screen and is NOT part of this component.)
//
// This component is framework-agnostic about the data — callers pass the
// `$query` binding and the parent view performs the actual filtering in
// its own computed property.

struct BarsysSearchBar: View {
    @Binding var query: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // LEADING magnifier — `exploreSearch` icon stays put
            // regardless of whether the field has content. Tapping it
            // focuses the text field (matches UIKit
            // `searchAndCloseButton`'s "tap when empty →
            // becomeFirstResponder" behaviour). The clear-text
            // affordance lives on the trailing edge as a separate
            // button (1:1 with `txtSearch.clearButtonMode = .always`),
            // so this leading icon never swaps to a cross — the
            // previous SwiftUI port toggled the image here, which the
            // user reported as the cross being on the wrong side.
            Button {
                HapticService.light()
                isFocused = true
            } label: {
                Image("exploreSearch")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color("grayBorderColor"))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            // Text field — `Wl4-tx-sp4`: placeholder="Search", system 14pt,
            // textColor=appBlackColor.
            TextField("", text: $query,
                      prompt: Text(placeholder)
                        .foregroundColor(Color("grayBorderColor")))
                .font(.system(size: 14))
                .foregroundStyle(Color("appBlackColor"))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled() // UIKit: `autocorrectionType="no"`
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }

            // TRAILING clear button — 1:1 with UIKit
            // `txtSearch.clearButtonMode = .always`. UIKit's native
            // `UITextField.clearButtonMode = .always` paints a small "×"
            // glyph inside the field's right margin whenever the field
            // has text, giving the user a second one-tap-to-clear
            // affordance positioned at the trailing edge — exactly
            // where iOS users expect it. SwiftUI's `TextField` has no
            // equivalent, so we synthesise it as a sibling button.
            // Hidden (not just disabled) when empty so it consumes no
            // space — matches UIKit, where the native clear button only
            // appears while editing with content.
            if !query.isEmpty {
                Button {
                    HapticService.light()
                    query = ""
                } label: {
                    Image("crossIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // 14pt glyph inside a 44pt-tall hit area —
                        // matches UIKit's native clear button visual
                        // size and the standard 44pt iOS hit target.
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Color("grayBorderColor"))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }

            // Storyboard `JXF-Zi-7p5`: `txtSearch.trailing` is 10pt
            // from the container's trailing edge. When the clear button
            // is hidden the text field consumes this slot; when shown,
            // we still keep a 10pt outer gutter so the cross sits
            // 10pt from the rounded-corner border, matching UIKit.
            Spacer().frame(width: 10)
        }
        .animation(.easeInOut(duration: 0.18), value: query.isEmpty)
        // Container: 44pt tall, cornerRadius 12, 1pt `barbotBorderColor`
        // stroke (ExploreRecipesViewController.setupView L153:
        //   viewSearch.makeBorder(width: 1.0, color: .barbotBorderColor))
        .frame(height: 44)
        .background(Color.clear) // UIKit backgroundColor = clear
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color("barbotBorderColor"), lineWidth: 1)
        )
    }
}

// MARK: - OTP boxes (ports OtpTextField row from LoginViewController.swift)
//
// Storyboard reference (User.storyboard scene Q1K-6a-eji, OTP container
// `zUX-Ks-vb8` → stack `3g1-GP-a66`):
//   - 6 OtpTextField boxes, distribution=fillEqually, spacing=10
//   - Each box has constraint: width = height (1:1) → SQUARE
//   - userDefinedRuntimeAttributes:
//       roundCorners = 10
//       layer.borderWidth = 1
//       ViewBorderColor = paleBlueGrayColor
//   - Font: system 18pt
//   - textColor: subtitleGrayColor
//   - placeholder: "0"
//   - textAlignment: center
//   - keyboardType: phonePad
//
// SwiftUI port: HStack with `fillEqually` semantics (each box uses
// `.frame(maxWidth: .infinity)` and a 1:1 aspect ratio enforced via
// `.aspectRatio(1, contentMode: .fit)`), so the row stretches to whatever
// width its container gives it (~28–32pt per box inside the 333pt card).

struct OTPBoxField: View {
    @Binding var code: String
    var length: Int = 6

    /// Drives the UIKit-backed input field's first-responder state.
    /// Uses `@State Bool` (rather than `@FocusState`) because the
    /// underlying input is a `UIKitTextField` — see the comment on
    /// `UIKitTextField` for why we ditched the SwiftUI keyboard
    /// accessory toolbar on the auth flows.
    @State private var focused: Bool = true
    /// Drives the blinking caret that mimics UIKit's per-box cursor.
    /// UIKit had 6 individual `OtpTextField`s, so the system caret
    /// appeared inside the active box. The SwiftUI port uses a single
    /// hidden field, so we render our own caret in the next-to-fill
    /// box while focused.
    ///
    /// Driven by a `Timer` (not `withAnimation(.repeatForever)`)
    /// because the implicit-animation approach didn't carry over to
    /// a *freshly-inserted* caret view when the active box advanced
    /// — the user would type a digit, the caret would move to the
    /// next box, and then sit invisible (opacity stuck at the value
    /// the previous box's animation had just rendered). A timer
    /// drives the @State directly, so the new caret view picks up
    /// the live animated value on its very first render.
    @State private var caretVisible: Bool = true

    var body: some View {
        ZStack {
            // Hidden UIKit-backed text field that captures all input.
            // Using `UIKitTextField` (vs. SwiftUI `TextField`) gives
            // us a real `inputAccessoryView` Cancel/Done bar that
            // appears reliably above the keyboard on iOS 26 — the
            // SwiftUI `.toolbar { keyboard }` mechanism races with
            // `.toolbar(.hidden, for: .navigationBar)` and the bar
            // can fail to attach.
            UIKitTextField(
                text: Binding(
                    get: { code },
                    set: { newValue in
                        let filtered = newValue.filter(\.isNumber)
                        code = String(filtered.prefix(length))
                    }),
                isFocused: $focused,
                keyboardType: .numberPad,
                textContentType: .oneTimeCode,
                sanitize: { raw in
                    let filtered = raw.filter(\.isNumber)
                    return String(filtered.prefix(length))
                },
                onDone: { focused = false },
                onCancel: { focused = false }
            )
            .opacity(0.001)
            .frame(width: 1, height: 1)

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { idx in
                    boxAt(idx)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .task(id: focused) {
            // Drive the caret blink off a sleep loop so each freshly-
            // inserted caret view (when the active box advances after
            // a keystroke) participates from its very first render.
            // Re-runs whenever `focused` flips because of `id:` —
            // dismissing the keyboard cancels the loop, focusing
            // again restarts it.
            guard focused else { return }
            caretVisible = true
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { break }
                caretVisible.toggle()
            }
        }
    }

    private func boxAt(_ idx: Int) -> some View {
        let chars = Array(code)
        let value = idx < chars.count ? String(chars[idx]) : "0"
        let isFilled = idx < chars.count
        // The currently-active box is the first unfilled slot. UIKit
        // showed the system caret here; we render a brand-tinted bar
        // with a blinking opacity to match that affordance.
        let isActiveCaret = focused && idx == chars.count
        // Fixed square 32x32 — matches the storyboard runtime size of the
        // 6 OtpTextField boxes (form card 333pt − padding − 6 boxes with
        // 10pt spacing ≈ 28–32pt per box). Square via 1:1 aspect ratio.
        return ZStack {
            Text(value)
                .font(.system(size: 18))
                .foregroundStyle(isFilled
                                 ? Color("subtitleGrayColor")
                                 : Color("subtitleGrayColor").opacity(0.45))
                .opacity(isActiveCaret ? 0 : 1)

            // Caret view is ALWAYS rendered (rather than wrapped in
            // `if isActiveCaret`) so SwiftUI doesn't have to insert /
            // remove the view as the active box advances — it only
            // toggles its opacity. That side-steps the implicit-
            // animation discontinuity that was leaving the caret
            // invisible on the new active box after each keystroke.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.Color.brand)
                .frame(width: 2, height: 18)
                .opacity(isActiveCaret && caretVisible ? 1 : 0)
        }
        .frame(width: 32, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.001))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color("paleBlueGrayColor"), lineWidth: 1)
        )
        // 1:1 with UIKit `AccessibilityHelper.swift:142` —
        // `configureOTPFields()` sets each box's `accessibilityLabel`
        // to "OTP digit N" so VoiceOver users can identify the
        // current digit position.
        .accessibilityLabel("OTP digit \(idx + 1)")
        .accessibilityValue(isFilled ? value : "")
    }
}

// MARK: - Recipe card

struct RecipeCard: View {
    let recipe: Recipe
    var onFavorite: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.Color.brand.opacity(0.5), Theme.Color.coral.opacity(0.35)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 140)
                        .overlay(
                            Image(systemName: recipe.imageName.isEmpty ? "wineglass" : recipe.imageName)
                                .font(.system(size: 52))
                                .foregroundStyle(Theme.Color.softWhiteText.opacity(0.85))
                        )

                    if let onFavorite {
                        let isFav = recipe.isFavourite ?? false
                        Button(action: onFavorite) {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isFav ? Theme.Color.danger : Theme.Color.softWhiteText)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(8)
                    }
                }

                Text(recipe.displayName)
                    .font(Theme.Font.semibold(17))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                if !recipe.subtitle.isEmpty {
                    Text(recipe.subtitle)
                        .font(Theme.Font.medium(13))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .fill(Theme.Color.surface)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String = "See all"

    var body: some View {
        HStack {
            Text(title).font(Theme.Font.headline(20)).foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .font(Theme.Font.caption(14))
                    .foregroundStyle(Theme.Color.brand)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.textTertiary)
            Text(title).font(Theme.Font.headline()).foregroundStyle(Theme.Color.textPrimary)
            Text(subtitle).font(Theme.Font.body(14)).foregroundStyle(Theme.Color.textSecondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading overlay + alerts as view modifiers

struct LoadingOverlayModifier: ViewModifier {
    @ObservedObject var state: LoadingState
    /// Drives the dark-mode invert of the `BarsysLoader` GIF. The
    /// spinner ships as a DARK-inked Barsys logo animation on a
    /// transparent backdrop, tuned for the light glass card. Against
    /// the dark glass card it visually disappears because the ink
    /// blends into the darkened material. Inverting the GIF in dark
    /// mode flips the ink to near-white so the spinner reads on
    /// either theme. Light mode untouched.
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay {
                if state.isVisible {
                    // 1:1 with UIKit `showGlassLoader(message:)` from
                    // `UIViewController+GlassLoader.swift`:
                    //   • Backdrop: black @ 0.30 alpha (UIKit L26-29)
                    //   • Card: 200pt × 150pt, centered (UIKit L31-37)
                    //   • Corner: BarsysCornerRadius.xlarge = 20pt (UIKit L34)
                    //   • Shadow: black, opacity 0.18, radius 18, offset (0,10) (UIKit L40-44)
                    //   • Glass: GlassEffectView.apply(to:) — UIGlassEffect on iOS 26+,
                    //            UIBlurEffect(.systemMaterial) + vibrancy on iOS <26
                    //   • Inner content: 60×60 GIF spinner over a 15pt-medium
                    //     loaderTextColor message label, 10pt vertical spacing,
                    //     centered inside the card.
                    ZStack {
                        Color.black.opacity(0.30).ignoresSafeArea()

                        VStack(spacing: 10) {
                            // 1:1 with UIKit `showGlassLoader`
                            // (UIViewController+GlassLoader.swift L82-87):
                            //   `SDAnimatedImageView.sd_setImage(with:
                            //    Bundle.main.url(forResource:
                            //    "BarsysLoader", withExtension: "gif"))`
                            //   frame: 60×60, contentMode: .scaleAspectFit.
                            // `AnimatedGIFView` (defined in
                            // BarBotScreens.swift) reads the raw GIF
                            // bytes from the data asset + plays every
                            // frame with its encoded per-frame delay
                            // via `CGImageSource`, matching the SDWebImage
                            // playback the UIKit version uses. The
                            // `BarsysLoader.dataset` is copied verbatim
                            // from UIKit so the animation is bit-identical.
                            AnimatedGIFView(assetName: "BarsysLoader")
                                .frame(width: 60, height: 60)
                                // Dark-mode invert — see the
                                // @Environment declaration at the top
                                // of this modifier for the rationale.
                                // Reuses the `invertedInDarkMode`
                                // helper from LoginView.swift so Login
                                // / SignUp / Splash / BarBot / this
                                // loader all flip their dark-ink GIF
                                // assets via one consistent path.
                                .invertedInDarkMode(colorScheme == .dark)

                            // UIKit message label (UIViewController+GlassLoader.swift L89-96):
                            //   font      = AppFontClass.font(.subheadline, weight: .medium)
                            //               → SFProDisplay-Medium 15pt (NOT system SF)
                            //   textColor = .loaderTextColor (#333333 light / #D1D1D6 dark)
                            //   alignment = .center, numberOfLines = 2
                            //   frame     = (x: padded.minX, width: padded.width=166,
                            //                height: labelHeight=34) — FIXED height even
                            //                when message is empty, so the GIF always
                            //                sits at y=23 from the card's top (startY
                            //                calc in UIKit L65-66 uses `total = gifSize
                            //                + spacing + labelHeight = 104` regardless
                            //                of message length).
                            // Rendering the Text unconditionally with a fixed 34pt
                            // height keeps the GIF position stable for "" vs multi-line
                            // messages — matches UIKit's layout byte-for-byte.
                            Text(state.message)
                                .font(Theme.Font.of(.subheadline, .medium))
                                .foregroundStyle(Theme.Color.loaderText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .padding(.horizontal, 16)
                        }
                        .frame(width: 200, height: 150)
                        .background(loaderCardBackground)
                        .overlay(loaderCardBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.isVisible)
    }

    /// `GlassEffectView.apply(to:)` (UIKit) — frosted card.
    /// iOS 26+ → `.ultraThinMaterial` for a clearer / more transparent
    ///           glass look. UIKit uses `UIGlassEffect(style: .regular)`
    ///           which on real-device iOS 26 renders noticeably more
    ///           see-through than SwiftUI's `.regularMaterial` did, so
    ///           dropping a step to `.ultraThinMaterial` brings the
    ///           rendered alpha down to a UIKit-equivalent level (the
    ///           "0.98 transparency" the user asked for) without
    ///           completely dissolving the card. Pre-26 also drops to
    ///           `.ultraThinMaterial` so the card looks visually
    ///           consistent across iOS versions.
    /// The pre-26 UIKit branch additionally layered a 20% white tint
    /// over `UIBlurEffect(.systemMaterial)` (GlassEffectView.swift L63);
    /// we reproduce that with a `Color.white.opacity(0.20)` overlay so
    /// the card still reads as a frosted-white surface against busy
    /// backgrounds, not as a near-invisible blur.
    @ViewBuilder
    private var loaderCardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.20))
                )
        }
    }

    /// `GlassEffectView` border — 1pt, white@0.25 (iOS 26) or white@0.22 (pre-26).
    @ViewBuilder
    private var loaderCardBorder: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }
}

// MARK: - Barsys Alert Overlay (1:1 port of UIKit AlertPopUpViewController /
// AlertPopUpHorizontalStackController — AlertPopUp.storyboard)
//
// UIKit shipping behaviour:
//
//   **Single-button variant** (`AlertPopUpViewController`):
//     • `mainBackgroundView` — full screen dim. On iOS 26 it's black@0.3
//       when `isBackgroundNeededDark` is true, otherwise transparent so
//       the presenting VC shows through.
//     • `glassBackgroundView` — centered rounded container. Runtime
//       `alertPopUpBackgroundStyle(cornerRadius: .medium)` applies a
//       gradient/blur on iOS 26 and a plain white card pre-26, both
//       with 12pt corners.
//     • `lblTitle` — the primary message. System-font, centre aligned.
//     • `lblBoldStationName` — optional emphasized sub-line.
//     • `btnContinue` — `PrimaryOrangeButton`, filled orange fill on
//       iOS 26 via `makeOrangeStyle()`, rounded 8pt. Title font
//       `AppFontClass.font(.caption1)` (12pt regular).
//     • `btnClose` — 40×40 circular close "×" at top-right, hidden
//       when `isCloseButtonHidden = true`.
//
//   **Two-button variant** (`AlertPopUpHorizontalStackController`):
//     • Same container / close styling.
//     • Horizontal stack with CANCEL on the left, CONTINUE on the right.
//     • Both buttons: 8pt corners, 12pt caption1 font, bordered
//       `craftButtonBorderColor` on pre-26, glass-style on iOS 26.
//     • `continueButtonColor` / `cancelButtonColor` overrides the fill
//       colour when caller wants a tinted primary.
//
// System `.alert()` can't reproduce any of that — rounded container,
// close X, orange fill, glass effect. Replacing it with a custom
// overlay so `env.alerts.show(...)` renders exactly like UIKit.

struct AppAlertModifier: ViewModifier {
    @ObservedObject var queue: AlertQueue

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item = queue.current {
                    BarsysAlertOverlay(item: item, onDismiss: { queue.dismiss() })
                        // 1:1 with UIKit `showCustomAlert` /
                        // `showCustomAlertMultipleButtons`
                        // (UIViewController.swift:241/264) which call
                        // `present(alertPopUpVc!, animated: true)` with
                        // `modalPresentationStyle = .overFullScreen` —
                        // UIKit's default modal animation is
                        // `.coverVertical`, i.e. the popup slides up
                        // from the bottom edge over a dimmed backdrop.
                        // The previous `.opacity` fade made the card
                        // pop in place, which read as a different
                        // affordance. Combining `.move(edge: .bottom)`
                        // with `.opacity` matches UIKit's slide-up +
                        // brief fade, producing the same physical
                        // motion the user remembers from the UIKit
                        // build.
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Bump from 0.2s → 0.35s so the slide is actually visible.
            // UIKit's default `coverVertical` modal animation runs in
            // ~0.35–0.45s, so this lands in the same perceptual range
            // without feeling sluggish.
            .animation(.easeInOut(duration: 0.35), value: queue.current?.id)
    }
}

/// Full-screen custom alert — renders the UIKit `AlertPopUpViewController`
/// visuals in SwiftUI.
struct BarsysAlertOverlay: View {
    let item: AppAlertItem
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // `mainBackgroundView` — black 0.45 dim (UIKit uses 0.3 on
            // iOS 26 and transparent pre-26; we use a slightly stronger
            // dim so the card pops on both paths — looks closer to the
            // iOS 26 glass behind the storyboard alert).
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { /* swallow — UIKit also ignores tap-outside */ }

            // `glassBackgroundView` — rounded card. The UIKit storyboard
            // uses a 40pt horizontal inset from the screen edges and
            // sizes vertically based on content.
            VStack(spacing: 20) {
                // Close "×" row — mirrors btnClose top-right placement.
                // 1:1 with UIKit `isCloseButtonHidden` flag (L62 of
                // UIViewController+Alerts.swift): when true, the X
                // button is suppressed entirely so success popups have
                // a single committed action (OK) and no escape hatch.
                if !item.hideClose {
                    HStack {
                        Spacer()
                        Button {
                            HapticService.light()
                            onDismiss()
                        } label: {
                            // Stroke-only `Circle()` has an empty
                            // interior — taps inside the empty disc
                            // were falling through. `contentShape`
                            // forces the entire 30×30 frame to be
                            // hit-testable so the close button works
                            // anywhere inside the visual circle.
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color("appBlackColor"))
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle().stroke(
                                        Color("craftButtonBorderColor"),
                                        lineWidth: 1
                                    )
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                }

                // lblTitle — centred, system 16pt. UIKit uses the
                // default label font from AlertPopUp.storyboard.
                // UIKit AlertPopUp.storyboard: lblTitle — system 16pt,
                // veryDarkGrayColor (#262626), centered.
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 16))
                        .foregroundStyle(Color("veryDarkGrayColor"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // lblBoldStationName — optional subtitle (we funnel
                // `item.message` into this slot since AppAlertItem
                // only has title + message, not title/subtitle/station).
                if !item.message.isEmpty {
                    Text(item.message)
                        .font(.system(size: 14))
                        .foregroundStyle(Color("appBlackColor"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Buttons. If secondary is present we render the
                // horizontal two-button variant; otherwise the single
                // full-width orange continue button.
                if let secondaryTitle = item.secondaryActionTitle {
                    // 1:1 with UIKit `AlertPopUpHorizontalStackController.viewSetup()`
                    // (AlertPopUpHorizontalStackController.swift L60-100):
                    //   • Both buttons: 45pt tall (storyboard constraints
                    //     `M7r-qm-fEL` / `MQx-vd-d9j`), 8pt corner radius
                    //     (`roundCorners = BarsysCornerRadius.small`), 12pt
                    //     `.caption1` font, black title color, distributed
                    //     fillEqually with 10pt spacing (storyboard SHM-jX-PBk).
                    //   • LEFT (storyboard `S94-K7-bsR`, btnContinue) →
                    //     `continueAction` handler → onComplete callback.
                    //     Style: when `continueButtonColor` is set → fill;
                    //     when nil → glass-bordered (iOS 26) or
                    //     craftButtonBorderColor 1pt border (pre-26).
                    //   • RIGHT (storyboard `O9K-cF-5wQ`, btnCancel) →
                    //     `cancelButtonClicked` handler → onCancel callback.
                    //     Same fill/border decision tree against
                    //     `cancelButtonColor`.
                    //
                    // SwiftUI maps:
                    //   item.primaryActionTitle / primaryAction → RIGHT (the
                    //     filled / "tinted" button — UIKit pattern is to
                    //     pass cancelButtonColor=.segmentSelectionColor for
                    //     the primary action of a decision alert).
                    //   item.secondaryActionTitle / secondaryAction → LEFT
                    //     (the neutral / cancel button).
                    HStack(spacing: 10) {
                        // LEFT — neutral / cancel button (btnContinue slot
                        // when continueButtonColor is nil). UIKit fallback:
                        //   iOS 26+ → `applyCancelCapsuleGradientBorderStyle()`
                        //              with 8pt CORNER (alertPopupButtonBackgroundStyle
                        //              passes BarsysCornerRadius.small)
                        //   Pre-26  → `makeBorder(1, .craftButtonBorderColor)`
                        //
                        // Uses `BounceButtonStyle()` to mirror the working
                        // "No, stay in the app" button on the rate-app
                        // `.confirm` popup (`alertBorderedButton` in
                        // Theme.swift) — same style class, same hit-test
                        // semantics.
                        Button {
                            HapticService.light()
                            item.secondaryAction?()
                            onDismiss()
                        } label: {
                            Text(secondaryTitle)
                                .modifier(AlertPopupButtonStyle(fill: nil))
                        }
                        .buttonStyle(BounceButtonStyle())

                        // RIGHT — primary / tinted button. UIKit:
                        //   alertPopUpButtonBackgroundStyle(cornerRadius: 8,
                        //                                   fillColor: cancelButtonColor)
                        // Fill = `.segmentSelectionColor` (the orange tint).
                        Button {
                            HapticService.light()
                            item.primaryAction?()
                            onDismiss()
                        } label: {
                            Text(item.primaryActionTitle)
                                .modifier(AlertPopupButtonStyle(fill: Theme.Color.segmentSelection))
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                } else if item.singlePrimaryStyle == .popup {
                    // 1:1 UIKit `AlertPopUpHorizontalStackController` SINGLE
                    // continue-button layout (success popup). Routes through
                    // the same `AlertPopupButtonStyle` as the two-button
                    // variant so the corners / font / height / glass treatment
                    // are byte-identical between alert types.
                    Button {
                        HapticService.light()
                        item.primaryAction?()
                        onDismiss()
                    } label: {
                        Text(item.primaryActionTitle)
                            .modifier(AlertPopupButtonStyle(fill: Theme.Color.segmentSelection))
                    }
                    .buttonStyle(.plain)
                } else {
                    // Single continue button — 1:1 UIKit AlertPopUp.storyboard:
                    // `mSZ-L7-enf` (continueButton): 209×45pt, brandTanColor
                    // background, 16pt text, 20pt corner radius.
                    //
                    // Title color: UIKit storyboard hard-codes
                    // `<color key="titleColor" white="0.0" alpha="1"
                    // customColorSpace="genericGamma22GrayColorSpace"/>`
                    // — pure BLACK, static in both light and dark
                    // appearance. The previous SwiftUI port tinted the
                    // label with `Theme.Color.softWhiteText`, which the
                    // user reported as off-brand on the
                    // "{device} is Disconnected" popup in light mode
                    // (white-on-orange where UIKit shows black-on-orange).
                    // Switching to `SwiftUI.Color.black` matches UIKit
                    // exactly on both appearances and stays consistent
                    // with the two-button variant's `AlertPopupButtonStyle`
                    // which already uses static black for the same
                    // storyboard-parity reason (Components.swift:1055).
                    Button {
                        HapticService.light()
                        item.primaryAction?()
                        onDismiss()
                    } label: {
                        Text(item.primaryActionTitle)
                            .font(.system(size: 16))
                            .foregroundStyle(SwiftUI.Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(primaryOrange)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            // 1:1 UIKit storyboard `t2p-he-XsL` (popupContainerView):
            //   • Outer card: 277pt wide × 158pt tall (single button)
            //   • Inner content view `mnn-57-zFZ`: 229pt wide × 120pt tall
            //     (24pt margin from card edges)
            //   • Title-stack to button-stack vertical spacing: 31pt
            //   • Button stack: 45pt tall, 10pt inter-button spacing
            //   • Card corner radius: 12 (BarsysCornerRadius.medium)
            //   • Centered on screen with 49pt left/right margin from
            //     safeArea (375 - 277 = 98 / 2 = 49pt per side on iPhone X)
            //   • Glass background via alertPopUpBackgroundStyle
            .padding(.horizontal, 24)        // UIKit `mnn-57-zFZ` 24pt margin
            .padding(.vertical, 24)
            // Storyboard width was 277pt, but "No, stay in the app" (the
            // widest secondary title in the app) was hitting the button's
            // edges. Each button now gets an extra 15pt of width (30pt
            // total across the two-button row) so labels sit with ≥10pt
            // of leading/trailing breathing room inside the pill.
            .frame(width: 345)
            .background(alertCardBackground)
            .overlay(
                // 1:1 UIKit `BarsysGlassBackground` border gradient
                // (Theme.swift L456-514): top-leading white@0.80 →
                // bottom-trailing white@0.25. The 0.3 flat stroke we had
                // was too subtle vs UIKit's etched-glass look.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.80),
                                Color.white.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // UIKit shadow on the alert card matches the glass-card
            // shadow used app-wide: lighter, larger blur than the previous
            // SwiftUI value (0.2 was too dark, made the popup look heavier
            // than the UIKit native alert).
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
        }
    }

    /// UIKit `alertPopUpBackgroundStyle()` from UIViewClass+GradientStyles.swift:
    ///   iOS 26+: addGlassEffect(cornerRadius: BarsysCornerRadius.medium=12)
    ///            — REAL `UIGlassEffect(.regular)`. We route through
    ///            `BarsysGlassPanelBackground` (the same UIViewRepresentable
    ///            used by SideMenu, DeviceListPopup, DeviceConnectedPopup,
    ///            BarsysPopupCard). Previously this used SwiftUI's
    ///            `.regularMaterial` which is a different recipe — the
    ///            Device Disconnected alert read as a flatter, more
    ///            translucent card than the rest of the app's glass
    ///            popups (especially in dark mode where the two
    ///            materials diverge visibly).
    ///   Pre-26: UIColor.white.withAlphaComponent(0.95), cornerRadius=12.
    ///           Routed through `Theme.Color.surface` (light = pure
    ///           sRGB(1,1,1), bit-identical to the previous hard-coded
    ///           `Color.white`, so light mode renders the EXACT same
    ///           card; dark = elevated dark surface #2C2C2E) so the
    ///           "Unable to create account…" / generic Barsys popups
    ///           don't render as a stark white slab over the dark sign-up
    ///           flow with the now-near-white adaptive `appBlackColor` /
    ///           `veryDarkGrayColor` title and message text becoming
    ///           illegible.
    @ViewBuilder
    private var alertCardBackground: some View {
        if #available(iOS 26.0, *) {
            BarsysGlassPanelBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.surface.opacity(0.95))
        }
    }

    /// Resolves the app's primary button colour. UIKit
    /// `PrimaryOrangeButton.makeOrangeStyle()` uses
    /// `segmentSelectionColor` (RGB 0.878/0.702/0.573 — a warm peach
    /// orange) as the flat fill on iOS <26, and a
    /// `brandGradientTop → brandGradientBottom` gradient on iOS 26+.
    /// We fall back to the RGB values inline when the asset is missing.
    private var primaryOrange: Color {
        if let asset = UIColor(named: "segmentSelectionColor") {
            return Color(asset)
        }
        return Color(red: 0.878, green: 0.702, blue: 0.573)
    }
}

extension View {
    func loadingOverlay(_ state: LoadingState) -> some View {
        modifier(LoadingOverlayModifier(state: state))
    }
    func appAlert(_ queue: AlertQueue) -> some View {
        modifier(AppAlertModifier(queue: queue))
    }
    func toastOverlay(_ manager: ToastManager) -> some View {
        modifier(ToastModifier(manager: manager))
    }
}

// MARK: - Toast
//
// Ports UIKit `UIView.showToast(message:duration:textColor:)` from UIViewClass.swift.
// White background, rounded corners, springs in from top, auto-dismisses.
//
// Usage:
//   1. Add `@StateObject var toast = ToastManager()` at app root
//   2. Apply `.toastOverlay(toast)` to root view
//   3. Call `toast.show("Message", color: .green, duration: 6)`

final class ToastManager: ObservableObject {
    @Published fileprivate(set) var current: ToastItem?

    struct ToastItem: Equatable {
        let message: String
        let color: Color
        let duration: TimeInterval
        let id = UUID()
    }

    func show(_ message: String, color: Color = .primary, duration: TimeInterval = 5) {
        current = ToastItem(message: message, color: color, duration: duration)
        let id = current?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.current?.id == id {
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.current = nil
                }
            }
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            current = nil
        }
    }
}

struct ToastModifier: ViewModifier {
    @ObservedObject var manager: ToastManager

    func body(content: Content) -> some View {
        // 1:1 with UIKit `UIView.showToast(message:duration:textColor:)`
        // (UIViewClass.swift L30-69):
        //   • PaddingLabel — 24pt left/right, multiline, centered
        //   • Font: AppFontClass.font(.footnote, weight: .bold) = 13pt bold
        //   • Background: UIColor.white @ 100% alpha (NOT translucent)
        //   • Corner: BarsysCornerRadius.medium = 12pt
        //   • Position: 40pt from safeArea top, centerX
        //   • Min height: 50pt (greaterThanOrEqualToConstant)
        //   • Side margins: 20pt min (greaterThanOrEqual / lessThanOrEqual)
        //   • Animation IN: 0.45s spring, damping 0.75, velocity 0.5,
        //                    transform y: -20 → 0, alpha 0 → 1
        //   • Animation OUT: 0.3s spring, damping 0.85 (subtle), velocity 0.5,
        //                    transform y: 0 → -12, alpha 1 → 0
        //   • Haptic: .light() on show (HapticService.shared.light())
        content.overlay(alignment: .top) {
            if let toast = manager.current {
                Text(toast.message)
                    .font(Theme.Font.of(.footnote, .bold))
                    .foregroundStyle(toast.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(minHeight: 50)              // UIKit min-height 50pt
                    .background(
                        // White @ 100% — UIKit explicitly uses
                        // `UIColor.white.withAlphaComponent(1.0)`, not a
                        // translucent material. `Theme.Color.surface`
                        // light value is sRGB(1, 1, 1) — bit-identical
                        // to the previous hard-coded `Color.white`,
                        // so light-mode toasts render the EXACT same
                        // opaque white pill as before. Dark mode picks
                        // up the elevated dark surface (#2C2C2E) so the
                        // toast text (default `Color.primary` adapts to
                        // white in dark) remains legible against the
                        // bar instead of disappearing into a white-on-
                        // white invisible pill.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.Color.surface)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    )
                    .padding(.horizontal, 20)         // UIKit min-margin 20pt
                    .padding(.top, 40)                // UIKit safeArea top + 40
                    // UIKit slides from y=-20 → y=0 — `.move(edge: .top)`
                    // is the SwiftUI equivalent vertical translate.
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // UIKit timing: 0.45s in / 0.3s out springs. The spring
        // (response: 0.45, damping: 0.75) approximates the in-curve
        // closely; the out gets the same animation here for symmetry.
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: manager.current?.id)
    }
}

// MARK: - AlertPopupButtonStyle
//
// 1:1 port of UIKit `alertPopUpButtonBackgroundStyle(cornerRadius:fillColor:)`
// + `applyCancelCapsuleGradientBorderStyle()` decision tree as used in
// `AlertPopUpHorizontalStackController.viewSetup()` (L60-100).
//
// UIKit logic per button (LEFT continue, RIGHT cancel — both treated the same):
//
//   roundCorners = BarsysCornerRadius.small  // 8pt
//   if let fillColor {
//       alertPopUpButtonBackgroundStyle(cornerRadius: 8, fillColor: fillColor)
//       // iOS 26: capsule glass + brand gradient + glass clear effect with bg @ 0.2
//       // pre-26: backgroundColor = fillColor
//   } else {
//       if #available(iOS 26.0, *) {
//           applyCancelCapsuleGradientBorderStyle()
//           // → addGlassEffect(tintColor: .cancelButtonGray, cornerRadius: h/2)
//       } else {
//           makeBorder(width: 1, color: .craftButtonBorderColor)
//           alertPopUpButtonBackgroundStyle(cornerRadius: 8, fillColor: nil)
//       }
//   }
//   titleLabel.font = AppFontClass.font(.caption1)  // 12pt regular
//   title.color = .black  (storyboard normal title color)
//   height = 45  (storyboard constraint)
//
// SwiftUI mirrors this decision tree exactly: filled buttons get the
// orange tint via `Theme.Color.segmentSelection`; bordered buttons get
// either an iOS 26 glass material with the cancel gradient stroke, or a
// pre-26 white-fill + 1pt craftButtonBorder stroke.
private struct AlertPopupButtonStyle: ViewModifier {
    /// Optional fill color — when non-nil, renders the FILLED variant
    /// (right-side cancel/primary button). When nil, renders the
    /// BORDERED variant (left-side continue/neutral button).
    let fill: Color?

    /// 1:1 port of UIKit `alertPopUpButtonBackgroundStyle` shape rule
    /// (UIViewClass+GradientStyles.swift L24-90):
    ///   • iOS 26+ → `addGlassEffect(cornerRadius: bounds.height/2)` —
    ///     OVERRIDES the storyboard's `BarsysCornerRadius.small = 8pt`
    ///     with a CAPSULE shape. At 45pt button height this resolves
    ///     to a 22.5pt corner radius (a proper pill).
    ///   • Pre-26  → 8pt rounded rect (storyboard `roundCorners = 8`
    ///     is respected because `addGlassEffect` is iOS 26 gated).
    ///
    /// The previous SwiftUI port used a flat 8pt corner radius on
    /// every iOS version, so the "Your drink has been saved" / popup
    /// OK button appeared as a small-rounded rect instead of the
    /// UIKit capsule on iOS 26. Now both match UIKit exactly.
    private var buttonShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12))                          // .caption1 = 12pt
            // 1:1 with UIKit `AlertPopUp.storyboard` — both `btnContinue`
            // and `btnCancel` define `<color key="titleColor" white="0.0"
            // alpha="1" colorSpace="custom" customColorSpace=
            // "genericGamma22GrayColorSpace"/>`, i.e. **static black** in
            // BOTH light and dark mode (it's a hard-coded color, not a
            // dynamic asset). Using `Color("appBlackColor")` here would
            // adapt to near-white in dark mode and break parity with
            // UIKit, which keeps the title BLACK on both the orange
            // gradient (right) and the gray-glass capsule (left) in
            // every appearance.
            .foregroundStyle(SwiftUI.Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.85)                          // gracefully shrink
                                                               // if a longer title
                                                               // still overflows
            .padding(.horizontal, 10)                          // ≥10pt between
                                                               // label text and
                                                               // pill edges
            .frame(maxWidth: .infinity)
            .frame(height: 45)                                // storyboard constraint
            .background(buttonBackground)
            .overlay(buttonBorder)
            .clipShape(buttonShape)
            // Explicit hit-test region — guarantees the entire pill
            // accepts taps even when the visible content (Text) is
            // narrower than the 45pt frame. Without this, SwiftUI
            // sometimes constrains the Button's tap region to the
            // intrinsic content, which left the LEFT "No" pill
            // partially unreachable along its trailing edge.
            .contentShape(buttonShape)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if let fill {
            // FILLED variant — 1:1 port of UIKit
            // `alertPopUpButtonBackgroundStyle(fillColor:)`
            // (UIViewClass+GradientStyles.swift L24-48):
            //   1. `applyCapsuleGradientStyle()` inserts a CAGradientLayer
            //      with vertical `brandGradientTop → brandGradientBottom`
            //      (#FAE0CC → #F2C2A1).
            //   2. `self.backgroundColor.withAlphaComponent(0.2)` —
            //      wiped on the next line by `addGlassEffect`, so this
            //      is dead code visually.
            //   3. `addGlassEffect(effect: "clear")` adds a near-
            //      transparent `UIGlassEffect(style: .clear)` view that
            //      ends with `backgroundColor = .clear`. The clear glass
            //      adds a faint sheen but the gradient reads through it
            //      unchanged — letting the two-stop peach→tan transition
            //      stay clearly visible.
            //
            // Mirrors `BarsysPopupCard.alertFilledButtonBackground` in
            // Theme.swift so the LOGOUT / rate-app / Yes please! popups
            // all render an identical primary pill.
            //
            // Hard-coded light-mode RGB matches `primaryOrangeButtonBackground`
            // (RecipesScreens.swift) — UIKit's `makeOrangeStyle()` keeps
            // brand orange in both appearances; the dynamic asset's dark
            // variant would render as an invisible near-black pill.
            //
            // The `_ = fill` discard preserves the bordered/filled
            // dispatch (callers pass non-nil fill to choose this branch)
            // without applying it as the dim tint UIKit clears.
            let _ = fill
            if #available(iOS 26.0, *) {
                // Vertical brand gradient capsule, hard-coded light
                // RGB so dark mode renders the same peach → tan pill
                // (matches `primaryOrangeButtonBackground` on the Recipe
                // Craft button and `BarsysPopupCard.alertFilledButtonBackground`
                // on `.confirm` popups). No `UIVisualEffectView`-backed
                // overlay — the previous attempt blocked the LEFT
                // button's tap gesture, and a pure SwiftUI Capsule
                // fill never interferes with hit testing.
                buttonShape.fill(
                    LinearGradient(
                        colors: [
                            SwiftUI.Color(red: 0.980, green: 0.878, blue: 0.800), // #FAE0CC
                            SwiftUI.Color(red: 0.949, green: 0.761, blue: 0.631)  // #F2C2A1
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            } else {
                // Pre-26 — UIKit L45: solid fillColor at full alpha.
                buttonShape.fill(fill)
            }
        } else if #available(iOS 26.0, *) {
            // BORDERED variant on iOS 26+ — IDENTICAL approach to
            // `BarsysPopupCard.alertSecondaryButtonBackground` in
            // Theme.swift, which renders the "No, stay in the app"
            // button on the rate-app `.confirm` popup correctly in
            // both light and dark mode.
            //
            // Two SwiftUI Capsule fills (no UIViewRepresentable):
            //   1. white @ 85 % — the bright base that keeps the pill
            //      reading as a light glass capsule in both modes.
            //   2. cancelButtonGray @ 15 % — the subtle gray wash
            //      mirroring UIKit `addGlassEffect(tintColor:
            //      .cancelButtonGray)` (UIViewClass+GradientStyles.swift
            //      L92-110, body of `applyCancelCapsuleGradientBorderStyle`).
            //
            // Why not a real `UIGlassEffect` here? The previous attempt
            // wrapped a `UIVisualEffectView` in `.background(...)`. Even
            // with `isUserInteractionEnabled = false` and SwiftUI's
            // `.allowsHitTesting(false)`, the representable was
            // intercepting the Button's tap. SwiftUI Capsule fills are
            // pure shape primitives that never touch hit testing, so
            // the "No" button stays tappable while still rendering the
            // intended bright pill — same recipe + same caller-perceived
            // behaviour as the working "No, stay in the app" button.
            ZStack {
                Capsule(style: .continuous)
                    .fill(SwiftUI.Color.white.opacity(0.85))
                Capsule(style: .continuous)
                    .fill(Theme.Color.cancelButtonGray.opacity(0.15))
            }
        } else {
            // Pre-26 BORDERED variant — UIKit
            // `makeBorder(1, .craftButtonBorderColor)` + white bg.
            // `Theme.Color.surface` preserves the historical white
            // fill in light mode bit-identically and adapts in dark.
            buttonShape.fill(Theme.Color.surface)
        }
    }

    @ViewBuilder
    private var buttonBorder: some View {
        if fill != nil {
            // No border on filled buttons (UIKit only sets fill).
            EmptyView()
        } else if #available(iOS 26.0, *) {
            // iOS 26 BORDERED — IDENTICAL stroke to
            // `BarsysPopupCard.alertSecondaryButtonBorder` in Theme.swift
            // (the "No, stay in the app" button). 6-stop white@0.95 ↔
            // cancelBorderGray@0.9 sheen at 1.5pt — the same etched-glass
            // edge `BarsysGlassPanelBackground` puts on the popup card
            // itself. UIKit's `applyCancelCapsuleGradientBorderStyle`
            // technically ignores its border params at runtime, but the
            // SwiftUI port has carried this stroke since launch as the
            // visual signature of the alert popup's neutral pill — and
            // matching the working "No, stay in the app" button means
            // matching this border too.
            buttonShape
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
            // Pre-26 — plain 1pt craftButtonBorderColor stroke
            // (UIKit `makeBorder(1, .craftButtonBorderColor)`).
            buttonShape.stroke(Theme.Color.craftButtonBorder, lineWidth: 1)
        }
    }
}

// MARK: - Keyboard input accessory toolbars
//
// 1:1 port of UIKit `UITextField+addDoneToolbar` /
// `addDoneCancelToolbar` helpers (UITextField.swift L11-40, L85-117):
//
//   • addDoneToolbar()       → [flexibleSpace, Done]
//   • addDoneCancelToolbar() → [Cancel, flexibleSpace, Done]
//     (tintColor = appBlackColor, barStyle = .default)
//
// Applied across the UIKit app wherever a keyboard has no built-in
// "Done" / "Return" affordance — notably:
//
//   • Login / SignUp: phone + OTP (numberPad / phonePad)
//   • BarBot "Ask Anything" (UITextView)
//   • Recipe / Edit-recipe / Make-My-Own ingredient quantities
//     (numberPad / decimalPad)
//   • SelectQuantity picker fields
//   • Date-of-birth picker
//
// iOS 26 glass design (user ask): use icon buttons — `xmark` for
// Cancel and `checkmark` for Done — inside the toolbar so the chrome
// matches the system's liquid-glass accessory bar. Pre-26 keeps the
// classic "Cancel" / "Done" text labels for bit-identical parity
// with the UIKit system items.
//
// SwiftUI implementation uses `.toolbar { ToolbarItemGroup(placement:
// .keyboard) { ... } }` which renders as the native input accessory.
// The caller passes close closures; the modifier also hides the
// keyboard via `dismissKeyboard()` so the Done/Cancel behavior
// matches `resignFirstResponder()` in UIKit.

/// Hides the currently-focused keyboard.
///
/// Mirrors UIKit `self.view.endEditing(true)` / `resignFirstResponder()`.
private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil
    )
}

/// Ports `addDoneToolbar()` — single trailing-aligned Done button.
/// Callers that only need dismissal can omit `onDone`; the default
/// just hides the keyboard (same as UIKit's default target action).
struct KeyboardDoneToolbar: ViewModifier {
    var onDone: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer() // flexibleSpace — right-aligns the Done button
                Button {
                    HapticService.light()
                    dismissKeyboard()
                    onDone?()
                } label: {
                    if #available(iOS 26.0, *) {
                        // iOS 26 glass → tick icon (matches the user's
                        // "cross / tick" ask for the glass toolbar).
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .tint(Color("appBlackColor"))
                .accessibilityLabel("Done")
            }
        }
    }
}

/// Ports `addDoneCancelToolbar(onDone:onCancel:)` — Cancel on the
/// leading edge, Done on the trailing edge, flexible space between.
/// Cancel uses `xmark` and Done uses `checkmark` on iOS 26 for the
/// glass look; pre-26 keeps "Cancel" / "Done" text.
struct KeyboardDoneCancelToolbar: ViewModifier {
    var onDone: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    HapticService.light()
                    dismissKeyboard()
                    onCancel?()
                } label: {
                    if #available(iOS 26.0, *) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .regular))
                    }
                }
                .tint(Color("appBlackColor"))
                .accessibilityLabel("Cancel")

                Spacer() // flexibleSpace

                Button {
                    HapticService.light()
                    dismissKeyboard()
                    onDone?()
                } label: {
                    if #available(iOS 26.0, *) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .tint(Color("appBlackColor"))
                .accessibilityLabel("Done")
            }
        }
    }
}

extension View {
    /// Attaches the `[flexibleSpace, Done]` keyboard accessory bar
    /// used on recipe-quantity, edit-recipe-quantity, and
    /// make-my-own fields (UIKit `addDoneToolbar()`).
    func keyboardDoneToolbar(onDone: (() -> Void)? = nil) -> some View {
        modifier(KeyboardDoneToolbar(onDone: onDone))
    }

    /// Attaches the `[Cancel, flexibleSpace, Done]` keyboard accessory
    /// bar used on login / signup / BarBot / select-quantity fields
    /// (UIKit `addDoneCancelToolbar(onDone:onCancel:)`).
    func keyboardDoneCancelToolbar(onDone: (() -> Void)? = nil,
                                   onCancel: (() -> Void)? = nil) -> some View {
        modifier(KeyboardDoneCancelToolbar(onDone: onDone, onCancel: onCancel))
    }
}

// MARK: - UIKitTextField (reliable inputAccessoryView Cancel/Done bar)
//
// SwiftUI's `.toolbar { ToolbarItemGroup(placement: .keyboard) }` can
// fail to attach on screens that also call `.toolbar(.hidden, for:
// .navigationBar)` — on iOS 26 the two toolbar modifiers race and the
// Cancel/Done accessory goes missing on the Login / Sign-Up phone
// field even though the previous fix (commit 34bd8ee) reordered the
// modifiers. Bypassing SwiftUI here and attaching a real `UIToolbar`
// as the underlying UITextField's `inputAccessoryView` (1:1 with the
// UIKit `addDoneCancelToolbar` and the BarBotScreens implementation)
// makes the bar deterministic regardless of the surrounding SwiftUI
// modifier chain.
struct UIKitTextField: UIViewRepresentable {
    @Binding var text: String
    /// Optional two-way focus binding — when set, the parent can drive
    /// the underlying UITextField's first-responder state and observe
    /// it back. Pass `nil` (the default) for fields whose focus is
    /// only ever driven by the user tapping into the field.
    var isFocused: Binding<Bool>? = nil
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var font: UIFont = .systemFont(ofSize: 17)
    var textColor: UIColor = UIColor(named: "appBlackColor") ?? .label
    var alignment: NSTextAlignment = .natural
    /// Sanitises the value coming from the field BEFORE writing it to
    /// the binding — used by the Login phone field to strip non-digits
    /// and cap length, so the rendered text matches the binding.
    var sanitize: ((String) -> String)? = nil
    var onChange: ((String) -> Void)? = nil
    var onDone: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        if let tct = textContentType { field.textContentType = tct }
        field.font = font
        field.textColor = textColor
        field.textAlignment = alignment
        field.borderStyle = .none
        // The blinking caret colour is driven by `tintColor`. Pin it
        // to `appBlackColor` (adaptive: dark in light mode, light in
        // dark mode) so the cursor is always legible — without this
        // it inherits the parent view's tint, which on the auth
        // screens leaves the caret nearly invisible against the form
        // surface (the QA "blinking cursor not showing" report).
        field.tintColor = UIColor(named: "appBlackColor") ?? .label
        field.delegate = context.coordinator
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.editingChanged(_:)),
                        for: .editingChanged)

        // Cancel + flexibleSpace + Done — 1:1 with UIKit's
        // `addDoneCancelToolbar` and BarBotScreens' inputAccessoryView.
        let bar = UIToolbar()
        bar.sizeToFit()
        bar.tintColor = UIColor(named: "appBlackColor")
        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel,
                                     target: context.coordinator,
                                     action: #selector(Coordinator.tapCancel))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                                   target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done,
                                   target: context.coordinator,
                                   action: #selector(Coordinator.tapDone))
        bar.items = [cancel, flex, done]
        field.inputAccessoryView = bar

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = font
        uiView.textColor = textColor
        uiView.placeholder = placeholder
        // Refresh the coordinator's parent so its closures capture the
        // latest View-state — without this the onChange/onDone/onCancel
        // closures would forever point at the first SwiftUI render's
        // copy.
        context.coordinator.parent = self

        // Programmatic focus sync. Only run when the SwiftUI side
        // diverges from the UIKit side so we don't fight the user
        // tapping into the field.
        if let binding = isFocused {
            if binding.wrappedValue, !uiView.isFirstResponder {
                DispatchQueue.main.async { uiView.becomeFirstResponder() }
            } else if !binding.wrappedValue, uiView.isFirstResponder {
                DispatchQueue.main.async { uiView.resignFirstResponder() }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: UIKitTextField

        init(_ parent: UIKitTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ sender: UITextField) {
            let raw = sender.text ?? ""
            let cleaned = parent.sanitize?(raw) ?? raw
            if cleaned != raw {
                sender.text = cleaned
            }
            parent.text = cleaned
            parent.onChange?(cleaned)
        }

        @objc func tapDone() {
            HapticService.light()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil)
            parent.onDone?()
        }

        @objc func tapCancel() {
            HapticService.light()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil)
            parent.onCancel?()
        }

        // Mirror first-responder state back into the SwiftUI focus
        // binding so parents that observe it (e.g. the OTP caret
        // animation) react correctly.
        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard let binding = parent.isFocused else { return }
            DispatchQueue.main.async { [weak textField] in
                guard let tf = textField, tf.isFirstResponder,
                      !binding.wrappedValue else { return }
                binding.wrappedValue = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard let binding = parent.isFocused else { return }
            // Re-check at execution time: the user may have already
            // re-tapped a box (flipping focus back to true) before
            // this async hop runs. Without this guard, the late
            // didEndEditing closure would clobber the user's fresh
            // focus and the caret would disappear right after the
            // user re-focused — the QA "cursor not visible" trail.
            DispatchQueue.main.async { [weak textField] in
                guard let tf = textField, !tf.isFirstResponder,
                      binding.wrappedValue else { return }
                binding.wrappedValue = false
            }
        }
    }
}
