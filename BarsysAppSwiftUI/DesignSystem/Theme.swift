//
//  Theme.swift
//  BarsysAppSwiftUI
//
//  Design tokens that mirror the existing UIKit BarsysApp.
//  Colors are read from the real Assets.xcassets catalog copied from the
//  UIKit project, so light/dark variants and alpha levels match exactly.
//  Fonts reference the SF Pro Display custom fonts bundled in Fonts/.
//

import SwiftUI

enum Theme {

    enum Color {

        // Core / background — light theme, matches primaryBackgroundColor etc.
        static let background           = SwiftUI.Color("primaryBackgroundColor")
        static let secondaryBackground  = SwiftUI.Color("secondaryBackgroundColor")
        static let tertiaryBackground   = SwiftUI.Color("tertiaryBackgroundColor")
        static let warmBackground       = SwiftUI.Color("warmBackgroundColor")
        static let softPlatinum         = SwiftUI.Color("softPlatinumColor")
        static let whiteTranslucent     = SwiftUI.Color("whiteTranslucent70")

        // Surfaces (for cards / sheets)
        static let surface              = SwiftUI.Color.white
        static let surfaceElevated      = SwiftUI.Color("warmBackgroundColor")

        // Brand (tan / peach)
        static let brand                = SwiftUI.Color("brandTanColor")
        static let brand45              = SwiftUI.Color("brandTanColor45")
        static let brand60              = SwiftUI.Color("brandTanColor60")
        static let coral                = SwiftUI.Color("coralColor")
        static let darkRed              = SwiftUI.Color("darkRedColor")
        static let lightPeach           = SwiftUI.Color("lightPeachColor")
        static let segmentSelection     = SwiftUI.Color("segmentSelectionColor")
        static let sideMenuSelection    = SwiftUI.Color("sideMenuSelectionColor")

        // Semantic
        static let success              = SwiftUI.Color("successGreenColor")
        static let danger               = SwiftUI.Color("errorLabelColor")
        static let perishable           = SwiftUI.Color("perishableColor")

        // Text
        static let textPrimary          = SwiftUI.Color("appBlackColor")       // #4C4D4F
        static let textSecondary        = SwiftUI.Color("mediumGrayColor")
        static let textTertiary         = SwiftUI.Color("lightGrayColor")
        static let textDisabled         = SwiftUI.Color("disabledGrayColor")
        static let textMuted            = SwiftUI.Color("mutedGrayColor")
        static let inputPlaceholder     = SwiftUI.Color("inputPlaceholderColor")
        static let craftingTitle        = SwiftUI.Color("craftingTitleColor")
        static let charcoalGray         = SwiftUI.Color("charcoalGrayColor")
        static let darkGrayText         = SwiftUI.Color("darkGrayTextColor")
        static let aiBlack              = SwiftUI.Color("aiBlackTextColor")
        static let subtitleGray         = SwiftUI.Color("subtitleGrayColor")
        static let unSelected           = SwiftUI.Color("unSelectedColor")

        // Borders
        static let border               = SwiftUI.Color("borderColor")
        static let paleBlueGrayBorder   = SwiftUI.Color("paleBlueGrayColor")
        static let steelGrayBorder      = SwiftUI.Color("steelGrayColor")
        static let softDivider          = SwiftUI.Color("softDividerColor")
        static let silver               = SwiftUI.Color("silverColor")
        static let separator30          = SwiftUI.Color("separatorColor30Alpha")
        static let warmGray             = SwiftUI.Color("warmGrayColor")
        static let craftButtonBorder    = SwiftUI.Color("craftButtonBorderColor")
        static let otpPlaceholder       = SwiftUI.Color("otpPlaceHolderColor")
    }

    // MARK: - Fonts
    //
    // Exact parity with UIKit AppFontClass. PostScript names are verified
    // from the real BarsysApp/Helpers/AppFont/AppFontClass.swift:
    //   SFProDisplay-Regular, -Medium, -Semibold, -Bold, -Black, -LightItalic
    // Type scale matches AppFontClass.TextStyle point sizes (iOS HIG-aligned).

    enum Font {

        /// Semantic type scale — mirrors AppFontClass.TextStyle.
        enum Style {
            case caption2        // 10
            case caption1        // 12
            case footnote        // 13
            case callout         // 14
            case subheadline     // 15
            case body            // 16
            case headline        // 17
            case title3          // 18
            case title2          // 20
            case title1          // 24
            case largeTitleSmall // 28
            case largeTitle      // 30

            var size: CGFloat {
                switch self {
                case .caption2:         return 10
                case .caption1:         return 12
                case .footnote:         return 13
                case .callout:          return 14
                case .subheadline:      return 15
                case .body:             return 16
                case .headline:         return 17
                case .title3:           return 18
                case .title2:           return 20
                case .title1:           return 24
                case .largeTitleSmall:  return 28
                case .largeTitle:       return 30
                }
            }
        }

        enum Weight { case regular, medium, semibold, bold, black }

        private static func psName(_ weight: Weight) -> String {
            switch weight {
            case .regular:  return "SFProDisplay-Regular"
            case .medium:   return "SFProDisplay-Medium"
            case .semibold: return "SFProDisplay-Semibold"
            case .bold:     return "SFProDisplay-Bold"
            case .black:    return "SFProDisplay-Black"
            }
        }

        /// Semantic, weighted font. Use this by default: `.font(Theme.Font.of(.body, .medium))`
        static func of(_ style: Style, _ weight: Weight = .regular) -> SwiftUI.Font {
            .custom(psName(weight), size: style.size, relativeTo: .body)
        }

        static func italic(_ style: Style) -> SwiftUI.Font {
            .custom("SFProDisplay-LightItalic", size: style.size, relativeTo: .body)
        }

        // Raw sized variants — use sparingly, prefer .of(.style, .weight)
        static func regular(_ size: CGFloat) -> SwiftUI.Font {
            .custom("SFProDisplay-Regular", size: size, relativeTo: .body)
        }
        static func medium(_ size: CGFloat) -> SwiftUI.Font {
            .custom("SFProDisplay-Medium", size: size, relativeTo: .body)
        }
        static func semibold(_ size: CGFloat) -> SwiftUI.Font {
            .custom("SFProDisplay-Semibold", size: size, relativeTo: .headline)
        }
        static func bold(_ size: CGFloat) -> SwiftUI.Font {
            .custom("SFProDisplay-Bold", size: size, relativeTo: .headline)
        }
        static func black(_ size: CGFloat) -> SwiftUI.Font {
            .custom("SFProDisplay-Black", size: size, relativeTo: .largeTitle)
        }

        // Convenience role-based fonts (used by pre-existing views)
        static func title(_ size: CGFloat = 28) -> SwiftUI.Font { bold(size) }
        static func headline(_ size: CGFloat = 17) -> SwiftUI.Font { semibold(size) }
        static func body(_ size: CGFloat = 16) -> SwiftUI.Font { regular(size) }
        static func caption(_ size: CGFloat = 13) -> SwiftUI.Font { medium(size) }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    /// 1:1 port of UIKit `BarsysCornerRadius`
    /// (BarsysApp/Helpers/Constants/Constants+UI.swift lines 226-232).
    /// Every rounded surface in the app is quantised to one of these
    /// five tokens — keep the raw numbers locked to UIKit so cards,
    /// buttons, and glass effects never drift.
    enum Radius {
        /// UIKit `BarsysCornerRadius.small` — small cells, inline
        /// pills, action-card chips.
        static let s: CGFloat = 8
        /// UIKit `BarsysCornerRadius.medium` — Choose-Options tile,
        /// hero images, popup cards.
        static let m: CGFloat = 12
        /// UIKit `BarsysCornerRadius.large` — mixlist / recipe cells,
        /// MixlistRowCell glass wrapper.
        static let l: CGFloat = 16
        /// UIKit `BarsysCornerRadius.xlarge` — tall glass containers
        /// such as side menu wrappers.
        static let xl: CGFloat = 20
        /// UIKit `BarsysCornerRadius.pill` — 48pt-tall buttons render
        /// as true capsules (height / 2 = 24).
        static let pill: CGFloat = 24
    }
}

// MARK: - View modifiers / helpers

struct CardBackground: ViewModifier {
    var corner: CGFloat = Theme.Radius.m
    var fill: Color = Theme.Color.surface
    var border: Color = Theme.Color.softDivider
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: shadow ? .black.opacity(0.04) : .clear,
                    radius: shadow ? 8 : 0, x: 0, y: 4)
    }
}

extension View {
    func cardBackground(corner: CGFloat = Theme.Radius.m,
                        fill: Color = Theme.Color.surface,
                        border: Color = Theme.Color.softDivider,
                        shadow: Bool = true) -> some View {
        modifier(CardBackground(corner: corner, fill: fill, border: border, shadow: shadow))
    }

    /// Standard horizontal page padding (matches UIKit 16 pt gutter).
    func pagePadding() -> some View {
        padding(.horizontal, Theme.Spacing.m)
    }
}
//  the underlying CAGradientLayer / UIVisualEffectView dance.
//
//  UIKit references (each modifier is annotated with the source helper):
//
//   • UIViewClass+GlassEffects.swift
//       — addGlassEffect(isBorderEnabled:cornerRadius:alpha:effect:)
//       — addGlassEffectToUIButton(...)
//       — addBlurEffect(cornerRadius:alpha:)
//       — addGlassEffectNavigationRightGlassViewOnly()
//       — Internal shadow values (shadowOpacity 0.30, offset (0,10),
//         radius 25, color black @ 0.20).
//   • UIViewClass+GradientStyles.swift
//       — applyCapsuleGradientStyle(topColor:bottomColor:textColor:)
//       — applyCancelCapsuleGradientBorderStyle(borderColors:bg:bg:width:)
//       — addGradientLayer(colors:locations:start:end:cornerRadius:)
//       — alertPopUpBackgroundStyle / alertPopUpButtonBackgroundStyle
//   • UIViewClass.swift
//       — applyCustomShadow(cornerRadius:size:opacity:radius:color:)
//   • PrimaryOrangeButton.swift
//       — makeOrangeStyle()
//

// MARK: - Gradient palette

extension Theme {

    enum Gradient {

        /// Brand capsule gradient — `brandTanColor` → `coralColor`,
        /// vertical (top → bottom). Used by `PrimaryOrangeButton`,
        /// "Craft Recipe", "Setup Stations", "Update Profile",
        /// "Confirm" CTAs across the UIKit project.
        ///
        /// Mirrors UIKit `applyCapsuleGradientStyle(topColor:.brandGradientTop,
        /// bottomColor:.brandGradientBottom)`.
        static var brand: LinearGradient {
            LinearGradient(
                colors: [Theme.Color.brand, Theme.Color.coral],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// Diagonal brand gradient — used by RecipeDetail's "Add to
        /// Favorites" outline + Mixlist hero placeholders.
        static var brandDiagonal: LinearGradient {
            LinearGradient(
                colors: [Theme.Color.brand, Theme.Color.coral],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Soft horizontal brand stroke — used by gradient borders on
        /// secondary buttons (e.g. "Add to Favorites").
        static var brandHorizontal: LinearGradient {
            LinearGradient(
                colors: [
                    Theme.Color.brand,
                    Theme.Color.brand.opacity(0.4),
                    Theme.Color.coral
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        /// Cancel-capsule border gradient — alternating
        /// white@0.95 / cancelBorderGray@0.9 stops used by
        /// `applyCancelCapsuleGradientBorderStyle`. Re-creates the
        /// faux-glass etched border on cancel/secondary buttons.
        static var cancelCapsuleBorder: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.95), location: 0.0),
                    .init(color: SwiftUI.Color(white: 0.74).opacity(0.9), location: 0.2),
                    .init(color: .white.opacity(0.95), location: 0.4),
                    .init(color: .white.opacity(0.95), location: 0.6),
                    .init(color: SwiftUI.Color(white: 0.74).opacity(0.9), location: 0.8),
                    .init(color: .white.opacity(0.95), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Top-down white-highlight overlay used as the "wet glass"
        /// sheen on every glass capsule. Mirrors UIKit's
        /// `alertPopUpSecondGradientStyle` second layer.
        static var glassHighlight: LinearGradient {
            LinearGradient(
                colors: [SwiftUI.Color.white.opacity(0.30), SwiftUI.Color.white.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// Subtle scrim used at the bottom of long scrolls so floating
        /// CTAs stay readable. Background → transparent (top to bottom).
        static var bottomScrim: LinearGradient {
            LinearGradient(
                colors: [Theme.Color.background.opacity(0), Theme.Color.background],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Shadow tokens
//
// Centralises the four shadow recipes that recur across the UIKit
// project so views don't drift apart.

extension Theme {
    enum Shadow {
        /// Mirrors `applyCustomShadow(size:1.0, shadowRadius:3.0)` —
        /// used on `ChooseOptionCollectionViewCell` tile.
        case tile
        /// Mirrors `applyCustomShadow(size:4.0)` —
        /// used on `ChooseOptionsDashboardViewController` inner card.
        case card
        /// Mirrors `addGlassEffect()` shadow values — black@0.18,
        /// y=6, radius 12. Used on every `GlassCircleButton` + the
        /// glass capsules in the side menu.
        case glass
        /// Soft drop shadow used on floating bottom CTAs (Craft,
        /// Setup Stations, Reset System).
        case floatingButton

        var color: SwiftUI.Color {
            switch self {
            case .tile:           return .black.opacity(0.43)
            case .card:           return .black.opacity(0.43)
            case .glass:          return .black.opacity(0.18)
            case .floatingButton: return .black.opacity(0.15)
            }
        }
        var radius: CGFloat {
            switch self {
            case .tile:           return 3
            case .card:           return 9
            case .glass:          return 12
            case .floatingButton: return 6
            }
        }
        var offset: CGSize {
            switch self {
            case .tile:           return CGSize(width: 0, height: 1)
            case .card:           return CGSize(width: 0, height: 4)
            case .glass:          return CGSize(width: 0, height: 6)
            case .floatingButton: return CGSize(width: 0, height: 3)
            }
        }
    }
}

extension View {
    /// Applies one of the canonical Barsys shadow recipes.
    func barsysShadow(_ token: Theme.Shadow) -> some View {
        shadow(color: token.color,
               radius: token.radius,
               x: token.offset.width,
               y: token.offset.height)
    }
}

// MARK: - Glass background
//
// 1:1 port of UIKit `addGlassEffect(isBorderEnabled:cornerRadius:alpha:)`.
// On iOS 26+ UIKit uses `UIGlassEffect`; SwiftUI's `.regularMaterial`
// is the documented bridge. The white border + glass-highlight gradient
// overlay re-create the "wet glass" sheen the helper produces, and the
// shadow matches UIKit's internal values.

struct BarsysGlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var alpha: CGFloat
    var isBorderEnabled: Bool
    var tint: SwiftUI.Color?

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(alpha)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.Gradient.glassHighlight)
                        .blendMode(.plusLighter)
                        .opacity(0.6)
                }
            )
            .overlay(
                Group {
                    if isBorderEnabled {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [SwiftUI.Color.white.opacity(0.8),
                                             SwiftUI.Color.white.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .barsysShadow(.glass)
    }
}

extension View {
    /// Applies the Barsys glass effect — material fill + sheen +
    /// optional white border + canonical glass shadow.
    /// Direct port of UIKit `addGlassEffect(isBorderEnabled:
    /// cornerRadius:alpha:effect:)`.
    func barsysGlass(cornerRadius: CGFloat,
                     alpha: CGFloat = 1.0,
                     isBorderEnabled: Bool = true,
                     tint: SwiftUI.Color? = nil) -> some View {
        modifier(BarsysGlassBackground(cornerRadius: cornerRadius,
                                       alpha: alpha,
                                       isBorderEnabled: isBorderEnabled,
                                       tint: tint))
    }
}

// MARK: - Brand capsule button
//
// 1:1 port of `applyCapsuleGradientStyle()` + `PrimaryOrangeButton.makeOrangeStyle()`.
// Vertical brand gradient fill, white text, capsule shape, soft glass
// highlight overlay, floating-button shadow.

struct BarsysBrandCapsuleStyle: ButtonStyle {
    var height: CGFloat = 54
    var horizontalPadding: CGFloat = 24
    var cornerRadius: CGFloat? = nil
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        // 1:1 port of UIKit `PrimaryOrangeButton.makeOrangeStyle()`:
        //   • iOS 26+: vertical `brandGradientTop → brandGradientBottom`
        //     gradient, capsule corner radius = height/2, with a subtle
        //     glass-highlight overlay.
        //   • iOS <26: FLAT `segmentSelection` fill, corner radius 8.
        // Matches the PrimaryOrangeButton branch at
        // Helpers/CustomViews/PrimaryOrangeButton.swift L35-L69.
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        let radius: CGFloat = cornerRadius ?? (iOS26Available ? height / 2 : 8)
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(iOS26Available ? SwiftUI.Color.white : SwiftUI.Color.black)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.brand)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.35)
                    } else {
                        // UIKit L62-66: flat `segmentSelection` fill,
                        // rounded 8, no gradient. Title stays black.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Color.segmentSelection)
                    }
                }
            )
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .barsysShadow(.floatingButton)
    }
}

// MARK: - Cancel capsule (gradient-bordered glass button)
//
// 1:1 port of `applyCancelCapsuleGradientBorderStyle()`. Glass fill
// + alternating white/grey border gradient, used on Cancel / Pause /
// Stop / Continue / "More" / secondary CTAs.

struct BarsysCancelCapsuleStyle: ButtonStyle {
    var height: CGFloat = 54
    var horizontalPadding: CGFloat = 24
    var cornerRadius: CGFloat? = nil
    var textColor: SwiftUI.Color = SwiftUI.Color("appBlackColor")

    func makeBody(configuration: Configuration) -> some View {
        // 1:1 port of UIKit `applyCancelCapsuleGradientBorderStyle()`:
        //   • iOS 26+ → `addGlassEffect(tintColor: cancelButtonGray,
        //                cornerRadius: height/2)` with the 8-stop
        //                `cancelCapsuleBorder` gradient stroke.
        //   • iOS <26 → UIKit callers (CraftingVC L271, RecipePage
        //                L249-252, StationsMenu L84) fall back to
        //                `makeBorder(width: 1, color: .craftButtonBorderColor)`
        //                on a flat white bg with the same radius.
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        let radius = cornerRadius ?? height / 2
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        // Glass fill — `addGlassEffect(tintColor:cancelButtonGray)`
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(SwiftUI.Color.white.opacity(0.35))
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.5)
                    } else {
                        // Flat white fill for pre-iOS 26 (UIKit fallback).
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(SwiftUI.Color.white)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        iOS26Available
                            ? AnyShapeStyle(Theme.Gradient.cancelCapsuleBorder)
                            : AnyShapeStyle(Theme.Color.craftButtonBorder),
                        lineWidth: iOS26Available ? 1.5 : 1.0
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .barsysShadow(.floatingButton)
    }
}

// MARK: - Convenience initialisers

extension ButtonStyle where Self == BarsysBrandCapsuleStyle {
    /// `Button("Craft Recipe") { … }.buttonStyle(.barsysBrand)`
    static var barsysBrand: BarsysBrandCapsuleStyle { .init() }
    static func barsysBrand(height: CGFloat,
                            cornerRadius: CGFloat? = nil) -> BarsysBrandCapsuleStyle {
        .init(height: height, cornerRadius: cornerRadius)
    }
}

extension ButtonStyle where Self == BarsysCancelCapsuleStyle {
    /// `Button("Cancel") { … }.buttonStyle(.barsysCancel)`
    static var barsysCancel: BarsysCancelCapsuleStyle { .init() }
    static func barsysCancel(height: CGFloat,
                             cornerRadius: CGFloat? = nil) -> BarsysCancelCapsuleStyle {
        .init(height: height, cornerRadius: cornerRadius)
    }
}

// MARK: - PrimaryButton / SecondaryButton bridge
//
// Existing screens call `PrimaryButton(title:)` / `SecondaryButton(title:)`
// from `Components.swift`. Those now render through the brand /
// cancel capsule styles below, ensuring every CTA in the app picks up
// the new gradient + glass + shadow without per-screen edits.

extension View {
    /// Wraps content with the brand capsule treatment — drop-in
    /// replacement when the existing PrimaryButton component cannot
    /// be modified directly.
    ///
    /// Mirrors UIKit `PrimaryOrangeButton.makeOrangeStyle()`:
    ///   • iOS 26+  → gradient + capsule (height/2) + white title
    ///   • iOS <26 → flat `segmentSelection` + corner 8 + black title
    func brandCapsule(height: CGFloat = 54,
                      cornerRadius: CGFloat? = nil,
                      isEnabled: Bool = true) -> some View {
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        let radius: CGFloat = cornerRadius ?? (iOS26Available ? height / 2 : 8)
        return self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(iOS26Available ? SwiftUI.Color.white : SwiftUI.Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.brand)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.35)
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Color.segmentSelection)
                    }
                }
            )
            .opacity(isEnabled ? 1.0 : 0.5)
            .barsysShadow(.floatingButton)
    }

    /// Cancel-capsule treatment for secondary CTAs.
    ///
    /// Mirrors UIKit `applyCancelCapsuleGradientBorderStyle()` (iOS 26+
    /// glass) or the flat `makeBorder(width: 1, color:
    /// .craftButtonBorderColor)` fallback most screens use on earlier
    /// iOS.
    func cancelCapsule(height: CGFloat = 54,
                       cornerRadius: CGFloat? = nil,
                       textColor: SwiftUI.Color = SwiftUI.Color("appBlackColor")) -> some View {
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        let radius = cornerRadius ?? height / 2
        return self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(SwiftUI.Color.white.opacity(0.35))
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.5)
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(SwiftUI.Color.white)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        iOS26Available
                            ? AnyShapeStyle(Theme.Gradient.cancelCapsuleBorder)
                            : AnyShapeStyle(Theme.Color.craftButtonBorder),
                        lineWidth: iOS26Available ? 1.5 : 1.0
                    )
            )
            .barsysShadow(.floatingButton)
    }
}
//   • AlertPopUpViewController                — generic 1- or 2-button alert
//   • ManualStartSpiningPopUpViewController   — Shaker manual-spin prompt
//   • MultipleIngredientsPopUpViewController  — ingredient-detection chooser
//   • ShakerFlatSurfacePopUpViewController    — Shaker not flat warning
//   • WaitingRecipePopUpViewController        — long-running craft progress
//
//  Each UIKit screen uses a custom xib but they all share the same dark
//  scrim + frosted-glass card + title + body + button stack pattern.
//  This file exposes one `BarsysPopup` enum + a `.barsysPopup($state)`
//  modifier so any view can present any of the six popups uniformly.
//
//  Visual recipe (matches UIKit `alertPopUpBackgroundStyle` + glass
//  effect + UIKit storyboard frames):
//   • Backdrop: black @ 0.55 alpha, full-screen, tap-to-dismiss when the
//     popup is non-blocking.
//   • Card: 320pt wide × auto height, 16pt corner radius (`BarsysCornerRadius.large`),
//     `.regularMaterial` glass fill + `glassHighlight` overlay + 1pt
//     white border, `.glass` shadow.
//   • Title: 16pt semibold, `appBlackColor`, multi-line.
//   • Body: 14pt regular, `charcoalGrayColor`.
//   • Buttons: brand capsule (primary) + cancel capsule (secondary),
//     45pt height, 8pt corners, side-by-side when both present.
//   • Spinning loader (Manual Start Spinning, Waiting Recipe) shows a
//     brand-tinted ProgressView under the title.
//

import SwiftUI

// MARK: - Popup descriptor

enum BarsysPopup: Equatable, Identifiable {
    /// Generic single-action alert ("OK" or custom title).
    case alert(title: String,
               message: String?,
               primaryTitle: String = ConstantButtonsTitle.okButtonTitle,
               isBlocking: Bool = false)

    /// Generic two-action confirm (primary brand + secondary cancel).
    /// Mirrors UIKit `AlertPopUpHorizontalStackController.show(...)`.
    case confirm(title: String,
                 message: String?,
                 primaryTitle: String,
                 secondaryTitle: String = ConstantButtonsTitle.cancelButtonTitle,
                 isDestructive: Bool = false)

    /// Manual-start spinning prompt for the Shaker — title +
    /// brand-spinner + "Cancel" footer button.
    case manualSpinning(title: String, message: String?)

    /// Multiple-ingredients picker — shows a list of detected ingredient
    /// names and lets the user pick one. Mirrors
    /// `MultipleIngredientsPopUpViewController`.
    case multipleIngredients(title: String, ingredients: [String])

    /// Shaker-not-flat warning — message + single dismiss button. Mirrors
    /// `ShakerFlatSurfacePopUpViewController`.
    case shakerFlatSurface(message: String)

    /// Long-running waiting popup with brand spinner. Mirrors
    /// `WaitingRecipePopUpViewController`.
    case waiting(title: String, message: String?)

    var id: String {
        switch self {
        case .alert(let t, _, _, _):                  return "alert-\(t)"
        case .confirm(let t, _, _, _, _):             return "confirm-\(t)"
        case .manualSpinning(let t, _):               return "manualSpin-\(t)"
        case .multipleIngredients(let t, _):          return "multi-\(t)"
        case .shakerFlatSurface:                      return "shakerFlat"
        case .waiting(let t, _):                      return "waiting-\(t)"
        }
    }

    var isBlocking: Bool {
        switch self {
        case .alert(_, _, _, let blocking):     return blocking
        case .manualSpinning, .waiting:         return true   // user must wait
        case .shakerFlatSurface:                return true
        case .confirm, .multipleIngredients:    return true
        }
    }
}

// MARK: - View modifier

extension View {
    /// Attach a `BarsysPopup?` binding to any view to render the unified
    /// glass-card overlay with built-in scrim + fade-in transition.
    /// Provide an `onResult` closure for popups that return a value
    /// (confirmation Yes/No, picked ingredient, etc.).
    func barsysPopup(
        _ binding: Binding<BarsysPopup?>,
        onPrimary: @escaping () -> Void = {},
        onSecondary: @escaping () -> Void = {},
        onPickIngredient: @escaping (String) -> Void = { _ in }
    ) -> some View {
        modifier(BarsysPopupModifier(
            popup: binding,
            onPrimary: onPrimary,
            onSecondary: onSecondary,
            onPickIngredient: onPickIngredient
        ))
    }
}

private struct BarsysPopupModifier: ViewModifier {
    @Binding var popup: BarsysPopup?
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onPickIngredient: (String) -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if let current = popup {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if !current.isBlocking { popup = nil }
                        }
                        .transition(.opacity)
                    BarsysPopupCard(
                        popup: current,
                        onPrimary: { popup = nil; onPrimary() },
                        onSecondary: { popup = nil; onSecondary() },
                        onPickIngredient: { name in
                            popup = nil
                            onPickIngredient(name)
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.2), value: popup)
                .zIndex(50)
            }
        }
    }
}

// MARK: - Card

private struct BarsysPopupCard: View {
    let popup: BarsysPopup
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onPickIngredient: (String) -> Void

    private let cardWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 16) {
            switch popup {
            case .alert(let title, let message, let primaryTitle, _):
                titleLabel(title)
                if let message { bodyLabel(message) }
                primaryButton(primaryTitle, action: onPrimary)

            case .confirm(let title, let message, let primaryTitle, let secondaryTitle, let isDestructive):
                titleLabel(title)
                if let message { bodyLabel(message) }
                HStack(spacing: 8) {
                    secondaryButton(secondaryTitle, action: onSecondary)
                    if isDestructive {
                        destructiveButton(primaryTitle, action: onPrimary)
                    } else {
                        primaryButton(primaryTitle, action: onPrimary)
                    }
                }

            case .manualSpinning(let title, let message):
                titleLabel(title)
                if let message { bodyLabel(message) }
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.Color.brand)
                    .scaleEffect(1.4)
                    .padding(.vertical, 8)
                secondaryButton(ConstantButtonsTitle.cancelButtonTitle,
                                action: onSecondary)

            case .multipleIngredients(let title, let ingredients):
                titleLabel(title)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(ingredients, id: \.self) { ing in
                            Button {
                                onPickIngredient(ing)
                            } label: {
                                Text(ing)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color("appBlackColor"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color("borderColor"), lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel(ing)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 200)
                secondaryButton(ConstantButtonsTitle.cancelButtonTitle,
                                action: onSecondary)

            case .shakerFlatSurface(let message):
                titleLabel("Shaker not flat")
                bodyLabel(message)
                primaryButton(ConstantButtonsTitle.okButtonTitle,
                              action: onPrimary)

            case .waiting(let title, let message):
                titleLabel(title)
                if let message { bodyLabel(message) }
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.Color.brand)
                    .scaleEffect(1.4)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Gradient.glassHighlight)
                .opacity(0.6)
                .blendMode(.plusLighter)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.7),
                                            .white.opacity(0.25)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .barsysShadow(.glass)
    }

    // MARK: - Subviews

    private func titleLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color("appBlackColor"))
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    private func bodyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Color("charcoalGrayColor"))
            .multilineTextAlignment(.center)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { HapticService.light(); action() } label: {
            Text(title).brandCapsule(height: 45, cornerRadius: 8)
        }
        .buttonStyle(BounceButtonStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { HapticService.light(); action() } label: {
            Text(title).cancelCapsule(height: 45, cornerRadius: 8)
        }
        .buttonStyle(BounceButtonStyle())
    }

    private func destructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { HapticService.light(); action() } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color("errorLabelColor"))
                )
                .barsysShadow(.floatingButton)
        }
        .buttonStyle(BounceButtonStyle())
    }
}
