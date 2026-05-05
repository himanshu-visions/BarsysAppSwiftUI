//
//  UserDefaultsClass.swift
//  BarsysAppSwiftUI
//
//  Direct 1:1 port of BarsysApp/Controllers/Login/UserDefaultsClass.swift
//  — same method names, same underlying keys, same Keychain backing for
//  sensitive data so a user who logs in on the UIKit build and then
//  runs the SwiftUI build (same bundle id) sees the same session token,
//  user id, email, phone, etc.
//
//  Storage policy (matches UIKit):
//    • SENSITIVE — Keychain via `KeychainHelper.shared`:
//        userId, sessionId, sessionToken, accessToken,
//        name, email, phone, dob, countryName,
//        deviceId, profileImage URL.
//    • NON-SENSITIVE — UserDefaults:
//        last-connected-device id / time, preferences unit, cache
//        timestamps, per-device first-time tutorial flags, analytics
//        consent flags, has-launched-before flag, has-seen-tutorial flag.
//
//  Migration: earlier scaffold builds wrote sensitive values to
//  `UserDefaults`. On every read of a Keychain-backed key we look in the
//  Keychain first; if missing AND a value is found in UserDefaults we
//  copy it across and delete the UserDefaults entry — the migration is
//  silent, idempotent, and runs at most once per key per device.
//

import Foundation

enum UserDefaultsClass {

    // MARK: - Keys (byte-identical to BarsysApp/Controllers/Login/UserDefaultsClass.swift)

    private enum Keys {
        // "Keychain" keys — stored in UserDefaults in the SwiftUI port
        static let userId        = "userId"
        static let sessionId     = "sessionId"
        static let email         = "user_email"
        static let phone         = "user_phone"
        static let sessionToken  = "session_token"
        static let name          = "name"
        static let accessToken   = "accessToken"
        static let countryName   = "countryName"
        static let deviceId      = "deviceId"
        static let profileImage  = "user_Profile_image"
        static let dob           = "user_dob"

        // UserDefaults keys (non-sensitive)
        static let lastConnectedDevice              = "lastConnectedDevice"
        static let lastConnectedDeviceTimeInterval  = "lastConnectedDeviceTimeInterval"
        static let savePreferencesUnit              = "savePreferencesUnit"
        static let updatedDataTimeStampForMixlistData = "updatedDataTimeStampForMixlistData"
        static let coreDataMixlistCount             = "coreDataMixlistCount"
        static let coasterConnectedNotFirstTime     = "coasterConnectedNotFirstTime"
        static let shakerConnectedNotFirstTime      = "shakerConnectedNotFirstTime"
        static let barsys360ConnectedNotFirstTime   = "barsys360ConnectedNotFirstTime"
        static let isFirstTimeShownDevicePopUp      = "isFirstTimeShownDevicePopUp"
        static let updatedDataTimeStampForFavourites = "updatedDataTimeStampForFavourites"
        static let updatedDataTimeStampForCacheRecipeData = "updatedDataTimeStampForCacheRecipeData"
        static let lastRatingViewShownTimeInterval  = "lastRatingViewShownTimeInterval"
        static let analyticsConsentGranted          = "analyticsConsentGranted"
        static let analyticsConsentPromptShown      = "analyticsConsentPromptShown"
        static let isManuallyDisconnected           = "kBarsysIsManuallyDisconnected"
        static let hasLaunchedBefore                = "hasLaunchedBefore"
        static let hasSeenTutorial                  = "hasSeenTutorial"

        // Storage cache keys — JSON-encoded recipes / mixlists / favourites
        // written by `MockStorageService.persistCache()`. Mirrors UIKit's
        // SQLite tables (`cocktails_recipes`, `mixlists`,
        // `favourite_recipes`). Listed here so `clearAll()` wipes them on
        // logout / delete-account / session-expired — matches UIKit
        // dropping the SQLite rows in those flows.
        static let storageRecipesCache              = "barsys_storage_recipes"
        static let storageMixlistsCache             = "barsys_storage_mixlists"
        static let storageFavoritesCache            = "barsys_storage_favorites"
    }

    private static var defaults: UserDefaults { .standard }
    private static let keychain = KeychainHelper.shared

    /// Every Keychain-backed key — used by `clearAll()` and the
    /// migration sweep. Order is informational only; the helpers
    /// just need a stable list to iterate.
    private static let keychainKeys: [String] = [
        Keys.userId,
        Keys.sessionId,
        Keys.email,
        Keys.phone,
        Keys.sessionToken,
        Keys.name,
        Keys.accessToken,
        Keys.countryName,
        Keys.deviceId,
        Keys.profileImage,
        Keys.dob
    ]

    // MARK: - Keychain plumbing
    //
    // 1:1 with UIKit `UserDefaultsClass.saveToKeychain(_:forKey:)` —
    //   • non-nil  → save (delete + add, matches UIKit)
    //   • nil      → delete (matches UIKit)
    //
    // Empty strings are passed straight through (matches UIKit which
    // stores `""` instead of treating empty as nil).
    private static func writeKeychain(_ value: String?, forKey key: String) {
        if let value {
            keychain.save(value, forKey: key)
        } else {
            keychain.delete(forKey: key)
        }
    }

    /// Read a Keychain-backed key, with a one-shot UserDefaults
    /// migration fallback so users who already logged in on the
    /// pre-Keychain SwiftUI scaffold aren't silently kicked out.
    ///
    /// Order:
    ///   1. Keychain hit → return.
    ///   2. Keychain miss + UserDefaults hit → copy to Keychain,
    ///      delete from UserDefaults, return the value.
    ///   3. Both miss → return nil.
    ///
    /// Idempotent: once step 2 has run, step 1 always wins on every
    /// subsequent read, so the migration cost is paid at most once
    /// per key per device.
    private static func readKeychain(forKey key: String) -> String? {
        if let kc = keychain.get(forKey: key) {
            return kc
        }
        // Migration fallback — strictly transitional.
        if let legacy = defaults.string(forKey: key) {
            keychain.save(legacy, forKey: key)
            defaults.removeObject(forKey: key)
            return legacy
        }
        return nil
    }

    // MARK: - Store (sensitive — Keychain-backed, mirrors UIKit
    //          `BarsysApp/Controllers/Login/UserDefaultsClass.swift`
    //          `store*` helpers L71-81 + `saveToKeychain` L56-62)

    static func storeName(_ value: String?)         { writeKeychain(value, forKey: Keys.name) }
    static func storeEmail(_ value: String?)        { writeKeychain(value, forKey: Keys.email) }
    static func storePhone(_ value: String?)        { writeKeychain(value, forKey: Keys.phone) }
    static func storeDoB(_ value: String?)          { writeKeychain(value, forKey: Keys.dob) }
    static func storeSessionToken(_ value: String?) { writeKeychain(value, forKey: Keys.sessionToken) }
    static func storeAccessToken(_ value: String?)  { writeKeychain(value, forKey: Keys.accessToken) }
    static func storeSessionId(_ value: String?)    { writeKeychain(value, forKey: Keys.sessionId) }
    static func storeUserId(_ value: String?)       { writeKeychain(value, forKey: Keys.userId) }
    static func storeCountryName(_ value: String?)  { writeKeychain(value, forKey: Keys.countryName) }
    static func storeDeviceId(_ value: String?)     { writeKeychain(value, forKey: Keys.deviceId) }
    static func storeProfileImage(_ value: String?) { writeKeychain(value, forKey: Keys.profileImage) }

    // MARK: - Get (sensitive — Keychain reads with UserDefaults
    //          migration fallback; matches UIKit `keychain.get(forKey:)`
    //          getter pattern L144-189)

    static func getName() -> String?          { readKeychain(forKey: Keys.name) }
    static func getEmail() -> String?         { readKeychain(forKey: Keys.email) }
    static func getPhone() -> String?         { readKeychain(forKey: Keys.phone) }
    static func getDoB() -> String?           { readKeychain(forKey: Keys.dob) }
    static func getSessionToken() -> String?  { readKeychain(forKey: Keys.sessionToken) }
    static func getAccessToken() -> String?   { readKeychain(forKey: Keys.accessToken) }
    static func getSessionId() -> String?     { readKeychain(forKey: Keys.sessionId) }
    static func getUserId() -> String?        { readKeychain(forKey: Keys.userId) }
    static func getCountryName() -> String?   { readKeychain(forKey: Keys.countryName) }
    static func getProfileImage() -> String?  { readKeychain(forKey: Keys.profileImage) }

    /// 1:1 with UIKit `UserDefaultsClass.getDeviceID()` (L151-158) —
    /// returns the existing Keychain-backed `deviceId` if present,
    /// otherwise mints a fresh UUID, stores it in the Keychain, and
    /// returns the new value. The non-optional return matches the
    /// previous SwiftUI signature so existing call-sites don't have
    /// to handle nil.
    static func getDeviceID() -> String {
        if let existing = readKeychain(forKey: Keys.deviceId), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        storeDeviceId(new)
        return new
    }

    // MARK: - Last connected device (UserDefaults-backed in UIKit)

    static func saveLastConnectedDevice(_ value: String?) {
        defaults.set(value, forKey: Keys.lastConnectedDevice)
    }
    static func getLastConnectedDevice() -> String? {
        defaults.string(forKey: Keys.lastConnectedDevice)
    }
    static func removeLastConnectedDevice() {
        defaults.removeObject(forKey: Keys.lastConnectedDevice)
    }

    static func saveLastConnectedDeviceTime(_ value: String?) {
        defaults.set(value, forKey: Keys.lastConnectedDeviceTimeInterval)
    }
    static func getLastConnectedDeviceTime() -> String? {
        defaults.string(forKey: Keys.lastConnectedDeviceTimeInterval)
    }
    static func removeLastConnectedDeviceTime() {
        defaults.removeObject(forKey: Keys.lastConnectedDeviceTimeInterval)
    }

    /// Convenience wrapper so older call sites that used `storeLastConnectedDevice`
    /// (my earlier port) still compile.
    static func storeLastConnectedDevice(_ value: String?) {
        saveLastConnectedDevice(value)
    }

    // MARK: - Preferences / flags

    static func savePreferencesUnit(_ value: String?) {
        defaults.set(value, forKey: Keys.savePreferencesUnit)
    }
    static func getPreferencesUnit() -> QuantityType {
        let raw = defaults.string(forKey: Keys.savePreferencesUnit)?.lowercased()
        if raw == "oz" { return .oz }
        return .ml
    }

    static func storeIsManuallyDisconnected(_ flag: Bool) {
        defaults.set(flag, forKey: Keys.isManuallyDisconnected)
    }
    static func getIsManuallyDisconnected() -> Bool {
        defaults.bool(forKey: Keys.isManuallyDisconnected)
    }

    static func hasLaunchedBefore() -> Bool {
        defaults.bool(forKey: Keys.hasLaunchedBefore)
    }
    static func markHasLaunchedBefore() {
        defaults.set(true, forKey: Keys.hasLaunchedBefore)
    }
    static func hasSeenTutorial() -> Bool {
        defaults.bool(forKey: Keys.hasSeenTutorial)
    }
    static func markHasSeenTutorial(_ value: Bool) {
        defaults.set(value, forKey: Keys.hasSeenTutorial)
    }

    // MARK: - Per-device first-time tutorial flags
    //
    // 1:1 ports of UIKit
    // `UserDefaultsClass.{save,get}{Coaster,Shaker,Barsys360}ConnectedNotFirstTime`.
    // Drive `DevicePairedViewModel.shouldHideTutorial()` and
    // `tutorialVideoURLAndMarkShown()` so the Explore-screen tutorial
    // card only appears the FIRST time a user connects each device kind.
    // Once the tutorial is shown, the flag is set to `true` and the
    // card stays hidden on subsequent connections.

    static func saveCoasterConnectedNotFirstTime(_ value: Bool) {
        defaults.set(value, forKey: Keys.coasterConnectedNotFirstTime)
    }
    static func getCoasterConnectedNotFirstTime() -> Bool {
        defaults.bool(forKey: Keys.coasterConnectedNotFirstTime)
    }

    static func saveShakerConnectedNotFirstTime(_ value: Bool) {
        defaults.set(value, forKey: Keys.shakerConnectedNotFirstTime)
    }
    static func getShakerConnectedNotFirstTime() -> Bool {
        defaults.bool(forKey: Keys.shakerConnectedNotFirstTime)
    }

    static func saveBarsys360ConnectedNotFirstTime(_ value: Bool) {
        defaults.set(value, forKey: Keys.barsys360ConnectedNotFirstTime)
    }
    static func getBarsys360ConnectedNotFirstTime() -> Bool {
        defaults.bool(forKey: Keys.barsys360ConnectedNotFirstTime)
    }

    // MARK: - First-time device popup flag (1:1 UIKit
    //          `saveisFirstTimeShownDevicePopUp`/`getisFirstTimeShownDevicePopUp`)

    static func saveisFirstTimeShownDevicePopUp(_ value: Bool?) {
        defaults.set(value, forKey: Keys.isFirstTimeShownDevicePopUp)
    }
    static func getisFirstTimeShownDevicePopUp() -> Bool {
        defaults.bool(forKey: Keys.isFirstTimeShownDevicePopUp)
    }

    // MARK: - Cache + sync timestamps (1:1 UIKit `save*` / `get*`
    //          for mixlist / favourites / recipe / rating timestamps)

    static func saveUpdatedDataTimeStampForMixlistData(_ timeStamp: Int?) {
        defaults.set(timeStamp, forKey: Keys.updatedDataTimeStampForMixlistData)
    }
    static func getUpdatedDataTimeStampForMixlistData() -> Int? {
        defaults.integer(forKey: Keys.updatedDataTimeStampForMixlistData)
    }

    static func saveUpdatedDataTimeStampForFavourites(_ timeStamp: Int?) {
        defaults.set(timeStamp, forKey: Keys.updatedDataTimeStampForFavourites)
    }
    static func getUpdatedDataTimeStampForFavourites() -> Int? {
        defaults.integer(forKey: Keys.updatedDataTimeStampForFavourites)
    }

    static func saveCoreDataMixlistCount(_ count: Int) {
        defaults.set(count, forKey: Keys.coreDataMixlistCount)
    }
    static func getCoreDataMixlistCount() -> Int {
        defaults.integer(forKey: Keys.coreDataMixlistCount)
    }

    static func saveUpdatedDataTimeStampForCacheRecipes(_ timeStamp: Int?) {
        defaults.set(timeStamp, forKey: Keys.updatedDataTimeStampForCacheRecipeData)
    }
    static func getUpdatedDataTimeStampForCacheRecipeData() -> Int? {
        defaults.integer(forKey: Keys.updatedDataTimeStampForCacheRecipeData)
    }

    static func saveLastRatingViewShownTimeInterval(_ timeStamp: Int?) {
        defaults.set(timeStamp, forKey: Keys.lastRatingViewShownTimeInterval)
    }
    static func getLastRatingViewShownTimeInterval() -> Int? {
        defaults.integer(forKey: Keys.lastRatingViewShownTimeInterval)
    }

    // MARK: - Analytics consent (1:1 UIKit
    //          `saveAnalyticsConsentGranted` / `getAnalyticsConsentGranted` /
    //          `removeAnalyticsConsentGranted` and the prompt-shown twin)
    //
    // The keys here (camelCase: `analyticsConsentGranted` /
    // `analyticsConsentPromptShown`) match UIKit BYTE-FOR-BYTE so a
    // user who already accepted on UIKit doesn't see the prompt again
    // after upgrading to SwiftUI. The SwiftUI scaffold previously
    // stored these under snake_case keys (`analytics_consent_granted`
    // / `analytics_consent_prompt_shown`) — `AnalyticsConsentManager`
    // migrates from those legacy keys on first read.

    static func saveAnalyticsConsentGranted(_ granted: Bool?) {
        defaults.set(granted, forKey: Keys.analyticsConsentGranted)
    }
    static func getAnalyticsConsentGranted() -> Bool {
        defaults.bool(forKey: Keys.analyticsConsentGranted)
    }
    static func removeAnalyticsConsentGranted() {
        defaults.removeObject(forKey: Keys.analyticsConsentGranted)
        defaults.synchronize()
    }

    static func saveAnalyticsConsentPromptShown(_ shown: Bool?) {
        defaults.set(shown, forKey: Keys.analyticsConsentPromptShown)
    }
    static func getAnalyticsConsentPromptShown() -> Bool {
        defaults.bool(forKey: Keys.analyticsConsentPromptShown)
    }
    static func removeAnalyticsConsentPromptShown() {
        defaults.removeObject(forKey: Keys.analyticsConsentPromptShown)
        defaults.synchronize()
    }

    // MARK: - Clear (logout)

    /// Ports `UserDefaultsClass.clearAll()` — wipes every key this class
    /// writes to, exactly matching the UIKit version
    /// (BarsysApp/Controllers/Login/UserDefaultsClass.swift L272-298):
    /// Keychain entries first, then non-sensitive UserDefaults entries,
    /// then `synchronize()`. The Keychain wipe also clears any legacy
    /// UserDefaults copies that the migration fallback may not have
    /// touched yet for keys the user never read post-upgrade.
    static func clearAll() {
        // Keychain (sensitive) — matches UIKit `keychain.delete(forKey:)`
        // calls L276-286.
        keychain.deleteAll(forKeys: keychainKeys)

        // Belt-and-braces: also remove any pre-migration UserDefaults
        // copies of the sensitive keys. If the migration fallback has
        // already moved them, this is a no-op; if the user is on the
        // very first launch of the Keychain build and never read a
        // sensitive key (so migration didn't run for that key), the
        // legacy UserDefaults entry would otherwise survive logout —
        // this loop guarantees full cleanup either way.
        for key in keychainKeys { defaults.removeObject(forKey: key) }

        // Non-sensitive UserDefaults — matches UIKit `clearAll()` L289-296.
        let userDefaultsKeys: [String] = [
            Keys.isFirstTimeShownDevicePopUp,
            Keys.updatedDataTimeStampForFavourites,
            Keys.updatedDataTimeStampForMixlistData,
            Keys.coreDataMixlistCount,
            Keys.coasterConnectedNotFirstTime,
            Keys.barsys360ConnectedNotFirstTime,
            Keys.lastConnectedDevice,
            Keys.updatedDataTimeStampForCacheRecipeData,
            Keys.isManuallyDisconnected,
            Keys.hasSeenTutorial,
            // Storage disk-cache keys — wipe alongside the rest so the
            // next user / fresh login doesn't see the previous user's
            // recipes / mixlists / favourites. UIKit drops the SQLite
            // rows here (`DBManager.deleteAllData`); we drop the
            // JSON-encoded equivalents.
            //
            // Kept for backwards compatibility with builds that
            // persisted the catalog in UserDefaults — current builds
            // write to file storage (see below) but a stale
            // UserDefaults blob from a pre-migration build still gets
            // cleared here so it never lingers post-logout.
            Keys.storageRecipesCache,
            Keys.storageMixlistsCache,
            Keys.storageFavoritesCache
        ]
        for key in userDefaultsKeys { defaults.removeObject(forKey: key) }
        defaults.synchronize()

        // The catalog cache moved from UserDefaults to JSON files in
        // the Caches directory (UserDefaults can't hold the ~5 MB
        // recipes payload). Delete the file copies on logout so the
        // next user / fresh login starts with an empty cache, just
        // like UIKit's `DBManager.deleteAllData()`.
        clearStorageCacheFiles()
    }

    /// Removes the catalog cache files that `MockStorageService`
    /// writes (`barsys_storage_recipes.json` etc.) so a logout / delete-
    /// account flow drops the on-disk JSON copies in addition to the
    /// in-memory dictionaries the auth-flow tear-down already clears.
    /// Filenames are duplicated from `MockStorageService` because the
    /// Services-side constants are private to that type.
    private static func clearStorageCacheFiles() {
        guard let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first else { return }
        let filenames = [
            "barsys_storage_recipes.json",
            "barsys_storage_mixlists.json",
            "barsys_storage_favorites.json"
        ]
        for filename in filenames {
            let url = cacheDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - AppStateManager (lightweight port of AppStateManager.swift)

@MainActor
final class AppStateManager: ObservableObject {
    static let shared = AppStateManager()

    @Published var isSpeakEasyCase: Bool = false
    @Published var recipeCache: [Recipe] = []
    /// Set to `true` by `DrinkCompleteView`'s "Craft again" button so
    /// the next time `CraftingView` appears it bypasses the
    /// "Ready to Pour?" confirmation alert and starts crafting
    /// immediately — matching UIKit's
    /// `craftingVc?.skipPourConfirmation = true` on re-entry
    /// (`DrinkCompleteViewController.swift` L262-287).
    ///
    /// Consumed once on the next `CraftingView.onAppear` and reset
    /// to `false` so subsequent manual pushes of CraftingView still
    /// show the pour confirmation.
    @Published var makeItAgainPending: Bool = false

    private init() {}

    func setSpeakEasyCaseState(_ value: Bool) {
        isSpeakEasyCase = value
    }

    func updateRecipeCache(_ recipes: [Recipe]) {
        recipeCache = recipes
    }

    /// Read-and-clear helper — returns the current
    /// `makeItAgainPending` value and resets it to `false` atomically
    /// so only the first `CraftingView.onAppear` after DrinkComplete's
    /// "Craft again" tap picks it up.
    func consumeMakeItAgainPending() -> Bool {
        let value = makeItAgainPending
        makeItAgainPending = false
        return value
    }
}

// MARK: - HapticService (ports HapticService.shared from UIKit)

enum HapticService {
    /// Mirrors UIKit `HapticService.shared.light()` — light tap used on
    /// most button presses (navigation, tab switches, pencil edits).
    static func light() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.medium()` — used on confirm
    /// actions: "Start Pouring" in CraftingVC, "Make It Again" return
    /// to crafting, etc. UIKit triggers this via
    /// `.medium` `UIImpactFeedbackGenerator`.
    static func medium() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.heavy()` — reserved for hard
    /// commit actions (e.g. deleting an account).
    static func heavy() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.selection()` — segmented
    /// controls, tab swaps, country-picker selection.
    static func selection() {
        #if canImport(UIKit)
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.error()` — validation failures.
    static func error() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.success()` — profile save,
    /// drink complete, favorite added.
    static func success() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        #endif
    }
    /// Mirrors UIKit `HapticService.shared.warning()`.
    static func warning() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.warning)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
