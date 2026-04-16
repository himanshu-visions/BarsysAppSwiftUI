# BarsysAppSwiftUI

Pure-SwiftUI rewrite of BarsysApp. The original UIKit project under
`BarsysApp/` is **untouched** — this new project lives alongside it and
can be opened, built, and run on its own.

## What's here

```
BarsysAppSwiftUI/
├── Podfile                         # platform :ios, '16.0' — all pods optional
├── README.md
└── BarsysAppSwiftUI/
    ├── App/                        # @main, AppRouter, AppEnvironment, AppDelegateAdaptor
    ├── Core/
    │   ├── Models/                 # Recipe, Mixlist, Device, UserProfile, Country, …
    │   ├── Services/               # APIClient, StorageService, AuthService, BLEService, SocketService, BrazeService, Analytics, Catalog
    │   └── Utilities/              # SampleData
    ├── DesignSystem/               # Theme, Components (buttons, text fields, cards, overlays, alerts)
    ├── Bridging/                   # WKWebView + QR scanner UIViewRepresentables
    └── Features/
        ├── Auth/                   # Splash, AuthFlow, Login, SignUp, Tutorial
        ├── Main/                   # MainTabView, SideMenuView, HomeView
        ├── Recipes/                # Explore, Detail, MakeMyOwn, EditRecipe
        ├── Mixlists/               # Detail, Edit
        ├── Favorites/
        ├── MyBar/                  # MyBar, ScanIngredients
        ├── MyProfile/
        ├── Preferences/            # Preferences, CountryPicker, SelectQuantity
        ├── ControlCenter/          # ControlCenter, StationsMenu, StationCleaning
        ├── Devices/                # PairDevice, DeviceList, DeviceConnected, DeviceRename
        ├── Crafting/               # Crafting, DrinkComplete
        └── BarBot/                 # BarBotCraft chat, History, QRReader
```

Every screen referenced by the original UIKit app has a SwiftUI equivalent
in this project.

## Architecture

- **`@main BarsysAppSwiftUIApp`** — app entry. Owns the root `AppEnvironment`
  and `AppRouter` and injects every inner service (`AuthService`,
  `CatalogService`, `BLEService`, `LoadingState`, `AlertQueue`, …) into the
  SwiftUI environment so any view can grab what it needs.
- **`AppRouter`** — replaces the original `AppCoordinator` and the 15
  child coordinators. Holds the top-level screen (splash / auth / tutorial /
  main), the selected tab, and one `NavigationPath` per tab. Views push
  `Route` enum cases instead of instantiating view controllers.
- **`AppEnvironment`** — DI container. Produced once via
  `AppEnvironment.live()`. Services are protocol-typed so they can be swapped
  for the real backend without touching views.
- **Services** (`Core/Services/Services.swift`) — `APIClient`, `StorageService`,
  `AuthService`, `PreferencesService`, `BLEService`, `SocketService`,
  `BrazeService`, `AnalyticsService`, `CatalogService`. The file ships with
  `MockAPIClient` + `MockStorageService` so the app runs end-to-end with no
  backend. Every view model talks to these protocols, never to network or
  DB code directly.
- **DesignSystem** (`DesignSystem/Theme.swift` + `Components.swift`) —
  centralized colors, fonts, spacing, and every reusable UI primitive
  (`PrimaryButton`, `SecondaryButton`, `AppTextField`, `SecureAppTextField`,
  `RecipeCard`, `SectionHeader`, `EmptyStateView`, `LoadingOverlay`, and
  `.appAlert()` modifier).
- **Bridging** (`Bridging/Bridging.swift`) — `WebView` (WKWebView) and
  `QRScannerView` (AVFoundation) as `UIViewRepresentable`/
  `UIViewControllerRepresentable` wrappers, so SwiftUI screens can use them
  natively.
- **Feature modules** — each feature folder contains its SwiftUI view(s)
  and (where relevant) an `ObservableObject` view model that matches the
  original UIKit view model's responsibilities.

## Running the app

**Just open `BarsysAppSwiftUI.xcodeproj` in Xcode and hit ⌘R.**

The project is pre-configured with:
- iOS 16.0 deployment target
- SwiftUI app lifecycle (`@main`)
- Camera usage description (for QR scanner)
- Auto-generated Info.plist (no plist file in the repo)
- App icon asset slot + accent color
- A shared scheme so the target is selectable immediately

Verified clean build:

```
xcodebuild -project BarsysAppSwiftUI.xcodeproj \
           -scheme BarsysAppSwiftUI \
           -destination 'generic/platform=iOS Simulator' \
           -configuration Debug build
** BUILD SUCCEEDED **
```

No CocoaPods required — the `Podfile` ships with every pod commented out.
You only need `pod install` if/when you uncomment SDK pods to wire the real
backend.

### Regenerating the project

If you add new Swift files later, re-run the generator to refresh
`BarsysAppSwiftUI.xcodeproj`:

```
python3 generate_xcodeproj.py
```

It scans `BarsysAppSwiftUI/` and rewrites the pbxproj with every `.swift`
file and every `.xcassets` catalog it finds. No external dependencies.

## Using the real backend instead of the mocks

All views talk to services through protocols in
`Core/Services/Services.swift`. To swap in the existing BarsysApp networking,
BLE, DB, Braze, and Firebase layers:

1. Copy the relevant files from `BarsysApp/BarsysApp/` (e.g.
   `MyProfileApiService`, `LoginSignUpOryApiService`, `DBManager`,
   `BleManager`, `SocketManager`, Braze/Firebase configuration) into
   `Core/` in this project.
2. Create adapter classes that conform to the service protocols
   (`APIClient`, `StorageService`, `BLEService`, etc.) and delegate to
   the copied-in implementations.
3. In `AppEnvironment.live()` swap the `Mock*` instances for your adapter
   classes.
4. In `AppDelegateAdaptor` uncomment the `FirebaseApp.configure()`,
   Braze initialization, and `IQKeyboardManager` enablement calls, and
   add the corresponding pods to `Podfile`.

Nothing in the `Features/` layer has to change — the mock → real swap is
an `AppEnvironment.live()` edit.

## Honest notes on scope

The original BarsysApp is ~50,600 lines of Swift across 307 files with
deep coupling to Braze, Firebase, IQKeyboardManager, a custom BLE stack,
a WebSocket SocketManager, and 10 storyboards + 32 XIBs. A true 1:1 port
that faithfully preserves every screen, every animation, every BLE state
transition, every analytics event, and every Braze in-app message is a
multi-week effort.

What this rewrite delivers:

- **Every screen** in the original app has a SwiftUI equivalent with the
  same navigation shape, the same core functionality, and a matching visual
  language.
- **A complete architecture** (App, Router, Environment, DesignSystem,
  Bridging, Services) that is genuinely the right long-term shape for a
  SwiftUI app — not a line-for-line transliteration of the UIKit
  coordinator code.
- **Mock services** so the app runs end-to-end on day one without the
  backend wired in.
- **Clear integration points** (labeled `TODO`) in `AppDelegateAdaptor`
  and `AppEnvironment.live()` where the real BLE / Socket / Braze /
  Firebase layers plug back in.

What you should expect to iterate on:

- Pixel-exact parity with the original UIKit screens (fonts, colors, padding
  will need small tweaks to match your brand guide once assets are imported).
- Wiring the real networking, DB, BLE, socket, and Braze layers into the
  service adapters.
- Importing the existing `Assets.xcassets` catalog so SwiftUI `Image(…)`
  calls pick up the real artwork instead of SF Symbols placeholders.
- Analytics events on every button tap (the `AnalyticsService` stub is in
  place; every view model has an obvious place to call
  `analytics.track(…)`).

## File inventory

| Layer | Files |
| --- | --- |
| App | BarsysAppSwiftUIApp, AppDelegateAdaptor, AppRouter, AppEnvironment |
| Core | Models, Services, SampleData |
| DesignSystem | Theme, Components |
| Bridging | WebView, QRScannerView |
| Auth | SplashView, AuthFlowView, LoginView, SignUpView, TutorialView |
| Main | MainTabView, SideMenuView, HomeView |
| Recipes | ExploreRecipesView, RecipeDetailView, MakeMyOwnView, EditRecipeView |
| Mixlists | MixlistDetailView, EditMixlistView |
| Favorites | FavoritesView |
| MyBar | MyBarView, ScanIngredientsView |
| MyProfile | MyProfileView |
| Preferences | PreferencesView, CountryPickerView, EmbeddedCountryPicker, SelectQuantityView |
| ControlCenter | ControlCenterView, StationsMenuView, StationCleaningView |
| Devices | PairDeviceView, DeviceListView, DeviceConnectedView, DeviceRenameView |
| Crafting | CraftingView, DrinkCompleteView |
| BarBot | BarBotCraftView, BarBotHistoryView, QRReaderView |
