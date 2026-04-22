//
//  MyProfileView.swift
//  BarsysAppSwiftUI
//
//  1:1 port of the UIKit `MyProfileViewController`:
//   - BarsysApp/Controllers/MyProfile/MyProfileViewController.swift
//   - BarsysApp/Controllers/MyProfile/MyProfileViewController+ProfileSetup.swift
//   - BarsysApp/Controllers/MyProfile/MyProfileViewController+FormHandlers.swift
//   - BarsysApp/Controllers/MyProfile/MyProfileViewModel.swift
//   - BarsysApp/Controllers/MyProfile/MyProfileApiService.swift
//   - BarsysApp/StoryBoards/Base.lproj/SideMenu.storyboard scene `lA6-Bl-drp`
//
//  ======================= STORYBOARD AUDIT =======================
//
//  Root backgroundColor: `primaryBackgroundColor`
//
//  Top bar (Bbr-0Z-CP5) — 60pt tall, pinned to safeArea top:
//      • btnBack `Ljh-md-9Wa`   leading:12, centerY, size 30×30 (chevron)
//      • Centered stack `7EI-ic-Ob3` centerX/centerY (device icon + label)
//      • navigationRightGlassView `pSf-RK-NlW` trailing:24, centerY,
//        width 100 (or 63 when SpeakEasy): heart fav + profile avatar
//        icons rendered inside an iOS-26 `.addGlassEffect` wrapper.
//
//  Body (dUf-Po-DP6) — starts at y=60:
//      • Title `cz5-bS-UCa` "My Profile"   leading:24 top:18,
//        system 24pt `appBlackColor`.
//      • ScrollView `gti-lo-gaL` top:cz5+20.
//          ▸ Profile image `PZN-LG-6hy` 126×126 centered, y=10,
//            `roundCorners: 63` (circular), `white` bg, aspectFill,
//            placeholder = `icon_profile.png`.
//          ▸ Plus button `dXy-hd-NhR` 24×24 at (x=259.66, y=112) —
//            `icon_plus` asset (brand tan circle with +).
//          ▸ Form stack `6NM-Az-0yE` at y=181, leading:20 trailing:20,
//            axis vertical, spacing 30pt. EACH ROW IS HORIZONTAL:
//                ├ 90pt label view  — system 14pt default text color
//                │  (Name/Email/DoB have nil textColor → label default;
//                │   "Phone No." has `lightGrayColor` textColor).
//                └ 263pt right stack:
//                    • TextField (233pt) + icon_edit pencil (30pt) +
//                      1pt `paleBlueGrayColor` underline.
//                    • Phone row replaces the TextField with a
//                      horizontal stack: flag emoji (35pt) +
//                      `downArrowSmall` (25pt, template lightGray) +
//                      country-code label (17pt light,
//                      66.6% gray) + phone TextField (17pt appBlackColor,
//                      numberPad).
//                    • Hidden 13pt bold `errorLabelColor` under each row.
//          ▸ Bottom buttons container `wBo-Ct-8rR` — top 20pt:
//                ├ btnOk `3NG-Ld-yEF`     166.66×45, system 14pt,
//                │  white bg, appBlackColor title, `roundCorners: 8`,
//                │  runtime 1pt `craftButtonBorderColor` border.
//                │  iOS 26 → applyCancelCapsuleGradientBorderStyle().
//                └ btnUpdate `8jf-NV-Wno` 166.66×45, system 14pt,
//                   `segmentSelectionColor` bg, black title,
//                   `roundCorners: 8`, alpha 0.5 until user edits.
//                   iOS 26 → makeOrangeStyle().
//          ▸ Delete button container `bOD-ma-2Ne` — top 20pt:
//                • btnDeleteAccount `sT4-bt-LoM` 98×43, trailing,
//                  system 14pt `appBlackColor`, UNDERLINED attributed
//                  title "Delete account".
//
//  ======================= RUNTIME BEHAVIOR =======================
//
//  • viewDidLoad:
//      - btnBack/btnFavourite/btnSideMenu/btnAddImage/btnEditFullName/
//        btnEditEmail/btnEditDoB/btnOk/btnDeleteAccount .addBounceEffect()
//      - hideTabBarSelectionView() (custom tab bar dims)
//      - iOS < 26 → bottomMainConstraint.constant = 31.0
//      - iOS 26+ → btnProfileIconRightConstraint = 40,
//                  navigationRightGlassView.addGlassEffect(.radius)
//      - TrackEventsClass addBrazeCustomEventWithEventName viewProfile
//      - setupView()
//  • setupView:
//      - viewModel.onValidationUpdate = {...}   updates each row's
//        error label + underline color; shakeOnError() + HapticService.error()
//      - viewModel.controller = self + refreshProfile()
//      - lblDeviceName + imgDevice are toggled by BLE connection (hidden
//        when none). btnFavourite is hidden in SpeakEasy only.
//      - btnDeleteAccount.titleLabel gets `.underline` attributed text.
//      - btnOk.setTitleColor(.black)  bg clear  1pt craftButtonBorderColor
//      - btnUpdate.backgroundColor = .segmentSelectionColor
//      - btnUpdate.setTitleColor(.black)  alpha 0.5  isUserInteractionEnabled=false
//      - allCountries = getAllCountries()  selectedCountry filtered by
//        UserDefaultsClass.getCountryName().
//      - tap gesture on backgroundView (tag 786) dismisses keyboard.
//      - all 4 textfields .isUserInteractionEnabled = false initially.
//      - imgFlagDropDown rendered template.
//      - txtPhoneNumber.textColor = .lightGrayColor (always greyed).
//      - DatePickerManager wired to txtDob (mode .date, maxDate = today).
//  • viewWillAppear: viewModel.getProfile() unless image was just picked.
//  • refreshProfile: populates textfields from UserDefaultsClass,
//    loads profile image via SDWebImage, resolves country+phone split,
//    parses DoB with two formats.
//  • enableUpdateAction(enable):
//      - btnUpdate.setTitleColor(.black) always
//      - alpha 1.0 + isUserInteractionEnabled=true when enable
//      - alpha 0.5 + isUserInteractionEnabled=false otherwise
//      - iOS 26 → makeOrangeStyle() + applyCancelCapsuleGradientBorderStyle()
//  • actionEditFullName / actionEditEmail / actionEditDoB:
//      - HapticService.light
//      - turn on isUserInteractionEnabled + becomeFirstResponder
//      - enableUpdateAction(true)
//  • actionUpdate:
//      - if !isEdit → no-op
//      - viewModel populated, validateProfile():
//          - errorFullName / errorPhoneNumber / errorEmail / errorDob
//          - age computed via Calendar; < country.age → age error
//      - on success: HapticService.success + updateProfile API
//      - if image is nil AND base64 empty → call updateProfile only
//      - else imgProfile.image → base64 → updateProfileImageOnly then updateProfile
//  • actionDelete:
//      - showCustomAlertMultipleButtons(title: areYouSureYouWantToDeleteAccount, ...)
//      - onContinue → viewModel.deleteProfile → clearAll + logout
//
//  ======================= ASSET & COLOR TOKENS =======================
//
//  icon_profile.png    : placeholder for profile image (white circle with
//                        a silhouette drawn in `ironGrayColor`).
//  icon_plus           : 24×24 brand-tan circle with white +.
//  icon_edit           : 30×30 pencil glyph (dark gray).
//  downArrowSmall      : 25pt chevron-down; tinted `lightGrayColor`.
//  segmentSelectionColor : Update button fill (brand peach).
//  craftButtonBorderColor: 1pt stroke around the Ok button.
//  paleBlueGrayColor   : 1pt underline below every field.
//  lightGrayColor      : Phone No. label + error-free underline state.
//  errorLabelColor     : Validation error underline + helper label.
//  appBlackColor       : Primary body text (labels, titles, textfield text).
//

import SwiftUI

// MARK: - ViewModel (ports MyProfileViewModel + MyProfileApiService)

@MainActor
final class MyProfileViewModel: ObservableObject {
    // Ports `fullName`, `phoneNumber`, `email`, `dob`, `selectedCountry`.
    @Published var fullName: String = ""
    @Published var email: String = ""
    @Published var phone: String = ""
    /// Canonical YYYY-MM-DD date. Displayed as MM/DD/YYYY to match UIKit's
    /// `DateFormatConstants.yearMonthDay` / display format.
    @Published var dob: Date?
    @Published var selectedCountry: Country = .unitedStates

    // Profile image state
    @Published var profileImageURL: String = ""
    @Published var selectedImage: UIImage?

    // Validation error strings (1:1 with viewModel.errorFullName / etc.)
    @Published var errorFullName: String?
    @Published var errorEmail: String?
    @Published var errorPhoneNumber: String?
    @Published var errorDob: String?

    // Form lifecycle flags — 1:1 with UIKit `isEdit`, `isProfileChanged`.
    @Published var isEdit: Bool = false
    @Published var isProfileChanged: Bool = false
    @Published var isWorking: Bool = false

    /// Canonical list used by the country picker — matches UIKit
    /// `allCountries = getAllCountries()`.
    @Published var allCountries: [Country] = []

    // MARK: - Derived
    var countryCodeDisplay: String { "+\(selectedCountry.dial_code)" }

    /// Display string MM/DD/YYYY for the DoB textfield (matches UIKit
    /// `convertToDateString(viewModel.dob)` → `MM/dd/yyyy`).
    var dobDisplay: String {
        guard let dob else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f.string(from: dob)
    }

    // MARK: - Profile load (ports getProfile + refreshProfile)
    //
    // Country resolution is a direct port of
    // `MyProfileViewController+ProfileSetup.swift::refreshProfile()` with
    // an ADDITIONAL dial-code fallback so an India user whose phone is
    // `+917743009671` resolves to India 🇮🇳 even if
    // `UserDefaultsClass.getCountryName()` is somehow nil (e.g. older
    // signup flows that only persisted the phone). This mirrors how the
    // UIKit signup/login path always stores the country alongside the
    // phone, but defends the profile screen against missing defaults.
    //
    // Resolution order:
    //   1. Exact case-insensitive name match on
    //      `UserDefaultsClass.getCountryName()`.
    //   2. If that fails, scan stored phone's leading `+NN…` prefix and
    //      match to the country with the longest-matching `dial_code`
    //      (greedy — dial codes range from 1 to 4 digits, so we test
    //      longest-first to distinguish e.g. +1 from +1876).
    //   3. Fallback to `defaultCountrySelection` (UIKit behaviour).
    func loadFromDefaults() {
        fullName = UserDefaultsClass.getName() ?? ""
        email    = UserDefaultsClass.getEmail() ?? ""
        profileImageURL = UserDefaultsClass.getProfileImage() ?? ""

        if allCountries.isEmpty { allCountries = CountryLoader.loadAll() }

        let rawPhone = UserDefaultsClass.getPhone() ?? ""
        let savedName = UserDefaultsClass.getCountryName()

        // 1 — Name match (UIKit's primary path).
        if let name = savedName,
           let country = allCountries.first(where: { $0.name.lowercased() == name.lowercased() }) {
            selectedCountry = country
            phone = rawPhone.replacingOccurrences(of: "+\(country.dial_code)", with: "")
        }
        // 2 — Dial-code fallback: derive country from the stored phone.
        else if let country = Self.countryMatching(phone: rawPhone, in: allCountries) {
            selectedCountry = country
            phone = rawPhone.replacingOccurrences(of: "+\(country.dial_code)", with: "")
            // Self-heal the persisted country name so future loads take
            // the fast path (UIKit-equivalent of re-saving after login).
            UserDefaultsClass.storeCountryName(country.name)
        }
        // 3 — UIKit fallback default (unitedStates).
        else {
            phone = rawPhone
        }

        // DoB — accept multiple formats like UIKit.
        if let raw = UserDefaultsClass.getDoB(), !raw.isEmpty {
            dob = Self.parseDate(raw)
        }
    }

    /// Greedy longest-prefix match on the stored phone number. Returns
    /// the `Country` whose `dial_code` appears right after the leading
    /// `+`. Matches India "+91…" → 🇮🇳, US "+1…" → 🇺🇸, etc.
    static func countryMatching(phone: String, in countries: [Country]) -> Country? {
        guard phone.hasPrefix("+") else { return nil }
        let digits = String(phone.dropFirst()) // drop the leading "+"
        // Sort by dial-code length DESC so we match +1876 (Jamaica) before +1 (US).
        let sorted = countries.sorted { $0.dial_code.count > $1.dial_code.count }
        for country in sorted where digits.hasPrefix(country.dial_code) {
            return country
        }
        return nil
    }

    static func parseDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd",
                       "yyyy-MM-dd'T'HH:mm:ssZ",
                       "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                       "MM/dd/yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    // MARK: - Validation (1:1 port of MyProfileViewModel.validateProfile)
    @discardableResult
    func validate() -> Bool {
        errorFullName = nil
        errorEmail = nil
        errorPhoneNumber = nil
        errorDob = nil

        if fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            errorFullName = Constants.pleaseEnterFullName
        }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errorEmail = Constants.pleaseEnterEmail
        } else if !Self.isValidEmail(trimmed) {
            errorEmail = Constants.invalidEmail
        }
        if dob == nil {
            errorDob = Constants.pleaseEnterDob
        } else if let dob {
            let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
            let required = Int(selectedCountry.age) ?? 21
            if age < required {
                errorDob = "You must be at least \(selectedCountry.age)+ years old to use this app."
            }
        }
        return errorFullName == nil && errorEmail == nil &&
               errorPhoneNumber == nil && errorDob == nil
    }

    static func isValidEmail(_ s: String) -> Bool {
        let rx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", rx).evaluate(with: s)
    }

    // MARK: - API endpoints (1:1 with UIKit `ApiConstants`)
    //
    //   GET    `baseUrlForRecipes + my/profile`        — fetch profile
    //   PATCH  `baseUrlForRecipes + my/profile`        — update profile
    //                                                    (JSON, includes
    //                                                    base64 profile_picture)
    //   PUT    `baseUrlForRecipes + my/profile/picture` — upload image
    //                                                    (multipart/form-data)
    //   DELETE `baseUrlForRecipes + my/profile`        — delete profile
    private static let baseURL =
        "https://defteros-service-47447659942.us-central1.run.app/api/v1/"
    private static let profilePath        = "my/profile"
    private static let profilePicturePath = "my/profile/picture"

    /// UIKit port: `Constants.sourceTypeBase64Str = "data:image/png;base64,"`.
    /// Prefix is `png` even though the payload is JPEG — this is the
    /// existing server contract (see `ImageClass.toBase64(format:)` which
    /// defaults to JPEG quality 0.6).
    private static let base64Prefix = "data:image/png;base64,"

    // MARK: - Networking helpers

    private func authorizedRequest(path: String,
                                   method: String,
                                   contentType: String = "application/json",
                                   timeout: TimeInterval = 60) -> URLRequest? {
        let token = UserDefaultsClass.getSessionToken() ?? ""
        guard !token.isEmpty,
              let url = URL(string: Self.baseURL + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Persists every field returned by the server to `UserDefaultsClass`,
    /// matching the UIKit `getProfile` / `updateProfile` completion block
    /// (lines 35-46 / 96-107 of `MyProfileApiService.swift`).
    private func persistResponse(_ model: MyProfileModel) {
        if let n = model.full_name, !n.isEmpty { UserDefaultsClass.storeName(n) }
        if let e = model.email, !e.isEmpty    { UserDefaultsClass.storeEmail(e) }
        if let u = model.profile_picture?.url, !u.isEmpty {
            UserDefaultsClass.storeProfileImage(u)
        }
        if let d = model.date_of_birth, !d.isEmpty { UserDefaultsClass.storeDoB(d) }
        if let p = model.phone, !p.isEmpty {
            UserDefaultsClass.storePhone(p)
        }
        UserProfileStore.shared.reload()
    }

    // MARK: - Fetch profile (GET /my/profile) — ports `getProfile`
    //
    // Called on `viewWillAppear` in UIKit when `isSelectedImageForProfile`
    // is false. Returns success only when `phone` is present (matches
    // UIKit completion-block condition).
    @discardableResult
    func fetchProfile() async -> Bool {
        guard let req = authorizedRequest(path: Self.profilePath, method: "GET") else {
            return false
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let model = try JSONDecoder().decode(MyProfileModel.self, from: data)
            persistResponse(model)
            // Reload UI state from the freshly persisted defaults.
            loadFromDefaults()
            return (model.phone?.isEmpty == false)
        } catch {
            return false
        }
    }

    // MARK: - Save (PATCH /my/profile + optional PUT /my/profile/picture)
    //
    // 1:1 port of `MyProfileViewModel.updateProfile` + controller's
    // `actionUpdate` branching:
    //
    //   • If user picked a NEW image:
    //       1. PUT /my/profile/picture with multipart/form-data
    //          ({"picture": <jpeg data>}).
    //       2. On success, PATCH /my/profile with JSON including the
    //          base64 profile_picture (legacy field kept for server
    //          compatibility — UIKit does this verbatim).
    //   • Else:
    //       Only PATCH /my/profile with empty profile_picture string.
    //
    // After either path succeeds, persist the server response, disable
    // edit mode, and show `Constants.profileUpdateMessage`.
    func save(env: AppEnvironment) async -> Bool {
        guard validate() else { return false }
        isWorking = true
        defer { isWorking = false }

        // DoB → yyyy-MM-dd (matches `DateFormatConstants.yearMonthDay`).
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let dobStr = dob.map { df.string(from: $0) } ?? ""

        // Determine branch — mirrors UIKit condition:
        //   (UserDefaultsClass.getProfileImage()?.isEmpty == true ||
        //    UserDefaultsClass.getProfileImage() == nil)
        //   && selectedImageForProfile == nil && selectedImage == nil
        //   → text-only PATCH.
        let existingProfileURL = UserDefaultsClass.getProfileImage() ?? ""
        let hasNewImage = (selectedImage != nil)
        let hasAnyImage = !existingProfileURL.isEmpty || hasNewImage

        var base64String: String = ""
        if hasAnyImage, let img = selectedImage,
           let jpeg = img.jpegData(compressionQuality: 0.6) {
            base64String = Self.base64Prefix + jpeg.base64EncodedString()
        }

        // Step 1 — multipart image upload when a NEW image was picked.
        if hasNewImage, let img = selectedImage {
            let ok = await uploadPictureOnly(image: img)
            if !ok {
                env.alerts.show(message: Constants.profileUpdateError)
                return false
            }
        }

        // Step 2 — PATCH /my/profile.
        guard var req = authorizedRequest(path: Self.profilePath, method: "PATCH") else {
            return false
        }
        let params: [String: String] = [
            "full_name":       fullName,
            "email":           email,
            "profile_picture": base64String,
            "date_of_birth":   dobStr
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: params,
                                                   options: [.prettyPrinted])

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                env.alerts.show(message: Constants.profileUpdateError)
                return false
            }
            // Decode + persist the fresh profile (same as UIKit completion).
            if let model = try? JSONDecoder().decode(MyProfileModel.self, from: data) {
                persistResponse(model)
                loadFromDefaults()
            }
            // Always also persist the country locally — it's not server-
            // owned (stored only in defaults, not in the response body).
            UserDefaultsClass.storeCountryName(selectedCountry.name)
            selectedImage = nil
            isEdit = false
            isProfileChanged = false
            env.analytics.track(TrackEventName.editProfileEvent.rawValue)
            // 1:1 with UIKit `MyProfileViewModel` L148, L164 calling
            // `TrackEventsClass().brazeUpdateProfile()` after a
            // successful PATCH so Braze re-syncs `firstName`, `email`,
            // `phoneNumber` for accurate IAM / push targeting.
            env.auth.syncBrazeProfile()
            env.alerts.show(message: Constants.profileUpdateMessage)
            return true
        } catch {
            env.alerts.show(message: error.localizedDescription)
            return false
        }
    }

    /// PUT /my/profile/picture — multipart/form-data upload.
    /// Ports `MyProfileApiService.updateProfileImageOnly(...)`.
    private func uploadPictureOnly(image: UIImage) async -> Bool {
        let boundary = UUID().uuidString
        guard var req = authorizedRequest(path: Self.profilePicturePath,
                                          method: "PUT",
                                          contentType: "multipart/form-data; boundary=\(boundary)") else {
            return false
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Self.multipartBody(image: image, boundary: boundary)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return false }
            // Server returns the same `MyProfileModel` shape with the new
            // picture URL — persist it so the image reload picks up.
            if let model = try? JSONDecoder().decode(MyProfileModel.self, from: data),
               let url = model.profile_picture?.url, !url.isEmpty {
                UserDefaultsClass.storeProfileImage(url)
                profileImageURL = url
                UserProfileStore.shared.reload()
            }
            return true
        } catch {
            return false
        }
    }

    /// Exact port of `MyProfileApiService.createMultipartBody(...)`:
    ///   - Boundary-wrapped single "picture" field carrying JPEG data
    ///     at quality 0.7 (UIKit literal).
    private static func multipartBody(image: UIImage, boundary: String) -> Data {
        var body = Data()
        if let imageData = image.jpegData(compressionQuality: 0.7) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"picture\"; filename=\"profile.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Delete (DELETE /my/profile) — ports `deleteProfile`
    //
    // Success = HTTP 204 in UIKit. We accept any 2xx here since the
    // server has occasionally shipped 200 with a body too.
    func deleteAccount(env: AppEnvironment) async {
        isWorking = true
        defer { isWorking = false }
        guard let req = authorizedRequest(path: Self.profilePath, method: "DELETE") else {
            return
        }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                env.analytics.track(TrackEventName.deleteProfileEvent.rawValue)
                // 1:1 with UIKit `TrackEventsClass.brazeDeleteUser(userID:)`
                // (TrackEventsClass.swift L188-200): clear PII, swap
                // user, `wipeData()` and disable the SDK so no further
                // events leak after the account is gone.
                BrazeService.shared.deleteUser(userId: env.auth.profile.id)
                UserDefaultsClass.clearAll()
            } else {
                env.alerts.show(message: Constants.profileUpdateError)
            }
        } catch {
            env.alerts.show(message: error.localizedDescription)
        }
    }
}

// MARK: - Server response model (1:1 with UIKit `MyProfileModel`)
//
// Lives in the same file so the ViewModel can decode without touching
// the core domain models. Mirrors the JSON shape exposed by
// `baseUrlForRecipes + my/profile`:
//   { id, user_id, full_name, email, phone, date_of_birth,
//     profile_picture: { url }, created_at, updated_at }

private struct MyProfileModel: Codable {
    let id: String?
    let user_id: String?
    let full_name: String?
    let email: String?
    let phone: String?
    let date_of_birth: String?
    let profile_picture: ProfileImageModel?
    let created_at: String?
    let updated_at: String?
}

private struct ProfileImageModel: Codable {
    let url: String?
}

// MARK: - Data helper
private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

// MARK: - View

struct MyProfileView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService
    @StateObject private var viewModel = MyProfileViewModel()

    /// Observe the shared profile store so external writes (login flow,
    /// side-menu edits, background re-fetches) trigger an immediate
    /// reload of this screen's view-model state. Mirrors the UIKit side
    /// effect where `viewWillAppear → viewModel.getProfile()` would
    /// re-pull on every foreground cycle.
    @ObservedObject private var profileStore = UserProfileStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showImageSourceSheet = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showDeleteConfirm = false
    @State private var showDatePicker = false
    @State private var showCountryPicker = false

    @FocusState private var focusedField: EditableField?
    enum EditableField: Hashable { case name, email, dob }

    private var isConnected: Bool { ble.isAnyDeviceConnected }
    private var deviceIconName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected()    { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }
    private var deviceKindName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected()    { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    // Update button enabled when ANY edit occurred (matches UIKit `isEdit`).
    private var isUpdateEnabled: Bool { viewModel.isEdit && !viewModel.isWorking }

    var body: some View {
        ZStack(alignment: .top) {
            Color("primaryBackgroundColor").ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title (`cz5-bS-UCa`): leading 24, top 18.
                        Text("My Profile")
                            .font(.system(size: 24))
                            .foregroundStyle(Color("appBlackColor"))
                            .padding(.leading, 24)
                            .padding(.top, 18)

                        profileImageBlock
                            .padding(.top, 10)

                        formStack
                            .padding(.leading, 20)
                            .padding(.trailing, 20)
                            .padding(.top, 45) // 6NM-Az-0yE top=PZN.bottom+45

                        bottomButtons
                            .padding(.leading, 20)
                            .padding(.trailing, 20)
                            .padding(.top, 30) // stackView spacing=30

                        deleteRow
                            .padding(.leading, 20)
                            .padding(.trailing, 20)
                            .padding(.top, 30)
                            .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        // Flat `primaryBackgroundColor` nav bar so the top-right glass
        // pill matches HomeView / ChooseOptions exactly.
        .chooseOptionsStyleNavBar()
        // UIKit parity:
        //   viewDidLoad    → setupView() reads UserDefaults.
        //   viewWillAppear → if !isSelectedImageForProfile { viewModel.getProfile() }
        //                    which re-fetches /my/profile and calls refreshProfile().
        // Guard with `isProfileChanged` so we DON'T clobber an in-flight
        // local image pick (mirrors the `isSeletedImageForProfile` flag).
        .onAppear {
            viewModel.loadFromDefaults()
            if !viewModel.isProfileChanged {
                Task { await viewModel.fetchProfile() }
            }
        }
        // Re-sync whenever the shared profile store publishes new
        // values (login, side-menu edit, other screens). This runs on
        // main actor and is safe because `loadFromDefaults()` is idempotent.
        .onReceive(profileStore.$profileImageURL) { _ in
            if !viewModel.isProfileChanged { viewModel.loadFromDefaults() }
        }
        .onReceive(profileStore.$name) { _ in
            if !viewModel.isEdit { viewModel.loadFromDefaults() }
        }
        // UIKit equivalent of `showActionSheetForImagePicker()`.
        .confirmationDialog("Select Image",
                            isPresented: $showImageSourceSheet,
                            titleVisibility: .hidden) {
            Button("Camera")      { imagePickerSource = .camera;       showImagePicker = true }
            Button("Photo Library") { imagePickerSource = .photoLibrary; showImagePicker = true }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showImagePicker) {
            BarBotImagePicker(image: $viewModel.selectedImage, source: imagePickerSource)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selection: Binding(
                get: { viewModel.dob ?? Date() },
                set: { _ in }),
                onDone: { date in
                    viewModel.dob = date
                    viewModel.isEdit = true
                    viewModel.errorDob = nil
                }
            )
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(countries: viewModel.allCountries,
                               selection: $viewModel.selectedCountry)
        }
        // UIKit `showCustomAlertMultipleButtons(title: areYouSureYouWantToDeleteAccount,
        //   subTitleStr: deleteTheAccountAlertMessage, …)`
        .alert(Constants.areYouSureYouWantToDeleteAccount,
               isPresented: $showDeleteConfirm) {
            // UIKit uses `ConstantButtonsTitle.donotDeleteTitle` ("Do not
            // delete") here; it's not defined in SwiftUI Constants so we
            // hard-code the same literal to stay 1:1 with the alert UX.
            Button("Do not delete", role: .cancel) {}
            Button(ConstantButtonsTitle.yesButtonTitle, role: .destructive) {
                Task {
                    await viewModel.deleteAccount(env: env)
                    router.logout()
                }
            }
        } message: {
            Text(Constants.deleteTheAccountAlertMessage)
        }
        .onChange(of: viewModel.selectedImage) { new in
            if new != nil { viewModel.isEdit = true; viewModel.isProfileChanged = true }
        }
        // When the user picks a new country from the sheet, flip `isEdit`
        // so the "Update" button enables — the country code IS a real
        // profile change even though UIKit's `actionFlag(_:)` is empty.
        // Also persist the selection immediately to `UserDefaultsClass`
        // so the next cold launch resolves to the newly chosen country
        // even before the user taps Update. Mirrors the UIKit signup
        // flow where `storeCountryName(...)` runs alongside any phone
        // change.
        .onChange(of: viewModel.selectedCountry) { newCountry in
            viewModel.isEdit = true
            UserDefaultsClass.storeCountryName(newCountry.name)
        }
    }

    // MARK: - Toolbar (ports top bar Bbr-0Z-CP5)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Back `Ljh-md-9Wa` — leading chevron.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticService.light()
                dismiss()
            } label: {
                Image("back")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color("appBlackColor"))
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Back")
        }
        // Device ICON ONLY centered (7EI-ic-Ob3) — only when connected.
        //
        // UIKit parity — MyProfileViewController.swift:200 sets
        // `lblDeviceName.isHidden = true` and never reverses it. Only
        // the 25×25 `imgDevice` renders in the centre of the nav bar.
        if isConnected {
            ToolbarItem(placement: .principal) {
                Image(deviceIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .accessibilityLabel(deviceKindName)
            }
        }
        // Trailing glass pill with favourite + side-menu icons —
        // shared 100×48 glass pill (iOS 26+) / bare 61×24 icon stack
        // (pre-26). 1:1 UIKit `navigationRightGlassView` parity.
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

    // MARK: - Profile image (ports PZN-LG-6hy + dXy-hd-NhR)
    //
    //   • 126×126 circular, centered horizontally.
    //   • backgroundColor `.white` (storyboard) — placeholder silhouette
    //     from `icon_profile.png` asset; replaced by the user's avatar
    //     when selected or returned from the API.
    //   • Add-image button uses `icon_plus` asset (NOT an SF Symbol)
    //     and overlaps the circle at its trailing-bottom corner.
    @ViewBuilder private var profileImageBlock: some View {
        ZStack {
            // Absolute positioning: centered horizontally, plus button
            // offset to match storyboard frame x=259.66 y=112 relative
            // to the 393pt viewport (profile center at 196.5pt).
            HStack {
                Spacer(minLength: 0)
                ZStack(alignment: .bottomTrailing) {
                    profileImage
                        .frame(width: 126, height: 126)
                        // `Theme.Color.surface` light = pure white
                        // sRGB(1, 1, 1), bit-identical to the previous
                        // hard-coded `Color.white`, so light mode
                        // renders the EXACT same white profile-circle
                        // bg. Dark mode picks up the elevated dark
                        // surface (#2C2C2E) so the avatar circle is
                        // visible against the dark profile page
                        // canvas instead of disappearing.
                        .background(Theme.Color.surface)
                        .clipShape(Circle())

                    Button {
                        HapticService.light()
                        viewModel.isProfileChanged = true
                        showImageSourceSheet = true
                    } label: {
                        Image("icon_plus")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityLabel("Change profile picture")
                    // Storyboard: btnAddImage bottom anchored to imgProfile
                    // bottom, leading just outside the circle's trailing
                    // edge → translated to a -2pt offset so it sits on
                    // the circle border rather than outside it.
                    .offset(x: -2, y: -2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 140)
    }

    @ViewBuilder private var profileImage: some View {
        if let picked = viewModel.selectedImage {
            Image(uiImage: picked)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if !viewModel.profileImageURL.isEmpty,
                  let url = URL(string: viewModel.profileImageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    // UIKit uses `icon_profile.png` asset as placeholder.
                    Image("icon_profile.png")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
        } else {
            Image("icon_profile.png")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    // MARK: - Form stack (6NM-Az-0yE — spacing 30)

    @ViewBuilder private var formStack: some View {
        VStack(spacing: 30) {
            // Row 1 — Name
            profileRow(label: "Name",
                       labelColor: nil,
                       field: .name,
                       errorText: viewModel.errorFullName,
                       input: {
                textField(text: $viewModel.fullName,
                          placeholder: "Your Full Name",
                          keyboard: .default,
                          field: .name)
            },
                       showPencil: true,
                       onEdit: { focusedField = .name })

            // Row 2 — Phone No. (lightGrayColor label)
            profileRow(label: "Phone No.",
                       labelColor: Color("lightGrayColor"),
                       field: nil,
                       errorText: viewModel.errorPhoneNumber,
                       input: { phoneInput },
                       showPencil: false,
                       onEdit: {})

            // Row 3 — Email
            profileRow(label: "Email",
                       labelColor: nil,
                       field: .email,
                       errorText: viewModel.errorEmail,
                       input: {
                textField(text: $viewModel.email,
                          placeholder: "Your Email",
                          keyboard: .emailAddress,
                          field: .email)
            },
                       showPencil: true,
                       onEdit: { focusedField = .email })

            // Row 4 — DoB
            profileRow(label: "DoB",
                       labelColor: nil,
                       field: .dob,
                       errorText: viewModel.errorDob,
                       input: { dobInput },
                       showPencil: true,
                       onEdit: { showDatePicker = true })
        }
    }

    // MARK: - Single horizontal row
    //
    // 90pt label on the left, 263pt input stack on the right. Below the
    // input: 1pt underline (paleBlueGrayColor default / errorLabelColor
    // on validation failure), then the hidden error label (13pt bold).
    @ViewBuilder
    private func profileRow<Input: View>(label: String,
                                         labelColor: Color?,
                                         field: EditableField?,
                                         errorText: String?,
                                         @ViewBuilder input: () -> Input,
                                         showPencil: Bool,
                                         onEdit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(labelColor ?? Color("appBlackColor"))
                    .frame(width: 90, alignment: .leading)
                    // Label is baseline-aligned with the textfield (UIKit
                    // uses `firstItem.bottom = textField.bottom`).
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        input()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 40)

                        if showPencil {
                            Button {
                                HapticService.light()
                                viewModel.isEdit = true
                                onEdit()
                            } label: {
                                Image("icon_edit")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityLabel("Edit \(label.lowercased())")
                        }
                    }
                    // Underline — 1pt paleBlueGray / errorLabelColor.
                    Rectangle()
                        .fill(errorText == nil
                              ? Color("paleBlueGrayColor")
                              : Color("errorLabelColor"))
                        .frame(height: 1)
                }
            }

            if let err = errorText, !err.isEmpty {
                // Hidden by default — storyboard label 13pt bold,
                // errorLabelColor; appears indented to match the field
                // (after the 90pt label).
                HStack {
                    Spacer().frame(width: 90)
                    Text(err)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color("errorLabelColor"))
                }
            }
        }
    }

    // MARK: - Primitive inputs

    // Plain textfield: system 17pt appBlackColor. Disabled unless the
    // matching edit pencil has been tapped (`isEdit`-gated doesn't
    // work here; UIKit toggles `isUserInteractionEnabled` on the
    // specific field, so we track focus per row).
    @ViewBuilder
    private func textField(text: Binding<String>,
                           placeholder: String,
                           keyboard: UIKeyboardType,
                           field: EditableField) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 17))
            .foregroundStyle(Color("appBlackColor"))
            .keyboardType(keyboard)
            .textContentType(keyboard == .emailAddress ? .emailAddress : .name)
            .autocapitalization(keyboard == .emailAddress ? .none : .words)
            .focused($focusedField, equals: field)
            .onChange(of: text.wrappedValue) { _ in
                viewModel.isEdit = true
                if field == .name  { viewModel.errorFullName = nil }
                if field == .email { viewModel.errorEmail    = nil }
            }
            .accessibilityLabel(placeholder)
    }

    // Phone input — matches UIKit `PEj-hh-RQX` / `tGr-RM-hcQ`:
    //   flag (35pt) + downArrow (25pt, template) + code (17pt light) +
    //   numberPad textfield (17pt, `lightGrayColor` text).
    //
    // COUNTRY PICKER FIX: UIKit's `actionFlag(_:)` is intentionally empty
    // (country changes happen during signup / login only). But the
    // product now expects the country to be editable from the profile
    // screen too, so we wire the full flag + arrow + code cluster up
    // to `showCountryPicker = true`. `contentShape(Rectangle())` makes
    // empty spacing inside the HStack hit-testable, and `.plain`
    // buttonStyle keeps the tap area identical to the visible label.
    @ViewBuilder private var phoneInput: some View {
        HStack(spacing: 7) {
            Button {
                HapticService.light()
                showCountryPicker = true
            } label: {
                HStack(spacing: 0) {
                    Text(viewModel.selectedCountry.flag)
                        .font(.system(size: 35))
                    Image("downArrowSmall")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 25)
                        .foregroundStyle(Color("lightGrayColor"))
                    Text(viewModel.countryCodeDisplay)
                        .font(.system(size: 17, weight: .light))
                        // UIKit `qPl-l8-7SS` textColor white 0.666 alpha 1.
                        .foregroundStyle(Color(white: 0.666))
                        .padding(.leading, 3)
                }
                // Hit-test the ENTIRE cluster, not just the glyphs —
                // UIKit `TlM-dI-cCu` is a 171×42 transparent button
                // layered on top of the flag stack.
                .frame(height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select country")
            .accessibilityHint("Opens a country picker")

            TextField("Phone no.", text: $viewModel.phone)
                .font(.system(size: 17))
                // UIKit: `txtPhoneNumber.textColor = .lightGrayColor`
                // (phone stays greyed, not edited in this screen).
                .foregroundStyle(Color("lightGrayColor"))
                .keyboardType(.numberPad)
                .disabled(true)
                .accessibilityLabel("Phone number")
        }
    }

    // DoB input — DatePickerManager-triggered textfield. Displayed as
    // MM/DD/YYYY to match `convertToDateString`. Tap opens the date
    // picker sheet (or the pencil does).
    @ViewBuilder private var dobInput: some View {
        Button {
            HapticService.light()
            viewModel.isEdit = true
            showDatePicker = true
        } label: {
            HStack(spacing: 0) {
                Text(viewModel.dobDisplay.isEmpty ? "MM/DD/YYYY" : viewModel.dobDisplay)
                    .font(.system(size: 17))
                    .foregroundStyle(viewModel.dobDisplay.isEmpty
                                     ? Color("lightGrayColor")
                                     : Color("appBlackColor"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date of birth")
    }

    // MARK: - Bottom buttons (wBo-Ct-8rR + V73-UU-NiR)
    //
    //   • Ok   — white bg, appBlackColor title, 1pt craftButtonBorderColor,
    //            `roundCorners: 8`, 166.66×45.
    //   • Update — segmentSelectionColor bg, appBlackColor title, 0.5
    //              alpha until user edits, `roundCorners: 8`.
    @ViewBuilder private var bottomButtons: some View {
        HStack(spacing: 20) {
            // OK — pops back. Matches UIKit `actionOk(_:)` →
            // `navigationController?.popViewController(animated: true)`.
            // OK — ports applyCancelCapsuleGradientBorderStyle():
            // iOS 26+: glass capsule + gradient border
            // Pre-26: white fill + craftButtonBorderColor 1pt stroke
            Button {
                HapticService.light()
                dismiss()
            } label: {
                Text("Ok")
                    .cancelCapsule(height: 45, cornerRadius: 22.5,
                                   textColor: Color("appBlackColor"))
                    .font(.system(size: 14))
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("OK")

            // Update — port of PrimaryOrangeButton behaviour:
            //   initial alpha 0.5 + not tappable; flips to alpha 1.0 +
            //   tappable only after any field is edited (`isEdit`).
            Button {
                HapticService.light()
                Task { _ = await viewModel.save(env: env) }
            } label: {
                // Ports PrimaryOrangeButton.makeOrangeStyle():
                // iOS 26+: brand gradient capsule, pre-26: flat segmentSelectionColor
                Text("Update")
                    .font(.system(size: 14))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(profileOrangeButtonBackground)
            }
            .buttonStyle(BounceButtonStyle())
            .disabled(!isUpdateEnabled)
            .opacity(isUpdateEnabled ? 1.0 : 0.5)
            .accessibilityLabel("Update profile")
        }
    }

    /// Ports PrimaryOrangeButton.makeOrangeStyle() for profile update button.
    @ViewBuilder
    private var profileOrangeButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color("brandGradientTop"), Color("brandGradientBottom")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                .fill(Color("segmentSelectionColor"))
        }
    }

    // MARK: - Delete row (bOD-ma-2Ne) — 98×43 trailing-aligned
    //                                     UNDERLINED "Delete account",
    //                                     system 14pt `appBlackColor`.
    @ViewBuilder private var deleteRow: some View {
        HStack {
            Spacer()
            Button {
                HapticService.light()
                showDeleteConfirm = true
            } label: {
                Text("Delete account")
                    .font(.system(size: 14))
                    .underline()
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(width: 98, height: 43)
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel("Delete account")
        }
    }
}

// MARK: - Date Picker Sheet (ports DatePickerManager in .date mode)

private struct DatePickerSheet: View {
    @Binding var selection: Date
    var onDone: (Date) -> Void
    @State private var local: Date
    @Environment(\.dismiss) private var dismissSheet

    init(selection: Binding<Date>, onDone: @escaping (Date) -> Void) {
        self._selection = selection
        self.onDone = onDone
        self._local = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Date of Birth",
                           selection: $local,
                           in: ...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                Spacer(minLength: 0)
            }
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismissSheet() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone(local); dismissSheet() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Country Picker Sheet (ports `allCountries` picker)

private struct CountryPickerSheet: View {
    let countries: [Country]
    @Binding var selection: Country
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Country] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return countries }
        return countries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { country in
                    Button {
                        selection = country
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(country.flag).font(.system(size: 28))
                            Text(country.name)
                                .font(.system(size: 16))
                                .foregroundStyle(Color("appBlackColor"))
                            Spacer()
                            Text("+\(country.dial_code)")
                                .font(.system(size: 14))
                                .foregroundStyle(Color("mediumGrayColor"))
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search country")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
