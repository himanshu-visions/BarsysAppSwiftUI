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

        // Surfaces (for cards / sheets).
        // `surfaceColor` is an adaptive asset:
        //   • Light: pure white sRGB(1, 1, 1) — bit-identical to the
        //     historical hard-coded `Color.white`, so every IconButton,
        //     AppTextField, RecipeCard etc. renders the EXACT same
        //     pixels in light mode as before this change.
        //   • Dark:  elevated dark surface (#2C2C2E) — sits one step
        //     lighter than `primaryBackgroundColor` so cards / inputs /
        //     popups still read as raised surfaces.
        static let surface              = SwiftUI.Color("surfaceColor")
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
        // Adaptive replacement for hard-coded `Color.white` foregrounds.
        // Light = pure white (1,1,1) — bit-identical to `Color.white` so
        // light-mode pixels are unchanged. Dark = #EBEBEB (0.92,0.92,0.92)
        // — a very subtle off-white that softens OLED glare without
        // looking grey.
        static let softWhiteText        = SwiftUI.Color("softWhiteTextColor")
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

        // 1:1 with UIKit `UIColor.swift` cancel-button + loader colors.
        // These are the exact dynamic light/dark tokens used by
        // `applyCancelCapsuleGradientBorderStyle()` (border, tint, fill)
        // and `showGlassLoader()` (text). They were referenced by hex
        // values inline before — exposing them as Theme tokens guarantees
        // dark-mode parity with UIKit instead of hard-coded RGB.
        static let cancelBorderGray     = SwiftUI.Color(
            UIColor(named: "cancelBorderGray")
                ?? UIColor.dynamic(light: UIColor(red: 0.851, green: 0.851, blue: 0.851, alpha: 1),  // #D9D9D9
                                   dark:  UIColor(red: 0.282, green: 0.282, blue: 0.290, alpha: 1)) // #48484A
        )
        static let cancelButtonGray     = SwiftUI.Color(
            UIColor(named: "cancelButtonGray")
                ?? UIColor.dynamic(light: UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1),  // #F2F2F2
                                   dark:  UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1)) // #3A3A3C
        )
        static let cancelBgTop          = SwiftUI.Color(
            UIColor(named: "cancelBgTop")
                ?? UIColor.dynamic(light: UIColor(red: 0.969, green: 0.969, blue: 0.969, alpha: 1),  // #F7F7F7
                                   dark:  UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)) // #2C2C2E
        )
        static let cancelBgBottom       = SwiftUI.Color(
            UIColor(named: "cancelBgBottom")
                ?? UIColor.dynamic(light: UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1),  // #E5E5E5
                                   dark:  UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)) // #1C1C1E
        )
        static let loaderText           = SwiftUI.Color(
            UIColor(named: "loaderTextColor")
                ?? UIColor.dynamic(light: UIColor(red: 0.20,  green: 0.20,  blue: 0.20,  alpha: 1),  // #333333
                                   dark:  UIColor(red: 0.820, green: 0.820, blue: 0.839, alpha: 1)) // #D1D1D6
        )
        static let veryDarkGray         = SwiftUI.Color(
            UIColor(named: "veryDarkGrayColor")
                ?? UIColor.dynamic(light: UIColor(red: 0.149, green: 0.149, blue: 0.149, alpha: 1),  // #262626
                                   dark:  UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1)) // #E5E5EA
        )
    }
}

// MARK: - UIColor.dynamic(light:dark:)
//
// 1:1 port of UIKit `UIColor.dynamic(light:dark:)` from
// `Helpers/Colors/UIColor.swift`. Used as a runtime fallback for the
// few cancel-button + loader colors that may not have asset entries —
// guarantees light/dark parity with the UIKit colour pipeline.
extension UIColor {
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension Theme {

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
            // UIKit PrimaryOrangeButton uses system default text (black)
            .foregroundStyle(SwiftUI.Color.black)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        // UIKit makeOrangeStyle(): brandGradientTop→brandGradientBottom
                        // vertical gradient, capsule shape
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SwiftUI.Color("brandGradientTop"),
                                        SwiftUI.Color("brandGradientBottom")
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        // "Wet glass" sheen overlay — 1:1 with UIKit
                        // `alertPopUpButtonBackgroundStyle` which layers a
                        // `.clear` glass effect on top of the coloured
                        // fill. 0.30 gives the button the same highlight
                        // as the native iOS 26 glass capsules without
                        // washing out the orange tone.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.30)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                    } else {
                        // UIKit L62-66: flat `segmentSelection` fill,
                        // rounded 8, no gradient. Title stays black.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Color.segmentSelection)
                    }
                }
            )
            .opacity(isEnabled ? 1.0 : 0.5)
            // Bounce: 0.95 scale, matching UIKit addBounceEffect
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.15, dampingFraction: 0.5),
                value: configuration.isPressed
            )
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
    /// 1:1 with UIKit `MultipleIngredientsPopUpViewController`'s
    /// `alpha = 0.5; userInteractionEnabled = false` pattern — used
    /// when a popup decision button is awaiting a required selection.
    var isEnabled: Bool = true

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
            .opacity(isEnabled ? 1.0 : 0.5)
            // Bounce: 0.95 scale, matching UIKit addBounceEffect
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.15, dampingFraction: 0.5),
                value: configuration.isPressed
            )
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
    /// 1:1 port of UIKit `PrimaryOrangeButton.makeOrangeStyle()`:
    ///   iOS 26+: vertical gradient brandGradientTop (#FAE0CC) → brandGradientBottom (#F2C2A1),
    ///            capsule shape (cornerRadius = height/2), masksToBounds = false
    ///   Pre-26:  solid segmentSelectionColor (#E0B392), 8pt corner radius
    ///   Both:    addBounceEffect(), black text, no border
    func brandCapsule(height: CGFloat = 54,
                      cornerRadius: CGFloat? = nil,
                      isEnabled: Bool = true) -> some View {
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        // UIKit makeOrangeStyle() ALWAYS uses height/2 on iOS 26+ (capsule),
        // regardless of storyboard cornerRadius. Pre-26 uses 8pt.
        let radius: CGFloat = iOS26Available ? height / 2 : (cornerRadius ?? 8)
        return self
            .font(.system(size: 16, weight: .semibold))
            // UIKit PrimaryOrangeButton doesn't set text color explicitly —
            // uses system default (black on light mode). Previous SwiftUI
            // used white on iOS 26 which was wrong.
            .foregroundStyle(SwiftUI.Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    if iOS26Available {
                        // UIKit: CAGradientLayer with brandGradientTop → brandGradientBottom
                        // startPoint (0.5, 0) endPoint (0.5, 1) — vertical top-to-bottom
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SwiftUI.Color("brandGradientTop"),
                                        SwiftUI.Color("brandGradientBottom")
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        // UIKit: backgroundColor = .segmentSelection (#E0B392)
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
                       textColor: SwiftUI.Color = SwiftUI.Color("appBlackColor"),
                       showsBorder: Bool = true) -> some View {
        let iOS26Available: Bool = {
            if #available(iOS 26.0, *) { return true } else { return false }
        }()
        // UIKit applyCancelCapsuleGradientBorderStyle() ALWAYS uses height/2
        // on iOS 26+ (capsule). Pre-26 uses the passed radius or height/2.
        let radius = iOS26Available ? height / 2 : (cornerRadius ?? height / 2)
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
                        // Force the light-mode wet-glass sheen in BOTH
                        // color schemes — the user asked for the dark-
                        // mode capsule to look identical to light mode
                        // (matches the Rating popup's left button in
                        // light mode). Trait-resolved 35% white alpha
                        // on a `.regularMaterial` base renders as the
                        // EXACT historical light-mode pixels on every
                        // device. (Previously dark mode used 5% which
                        // made the pill blend into the dark backdrop.)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(SwiftUI.Color.white.opacity(0.35))
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Gradient.glassHighlight)
                            .opacity(0.5)
                    } else {
                        // Pre-iOS 26 — `Theme.Color.surface` light =
                        // pure white sRGB(1, 1, 1), bit-identical to
                        // the previous hard-coded `Color.white`, so
                        // light mode renders the EXACT same capsule.
                        // Dark mode picks up elevated dark surface
                        // (#2C2C2E) → matches My Bar upload button
                        // style on pre-iOS 26 too.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.Color.surface)
                    }
                }
            )
            .overlay(
                // `showsBorder == false` matches the UIKit Crafting-view
                // cancel button where the pill has no visible stroke —
                // only the translucent glass fill. The default remains
                // `true` so every other call site (popups, alerts) keeps
                // the gradient border.
                Group {
                    if showsBorder {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(
                                iOS26Available
                                    ? AnyShapeStyle(Theme.Gradient.cancelCapsuleBorder)
                                    : AnyShapeStyle(Theme.Color.craftButtonBorder),
                                lineWidth: iOS26Available ? 1.5 : 1.0
                            )
                    }
                }
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
    /// `isCloseHidden`: hides the close X button. Default is `true` to
    /// mirror UIKit `showCustomAlert(isCloseButtonHidden: Bool = true)`
    /// (UIViewController+Alerts.swift L10) — every default-arg caller
    /// in UIKit relies on the X being suppressed for single-OK alerts.
    case alert(title: String,
               message: String?,
               primaryTitle: String = ConstantButtonsTitle.okButtonTitle,
               isBlocking: Bool = false,
               isCloseHidden: Bool = true)

    /// Generic two-action confirm — mirrors UIKit `AlertPopUpHorizontalStackController`.
    ///
    /// UIKit button mapping (AlertPopUpHorizontalStackController storyboard):
    ///   - continueButton (LEFT): `continueButtonTitle` — default glass/border style
    ///   - cancelButton (RIGHT):  `cancelButtonTitle` — optional fill via `cancelButtonColor`
    ///
    /// `primaryTitle` maps to the RIGHT button (cancel in UIKit naming = primary action).
    /// `secondaryTitle` maps to the LEFT button (continue in UIKit naming = secondary/dismiss).
    /// `primaryFillColor`: when set, fills the primary (right) button with this color
    ///   (e.g. `.segmentSelectionColor` for rating popup). `nil` = brand gradient.
    /// `isCloseHidden`: hides the close X button (UIKit `isCloseButtonHidden`).
    /// Default `true` — every UIKit `showCustomAlertMultipleButtons` call
    /// site passes `isCloseButtonHidden: true` except three intentional
    /// instruction popups (StationsMenu pour-ingredients, station-cleaning
    /// proceed-to-clean, EditRecipe unsaved-changes); those callers set
    /// `isCloseHidden: false` explicitly.
    /// UIKit `showCustomAlertMultipleButtons` ALWAYS passes
    /// `cancelButtonColor: .segmentSelectionColor` — the primary (right)
    /// button is ALWAYS brand-gradient-filled. Default reflects this.
    case confirm(title: String,
                 message: String?,
                 primaryTitle: String,
                 secondaryTitle: String = ConstantButtonsTitle.cancelButtonTitle,
                 isDestructive: Bool = false,
                 primaryFillColor: String? = "segmentSelectionColor",
                 isCloseHidden: Bool = true)

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
        case .alert(let t, _, _, _, _):                return "alert-\(t)"
        case .confirm(let t, _, _, _, _, _, _):        return "confirm-\(t)"
        case .manualSpinning(let t, _):               return "manualSpin-\(t)"
        case .multipleIngredients(let t, _):          return "multi-\(t)"
        case .shakerFlatSurface:                      return "shakerFlat"
        case .waiting(let t, _):                      return "waiting-\(t)"
        }
    }

    var isBlocking: Bool {
        switch self {
        case .alert(_, _, _, let blocking, _):  return blocking
        case .manualSpinning, .waiting:         return true   // user must wait
        case .shakerFlatSurface:                return true
        case .confirm, .multipleIngredients:    return true
        }
    }

    /// Whether the top-right X button is suppressed. Mirrors UIKit's
    /// `isCloseButtonHidden` flag on `AlertPopUpViewController` /
    /// `AlertPopUpHorizontalStackController` and the storyboard
    /// presence/absence of `btnClose` on the other popup VCs.
    ///   • `.alert` / `.confirm` — caller-controlled via `isCloseHidden`
    ///     (defaults to `true` to match UIKit's helpers).
    ///   • `.manualSpinning` — UIKit shows the X (storyboard `btnClose`
    ///     visible by default; tap = `closeButtonTapped` → BLE cancel
    ///     + dismiss).
    ///   • `.multipleIngredients` — UIKit hides the X. Both call sites
    ///     (`MyBarViewController.swift:397`,
    ///     `ScanIngredientsViewController.swift:303`) explicitly pass
    ///     `isCloseButtonHidden: true`.
    ///   • `.shakerFlatSurface` — storyboard has no `btnClose` at all.
    ///   • `.waiting` — storyboard uses a `btnCancel` (bottom button),
    ///     not a top-right X.
    var hidesClose: Bool {
        switch self {
        case .alert(_, _, _, _, let isCloseHidden):           return isCloseHidden
        case .confirm(_, _, _, _, _, _, let isCloseHidden):   return isCloseHidden
        case .manualSpinning:                                 return false
        case .multipleIngredients:                            return true
        case .shakerFlatSurface, .waiting:                    return true
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
                    // UIKit: btnTransparent backgroundColor = black.withAlphaComponent(0.5)
                    Color.black.opacity(0.50)
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
                        },
                        // UIKit `crossButtonClicked(_:)` for every popup
                        // (AlertPopUpViewController / Horizontal stack /
                        // ManualStartSpining / MultipleIngredients): just
                        // dismiss. Distinct from the secondary button so
                        // callers can tell "user explicitly closed" from
                        // "user picked Cancel" via `.onChange(of: popup)`.
                        onClose: { popup = nil }
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
    /// Top-right X button — fires when the user explicitly closes.
    /// 1:1 with UIKit `crossButtonClicked(_:)` IBAction across
    /// `AlertPopUpViewController`, `AlertPopUpHorizontalStackController`,
    /// `ManualStartSpiningPopUpViewController`, and
    /// `MultipleIngredientsPopUpViewController`.
    let onClose: () -> Void

    // Storyboard was 277pt but that pinned the two-button row to
    // 109.5pt per button — "No, stay in the app" touched the pill edges
    // with no breathing room. Widened by 30pt so each button gains
    // +15pt and the secondary label has ≥10pt leading/trailing inside
    // the pill (matched by `.padding(.horizontal, 10)` on the button
    // label text itself — see `alertBorderedButton` /
    // `alertPrimaryFilledButton`).
    private let cardWidth: CGFloat = 307

    var body: some View {
        // 1:1 port of UIKit `AlertPopUpHorizontalStackController` storyboard
        // (AlertPopUp.storyboard scene `49Z-qz-g5j`). Measurements:
        //
        //   Card `t2p-he-XsL`           : 277×158 at (49, 339.67) on 375pt canvas
        //   Inner content `mnn-57-zFZ`  : 229×120 at (24, 24) — 24pt margin all sides
        //   Title stack `2DB-u8-FOR`    : 209×16 at (10, 14) — **10pt** horiz +
        //                                 14pt top inset INSIDE inner content;
        //                                 VStack spacing=16 between title & subtitle
        //   Button stack `SHM-jX-PBk`   : 229×45 at (0, 61) — **0pt** horiz inset
        //                                 (flush with inner content), top = title
        //                                 stack bottom + **31pt**, bottom = inner
        //                                 content bottom - 14pt
        //   Each button                 : 109.5×45, fillEqually + 10pt spacing
        //
        // Previously the SwiftUI port:
        //   • Used `VStack(spacing: 16)` for the whole card, giving only 16pt
        //     between title and buttons (UIKit uses **31pt** — buttons looked
        //     too close to the title).
        //   • Shared the same `.padding(.horizontal, 24)` for title AND buttons,
        //     making the buttons the same width as the title (UIKit buttons are
        //     **20pt wider** than the title — "bigger button than text").
        //
        // Now: outer card padding is 24pt L/R (matching inner content inset),
        // but `titleLabel` / `bodyLabel` add an extra 10pt inset — so buttons
        // span the full 229pt inner width while the title is only 209pt.
        // Vertical spacing is controlled explicitly per-section to reproduce
        // the UIKit 14pt top / 16pt title-subtitle / 31pt title-buttons /
        // 14pt bottom ladder.
        VStack(alignment: .center, spacing: 0) {
            switch popup {
            case .alert(let title, let message, let primaryTitle, _, _):
                popupTitleBlock(title: title, message: message)
                primaryButton(primaryTitle, action: onPrimary)
                    .padding(.top, 31) // UIKit title.bottom + 31
                    .padding(.bottom, 14)

            case .confirm(let title, let message, let primaryTitle, let secondaryTitle, let isDestructive, let primaryFillColor, _):
                popupTitleBlock(title: title, message: message)
                // UIKit AlertPopUpHorizontalStackController: equal distribution,
                // spacing 10pt, each button 109.5×45, pill corners on iOS 26.
                HStack(spacing: 10) {
                    // LEFT = secondaryButton (UIKit "continueButton") — border only
                    alertSecondaryButton(secondaryTitle, action: onSecondary)
                    // RIGHT = primaryButton (UIKit "cancelButton") — filled or gradient
                    if isDestructive {
                        destructiveButton(primaryTitle, action: onPrimary)
                    } else if let fillColorName = primaryFillColor {
                        alertPrimaryFilledButton(primaryTitle, fillColor: fillColorName, action: onPrimary)
                    } else {
                        alertPrimaryButton(primaryTitle, action: onPrimary)
                    }
                }
                .padding(.top, 31) // UIKit title.bottom + 31
                .padding(.bottom, 14)

            case .manualSpinning(let title, let message):
                popupTitleBlock(title: title, message: message)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.Color.brand)
                    .scaleEffect(1.4)
                    .padding(.vertical, 8)
                    .padding(.top, 23) // 31 - 8 (vertical 8 above + 8 below)
                secondaryButton(ConstantButtonsTitle.cancelButtonTitle,
                                action: onSecondary)
                    .padding(.bottom, 14)

            case .multipleIngredients(let title, let ingredients):
                popupTitleBlock(title: title, message: nil)
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
                .padding(.top, 16)
                secondaryButton(ConstantButtonsTitle.cancelButtonTitle,
                                action: onSecondary)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

            case .shakerFlatSurface(let message):
                popupTitleBlock(title: "Shaker not flat", message: message)
                primaryButton(ConstantButtonsTitle.okButtonTitle,
                              action: onPrimary)
                    .padding(.top, 31)
                    .padding(.bottom, 14)

            case .waiting(let title, let message):
                popupTitleBlock(title: title, message: message)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.Color.brand)
                    .scaleEffect(1.4)
                    .padding(.vertical, 8)
                    .padding(.top, 23)
                    .padding(.bottom, 14)
            }
        }
        // UIKit card inner content is inset 24pt from the card edges on
        // top/leading/trailing. Bottom padding is handled per-case above
        // since the "14pt bottom" measurement is relative to the inner
        // content bottom which is exactly where our content ends.
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(width: cardWidth)
        .background(popupCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.7),
                                            .white.opacity(0.25)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        // Top-right close X — 1:1 with UIKit `btnClose` (top-right of
        // every AlertPopUp / ManualSpinning / MultipleIngredients
        // storyboard scene). Suppressed for `.shakerFlatSurface` and
        // `.waiting` (UIKit didn't render an X for those), and gated
        // by the caller-supplied `isCloseHidden` flag on `.alert` /
        // `.confirm` (mirrors UIKit `isCloseButtonHidden`).
        .overlay(alignment: .topTrailing) {
            if !popup.hidesClose {
                Button {
                    HapticService.light()
                    onClose()
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
                .padding(.top, 8)
                .padding(.trailing, 8)
                .accessibilityLabel("Close")
            }
        }
        .barsysShadow(.glass)
    }

    /// UIKit alertPopUpBackgroundStyle (UIViewClass+GradientStyles.swift):
    ///   iOS 26+: addGlassEffect(cornerRadius: BarsysCornerRadius.medium=12)
    ///            → real UIGlassEffect(.regular) → use
    ///            `BarsysGlassPanelBackground` for parity with side
    ///            menu / edit panel / device popups.
    ///   Pre-26 : UIColor.white.withAlphaComponent(0.95), cornerRadius=12
    @ViewBuilder
    private var popupCardBackground: some View {
        if #available(iOS 26.0, *) {
            BarsysGlassPanelBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwiftUI.Color.white.opacity(0.95))
        }
    }

    // MARK: - Subviews

    /// Title + optional subtitle block with UIKit-parity insets.
    ///
    /// 1:1 with UIKit `AlertPopUpHorizontalStackController` storyboard
    /// `2DB-u8-FOR` stack (AlertPopUp.storyboard L179-195):
    ///   • Stack frame (10, 14, 209, h) — **10pt extra L/R inset**
    ///     beyond the 24pt inner content margin, plus a 14pt top inset
    ///     from the inner content.
    ///   • Title label (K0W-M9-x4d): **system 16pt** regular,
    ///     `veryDarkGrayColor`, centered (L184).
    ///   • Subtitle label (qtN-z4-sZq): **system 12pt** regular,
    ///     `veryDarkGrayColor`, centered (L190).
    ///   • VStack spacing between title & subtitle = **16pt** (L179).
    private func popupTitleBlock(title: String, message: String?) -> some View {
        VStack(alignment: .center, spacing: 16) {
            titleLabel(title)
            if let message, !message.isEmpty {
                bodyLabel(message)
            }
        }
        // UIKit title stack 10pt extra horizontal inset (frame.x = 10
        // within a 229pt-wide inner content area → 209pt title width).
        // This makes the title NARROWER than the buttons (which are
        // flush with the inner content at 229pt), matching UIKit's
        // "button bigger than text" visual rhythm.
        .padding(.horizontal, 10)
        // UIKit title stack top = inner content top + 14pt. Outer
        // view adds 24pt top for the inner content inset; we add 14pt
        // here for the extra title stack inset.
        .padding(.top, 0) // title stack top handled implicitly (outer VStack is flush)
    }

    private func titleLabel(_ text: String) -> some View {
        // 1:1 UIKit `K0W-M9-x4d` — system 16pt (changed from semibold:
        // UIKit storyboard uses regular weight at 16pt, not semibold).
        // veryDarkGrayColor, centered.
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(Color("veryDarkGrayColor"))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func bodyLabel(_ text: String) -> some View {
        // 1:1 UIKit `qtN-z4-sZq` — system 12pt, veryDarkGrayColor,
        // centered. Was 14pt/charcoalGrayColor — both incorrect.
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color("veryDarkGrayColor"))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { HapticService.light(); action() } label: {
            Text(title).brandCapsule(height: 45, cornerRadius: 8)
        }
        .buttonStyle(BounceButtonStyle())
    }

    // MARK: - Alert-specific buttons (pill-shaped, 12pt font)
    // Matches UIKit AlertPopUpHorizontalStackController storyboard:
    //   - Button dimensions: ~109×45, pill corners (height/2 = 20pt)
    //   - Font: System 12pt
    //   - Title color: black

    /// RIGHT button in UIKit (cancelButton) — filled with custom color.
    /// Used for "Yes please!" with segmentSelectionColor fill.
    ///
    /// Shape decision (critical parity fix):
    ///   iOS 26+ → CAPSULE. UIKit `alertPopUpButtonBackgroundStyle`
    ///             at L32-35 calls `applyCapsuleGradientStyle()` and
    ///             `addGlassEffect(cornerRadius: height/2)` — BOTH
    ///             override the storyboard `roundCorners = 8` with
    ///             `bounds.height / 2`. Buttons are 45pt tall, so the
    ///             runtime corner is 22.5pt — a proper capsule.
    ///   Pre-26  → 8pt rounded rect (UIKit `btnCancel.roundCorners =
    ///             BarsysCornerRadius.small` sticks).
    private func alertPrimaryFilledButton(_ title: String, fillColor: String, action: @escaping () -> Void) -> some View {
        Button { HapticService.light(); action() } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(SwiftUI.Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(alertFilledButtonBackground(fillColor))
                .clipShape(alertButtonShape)
        }
        .buttonStyle(BounceButtonStyle())
    }

    /// Shape for alert buttons — iOS 26+ capsule, pre-26 8pt rect.
    /// See UIKit `alertPopUpButtonBackgroundStyle` + `applyCapsuleGradientStyle`
    /// (UIViewClass+GradientStyles.swift L24-90).
    private var alertButtonShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Filled button background — 1:1 port of UIKit
    /// `alertPopUpButtonBackgroundStyle(fillColor:)`
    /// (UIViewClass+GradientStyles.swift L24-48).
    ///
    /// **What UIKit actually renders** (after tracing every line):
    ///   1. `applyCapsuleGradientStyle()` inserts a CAGradientLayer with
    ///      vertical `brandGradientTop → brandGradientBottom`
    ///      (startPoint 0.5, 0.0 → endPoint 0.5, 1.0), capsule corner.
    ///   2. `self.backgroundColor = self.backgroundColor?.withAlphaComponent(0.2)`
    ///      — sets the view's own backgroundColor to fillColor @ 20 % alpha.
    ///   3. `addGlassEffect(cornerRadius: h/2, effect: "clear")` adds a
    ///      `UIGlassEffect(style: .clear)` UIVisualEffectView **and ends
    ///      with `backgroundColor = .clear`** (UIViewClass+GlassEffects.swift
    ///      L66-67), which **wipes step 2 entirely**. The `.clear` glass
    ///      style is essentially transparent — it adds a faint sheen but
    ///      lets the gradient show through unchanged.
    ///
    /// So step 2 is dead code, and the `UIGlassEffect(.clear)` in step 3
    /// is so transparent that the visible result is just the brand
    /// gradient capsule. Mirrors what `PrimaryOrangeButton.makeOrangeStyle()`
    /// renders for the Recipe Craft button — see
    /// [RecipesScreens.swift `primaryOrangeButtonBackground`] which is
    /// the same UIKit primitive (`applyCapsuleGradientStyle()`) and
    /// renders as a pure gradient capsule with no material overlay.
    ///
    /// Two prior SwiftUI ports got this wrong:
    ///   • First version stacked an `.ultraThinMaterial` Capsule on top
    ///     for "glass". `.ultraThinMaterial` is much more opaque than
    ///     `UIGlassEffect(.clear)`; it blurred the two-stop gradient
    ///     into a single milky tone, hiding the peach → tan transition.
    ///   • Earlier version also stacked the fillColor at 20 % alpha on
    ///     top — UIKit clears that immediately, so the SwiftUI version
    ///     was over-tinting the top of the button.
    ///
    /// Fix: just render the brand gradient capsule, matching what the
    /// Recipe Craft button does. Dark mode hard-codes the light RGB
    /// values like `primaryOrangeButtonBackground` does, so the asset's
    /// dark variant (#3A2E26 → #4A3628) doesn't render as an invisible
    /// near-black pill on the popup card.
    ///
    /// Pre-26: solid fillColor fill (UIKit L45:
    /// `layer.backgroundColor = fillColor.withAlphaComponent(1.0).cgColor`).
    @ViewBuilder
    private func alertFilledButtonBackground(_ colorName: String) -> some View {
        if #available(iOS 26.0, *) {
            // Vertical brand gradient capsule (matches UIKit
            // `applyCapsuleGradientStyle`). Hard-coded light-mode RGB
            // mirrors `primaryOrangeButtonBackground` on the Recipe
            // Craft button — UIKit's `makeOrangeStyle()` keeps brand
            // orange in both appearances; the dynamic asset's dark
            // variant would otherwise render as an invisible
            // near-black pill against the popup-card glass.
            //
            // No `UIVisualEffectView`-backed overlay — wrapping a
            // `UIVisualEffectView` in `.background(...)` blocked the
            // adjacent secondary button's tap gesture even with
            // `isUserInteractionEnabled = false`. A pure SwiftUI
            // Capsule fill never participates in hit testing, so the
            // popup buttons stay reliably tappable.
            Capsule(style: .continuous).fill(
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SwiftUI.Color(colorName))
        }
    }

    /// RIGHT button when no custom fill color — rare path; same
    /// styling as the LEFT secondary button (UIKit treats both via
    /// `alertPopUpButtonBackgroundStyle(fillColor: nil)`).
    private func alertPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        alertBorderedButton(title, action: action)
    }

    /// LEFT button (continueButton in UIKit) — border only, no fill.
    ///
    /// 1:1 port of UIKit `applyCancelCapsuleGradientBorderStyle()`
    /// (UIViewClass+GradientStyles.swift L92-110) on iOS 26+ and the
    /// `makeBorder(1, craftButtonBorderColor)` fallback pre-26.
    ///
    /// Shape: CAPSULE on iOS 26+ (UIKit `alertPopUpButtonBackgroundStyle`
    /// L38-40 sets `roundCorners = height/2` when fillColor is nil);
    /// 8pt rounded rect pre-26.
    private func alertSecondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        alertBorderedButton(title, action: action)
    }

    private func alertBorderedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button { HapticService.light(); action() } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(SwiftUI.Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(alertSecondaryButtonBackground)
                .overlay(alertSecondaryButtonBorder)
                .clipShape(alertButtonShape)
        }
        .buttonStyle(BounceButtonStyle())
    }

    /// Secondary/default button background.
    ///
    /// iOS 26 — UIKit `alertPopUpButtonBackgroundStyle(fillColor: nil)`
    /// at L37-40 calls `addGlassEffect(effect: "clear")` then
    /// `backgroundColor = .clear`. Effectively: CLEAR glass (no tint).
    /// We layer a subtle `cancelButtonGray @ 0.15` overlay that
    /// `applyCancelCapsuleGradientBorderStyle()` also applies via
    /// `addGlassEffect(tintColor: cancelButtonGray)` (L109) — without
    /// it the capsule reads too transparent on a pale backdrop.
    ///
    /// Pre-26 — solid white (UIKit fallback fill before the `makeBorder`
    /// stroke is applied).
    @ViewBuilder
    private var alertSecondaryButtonBackground: some View {
        if #available(iOS 26.0, *) {
            // Force the light-mode background in BOTH color schemes so
            // the Rating / confirm popup's LEFT capsule button ("No, stay
            // in the app", "No", etc.) renders identically in dark mode
            // as it does in light mode. The previous dark rendering used
            // an adaptive `.ultraThinMaterial` that turned the pill into
            // a muddy dark shape against the already-dark popup card,
            // making the text barely legible. We keep the same visual
            // family by compositing white tints explicitly rather than
            // relying on trait-resolved materials.
            ZStack {
                Capsule(style: .continuous)
                    .fill(SwiftUI.Color.white.opacity(0.85))
                Capsule(style: .continuous)
                    .fill(Theme.Color.cancelButtonGray.opacity(0.15))
            }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SwiftUI.Color.white)
        }
    }

    /// Secondary button border — on iOS 26+ UIKit uses the 6-stop
    /// `white@0.95 ↔ cancelBorderGray@0.9` gradient stroke from
    /// `applyCancelCapsuleGradientBorderStyle` (UIViewClass+GradientStyles.swift
    /// L92-110). Pre-26 falls back to a flat `craftButtonBorderColor`
    /// 1pt stroke (`makeBorder`).
    @ViewBuilder
    private var alertSecondaryButtonBorder: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.95),                      location: 0.00),
                            .init(color: Theme.Color.cancelBorderGray.opacity(0.9), location: 0.20),
                            .init(color: .white.opacity(0.95),                      location: 0.40),
                            .init(color: .white.opacity(0.95),                      location: 0.60),
                            .init(color: Theme.Color.cancelBorderGray.opacity(0.9), location: 0.80),
                            .init(color: .white.opacity(0.95),                      location: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SwiftUI.Color("craftButtonBorderColor"), lineWidth: 1)
        }
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
                .foregroundStyle(Theme.Color.softWhiteText)
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
