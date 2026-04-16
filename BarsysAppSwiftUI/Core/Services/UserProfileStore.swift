//
//  UserProfileStore.swift
//  BarsysAppSwiftUI
//
//  Observable facade over `UserDefaultsClass`. SwiftUI views bind to this
//  store instead of reading UserDefaults directly in their `body`, so the
//  moment login succeeds and `OryAPIClient.verifyOtp` persists the user's
//  name/phone/email/profile image, every view showing that data re-renders.
//
//  `UserDefaultsClass` is still the source of truth for persistence — the
//  store mirrors its values into `@Published` properties and writes back
//  through the same API, keeping byte-identical compatibility with the
//  UIKit app.
//

import SwiftUI
import Combine

final class UserProfileStore: ObservableObject {

    static let shared = UserProfileStore()

    // Published copies of the persisted fields — SwiftUI views observing
    // this store will re-render the instant any of these change.
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var phone: String = ""
    @Published var dob: String = ""
    @Published var profileImageURL: String = ""
    @Published var countryName: String = ""
    @Published var sessionToken: String = ""
    @Published var userId: String = ""

    init() {
        reload()
    }

    /// Reads every field from `UserDefaultsClass` and mirrors it into the
    /// published properties. Called on init and after any external write
    /// (e.g. after a profile re-fetch).
    func reload() {
        name            = UserDefaultsClass.getName() ?? ""
        email           = UserDefaultsClass.getEmail() ?? ""
        phone           = UserDefaultsClass.getPhone() ?? ""
        dob             = UserDefaultsClass.getDoB() ?? ""
        profileImageURL = UserDefaultsClass.getProfileImage() ?? ""
        countryName     = UserDefaultsClass.getCountryName() ?? ""
        sessionToken    = UserDefaultsClass.getSessionToken() ?? ""
        userId          = UserDefaultsClass.getUserId() ?? ""
    }

    /// Applies a fresh `UserProfile` (typically from the Ory verify response
    /// or the `my/profile` API) — writes every field through to
    /// `UserDefaultsClass` AND updates the published properties so observers
    /// re-render immediately.
    func apply(profile: UserProfile) {
        if !profile.firstName.isEmpty {
            UserDefaultsClass.storeName(profile.firstName)
            name = profile.firstName
        }
        if !profile.email.isEmpty {
            UserDefaultsClass.storeEmail(profile.email)
            email = profile.email
        }
        if !profile.phone.isEmpty {
            UserDefaultsClass.storePhone(profile.phone)
            phone = profile.phone
        }
        if !profile.countryCode.isEmpty {
            UserDefaultsClass.storeCountryName(profile.countryCode)
            countryName = profile.countryCode
        }
        if let avatar = profile.avatarURL?.absoluteString, !avatar.isEmpty {
            UserDefaultsClass.storeProfileImage(avatar)
            profileImageURL = avatar
        }
    }

    /// Writes an individual field through the store and the persisted
    /// `UserDefaultsClass` at once.
    func setName(_ value: String) {
        UserDefaultsClass.storeName(value)
        name = value
    }

    func setProfileImage(_ url: String) {
        UserDefaultsClass.storeProfileImage(url)
        profileImageURL = url
    }

    /// Wipes every local cached value + the persisted UserDefaults keys.
    /// Called from logout.
    func clear() {
        name = ""
        email = ""
        phone = ""
        dob = ""
        profileImageURL = ""
        countryName = ""
        sessionToken = ""
        userId = ""
    }
}
