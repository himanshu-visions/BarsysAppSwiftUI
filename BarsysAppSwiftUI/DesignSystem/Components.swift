//
//  Components.swift
//  BarsysAppSwiftUI
//
//  Reusable SwiftUI primitives matching the existing UIKit components.
//

import SwiftUI

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
            // Search / close toggle — UIKit `searchAndCloseButton`
            // (storyboard id `Rgp-rv-h72`): 44×44, buttonType=system,
            // tintColor=grayBorderColor, image swaps between
            // `exploreSearch` and `crossIcon` based on whether the field
            // has content.
            Button {
                HapticService.light()
                if !query.isEmpty {
                    // Image is crossIcon → tap clears.
                    query = ""
                } else {
                    // Image is exploreSearch → tap activates the field.
                    isFocused = true
                }
            } label: {
                Image(query.isEmpty ? "exploreSearch" : "crossIcon")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color("grayBorderColor"))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(query.isEmpty ? "Search" : "Clear search")

            // Text field — `Wl4-tx-sp4`: placeholder="Search", system 14pt,
            // textColor=appBlackColor, leftView=30pt padding (we consume
            // that slot by the 44×44 button + small interior gap so the
            // typed text visually starts at ~44pt from the container edge,
            // which is identical to what UIKit renders).
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
                .padding(.trailing, 10) // storyboard trailing constraint constant=10
        }
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

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // Hidden text field that captures all input.
            TextField("", text: Binding(
                get: { code },
                set: { newValue in
                    let filtered = newValue.filter(\.isNumber)
                    code = String(filtered.prefix(length))
                }))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.001)
                .frame(width: 1, height: 1)

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { idx in
                    boxAt(idx)
                }
            }
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }

    private func boxAt(_ idx: Int) -> some View {
        let chars = Array(code)
        let value = idx < chars.count ? String(chars[idx]) : "0"
        let isFilled = idx < chars.count
        // Fixed square 32x32 — matches the storyboard runtime size of the
        // 6 OtpTextField boxes (form card 333pt − padding − 6 boxes with
        // 10pt spacing ≈ 28–32pt per box). Square via 1:1 aspect ratio.
        return Text(value)
            .font(.system(size: 18))
            .foregroundStyle(isFilled
                             ? Color("subtitleGrayColor")
                             : Color("subtitleGrayColor").opacity(0.45))
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.001))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color("paleBlueGrayColor"), lineWidth: 1)
            )
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
                                .foregroundStyle(.white.opacity(0.85))
                        )

                    if let onFavorite {
                        let isFav = recipe.isFavourite ?? false
                        Button(action: onFavorite) {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isFav ? Theme.Color.danger : .white)
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

                            if !state.message.isEmpty {
                                // UIKit message label: AppFontClass.font(.subheadline, weight: .medium)
                                // = SF Pro Display Medium 15pt, color .loaderTextColor,
                                // centered, 2-line max.
                                Text(state.message)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.Color.loaderText)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(.horizontal, 16)
                            }
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
    /// iOS 26+ → `.regularMaterial` (matches UIGlassEffect(style: .regular))
    /// Pre-26  → `.thinMaterial` (matches UIBlurEffect(style: .systemMaterial))
    @ViewBuilder
    private var loaderCardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
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
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: queue.current?.id)
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
                        Button {
                            HapticService.light()
                            item.secondaryAction?()
                            onDismiss()
                        } label: {
                            Text(secondaryTitle)
                                .modifier(AlertPopupButtonStyle(fill: nil))
                        }
                        .buttonStyle(.plain)

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
                        .buttonStyle(.plain)
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
                    // background, white 16pt text, 20pt corner radius.
                    Button {
                        HapticService.light()
                        item.primaryAction?()
                        onDismiss()
                    } label: {
                        Text(item.primaryActionTitle)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.white)
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
            .frame(width: 277)               // UIKit `t2p-he-XsL` exact width
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
    ///   Pre-26: UIColor.white.withAlphaComponent(0.95), cornerRadius=12
    @ViewBuilder
    private var alertCardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.95))
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
            .foregroundStyle(Color("appBlackColor"))          // black title
            .frame(maxWidth: .infinity)
            .frame(height: 45)                                // storyboard constraint
            .background(buttonBackground)
            .overlay(buttonBorder)
            .clipShape(buttonShape)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if let fill {
            // FILLED variant — UIKit `alertPopUpButtonBackgroundStyle`
            // with non-nil fillColor. Solid fill on both iOS versions.
            // UIKit iOS 26 path layers a `.clear` glass effect on top
            // (UIViewClass+GradientStyles.swift L141-162) so the tint
            // reads as a wet-glass pill rather than a flat fill. The
            // glassHighlight overlay gives us that sheen cleanly.
            ZStack {
                buttonShape.fill(fill)
                if #available(iOS 26.0, *) {
                    buttonShape
                        .fill(Theme.Gradient.glassHighlight)
                        .opacity(0.35)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
        } else if #available(iOS 26.0, *) {
            // iOS 26 BORDERED variant — UIKit `applyCancelCapsuleGradientBorderStyle()`
            // applies a glass effect with `cancelButtonGray` tint. We
            // approximate with `.regularMaterial` + a subtle white tint
            // so the button reads as a frosted pill on the popup card.
            buttonShape
                .fill(.regularMaterial)
                .overlay(
                    buttonShape.fill(Theme.Color.cancelButtonGray.opacity(0.15))
                )
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
            // iOS 26 cancel-capsule border gradient — same 8-stop
            // alternating white / cancelBorderGray sheen UIKit applies
            // via `applyCancelCapsuleGradientBorderStyle(borderColors:)`
            // (UIViewClass+GradientStyles.swift L92-110).
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
            // Pre-26 — plain 1pt craftButtonBorderColor stroke.
            buttonShape.stroke(Theme.Color.craftButtonBorder, lineWidth: 1)
        }
    }
}
