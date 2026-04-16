//
//  DomainEnums.swift
//  BarsysAppSwiftUI
//
//  Direct ports of the domain enums used in the UIKit BarsysApp project.
//  Keeping identical cases / raw values lets the SwiftUI views drive the
//  same state machines the UIKit code used.
//

import Foundation

// MARK: - StationName (ports Helpers/Constants/Constants+Enums.swift)

enum StationName: String, CaseIterable, Hashable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"

    var id: Self { self }

    var tag: Int {
        switch self {
        case .a: return 1
        case .b: return 2
        case .c: return 3
        case .d: return 4
        case .e: return 5
        case .f: return 6
        }
    }

    static func forTag(_ tag: Int) -> StationName? {
        switch tag {
        case 1: return .a
        case 2: return .b
        case 3: return .c
        case 4: return .d
        case 5: return .e
        case 6: return .f
        default: return nil
        }
    }
}

// MARK: - Station cleaning state machine

enum CleaningFlow: String, Hashable {
    case initialEmptySetup
    case placeGlassStart
    case dispensingInProgress
    case removeGlassAndContinue
    case pourCleaningSolution
    case placeGlassAfterPourCleaningSolution
    case cleaningComplete
    case cancelled
}

enum CleaningProcessState {
    case idle
    case dispensing
    case paused
    case cancelling
}

enum CleaningMode {
    case flush
    case clean
}

enum StationsMenuOrigin {
    case controlCenter
    case barBot
    case recipeCrafting
}

// MARK: - Quantity unit

enum QuantityType: String, Hashable, CaseIterable, Identifiable {
    case ml
    case oz
    var id: Self { self }
    var label: String { self == .ml ? "Milliliters (ml)" : "Ounces (oz)" }
    var shortLabel: String { self == .ml ? "ml" : "oz" }
}

// MARK: - Device kind (ports IsDeviceType)

enum IsDeviceType: String, CaseIterable, Hashable {
    case coaster = "Barsys Coaster"
    case barsys360 = "Barsys 360"
    case barsysShaker = "Barsys Shaker"

    var displayName: String { rawValue }
}

// MARK: - Recipe source (ports RecipeSource)

enum RecipeSource: String, Codable, Hashable {
    case barsys = "Barsys"
    case user = "User"
    case ai = "AI"
    case custom = "Custom"
}

// MARK: - Analytics events (ports TrackEventName)

enum TrackEventName: String {
    // Auth
    case tapLoginGetOTP = "login_get_otp"
    case tapLoginResend = "login_resend_OTP"
    case loginUnsuccessfulOTP = "login_fail"
    case loginSuccessFul = "login_successful"
    case tapLoginCreateAccount = "signup_begin"
    case tapSignupGetOTP = "signup_get_otp"
    case tapSignupResend = "signup_resend_otp"
    case signupUnsuccessfulOTP = "signup_fail"
    case tapSignupRegister = "signup_successful"
    case tapSignupLogIn = "login_redirect"
    case tapSignupTermsOfService = "view_signup_terms_of_service"
    case tapSignupPrivacyPolicy = "view_signup_privacy_policy"

    // Crafting
    case craftBegin = "craft_begin"
    case barbotCraftBegin = "barbot_craft_begin"
    case craftGlassPlaced = "craft_glass_placed"
    case craftMakeMyOwn = "craft_make_my_own"
    case craftGlassLifted = "craft_glass_lifted"
    case craftCancelled = "craft_cancelled"
    case craftCompleted = "craft_completed"
    case craftMakeAgain = "craft_make_again"
    case craftCustomise = "craft_customise"

    // Discovery
    case viewRecipe = "view_recipe"
    case viewMixlist = "view_mixlist"
    case viewProfile = "profile_viewed"
    case favouriteRecipeAdded = "favorite_recipe_added"
    case favouriteRecipeRemoved = "favorite_recipe_removed"
    case editRecipeBegin = "edit_recipe_begin"
    case editRecipeCancel = "edit_recipe_cancel"
    case editRecipeSuccessful = "edit_recipe_successful"
    case saveRecipeMakeMyOwn = "save_recipe_make_my_own"
    case deleteIngredientMakeMyOwn = "delete_ingredient_make_my_own"
    case insertIngredientMakeMyOwn = "insert_ingredient_make_my_own"

    // Screens
    case homeScreenViewed = "Home_Screen_Viewed"
    case favouratesScreenViewed = "favorites_viewed"
    case controlCenterViewed = "view_control_center"
    case makeMyOwnScreenViewed = "view_make_my_own"
    case viewMixlistsListing = "view_mixlists_list"
    case viewRecipesListing = "view_recipes_list"

    // Device
    case onDeviceConnect = "bluetooth_connected"
    case onDeviceDisconnect = "bluetooth_disconnected"
    case onDeviceConnectionLost = "bluetooth_connection_lost"
    case bluetoothAutoReconnected = "bluetooth_auto_reconnected"
    case deviceAvailableListViewed = "bluetooth_available_device_viewed"

    // Stations
    case beginFlushFlow = "flush_station_begin"
    case beginCleanFlow = "clean_station_begin"
    case pauseFlushFlow = "flush_station_pause"
    case pauseCleanFlow = "clean_station_pause"
    case flushStationCompletedFlow = "flush_station_completed"
    case cleanStationCompletedFlow = "clean_station_completed"
    case refillStation = "refill_station"
    case addedIngredientToStation = "added_ingredient_to_station"
    case systemResetControlCenter = "system_reset_control_center"
    case controlCenterCleanStationViewed = "view_clean_station_control_center"
    case controlCenterStationMenuViewed = "view_station_menu_control_center"

    // BarBot
    case viewBarBotViewedFromTabBar = "view_barbot_nav_bar"
    case viewBarBotConnectDeviceScreenViewed = "view_barbot_connect_device_screen"
    case barBotStationSetUpBegin = "barbot_station_setup_begin"
    case barBotCleanStationBegin = "barbot_clean_station_begin"

    // Profile / settings
    case editProfileEvent = "edit_profile"
    case logoutEvent = "logOut"
    case deleteProfileEvent = "delete_profile"
    case changePrefrencesEvent = "change_preference"
}

// MARK: - BLE command (ports Helpers/BLE/BleCommand.swift verbatim)

enum BleCommand {
    /// Cancel any active operation. Firmware code: "202"
    case cancel

    /// Begin flushing/cleaning a specific station. Firmware: "227,{stationNumber},"
    case flushStation(stationNumber: Int)

    /// Stop an active dispense during cleaning. Firmware: "227,222,"
    case stopDispense

    /// Pause an active dispense during cleaning. Firmware: "227,406,"
    case pauseDispense

    /// Pre-built crafting command (constructed by crafting view model).
    case craftRaw(command: String)

    /// Rename the connected device. Firmware: "241{name}"
    case renameDevice(name: String)

    /// Start manual spinning (Shaker). Firmware: "215"
    case manualSpinStart

    /// Stop manual spinning (Shaker). Firmware: "216"
    case manualSpinStop

    /// The exact string sent to the BLE peripheral, matching firmware expectations.
    var rawValue: String {
        switch self {
        case .cancel: return "202"
        case .flushStation(let stationNumber): return "227,\(stationNumber),"
        case .stopDispense: return "227,222,"
        case .pauseDispense: return "227,406,"
        case .craftRaw(let command): return command
        case .renameDevice(let name): return "241\(name)"
        case .manualSpinStart: return "215"
        case .manualSpinStop: return "216"
        }
    }
}

// MARK: - BleResponse (1:1 port of UIKit BleResponse.swift)
//
// Type-safe parser for BLE responses received via
// `peripheral(_:didUpdateValueFor:error:)`. Replaces fragile string
// matching with a switchable enum so the cleaning state machine can
// react to discrete firmware events.

enum BleResponse: Equatable {
    case glassLifted
    case glassWaiting
    case glassPlaced(is219: Bool)
    case dispensingStarted(stationIndex: Int)
    case dispensingComplete(stationIndex: Int)
    case allIngredientsPoured
    case glassRemoved
    case cancelAcknowledged
    case dispensePaused
    case glassRemovedDuringDispense
    case cleanComplete
    case stationCleanAcknowledged(stationNumber: Int)
    case quantityFeedback(raw: String)
    case dataFlushed
    case shakerNotFlat
    case shakerFlat
    case shakerNotDetected
    case unknown(raw: String)

    /// Parses a raw BLE string into a typed response. Priority order
    /// mirrors UIKit `BleResponse.init(raw:)` exactly so the SwiftUI
    /// state machine reacts identically to the firmware.
    init(raw: String) {
        let cleaned = raw.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        if cleaned == "DATA Flushed" { self = .dataFlushed; return }
        if cleaned.contains("202") && cleaned.contains("401") {
            self = .cancelAcknowledged; return
        }
        if cleaned.contains("227") && cleaned.contains("401") {
            if let n = Self.middle(cleaned, prefix: "227,", suffix: ",401") {
                self = .stationCleanAcknowledged(stationNumber: n); return
            }
        }
        if cleaned.contains("227,401") { self = .cleanComplete; return }
        if cleaned.contains("227,406") { self = .dispensePaused; return }
        if cleaned.contains("227,496") { self = .glassRemovedDuringDispense; return }
        if cleaned.contains("221,405") { self = .allIngredientsPoured; return }
        if cleaned.contains("221,401") { self = .glassRemoved; return }
        if cleaned.contains("218") && cleaned.contains("405"),
           let i = Self.middle(cleaned, prefix: "218,", suffix: ",405") {
            self = .dispensingStarted(stationIndex: i); return
        }
        if cleaned.contains("218") && cleaned.contains("401"),
           let i = Self.middle(cleaned, prefix: "218,", suffix: ",401") {
            self = .dispensingComplete(stationIndex: i); return
        }
        if cleaned.contains("200") && cleaned.contains("410") { self = .shakerNotFlat; return }
        if cleaned.contains("200") && cleaned.contains("411") { self = .shakerFlat; return }
        if cleaned.contains("200") && cleaned.contains("405") { self = .shakerNotDetected; return }
        if (cleaned.contains("222") && cleaned.contains("209")) ||
           (cleaned.contains("222") && cleaned.contains("224")) ||
           cleaned.contains("d") {
            self = .quantityFeedback(raw: cleaned); return
        }
        if (cleaned.contains("210") && cleaned.contains("401")) ||
           (cleaned.contains("217") && cleaned.contains("405")) ||
           (cleaned.contains("217") && cleaned.contains("402")) {
            self = .glassLifted; return
        }
        if (cleaned.contains("219") && cleaned.contains("405")) ||
           (cleaned.contains("219") && cleaned.contains("402")) {
            self = .glassWaiting; return
        }
        if cleaned.contains("219") && cleaned.contains("401") {
            self = .glassPlaced(is219: true); return
        }
        if cleaned.contains("217") && cleaned.contains("401") {
            self = .glassPlaced(is219: false); return
        }
        self = .unknown(raw: cleaned)
    }

    private static func middle(_ s: String, prefix: String, suffix: String) -> Int? {
        guard let p = s.range(of: prefix),
              let q = s.range(of: suffix, range: p.upperBound..<s.endIndex)
        else { return nil }
        return Int(String(s[p.upperBound..<q.lowerBound]))
    }
}
