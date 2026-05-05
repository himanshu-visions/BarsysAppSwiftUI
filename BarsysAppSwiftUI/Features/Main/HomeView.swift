//
//  HomeView.swift
//  BarsysAppSwiftUI
//
//  Direct 1:1 port of:
//   - BarsysApp/Controllers/ConnectDevices/ChooseOptionsDashboardViewController.swift (254 lines)
//   - BarsysApp/Controllers/ConnectDevices/ChooseOptionsDashboardViewController+Accessibility.swift
//   - BarsysApp/StoryBoards/Base.lproj/Device.storyboard scene "9lH-Lv-Iqd"
//   - BarsysApp/Helpers/CustomViews/UIViewClass.swift::applyCustomShadow
//   - BarsysApp/Helpers/Constants/Constants+UI.swift::BarsysCornerRadius
//
//  ======================= STORYBOARD AUDIT =======================
//
//  Screen size: 393 × 852 (iPhone 15 Pro), backgroundColor = primaryBackgroundColor
//
//  ┌─────────────────────── top bar (dbg-mw-KqI) ────────────────────────┐
//  │  top:0 safeArea, leading:0, trailing:0, height:44                    │
//  │                                                                      │
//  │  [exploreBtn]  Hi {name}                     [♥ fav]  [👤 profile]  │
//  │   18×22           17pt 2 lines                21×24      24×25       │
//  │   leading:24      leading:16 from exploreBtn  trailing stack:24      │
//  │                                                                      │
//  └──────────────────────────────────────────────────────────────────────┘
//  ↓ 24pt gap
//  "Welcome to Barsys AI,"     system 12pt darkGrayColor   leading/trailing:24
//  ↓ 4pt gap
//  "Tap on Barbot to chat…"    system 12pt grayBorderColor leading/trailing:24
//                               numberOfLines:0 (wraps to ~2 lines)
//  ↓ 16pt gap
//  ┌─── main card outer (ksd-U8-pOU) leading:19, trailing:19 ──────────────┐
//  │   rounded corners 12, applyCustomShadow(opacity 0.43, y 4, radius 9)  │
//  │  ┌── inner (lXl-Ba-h8J) inset 5pt on all sides, rounded corners 12 ──┐│
//  │  │  ┌── header row (kv0-qO-0NK) height:62, white background ────────┐││
//  │  │  │                                                               │││
//  │  │  │   [bleIcon] Connect Device                                    │││
//  │  │  │     13x17  system light 20pt appBlackColor                    │││
//  │  │  │                                                               │││
//  │  │  │   button is 215x30, leading:10 from header, top:16, bot:16    │││
//  │  │  │   contentHorizontalAlignment = leading                        │││
//  │  │  │   titleEdgeInsets.minX = 10 (10pt gap between icon and title) │││
//  │  │  └───────────────────────────────────────────────────────────────┘││
//  │  │  ┌── hero (xaz-fM-zZf) ──────────────────────────────────────────┐││
//  │  │  │                                                               │││
//  │  │  │              chooseOptionsBarsysImage                         │││
//  │  │  │              (asset: 327×325 @1x)                             │││
//  │  │  │              scaleAspectFit inside 1:1 square frame           │││
//  │  │  │              (width = height constraint)                      │││
//  │  │  │                                                               │││
//  │  │  └───────────────────────────────────────────────────────────────┘││
//  │  └────────────────────────────────────────────────────────────────────┘│
//  └────────────────────────────────────────────────────────────────────────┘
//  ↓ flexible space
//  ┌── Speakeasy card (7Ge-fd-usS) leading/trailing:24, height:60 ───────┐
//  │   rounded corners 8, white background, NO SHADOW                    │
//  │                                                                     │
//  │  Barsys Speakeasy                                    Check in       │
//  │  (system 20pt appBlackColor)                  (Helvetica-Oblique    │
//  │  Connect with Barsys at an IRL event.          14pt underlined)     │
//  │  (system 10pt appBlackColor)                                        │
//  │                                                                     │
//  │  stackView.leading:12, labels.centerY ; checkIn.trailing:12         │
//  └─────────────────────────────────────────────────────────────────────┘
//  ↓ bottom constraint: 30 (iOS 26+) / 45 (iOS <26) from safeArea bottom
//
//  ======================= ASSET DIMENSIONS =======================
//
//  chooseOptionsBarsysImage  : 327 × 325  (nearly square, NOT a perfect 1:1)
//  bleIcon                   :  13 ×  17
//  imgExploreSmall           :  18 ×  21
//  favoriteIcon              :  22 ×  19
//  profileIcon               :  24 ×  25
//
//  ======================= SHADOW PARAMS (applyCustomShadow) =======
//
//  cornerRadius : 12 (BarsysCornerRadius.medium)
//  size         :  4.0   (shadowOffset.height)
//  opacity      :  0.43
//  shadowRadius :  9.0
//  color        : .black
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var ble: BLEService
    @EnvironmentObject private var userStore: UserProfileStore

    // Ports `isReconnectingStarted` local flag from UIKit.
    @State private var isReconnectingStarted: Bool = false

    /// Preferred rendering of the signed-in user's first name. Reads from the
    /// observable `UserProfileStore` first so that login → home re-renders
    /// instantly; falls back to the in-memory auth profile, then a friendly
    /// default so the greeting never shows an empty string.
    private var displayName: String {
        if !userStore.name.isEmpty { return userStore.name }
        if !auth.profile.firstName.isEmpty { return auth.profile.firstName }
        return "there"
    }

    var body: some View {
        // 1:1 structure with `DevicePairedView`
        // (ControlCenterScreens.swift:637-1008) — the Explore tab root the
        // user flagged as the visual reference. That screen uses
        // `ScrollView { VStack { … } }` + `.background(primaryBackgroundColor.ignoresSafeArea())`
        // + `.navigationBarBackButtonHidden(true)` + `.chooseOptionsStyleNavBar()`.
        //
        // The crucial bit is the OUTER `ScrollView`. iOS 26's system
        // toolbar Liquid Glass auto-wrap relies on having scrollable
        // content underneath the nav bar to render the silvery-frosted
        // pill the user sees on Explore / Device-Paired. With a static
        // `VStack` (no ScrollView), the bar has no material to blur
        // through, so iOS 26 falls back to a thinner, more transparent
        // glass — which is exactly the "black transparent" right-pill
        // the user reported.
        //
        // The screen previously hung the speakeasy card off a `Spacer()`
        // so it sat at the bottom of the viewport. Inside a ScrollView
        // a `Spacer()` collapses (the scroll view has unlimited
        // vertical space), so the bottom card moves to a
        // `safeAreaInset(edge: .bottom)` instead — same visual outcome
        // (pinned to the bottom safe area, above the tab bar) AND the
        // ScrollView still gets the iOS 26 nav-bar treatment.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ─── "Hi {name}" greeting moved to the top-bar (`.toolbar`)
                // — sits as a plain-text `ToolbarItem` immediately
                // after the Explore button (10pt leading padding) so it
                // mirrors UIKit `ChooseOptionsDashboardViewController`'s
                // top-bar HStack `dbg-mw-KqI` where `lblHiUserName`
                // (`lUD-VJ-a4r`) sits beside `imgExploreSmall`
                // (`O3O-bl-vqo`). NO glass capsule wraps the text — only
                // the existing circular Explore button keeps its
                // auto-glass treatment.

                // ─── 2. "Welcome to Barsys AI," (Jlh-K8-Gez) ───
                // iPad bumps 12 → 18pt so the welcome greeting reads
                // at a comfortable scale on the wider canvas. iPhone
                // keeps storyboard 12pt bit-identically.
                Text("Welcome to Barsys AI,")
                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 12))
                    .foregroundStyle(Color("darkGrayColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .accessibilityLabel("Welcome message")

                // ─── 3. Description (Vky-cT-XzT) ───
                // Tinted with `darkGrayColor` to match the "Welcome to
                // Barsys AI," row directly above so the two-line intro
                // copy reads as a single visual block instead of the
                // previous two different greys (welcome = darkGrayColor,
                // description = grayBorderColor — visibly different
                // weights against the dark page in dark mode).
                //
                // iPad bumps the description 12 → 16pt so the body copy
                // reads next to the larger welcome line. iPhone keeps
                // storyboard 12pt bit-identically.
                Text("Tap on Barbot to chat about drinks, customize recipes, save favorites, or get recommendations.")
                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12))
                    .foregroundStyle(Color("darkGrayColor"))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                // ─── 4. Main card (ksd-U8-pOU → lXl-Ba-h8J → kv0-qO-0NK + xaz-fM-zZf) ───
                //
                // 16pt bottom inset on every device — matches UIKit
                // storyboard (no card-to-speakeasy gap there). iPad
                // breathing room is delivered by a 40pt TOP padding
                // on the Speakeasy card inside `safeAreaInset(.bottom)`
                // below, so iPhone layout stays bit-identical to the
                // storyboard (no padding hop introduced here).
                mainCard
                    .padding(.horizontal, 19)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // ─── 5. Speakeasy card (7Ge-fd-usS) ───
            //
            // Pinned to the bottom safe area instead of pushed down by a
            // Spacer in a VStack — see body comment above for why the
            // outer ScrollView is required.
            //
            // `bottomConstraintMain` — set by UIKit viewDidLoad
            // (L26-29) based on iOS version:
            //   • iOS 26+ → 30pt bottom inset (tighter because
            //     the custom tab bar is itself a glass pill)
            //   • iOS <26 → 45pt bottom inset
            speakeasyCard
                .padding(.horizontal, 24)
                .padding(.bottom, speakeasyCardBottomInset)
        }
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        // System toolbar — 1:1 with PairYourDevice
        // (DeviceScreens.swift:68-95). iOS 26 auto-wraps each item in
        // its native Liquid Glass capsule/circle, which is exactly the
        // chrome the user wants to match. Previously HomeView rendered
        // its own custom HStack top bar that couldn't pick up that
        // wrapping, which is why the right-nav pill looked duller than
        // PairYourDevice's.
        .navigationBarTitleDisplayMode(.inline)
        // 1:1 with DevicePairedView (ControlCenterScreens.swift:960) —
        // hides the auto-generated back button at the NavigationStack
        // root. Without this, iOS 26 reserves layout space for a
        // hidden back affordance and the toolbar bookkeeping renders
        // the right-pill auto-glass with a thinner, "black transparent"
        // material. Adding it makes the bar treat the toolbar layout
        // identically to DevicePairedView.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Explore button — bare `imgExploreSmall` icon, 18×22.
            // iOS 26 toolbar wraps this in a Liquid Glass circle
            // automatically (same treatment as PairYourDevice's back
            // button, DeviceScreens.swift:69-80).
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticService.light()
                    router.selectedTab = .explore
                } label: {
                    // iPad bumps the toolbar Explore icon 18×22 →
                    // 26×32 so it scales with the larger right-side
                    // pill. iPhone keeps storyboard 18×22 bit-identically.
                    Image("imgExploreSmall")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 26 : 18,
                               height: UIDevice.current.userInterfaceIdiom == .pad ? 32 : 22)
                        .foregroundStyle(Color("appBlackColor"))
                }
                .accessibilityLabel("Explore")
            }

            // 1:1 with UIKit `lblHiUserName` (`lUD-VJ-a4r`) — system
            // 17pt greeting hosted in the navigation title slot
            // (`.principal`) so iOS 26 renders it as a PLAIN label
            // with NO Liquid Glass capsule. The principal slot spans
            // the space between the leading Explore button and the
            // trailing favourites/profile pill, so:
            //   • `.padding(.leading, 10)`  → 10pt gap after the
            //                                   Explore button
            //   • `.padding(.trailing, 10)` → 10pt gap before the
            //                                   right glass pill
            //   • `.frame(maxWidth: .infinity, alignment: .leading)`
            //     stretches the Text into the full principal width so
            //     wrapping has room to breathe (without it, the slot
            //     hugs the text's intrinsic width and the trailing
            //     padding has nothing to push against).
            //   • `.lineLimit(1...3)` lets the label grow up to 3
            //     lines for long names (e.g. "Hi Ankit Singh Rajpoot
            //     Of Some Royal House"), wrapping at word boundaries.
            //   • `.fixedSize(horizontal: false, vertical: true)`
            //     allows the height to expand at runtime based on how
            //     many lines the text actually needs (1 line for
            //     short names, 2-3 for long).
            ToolbarItem(placement: .principal) {
                Text("Hi \(displayName)")
                    .font(.system(size: 17))
                    .foregroundStyle(Color("appBlackColor"))
                    .lineLimit(1...3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .padding(.trailing, 10)
                    .accessibilityAddTraits(.isHeader)
            }

            // Shared 100×48 glass pill — identical call to
            // PairDeviceView (DeviceScreens.swift:85-94) so iOS 26
            // toolbar auto-glass renders the same pill on both screens.
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
        // Flat `primaryBackgroundColor` nav bar — same modifier
        // PairDeviceView uses (DeviceScreens.swift:98) so the glass
        // pill composites on the identical canvas.
        .chooseOptionsStyleNavBar()
        .task {
            // viewWillAppear → getProfileHere() refreshes "Hi {name}".
            await refreshProfile()
            // 1:1 with UIKit `DevicePairedViewController` Home_Screen_Viewed
            // event — Braze receives the same `screenName` / `user_id` /
            // `date` triple so the event is attributable to a known user
            // and "Home" segment in dashboards.
            env.analytics.track(
                TrackEventName.homeScreenViewed.rawValue,
                properties: [
                    "screenName": "Home",
                    "user_id": UserDefaultsClass.getUserId() ?? "",
                    "date": Date()
                ]
            )
        }
        .onAppear {
            // viewDidLoad:
            //   AppStateManager.shared.setSpeakEasyCaseState(false)
            //   reconnectNowIfPreviouslyConnected()
            AppStateManager.shared.setSpeakEasyCaseState(false)
            reconnectIfPreviouslyConnected()
            // 1:1 with UIKit `ChooseOptionsDashboardViewController`
            // L30: `AnalyticsConsentManager.requestConsentIfNeeded(from:
            // self)` — surfaces the analytics + ATT consent prompt the
            // first time the user lands on Home after a successful
            // login. The consent decision is sticky in UserDefaults
            // (`hasPromptBeenShown`) so this is a no-op on every
            // subsequent appearance. Critical for Braze: without this
            // prompt being shown, `isConsentGranted` returns false
            // forever and every `BrazeService.track` / `loginUser` /
            // `updateProfile` early-returns at the consent guard.
            AnalyticsConsentManager.requestConsentIfNeeded(alertQueue: env.alerts)
        }
        .dynamicTypeSize(.small ... .accessibility2)
    }

    // MARK: - Top bar
    //
    // HomeView no longer renders a custom top-bar HStack. The Explore
    // button + heart/profile pill now live in the system `.toolbar` on
    // the body (see above), which gives iOS 26 a chance to wrap each
    // item in its native Liquid Glass — matching PairYourDevice /
    // Explore / MyBar / Mixlists / Recipes pixel-for-pixel. The
    // "Hi {name}" greeting moved into the content `VStack` as the
    // first row, same pattern PairYourDevice uses for its
    // "Pair your device" title.

    /// 1:1 with UIKit `bottomConstraintMain` set in viewDidLoad:
    ///   • iOS 26+ → 30pt
    ///   • Pre-26  → 45pt
    private var speakeasyCardBottomInset: CGFloat {
        if #available(iOS 26.0, *) { return 30 } else { return 45 }
    }

    // MARK: - Main card (outer + inner 5pt inset + header + hero)
    //
    // 1:1 port of the Device.storyboard scene for
    // `ChooseOptionsDashboardViewController`:
    //
    //   `ksd-U8-pOU`  (the view the code confusingly calls `innerView`):
    //      • frame 355×417, `roundCorners: 12`, backgroundColor CLEAR
    //      • runtime: `innerView.applyCustomShadow(cornerRadius: 12,
    //                                              size: 4.0)` →
    //         shadowColor  = black
    //         shadowOpacity = 0.43
    //         shadowRadius  = 9.0
    //         shadowOffset  = (0, 4)
    //         masksToBounds = false  (so the shadow bleeds past the
    //                                  rounded bounds)
    //   `lXl-Ba-h8J`  (inner content view, 5pt inset on all four sides):
    //      • frame 345×407, `roundCorners: 12`, backgroundColor CLEAR
    //      • `layer.masksToBounds` = true (default from roundCorners
    //        setter) so the header + image are clipped to 12pt corners.
    //      • Children:
    //          – `kv0-qO-0NK`  header row 345×62, bg = `systemBackgroundColor`
    //                          (white), holds the "Connect Device" button.
    //          – `xaz-fM-zZf`  hero image 345×345, `chooseOptionsBarsysImage`,
    //                          `scaleAspectFit`.
    //   `935-Gm-qEG`  invisible full-card button (overlays everything)
    //                  → `connectDeviceAction:`.
    //
    // In UIKit, the 5pt gap between outer (355) and inner (345) shows
    // the parent view's `primaryBackgroundColor` through the clear
    // outer view — giving the card a soft 5pt "ring" of warm cream
    // before the shadow spills out. SwiftUI replicates that by filling
    // the outer rounded rect with `primaryBackgroundColor` (the same
    // colour the parent ScrollView uses), so the shadow has a shape
    // to cast from AND the 5pt ring appears identical to UIKit.
    private var mainCard: some View {
        // iPhone: 1:1 hero image — bit-identical UIKit storyboard
        // parity (`xaz-fM-zZf` has a hard `width:height = 1:1`).
        //
        // iPad: cap with a 1.30:1 wider-than-tall ratio so the image
        // bottom edge stops AT the top of the 40pt spacer mounted
        // above the Speakeasy card — no overlap, no scrolling. UIKit
        // achieves the same effect implicitly because the storyboard
        // image has `verticalHuggingPriority=251` and Auto Layout
        // compresses the 1:1 constraint when vertical space runs out;
        // SwiftUI has no automatic compression, so we encode the cap
        // explicitly here. The 1.30 ratio leaves the entire Home
        // content visible without scrolling on every iPad portrait
        // (Mini through Pro 13").
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad

        return Button(action: connectDeviceTapped) {
            VStack(spacing: 0) {
                // Header row — 62pt tall, white bg (systemBackgroundColor).
                headerRow

                if isIPad {
                    // iPad: hard aspect-ratio cap on the hero image so
                    // its bottom edge stops well above the Speakeasy
                    // region.
                    //
                    // Renders via `GeometryReader` + explicit
                    // `frame(width:height:)` + `.clipped()` because
                    // `.overlay(Image.aspectRatio(.fill))` was letting
                    // the image overflow PAST `.clipped()` on the
                    // outer `Color.clear` — the user reported the
                    // image bottom showing behind the Speakeasy card,
                    // which is the symptom of an unclipped overlay
                    // overflow. The GeometryReader hands the Image a
                    // CONCRETE frame that `.clipped()` can bind to,
                    // guaranteeing no overflow on any iPad size.
                    GeometryReader { geo in
                        Image("chooseOptionsBarsysImage")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width,
                                   height: geo.size.height)
                            .clipped()
                    }
                    .aspectRatio(1.15, contentMode: .fit)
                    .accessibilityHidden(true)
                } else {
                    // iPhone: ORIGINAL storyboard 1:1, scaleAspectFit —
                    // byte-for-byte identical to the UIKit `xaz-fM-zZf`
                    // layout (no `.clipped()`, no extra modifiers).
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image("chooseOptionsBarsysImage")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        // Inner view (`lXl-Ba-h8J`) — white fill under the header +
        // image so the 12-corner mask shows crisp rounded corners.
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // 5pt gap on all four sides (inner inset from outer).
        .padding(0)
        // Outer view (`ksd-U8-pOU`) — in UIKit its background is CLEAR
        // so the parent's `primaryBackgroundColor` shows through the
        // 5pt ring. We fill the outer shape with the same
        // `primaryBackgroundColor` to reproduce that ring exactly and
        // give SwiftUI a concrete shape to cast the shadow from.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("primaryBackgroundColor"))
        )
        // applyCustomShadow(cornerRadius: 12, size: 4.0, opacity: 0.43,
        //                   shadowRadius: 9.0, shadowColor: .black)
        // SwiftUI projects this shadow from the outer rounded rect
        // above — matching UIKit's `masksToBounds = false` spill.
        .shadow(color: .black.opacity(0.43), radius: 9, x: 0, y: 4)
    }

    /// Header row `kv0-qO-0NK` — 62pt tall, white background, Connect Device
    /// button positioned at leading:10, top:16.
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Connect Device button — exactly 215×30, left-aligned inside row.
            //   leading:10 from header row leading, top:16, bottom:16
            //   contentHorizontalAlignment = leading
            //   titleEdgeInsets.minX = 10 (10pt between image and title)
            Button(action: connectDeviceTapped) {
                HStack(spacing: 10) {
                    // UIKit storyboard `2bn-ZB-O7K` uses the default
                    // `buttonType="system"` which auto-tints its image
                    // to the button's `titleColor` (`appBlackColor`).
                    // SwiftUI's `Image` does NOT auto-tint, so we apply
                    // `.template` + `.foregroundStyle(appBlackColor)`
                    // explicitly to reproduce the exact gray bluetooth
                    // glyph seen in the UIKit screenshot.
                    Image("bleIcon")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 17) // actual 1x asset size
                        .foregroundStyle(Color("appBlackColor"))
                    Text("Connect Device")
                        // iPad bumps 20 → 26pt so the "Connect Device"
                        // header reads next to the larger welcome
                        // copy. iPhone keeps storyboard 20pt
                        // bit-identically.
                        .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 26 : 20, weight: .light))
                        .foregroundStyle(Color("appBlackColor"))
                }
                .frame(width: 215, height: 30, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect Device")

            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `Theme.Color.surface` is an adaptive asset — light variant
        // is pure white sRGB(1, 1, 1), bit-identical to the previous
        // hard-coded `Color.white`, so light mode renders the EXACT
        // same pixels. Dark mode picks up the elevated dark surface
        // (#2C2C2E) from the asset catalog so the Connect Device
        // header row stops being a stark white slab in dark mode.
        .background(Theme.Color.surface)
        // The entire card is also tappable via `connectDeviceTapped` — in the
        // storyboard this is an invisible overlay button (935-Gm-qEG) that
        // covers the whole card. The SwiftUI equivalent is the Button wrapping
        // the hero image in the mainCard VStack above.
    }

    // MARK: - Speakeasy card

    private var speakeasyCard: some View {
        // Storyboard `7Ge-fd-usS`:
        //   height: 60, rounded corners 8, white background, NO shadow
        //   Title stack `k4X-bj-kX4` leading:12, centerY
        //     • "Barsys Speakeasy"             system 20pt appBlackColor
        //     • "Connect with Barsys at an IRL event."  system 10pt appBlackColor
        //   "Check in" label `uh5-pU-suK` trailing:12, centerY, Helvetica-Oblique 14pt underlined
        //   Invisible button `LXl-Zo-qhn` covering the whole card → detectQrAction
        //
        // iPad-only sizing knobs. iPhone keeps storyboard 20/10/14pt
        // bit-identically.
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        return Button(action: speakeasyTapped) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Barsys Speakeasy")
                        .font(.system(size: isIPad ? 26 : 20))
                        .foregroundStyle(Color("appBlackColor"))
                    Text("Connect with Barsys at an IRL event.")
                        .font(.system(size: isIPad ? 14 : 10))
                        .foregroundStyle(Color("appBlackColor"))
                }
                .padding(.leading, 12)

                Spacer()

                Text("Check in")
                    .font(.custom("Helvetica-Oblique", size: isIPad ? 18 : 14))
                    .underline()
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.trailing, 12)
            }
            .frame(height: isIPad ? 78 : 60)
            .frame(maxWidth: .infinity)
            // `Theme.Color.surface` is an adaptive asset — light
            // variant is pure white sRGB(1, 1, 1), bit-identical to
            // the previous hard-coded `Color.white`, so light mode
            // renders the EXACT same pixels. Dark mode picks up the
            // elevated dark surface (#2C2C2E) from the asset catalog
            // so the Speakeasy card adapts naturally on dark
            // backgrounds.
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // No shadow — applyCustomShadow is NOT called on this card in the
            // UIKit version.
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions (1:1 with UIKit IBActions)

    /// Ports `connectDeviceAction(_:)` — pushes the PairYourDevice flow.
    private func connectDeviceTapped() {
        HapticService.light()
        router.push(.pairDevice)
    }

    /// Ports `detectQrAction(_:)` — opens the QR scanner.
    private func speakeasyTapped() {
        HapticService.light()
        router.push(.qrReader)
    }

    // MARK: - Data loading

    /// Ports `getProfileHere()` — re-fetches the profile so the greeting is
    /// always up-to-date.
    @MainActor
    private func refreshProfile() async {
        do {
            let profile = try await env.api.fetchProfile()
            auth.applySignedInProfile(profile)
            if !profile.firstName.isEmpty {
                UserDefaultsClass.storeName(profile.firstName)
            }
        } catch {
            // Silent — view already shows whatever UserDefaults held last.
        }
    }

    /// Ports `reconnectNowIfPreviouslyConnected()` guard chain (lines 105-179):
    ///   * skip if AppStateManager.isSpeakEasyCase
    ///   * skip if no phone in UserDefaults
    ///   * skip if manually disconnected
    ///   * skip if Bluetooth state is off/unknown (simulated here)
    ///   * skip if there's no saved last-connected device name
    ///   * otherwise: reconnectionState = .attempting + scanForPeripherals
    ///   * 10-second timeout guard → fall through to handlingDeepLinks
    private func reconnectIfPreviouslyConnected() {
        guard !isReconnectingStarted else { return }
        guard !AppStateManager.shared.isSpeakEasyCase else { return }
        guard let phone = UserDefaultsClass.getPhone(), !phone.isEmpty else { return }
        guard ble.disconnectedState != .manuallyDisconnected else { return }
        guard let last = UserDefaultsClass.getLastConnectedDevice(), !last.isEmpty else {
            ble.reconnectionState = .idle
            ble.disconnectedState = .notManuallyDisconnected
            return
        }
        isReconnectingStarted = true
        ble.attemptReconnect(toDeviceNamed: last)
        // UIKit 10-second guard — fires handlingDeepLinks after timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            isReconnectingStarted = false
        }
    }
}

// MARK: - GlassCircleButton
//
// Individual circular glass-effect button for the favorite + profile icons
// in the top bar. Mirrors the UIKit iOS 26+ treatment where each button
// gets `addGlassEffectToUIButton(isBorderEnabled:false, cornerRadius: height/2,
// alpha:1, effect:"regular")` — a regular-blur circular glass capsule.
//
// SwiftUI equivalent uses `.regularMaterial` (iOS 15+) so the effect renders
// on all supported deployment targets, not just iOS 26+.

struct GlassCircleButton: View {
    let imageName: String
    let imageSize: CGSize
    let accessibilityLabel: String
    let action: () -> Void

    /// 44pt is the minimum iOS tap-target and matches the visual size of the
    /// UIKit glass button after `addGlassEffectToUIButton(cornerRadius: h/2)`.
    private let buttonSize: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                // Frosted glass fill — `.regularMaterial` is the direct
                // SwiftUI equivalent of `UIBlurEffect(style: .regular)` +
                // `UIGlassEffect(style: .regular)` used by the UIKit
                // `addGlassEffectToUIButton`. Matches the side menu glass
                // exactly so both elements feel visually consistent.
                Circle()
                    .fill(.regularMaterial)

                // Soft highlight gradient stroke — emulates the iOS 26 glass
                // border with a brighter top-leading edge fading to a dimmer
                // bottom-trailing edge.
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                // Icon
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .foregroundStyle(Color("appBlackColor"))
            }
            .frame(width: buttonSize, height: buttonSize)
            // Matches UIKit `addGlassEffect()` (UIViewClass+GlassEffects.swift
            // lines 137-140): shadowColor=black@0.20, shadowOpacity=0.30,
            // shadowOffset=(0,10), shadowRadius=25. Effective on-screen
            // intensity is ~0.18 alpha; offset/radius lifted accordingly so
            // the glass capsule reads as a depth element on every screen.
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - NavigationRightGlassButtons
//
// Shared "top-right nav" control — a 100×48 glass pill wrapping the
// heart + profile icons on iOS 26+, or a bare 61×24 icon row on older
// iOS. 1:1 port of UIKit's `navigationRightGlassView` (IBOutlet
// `Kri-Ka-NoE` etc.) that appears on ChooseOptions, DevicePaired
// (Explore), MyBar, Mixlist listing, Recipes listing, StationsMenu,
// StationCleaning, MyDrinks, Favorites, RecipePage, MixlistDetail —
// every top-level screen with a nav bar.
//
// The iOS version branching matches `viewDidLoad` across those UIKit
// controllers:
//   ```
//   if #available(iOS 26.0, *) {
//       btnProfileIconRightConstraint.constant = 40.0  // inset further
//       navigationRightGlassView.addGlassEffect(
//           isBorderEnabled: true,
//           cornerRadius: navigationRightGlassView.frame.height / 2,
//           effect: "clear"
//       )
//   }
//   ```
//
// Previously each call site used TWO `GlassCircleButton`s (44pt circles
// with individual glass effects on every iOS version). That didn't
// match UIKit on either path — UIKit wraps the two buttons in ONE
// container, with the pill only visible on iOS 26+.
struct NavigationRightGlassButtons: View {
    /// Reactive theme awareness — used to conditionally tint the
    /// leading heart + trailing profile glyphs in DARK MODE ONLY.
    ///
    /// In light mode, the raw PNG pixels are preserved verbatim (no
    /// `.renderingMode(.template)`, no `.foregroundStyle`) so light
    /// mode stays pixel-identical to the UIKit design.
    ///
    /// In dark mode, the icons get re-tinted with the adaptive
    /// `appBlackColor` asset (which resolves to a near-white
    /// `#E5E5EA` in dark mode), so the right-side glyphs read with
    /// the SAME contrast the left-hand `NavigationLeadingGlassButton`
    /// already has — dark heart / person icons were rendering washed
    /// out against the bright `.ultraThinMaterial` pill + dark page
    /// canvas, making them visibly inconsistent with the left button.
    @Environment(\.colorScheme) private var colorScheme

    /// Asset name for the leading icon. Defaults to `favoriteIcon`
    /// (heart) for tab-level screens; RecipeDetail / MixlistDetail
    /// override with a recipe-specific favorited/unfavorited glyph.
    let leadingImageName: String
    /// System image name to use instead of `leadingImageName` when
    /// the caller wants SF Symbol styling (e.g. `heart.fill` on
    /// RecipeDetail). Mutually exclusive with `leadingImageName`.
    let leadingSystemImage: String?
    /// Accessibility label for the leading icon.
    let leadingAccessibilityLabel: String
    /// Callback for the leading icon. Named `onFavorites` because the
    /// vast majority of call sites are tab-level screens where the
    /// leading icon is the "Favorites" heart. RecipeDetail /
    /// MixlistDetail pass a custom `leadingImageName` / `leadingSystemImage`
    /// and a recipe-specific toggle closure through this same property.
    let onFavorites: () -> Void
    /// Callback for the profile / side-menu button.
    let onProfile: () -> Void

    /// Explicit initializer so Swift's memberwise-synthesised init
    /// doesn't trip over "Extra arguments at positions #1, #2 in call"
    /// at call sites that only pass `onFavorites:` + `onProfile:`
    /// (relying on default values for the three optional `leading*`
    /// parameters). With a `let` property the compiler can't synthesise
    /// an init with defaults, so we write one explicitly.
    /// When `true` the component renders both the leading (favorites)
    /// and profile buttons inside the 100×48 glass pill — 1:1 match
    /// with UIKit `navigationRightGlassView`. When `false` only the
    /// profile button renders, wrapped in a SINGLE 48×48 circular
    /// glass capsule that reuses the exact same material / gradient
    /// stroke / drop-shadow recipe so the look matches ChooseOptions
    /// on screens that don't need the favorites heart.
    ///
    /// Adds this flag so screens that previously tried to skip the
    /// heart (or presented a lone profile button with `IconButton` /
    /// bare `Image`) can now render a compact glass capsule that
    /// visually matches the ChooseOptions pill — the user explicitly
    /// asked for "similar UI in other places… in case single button
    /// is displayed or both".
    let showsLeading: Bool

    /// When `true`, the two-button pill draws its own
    /// `.ultraThinMaterial` + 1pt white stroke + shadow. Defaults to
    /// `false` because every call site in the app is now hosted inside
    /// a system `ToolbarItemGroup(.topBarTrailing)` (HomeView included,
    /// after the PairYourDevice-parity refactor), and iOS 26 auto-wraps
    /// toolbar items in the native Liquid Glass capsule — drawing an
    /// explicit background on top of that would double-stack the
    /// effect. Left as an escape hatch for any future non-toolbar host.
    let rendersOwnPillBackground: Bool

    init(leadingImageName: String = "favoriteIcon",
         leadingSystemImage: String? = nil,
         leadingAccessibilityLabel: String = "Favorites",
         showsLeading: Bool = true,
         rendersOwnPillBackground: Bool = false,
         onFavorites: @escaping () -> Void,
         onProfile: @escaping () -> Void) {
        self.leadingImageName = leadingImageName
        self.leadingSystemImage = leadingSystemImage
        self.leadingAccessibilityLabel = leadingAccessibilityLabel
        self.showsLeading = showsLeading
        self.rendersOwnPillBackground = rendersOwnPillBackground
        self.onFavorites = onFavorites
        self.onProfile = onProfile
    }

    /// Storyboard exact size: favoriteButton=21×24, profileButton=24×24.
    /// iPad bumps both icons so they read at a comfortable scale on the
    /// wider canvas. iPhone keeps storyboard sizes bit-identically.
    private static var leadingIconSize: CGSize {
        UIDevice.current.userInterfaceIdiom == .pad
            ? CGSize(width: 28, height: 32)
            : CGSize(width: 21, height: 24)
    }
    private static var profileIconSize: CGSize {
        UIDevice.current.userInterfaceIdiom == .pad
            ? CGSize(width: 32, height: 32)
            : CGSize(width: 24, height: 24)
    }

    // MARK: - Shared glass styling helpers
    //
    // UIKit uses `UIGlassEffect(style: .clear)` + 1pt border at
    // `UIColor.white.withAlphaComponent(0.25)`.
    // `.ultraThinMaterial` is the closest SwiftUI match to UIKit's
    // `.clear` glass style — much more transparent than
    // `.regularMaterial` which looked too opaque / frosted.

    @ViewBuilder
    private func glassStyledBackground(capsule: Bool) -> some View {
        let borderColor = Color.white.opacity(0.25)
        if capsule {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        } else {
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().stroke(borderColor, lineWidth: 1))
        }
    }

    var body: some View {
        Group {
            if showsLeading {
                // Two-button variant — EXACT UIKit parity.
                twoButtonGroup
            } else {
                // Single-button variant — compact glass circle reusing
                // the SAME material / border / shadow recipe.
                singleButtonGroup
            }
        }
        // Consistent trailing inset across EVERY call site.
        // UIKit storyboard: `Kri-Ka-NoE.trailing = safeArea.trailing − 24`.
        // SwiftUI `ToolbarItemGroup` defaults to ~16pt system inset, so
        // we add 8pt to reach the UIKit 24pt target. In custom nav bars
        // (HomeView topBar), the parent supplies `.padding(.leading, 24)`
        // but intentionally not `.padding(.trailing, 24)` — this
        // component owns the trailing inset so every screen renders
        // pixel-identical.
        .padding(.trailing, Self.trailingSafeAreaInset)
    }

    /// Two-button variant — storyboard-exact 100×48 glass pill on iOS 26,
    /// flat 61×24 icon stack on pre-26. 1:1 parity with UIKit
    /// `navigationRightGlassView`.
    @ViewBuilder
    private var twoButtonGroup: some View {
        if #available(iOS 26.0, *) {
            // Glass pill (iOS 26+): **exactly 100×48** to match
            // UIKit `navigationRightGlassView` frame (storyboard
            // `Kri-Ka-NoE`: width=71, height=48). Icons sit
            // inside with 7 horizontal padding + 20pt spacing for leading is 5 + traling is 15
            // — matches the UIKit runtime layout where the
            // stackView `KMo-iR-2JY` is 61pt wide inside the
            // 71pt pill.
            //
            // iPad bumps the pill 71×48 → 110×68 with proportionally
            // larger inner padding so the larger heart + profile
            // glyphs sit comfortably inside. The taller pill also
            // nudges the toolbar height upward (iOS inline toolbar
            // sizes to its tallest item) — extra breathing room
            // above the page divider line on iPad. iPhone keeps the
            // exact storyboard 71×48 pill bit-identically.
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            HStack(spacing: isIPad ? 11 : 7) {
                leadingButton
                profileButton
            }
            .padding(.leading, isIPad ? 22 : 15)
            .padding(.trailing, isIPad ? 7 : 5)
            .frame(width: isIPad ? 110 : 71, height: isIPad ? 68 : 48)
            // Render the explicit glass pill background on every call
            // site by default so HomeView's custom top bar and the
            // toolbar-hosted screens (Explore / PairDevice / MyBar /
            // Mixlists / Recipes / Favorites / MyProfile / ControlCenter)
            // all look identical. iOS 26 system-toolbar auto-glass
            // alone was rendering differently from HomeView's custom
            // top bar, which is what the user flagged.
            .background(
                Group {
                    if rendersOwnPillBackground {
                        glassStyledBackground(capsule: true)
                    }
                }
            )
            .shadow(
                color: rendersOwnPillBackground ? .black.opacity(0.14) : .clear,
                radius: rendersOwnPillBackground ? 10 : 0,
                x: 0,
                y: rendersOwnPillBackground ? 4 : 0
            )
        } else {
            // Pre-iOS 26: **exactly 61×24** — icons on the flat
            // primaryBackground. No glass effect, no border, no
            // shadow. Fixed frame prevents toolbar-layout compression
            // on narrow screens.
            //
            // iPad bumps the stack 61×24 → 84×34 to fit the larger
            // heart + profile glyphs. iPhone unchanged.
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            HStack(spacing: isIPad ? 22 : 16) {
                leadingButton
                profileButton
            }
            .frame(width: isIPad ? 84 : 61, height: isIPad ? 34 : 24)
        }
    }

    /// Single-button variant — profile only, rendered in a 48×48 glass
    /// circle that reuses the same material / stroke / shadow recipe
    /// as the pill so the visual family is consistent with the
    /// ChooseOptions two-button pill on adjacent screens.
    @ViewBuilder
    private var singleButtonGroup: some View {
        // iPad bumps the single-button glass frame 48 → 68pt (iOS 26+)
        // and the bare-icon frame 30 → 44pt (pre-26). The taller
        // single-button frame matches the bumped two-button pill so
        // the toolbar reads as a unified taller bar on iPad. iPhone
        // unchanged.
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if #available(iOS 26.0, *) {
            profileButton
                .frame(width: isIPad ? 68 : 48, height: isIPad ? 68 : 48)
                .background(glassStyledBackground(capsule: false))
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        } else {
            // Pre-iOS 26: plain 30×30 icon on the flat background —
            // matches the UIKit pre-26 profile button which has no
            // glass container, only the raw `profileIcon` asset.
            profileButton
                .frame(width: isIPad ? 44 : 30, height: isIPad ? 44 : 30)
        }
    }

    /// 1:1 with UIKit `Kri-Ka-NoE.trailing = safeArea.trailing − 24`.
    /// System toolbar default is ~16pt, so we add the 8pt delta here so
    /// the pill / icon-stack right-edge matches across tab-level screens
    /// (Explore, MyBar, Mixlists, Recipes, Favorites, MyProfile,
    /// Preferences, Devices, StationsMenu, StationCleaning) AND the
    /// ChooseOptions custom top bar.
    private static let trailingSafeAreaInset: CGFloat = 8

    private var leadingButton: some View {
        // iPad ONLY: expand the hit-target to the FULL HStack slot
        // (the half of the pill this button occupies) instead of
        // just the icon's intrinsic frame. The 28×32 icon inside a
        // 110×68 pill leaves most of the visible pill-half
        // un-tappable without a `contentShape(Rectangle())` over
        // the full slot.
        //
        // iPhone takes the bare-icon branch — NO `.frame`,
        // NO `.contentShape` — so the Button's tap target equals
        // the icon's intrinsic 21×24 frame, exactly the
        // storyboard-driven UIKit behaviour. The HStack inside the
        // 71×48 pill on iPhone has just enough room for the two
        // intrinsic-sized icons; the `.frame(maxWidth: .infinity)`
        // would have asked SwiftUI to redistribute that tight
        // budget and could have produced sub-pixel visual shifts.
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        return Button {
            HapticService.light()
            onFavorites()
        } label: {
            if isIPad {
                leadingIconContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            } else {
                leadingIconContent
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(leadingAccessibilityLabel)
    }

    @ViewBuilder
    private var leadingIconContent: some View {
        if let systemName = leadingSystemImage {
            Image(systemName: systemName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: Self.leadingIconSize.width,
                    height: Self.leadingIconSize.height
                )
                .foregroundStyle(Color("appBlackColor"))
        } else {
            // DARK MODE ONLY: re-tint via `appBlackColor` (near-white
            // `#E5E5EA` in dark mode) so the heart icon reads with
            // the same contrast as the left-hand
            // `NavigationLeadingGlassButton`. In light mode we keep
            // the bare PNG — no `renderingMode` / `foregroundStyle`
            // override — so the light-mode pixels stay bit-identical
            // to the existing UIKit-parity design.
            //
            // Safety: this runs for ALL call-sites, INCLUDING
            // RecipeDetail / MixlistDetail which pass a recipe-
            // specific favorited / unfavorited asset. Those assets
            // are monochrome glyphs (see
            // `favIconRecipe.imageset` / `favIconRecipeSelected.imageset`),
            // so template-tinting them in dark mode yields the same
            // filled-vs-outlined silhouette — only the colour flips
            // from dark-grey PNG to adaptive near-white. If a call
            // site ever needs a truly un-tintable colourful asset
            // (brand gradient etc.) it must switch to
            // `leadingSystemImage` OR render through a different
            // toolbar slot.
            if colorScheme == .dark {
                Image(leadingImageName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: Self.leadingIconSize.width,
                        height: Self.leadingIconSize.height
                    )
                    .foregroundStyle(Color("appBlackColor"))
            } else {
                Image(leadingImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: Self.leadingIconSize.width,
                        height: Self.leadingIconSize.height
                    )
            }
        }
    }

    private var profileButton: some View {
        // iPad ONLY: expand the hit-target to the FULL pill-half
        // (same rationale as `leadingButton`). iPhone takes the
        // bare-icon branch — no `.frame(maxWidth:)`, no
        // `.contentShape` — so the Button's tap target equals the
        // icon's intrinsic 24×24 frame, exactly the storyboard /
        // UIKit behaviour. iPhone visual layout is byte-identical.
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        return Button {
            HapticService.light()
            onProfile()
        } label: {
            // DARK MODE ONLY template-tint — same rationale as the
            // leading icon above. `profileIcon.imageset` is a
            // monochrome person glyph so `.renderingMode(.template)`
            // produces an identically-shaped icon at the tinted
            // colour. Light-mode branch returns the bare PNG so no
            // pixels shift.
            let iconView: AnyView = {
                if colorScheme == .dark {
                    return AnyView(
                        Image("profileIcon")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: Self.profileIconSize.width,
                                height: Self.profileIconSize.height
                            )
                            .foregroundStyle(Color("appBlackColor"))
                    )
                } else {
                    return AnyView(
                        Image("profileIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: Self.profileIconSize.width,
                                height: Self.profileIconSize.height
                            )
                    )
                }
            }()
            if isIPad {
                iconView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            } else {
                iconView
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Side menu")
    }
}

// MARK: - ChooseOptionsStyleNavBar modifier
//
// On HomeView (ChooseOptions) the top-right glass pill renders on the
// flat `primaryBackgroundColor` canvas because HomeView uses a CUSTOM
// top bar with the system nav bar hidden. Any screen that places
// `NavigationRightGlassButtons` inside `ToolbarItemGroup(placement:
// .topBarTrailing)` gets the pill composited on top of the system
// nav-bar blur / material — a visibly different surface, so the glass
// effect reads differently even though the pill component itself is
// byte-identical.
//
// This modifier forces the system nav bar background to the SAME
// `primaryBackgroundColor` that HomeView shows behind its custom top
// bar, so the pill's `.regularMaterial` blur renders against the
// identical canvas and the look-and-feel matches HomeView pixel-for-
// pixel across BarBot / MyBar / Recipe Detail / Mixlist Detail
// (and any other toolbar-hosted screen that adopts it).
//
// Usage: `.chooseOptionsStyleNavBar()` on the screen's root view.
struct ChooseOptionsStyleNavBar: ViewModifier {
    /// Read the current SwiftUI color scheme so the nav-bar
    /// `toolbarColorScheme` can match it. In light system mode the
    /// resolved value is `.light` — bit-identical to the previous
    /// hard-coded `.toolbarColorScheme(.light, …)` — so light mode
    /// renders the EXACT same nav bar pixels as before. In dark
    /// system mode the resolver returns `.dark`, which lets the
    /// system tint titles / SF Symbols against the dark
    /// `primaryBackgroundColor` background instead of forcing them
    /// to the (now invisible) light-mode tinting.
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        // Common nav-bar styling that lands on EVERY device — applied
        // to a local helper so iPhone and iPad share the exact same
        // base modifier chain. iPhone gets ONLY this base chain; iPad
        // gets the same chain PLUS a small top inset for extra
        // breathing room above the page hairline.
        if UIDevice.current.userInterfaceIdiom == .pad {
            baseStyling(content)
                // iPad-only: insert a small `primaryBackgroundColor`
                // strip above the content so the toolbar reads as a
                // taller bar with extra breathing room above the page
                // hairline. The inset is filled with the same nav-bar
                // background colour so it visually merges with the
                // bar (no visible seam). The `safeAreaInset` modifier
                // ITSELF is gated so iPhone never attaches it —
                // guaranteeing iPhone's safe-area / scroll behaviour
                // stays bit-identical to before this fix.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color("primaryBackgroundColor")
                        .frame(height: 12)
                }
        } else {
            baseStyling(content)
        }
    }

    /// Base nav-bar styling shared by both device idioms — extracted so
    /// the iPad branch can layer the `safeAreaInset` on top without
    /// risking any difference in the underlying chain.
    @ViewBuilder
    private func baseStyling(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26 Liquid Glass nav bars draw their own divider/edge
            // line at the bottom when `.toolbarBackground(.visible)`
            // forces an opaque colour fill on top of the native
            // Liquid Glass material. The hairline is what the user
            // reported as "underline on top bar". Letting the system
            // render the bar naturally (no forced opaque fill) lets
            // Liquid Glass handle the bottom edge cleanly without a
            // visible line — the `UINavigationBarAppearance` set in
            // `BarsysAppSwiftUIApp.init()` already pins the bar's
            // standard / scroll-edge / compact / compactScrollEdge
            // backgrounds to `primaryBackgroundColor` with
            // `shadowColor = .clear`, so the colour stays consistent
            // app-wide even without the SwiftUI `.toolbarBackground`
            // modifier.
            //
            // Also pin the scroll-edge effect to `.hard` so the
            // toolbar's Liquid-Glass capsules don't tint themselves
            // from scroll content sliding underneath (already used by
            // RecipeDetail / MixlistDetail individually — applying it
            // here promotes it to every screen that adopts
            // `chooseOptionsStyleNavBar()`).
            content
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light,
                                    for: .navigationBar)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
                // Pre-iOS 26 — keep the explicit opaque background so
                // the right-hand pill renders against a flat canvas
                // (matches HomeView's custom top bar exactly). Pre-26
                // doesn't have a glass divider, and the
                // `UINavigationBarAppearance.shadowColor = .clear` +
                // `shadowImage = UIImage()` from app init already
                // strips the legacy 1pt hairline.
                .toolbarBackground(
                    Color("primaryBackgroundColor"),
                    for: .navigationBar
                )
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light,
                                    for: .navigationBar)
                // SwiftUI's `.toolbarBackground(.visible)` builds its
                // own `UINavigationBarAppearance` per-view and applies
                // it directly to the live UINavigationBar instance —
                // overriding the global proxy values set in
                // `BarsysAppSwiftUIApp.init()`. The new appearance
                // SwiftUI generates uses the system default shadow,
                // which is the 1pt grey hairline the user reports
                // appearing at the bottom of the nav bar across every
                // top-level screen on iOS < 26. Reaching INTO the
                // navigation controller post-mount and re-clearing the
                // shadow on its four appearance slots is the only
                // reliable way to undo that override — no SwiftUI API
                // exposes the shadow-color knob for `.toolbarBackground`.
                // Bit-identical iOS 26+ branch is untouched.
                .background(NavigationBarShadowKiller().frame(width: 0, height: 0))
        }
    }
}

/// Walks up the responder chain to find the hosting
/// `UINavigationController` for the SwiftUI view it sits inside, then
/// clears the shadow (the 1pt grey hairline below the nav bar) on
/// every UINavigationBarAppearance slot:
///
///   • `standardAppearance`           — opaque-bar style
///   • `scrollEdgeAppearance`         — scrolled-to-top style
///   • `compactAppearance`            — landscape compact-height style
///   • `compactScrollEdgeAppearance`  — compact + scrolled-to-top
///
/// All four are needed because UIKit picks one based on size class /
/// scroll position, and any unset slot falls back to the system
/// default — which DOES draw the hairline. Setting them all to a
/// `shadowColor = .clear` + `shadowImage = UIImage()` appearance
/// guarantees no visible underline below the toolbar in any state.
///
/// This representable is intentionally a 0×0 invisible view: it just
/// piggy-backs on SwiftUI's mount lifecycle to run the UIKit hook.
private struct NavigationBarShadowKiller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Multiple staggered re-applications. SwiftUI's
        // `.toolbarBackground(.visible)` does NOT reliably apply its
        // generated UINavigationBarAppearance synchronously with our
        // UIViewRepresentable's `updateUIView` — sometimes SwiftUI's
        // own appearance write lands on a LATER runloop than our
        // first-tick clear-shadow override, so the override is
        // immediately stomped by SwiftUI and the 1pt hairline reappears.
        //
        // The 8-tier delay schedule below catches every observed
        // SwiftUI late-write timing:
        //   • 0ms     — common case: SwiftUI has already written
        //   • 50ms    — typical "next renderloop" write
        //   • 150ms   — slower push / pop animations
        //   • 400ms   — first-mount on cold app launch
        //   • 800ms   — appearance recompute on first scroll
        //   • 1.5s    — large-title collapse-to-standard transition
        //   • 3.0s    — covers tab switches that re-mount the host
        //   • 5.0s    — final belt-and-braces for slow devices
        // Each pass is idempotent (only writes when values differ
        // post-copy), so the extra runs are no-ops once the shadow
        // has actually been cleared. The total CPU cost is negligible
        // (eight property assignments spread over 5 seconds).
        for delay: Double in [0.0, 0.05, 0.15, 0.4, 0.8, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let nav = Self.findNavigationController(from: uiView) else { return }
                applyClearShadow(to: nav.navigationBar)
            }
        }
    }

    private static func findNavigationController(from view: UIView) -> UINavigationController? {
        var responder: UIResponder? = view
        while let r = responder {
            if let nav = r as? UINavigationController { return nav }
            responder = r.next
        }
        // Fallback — walk parent VCs from the view's nearest VC up
        // through `parent` in case the responder chain is detached
        // (can happen briefly during transition animations).
        var vc = view.findParentViewController()
        while let current = vc {
            if let nav = current as? UINavigationController { return nav }
            if let nav = current.navigationController { return nav }
            vc = current.parent
        }
        return nil
    }

    private func applyClearShadow(to navigationBar: UINavigationBar) {
        func clearShadow(on appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
            // Copy so we don't stomp on appearance instances shared
            // across nav controllers. Then null out every shadow knob
            // UIKit honours: `shadowColor` (modern), `shadowImage`
            // (legacy 1×1 stretchable), and the background image
            // (a non-nil background image with a 1pt-tall transparent
            // strip can also produce a visual divider on some iOS
            // pre-16 paths).
            let copy = (appearance.copy() as? UINavigationBarAppearance) ?? UINavigationBarAppearance()
            copy.shadowColor = .clear
            copy.shadowImage = UIImage()
            return copy
        }
        navigationBar.standardAppearance         = clearShadow(on: navigationBar.standardAppearance)
        navigationBar.scrollEdgeAppearance       = clearShadow(on: navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance)
        navigationBar.compactAppearance          = clearShadow(on: navigationBar.compactAppearance ?? navigationBar.standardAppearance)
        navigationBar.compactScrollEdgeAppearance = clearShadow(on: navigationBar.compactScrollEdgeAppearance ?? navigationBar.standardAppearance)
        // Legacy hairline strippers — some iOS pre-16 paths still
        // consult these on the UINavigationBar itself when computing
        // the bottom divider, even after a UINavigationBarAppearance
        // is set. Belt-and-braces.
        navigationBar.shadowImage = UIImage()
        navigationBar.setBackgroundImage(UIImage(), for: .default)

        // ROOT-CAUSE FIX — UIKit's old project hid the nav bar
        // entirely (`navigationController.navigationBar.isHidden =
        // true`) so the bottom hairline NEVER existed in the first
        // place. We can't hide the bar in SwiftUI without losing
        // toolbar items, so we go one level deeper: UIKit renders
        // the hairline as a private subview of the nav bar's
        // background view (`_UIBarBackgroundShadowView` /
        // `_UINavigationBarHairlineView` / similar internal class
        // — name varies by iOS version). Walking the nav bar's
        // subview tree and hiding ANY view whose class name carries
        // a "Shadow" / "Hairline" / "Separator" hint kills the line
        // regardless of what appearance values UIKit / SwiftUI later
        // applies on top — the line is GONE at the view level, not
        // just at the appearance level. This is the same technique
        // UI testers use to remove the hairline from custom toolbars
        // and is the only fully-reliable approach when SwiftUI's
        // `.toolbarBackground(.visible)` keeps re-installing its own
        // appearance object asynchronously.
        hideHairlineSubviews(in: navigationBar)
    }

    /// Recursively walks the nav bar's subview tree and hides any
    /// internal view that draws the bottom hairline. The view's
    /// class is private (one of `_UIBarBackgroundShadowView`,
    /// `_UINavigationBarHairlineView`, `_UIShadowView` — Apple
    /// renames these between iOS versions), so we match on name
    /// substrings rather than class identity. Setting `isHidden`
    /// AND `alpha = 0` AND removing the background defeats every
    /// rendering path the line might use.
    private func hideHairlineSubviews(in view: UIView, depth: Int = 0) {
        if depth > 6 { return }  // safety
        for subview in view.subviews {
            let className = NSStringFromClass(type(of: subview))
            // Match private hairline / shadow / separator views.
            // Filter by HEIGHT < 2pt as well — the hairline is always
            // ≤ 1pt tall, so this avoids accidentally hiding the
            // background view itself (which has the same kind of
            // class name on some iOS versions).
            let nameMatches = className.contains("Shadow")
                           || className.contains("Hairline")
                           || className.contains("Separator")
            if nameMatches && subview.bounds.height < 2 {
                subview.isHidden = true
                subview.alpha = 0
                subview.backgroundColor = .clear
                subview.layer.backgroundColor = UIColor.clear.cgColor
            }
            hideHairlineSubviews(in: subview, depth: depth + 1)
        }
    }
}

private extension UIView {
    func findParentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

extension View {
    /// Hides the 1pt grey hairline that UIKit / SwiftUI draws at the
    /// bottom of the navigation bar. iOS < 26 only — on iOS 26+ the
    /// Liquid-Glass nav bar handles its own bottom edge cleanly and
    /// this modifier is a no-op (the killer is gated internally).
    /// Use on any view whose hosting NavigationStack shows a system
    /// nav bar that would otherwise draw the divider.
    @ViewBuilder
    func hideNavigationBarBottomLine() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background(NavigationBarShadowKiller().frame(width: 0, height: 0))
        }
    }

    /// Applies the ChooseOptions-style flat `primaryBackgroundColor`
    /// nav bar so `NavigationRightGlassButtons` renders identically to
    /// HomeView on any toolbar-hosted screen.
    func chooseOptionsStyleNavBar() -> some View {
        modifier(ChooseOptionsStyleNavBar())
    }

    /// iOS 26+ only: forces the top scroll-edge effect to `.hard` so
    /// the toolbar's Liquid-Glass capsules (back-button circle +
    /// favourites/profile pill) do NOT pick up colours from the scroll
    /// content beneath them. Without this, full-bleed hero/banner
    /// images on screens like RecipeDetail and MixlistDetail tint the
    /// capsules grey/dark as the user scrolls — visibly inconsistent
    /// with ExploreRecipes / Cocktail Kits whose scroll content begins
    /// with light text. No-op on iOS < 26 since the modifier did not
    /// exist there and pre-26 toolbars don't apply Liquid Glass anyway.
    @ViewBuilder
    func hardTopScrollEdgeIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}

// MARK: - NavigationLeadingGlassButton
//
// Shared top-left button used on ChooseOptions (HomeView) and
// ControlCenterView. Mirrors the visual family of
// `NavigationRightGlassButtons.singleButtonGroup` — a 48×48 glass
// CIRCLE on iOS 26+, plain 30×30 icon on older iOS — so the left and
// right ends of the nav bar feel like the same chrome.
//
// Why a CIRCLE (not the 100×48 pill on the right): UIKit's single-item
// left-hand affordance is one icon with one action; the right-hand
// capsule hosts TWO icons. Reusing the pill shape for a single icon
// would look visually heavy. The `singleButtonGroup` branch of
// `NavigationRightGlassButtons` uses the same 48×48 circle recipe
// (lines 712–726) on RecipeDetail / MixlistDetail — we reuse it here
// for symmetry.
//
// Material recipe matches the right-hand pill:
//   • fill:   `.ultraThinMaterial`   (closest SwiftUI match to UIKit's
//                                      `UIGlassEffect(style: .clear)`)
//   • stroke: `Color.white.opacity(0.25)`, 1pt  (UIKit border colour)
//   • shadow: `black 0.14, r:10, y:4`           (matches pill shadow)
//
// Pre-iOS 26: plain bare icon, no glass container — matches the
// pre-26 branch of NavigationRightGlassButtons which also drops the
// glass shell.

struct NavigationLeadingGlassButton: View {
    /// Asset catalog name of the icon (e.g. `"imgExploreSmall"`).
    let imageName: String
    /// Icon rendered size inside the glass circle. UIKit imgExploreSmall
    /// is 18×22; Control Center uses it at 25×25. Caller decides.
    let iconSize: CGSize
    /// Tap handler.
    let action: () -> Void
    /// VoiceOver label.
    let accessibilityLabel: String

    init(imageName: String,
         iconSize: CGSize = CGSize(width: 18, height: 22),
         accessibilityLabel: String,
         action: @escaping () -> Void) {
        self.imageName = imageName
        self.iconSize = iconSize
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button {
            HapticService.light()
            action()
        } label: {
            iconView
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var iconView: some View {
        // iPad bumps the inner icon glyph 1.5× (e.g. 18→27 / 25→37) and
        // the outer glass circle 48 → 68pt to match the bumped right-
        // hand single-button frame, so the iPad toolbar reads as a
        // unified taller bar on both ends. iPhone keeps the
        // caller-supplied `iconSize` and 48pt circle bit-identically.
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let glyphW = isIPad ? iconSize.width * 1.5 : iconSize.width
        let glyphH = isIPad ? iconSize.height * 1.5 : iconSize.height
        if #available(iOS 26.0, *) {
            // 48×48 glass circle — same recipe as
            // NavigationRightGlassButtons.singleButtonGroup (HomeView.swift
            // L712-726).
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: glyphW, height: glyphH)
                .foregroundStyle(Color("appBlackColor"))
                .frame(width: isIPad ? 68 : 48, height: isIPad ? 68 : 48)
                .background(
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                )
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        } else {
            // Pre-iOS 26: plain icon on the flat nav bar background.
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: glyphW, height: glyphH)
                .foregroundStyle(Color("appBlackColor"))
        }
    }
}

// MARK: - DevicePrincipalIcon
//
// Shared top-bar principal device icon shown when a Barsys device is
// connected (`icon_barsys_360`, `icon_barsys_coaster`,
// `icon_barsys_shaker`). Rendered in the `ToolbarItem(placement: .principal)`
// slot across every screen that has a nav bar with the connected-device
// indicator.
//
// Dark-mode content-colour fix (size / position unchanged):
//   The three device-icon assets are single-tone glyphs whose raw PNG
//   colour resolves too light against the dark nav-bar surface in
//   dark mode — the user reported the icon as "very much light".
//   Light mode keeps the raw PNG (bit-identical pixels). Dark mode
//   template-renders the image and tints it via `appBlackColor`
//   (which resolves to the adaptive `#E5E5EA` near-white in dark),
//   restoring contrast against the dark nav bar without touching the
//   25×25 frame or toolbar placement.
struct DevicePrincipalIcon: View {
    let assetName: String
    let accessibilityLabel: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // iPad bumps the centered device icon 25 → 32pt — modest scale
        // that's readable on the wider canvas without overpowering the
        // top bar. Was previously 48pt; the user reported that as
        // visually too large compared to the rest of the toolbar
        // chrome (heart / profile glyphs in the right pill). Stepping
        // it down to 32pt keeps the icon legible while staying in
        // proportion with the bumped pill icons (28×32 heart,
        // 32×32 profile). iPhone keeps the storyboard 25pt frame
        // bit-identically.
        let side: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 32 : 25
        return Group {
            if colorScheme == .dark {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color("appBlackColor"))
            } else {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel(accessibilityLabel)
    }
}

