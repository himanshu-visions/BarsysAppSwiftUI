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
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: Theme.Spacing.m) {
                            ProgressView().controlSize(.large).tint(.white)
                            if !state.message.isEmpty {
                                Text(state.message).font(Theme.Font.body(14)).foregroundStyle(.white)
                            }
                        }
                        .padding(Theme.Spacing.l)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.isVisible)
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

                // lblTitle — centred, system 16pt. UIKit uses the
                // default label font from AlertPopUp.storyboard.
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color("appBlackColor"))
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
                    // AlertPopUpHorizontalStackController layout:
                    // cancel on LEFT, continue on RIGHT — both bordered
                    // with `craftButtonBorderColor`, 8pt corners,
                    // 12pt caption1 font.
                    HStack(spacing: 12) {
                        Button {
                            HapticService.light()
                            item.secondaryAction?()
                            onDismiss()
                        } label: {
                            Text(secondaryTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color("appBlackColor"))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            HapticService.light()
                            item.primaryAction?()
                            onDismiss()
                        } label: {
                            Text(item.primaryActionTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color("appBlackColor"))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Single orange continue button (PrimaryOrangeButton).
                    // UIKit `makeOrangeStyle()` produces a filled orange
                    // pill; we replicate via `primaryOrangeColor` if
                    // defined, otherwise fall back to a system orange.
                    Button {
                        HapticService.light()
                        item.primaryAction?()
                        onDismiss()
                    } label: {
                        Text(item.primaryActionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(primaryOrange)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: 320)
            .background(alertCardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 4)
            .padding(.horizontal, 40)
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
        content.overlay(alignment: .top) {
            if let toast = manager.current {
                Text(toast.message)
                    .font(Theme.Font.of(.footnote, .bold))
                    .foregroundStyle(toast.color)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    )
                    .padding(.top, 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.current?.id)
    }
}
