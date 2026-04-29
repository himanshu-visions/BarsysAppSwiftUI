//
//  OryAPIClient.swift
//  BarsysAppSwiftUI
//
//  Real APIClient implementation that calls the Ory backend used by the
//  UIKit BarsysApp. Direct port of:
//   - BarsysApp/Controllers/Login/LoginSignUpOryApiService.swift
//   - BarsysApp/Controllers/Login/LoginSignUpOryApiService+Registration.swift
//   - BarsysApp/Helpers/Constants/ApiConstants.swift (OryAPI / GlobalConstants)
//
//  Endpoints (verified from EnvironmentConfig.generated.swift):
//    base       https://api-ng.barsys.com/api/
//    base ory   https://iam.auth.barsys.com/self-service/
//
//  Login flow:
//    1. GET  {baseUrlOry}login/api?return_to=%2Fwebcredentials:iam.auth.barsys.com)
//       → returns { id: flowId, ui: { nodes: [{ attributes: { name: "csrf_token", value: ... }}]}}
//    2. POST {baseUrlOry}login?flow={flowId}
//       body: { method: "code", csrf_token: <csrf>, identifier: <phone> }
//       → on success the response.ui.messages[0].text says OTP sent
//    3. POST {baseUrlOry}login?flow={flowId}
//       body: { method: "code", csrf_token: <csrf>, identifier: <phone>, code: <otp> }
//       → on success: session_token + session.identity.traits.{email,phone,name,dob}
//
//  Test phone bypass: +917042199800 with hardcoded OTP "381260" (Constants.testPhoneNumber).
//

import Foundation

final class OryAPIClient: APIClient {

    // MARK: - Endpoint constants (mirror BarsysApp/Helpers/Constants)

    private enum Endpoint {
        static let baseUrl    = "https://api-ng.barsys.com/api/"
        static let baseUrlOry = "https://iam.auth.barsys.com/self-service/"
        static let iAmAuthBarsys = "iam.auth.barsys.com"

        // Note: the trailing ")" matches the literal in OryAPI.swift verbatim.
        static var getFlowIdForLogin: String {
            "login/api?return_to=%2Fwebcredentials:\(iAmAuthBarsys))"
        }
        static var getFlowIdForSignUp: String {
            "registration/api?return_to=%2Fsuccess)"
        }
        static let sendAndVerifyOtpForLogin = "login?flow="
        static let sendAndVerifyOtpForRegister = "registration?flow="
    }

    // MARK: - Stored flow / csrf for the current login or signup attempt

    /// Mirrors `LoginSignUpViewModel.userData` — flowId + csrf are kept across
    /// the send→verify call pair so the second call uses the same Ory flow.
    private actor FlowState {
        var flowId: String = ""
        var csrfToken: String = ""

        func update(flowId: String, csrf: String) {
            self.flowId = flowId
            self.csrfToken = csrf
        }
        func clear() {
            flowId = ""
            csrfToken = ""
        }
    }

    private let loginFlow = FlowState()
    private let signUpFlow = FlowState()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - APIClient protocol

    /// Login: send OTP. Mirrors `sendLoginOtpWithOry(phone:)`.
    func sendOtp(phone: String) async throws {
        // Test phone shortcut — matches LoginViewModel.isTestPhoneNumber path.
        if phone == Constants.testPhoneNumber {
            await loginFlow.update(flowId: "TEST", csrf: "TEST")
            return
        }

        // Step 1: get flowId + csrf
        let (flowId, csrf) = try await fetchFlowId(endpoint: Endpoint.getFlowIdForLogin)
        await loginFlow.update(flowId: flowId, csrf: csrf)

        // Step 2: send OTP
        let body: [String: Any] = [
            "method": "code",
            "csrf_token": csrf,
            "identifier": phone
        ]
        let url = URL(string: "\(Endpoint.baseUrlOry)\(Endpoint.sendAndVerifyOtpForLogin)\(flowId)")!
        let parsed = try await postOry(url: url, body: body)

        let text = parsed.ui?.messages?.first?.text ?? ""
        let kind = OryMessageMatcher.identify(text)
        switch kind {
        case .otpSent:
            return
        case .accountNotFound:
            throw AppError.network(Constants.accountDoesNotExist)
        case .invalidPhone:
            throw AppError.network(Constants.pleaseEnterValidPhoneNum)
        case .other:
            throw AppError.network(text.isEmpty ? Constants.loginError : text)
        }
    }

    /// Login: verify OTP. Mirrors `verifyOtpForLoginOry(code:phone:)`.
    func verifyOtp(phone: String, code: String) async throws -> UserProfile {
        // Test phone bypass.
        if phone == Constants.testPhoneNumber {
            guard code == Constants.testPhoneNumberOtp else {
                throw AppError.invalidCredentials
            }
            return UserProfile(id: "test-user",
                               firstName: "Test",
                               lastName: "User",
                               email: "test@barsys.com",
                               phone: phone,
                               countryCode: "IN")
        }

        let flowId = await loginFlow.flowId
        let csrf = await loginFlow.csrfToken
        guard !flowId.isEmpty else { throw AppError.network(Constants.loginError) }

        let body: [String: Any] = [
            "method": "code",
            "csrf_token": csrf,
            "identifier": phone,
            "code": code
        ]
        let url = URL(string: "\(Endpoint.baseUrlOry)\(Endpoint.sendAndVerifyOtpForLogin)\(flowId)")!
        let parsed = try await postOry(url: url, body: body)

        // The Ory response uses session.identity.verifiable_addresses[].status
        // — successful login has status "completed" or "sent". Match the same
        // logic as verifyOTPForLoginOry().
        let addresses = parsed.session?.identity?.verifiableAddresses ?? []
        let completedStatus = addresses.first(where: { $0.status?.lowercased() == "completed" })?.status
            ?? addresses.last?.status
            ?? ""

        if let reason = parsed.error?.reason,
           !reason.isEmpty,
           OryMessageMatcher.isFlowExpired(reason) {
            throw AppError.network(reason)
        }

        guard completedStatus.lowercased() == "completed" || completedStatus.lowercased() == "sent" else {
            let msg = parsed.ui?.messages?.first?.text ?? Constants.invalidOTP
            throw AppError.network(msg)
        }

        // Persist every field the UIKit verifyOTPForLoginOry persists via
        // UserDefaultsClass. The home screen greeting reads getName() from
        // here, and reconnect logic reads getPhone() / getLastConnectedDevice().
        let traits = parsed.session?.identity?.traits
        UserDefaultsClass.storeSessionToken(parsed.sessionToken)
        UserDefaultsClass.storeSessionId(parsed.session?.sessionId)
        UserDefaultsClass.storeUserId(parsed.session?.identity?.identityId)
        UserDefaultsClass.storeName(traits?.name?.first ?? "")
        UserDefaultsClass.storePhone(traits?.phone ?? phone)
        UserDefaultsClass.storeEmail(traits?.email ?? "")
        UserDefaultsClass.storeDoB(traits?.dob ?? "")

        return UserProfile(
            id: parsed.session?.identity?.identityId ?? UUID().uuidString,
            firstName: traits?.name?.first ?? "",
            lastName: "",
            email: traits?.email ?? "",
            phone: traits?.phone ?? phone,
            countryCode: ""
        )
    }

    /// Email + password login is not part of the real Ory flow — keep it as
    /// a stub that throws so the SwiftUI screen can warn the user. (The real
    /// UIKit app uses phone+OTP only via the Ory flow.)
    func login(email: String, password: String) async throws -> UserProfile {
        throw AppError.network("Email/password login is not supported. Please sign in with your phone number.")
    }

    /// Sign up: send OTP after collecting form fields.
    /// Mirrors `sendRegisterationOtpWithOry(phone:email:fullNameText:dobStr:)`.
    func signUp(firstName: String, lastName: String, email: String, phone: String, dob: Date?) async throws -> UserProfile {
        // The UIKit flow has two steps for signup. The "signUp" call here is
        // shaped for the SwiftUI view's "verify and register" tap, which
        // happens AFTER OTP entry. We assume the SwiftUI signup view first
        // calls sendOtp(...) just like the login view, then calls signUp(...)
        // to verify the OTP and create the account.
        //
        // For now, fall back to the email-mode error so the UI surfaces a
        // clear message until the SignUp view is wired to the dedicated
        // signup endpoints below (sendRegistrationOtp / verifyRegistrationOtp).
        throw AppError.network("Use sendRegistrationOtp / verifyRegistrationOtp for sign-up.")
    }

    /// Real "send registration OTP" endpoint. Call this from SignUpView when
    /// the user taps "Get OTP".
    func sendRegistrationOtp(fullName: String,
                             email: String,
                             phone: String,
                             dobStr: String) async throws {
        // Get the signup flow id + csrf
        let (flowId, csrf) = try await fetchFlowId(endpoint: Endpoint.getFlowIdForSignUp)
        await signUpFlow.update(flowId: flowId, csrf: csrf)

        var traits: [String: Any] = [
            "name": ["first": fullName, "last": ""],
            "termsofuse": true,
            "privacypolicy": true,
            "dob": dobStr
        ]
        if !phone.isEmpty { traits["phone"] = phone }
        traits["email"] = email

        let body: [String: Any] = [
            "method": "code",
            "csrf_token": csrf,
            "traits": traits
        ]
        let url = URL(string: "\(Endpoint.baseUrlOry)\(Endpoint.sendAndVerifyOtpForRegister)\(flowId)")!
        let parsed = try await postOry(url: url, body: body)

        var text = parsed.ui?.messages?.first?.text ?? ""
        if text.isEmpty { text = parsed.ui?.nodes?.first?.messages?.first?.text ?? "" }
        text = text.replacingOccurrences(of: "\"", with: "")
        let kind = OryMessageMatcher.identify(text)
        switch kind {
        case .otpSent: return
        case .invalidPhone:
            throw AppError.network(Constants.pleaseEnterValidPhoneNum)
        default:
            throw AppError.network(text.isEmpty ? Constants.signUpError : text)
        }
    }

    /// Real "verify registration OTP" endpoint. Call this from SignUpView
    /// when the user taps "Register" after entering the 6-digit code.
    func verifyRegistrationOtp(fullName: String,
                               email: String,
                               phone: String,
                               otp: String,
                               dobStr: String) async throws -> UserProfile {
        let flowId = await signUpFlow.flowId
        let csrf = await signUpFlow.csrfToken
        guard !flowId.isEmpty else { throw AppError.network(Constants.signUpError) }

        var traits: [String: Any] = [
            "termsofuse": true,
            "privacypolicy": true,
            "dob": dobStr,
            "name": ["first": fullName, "last": ""]
        ]
        if !phone.isEmpty { traits["phone"] = phone }
        if !email.isEmpty { traits["email"] = email }

        let body: [String: Any] = [
            "method": "code",
            "csrf_token": csrf,
            "traits": traits,
            "code": otp
        ]
        let url = URL(string: "\(Endpoint.baseUrlOry)\(Endpoint.sendAndVerifyOtpForRegister)\(flowId)")!
        let parsed = try await postOry(url: url, body: body)

        // Status resolution — 1:1 with UIKit
        // `VerifyOtpToRegisterUser` in BarsysApp. A successful registration
        // often returns the identity at the TOP level (`identity`, decoded
        // here as `signUpIdentity`) with NO `session` object yet — only
        // checking `session.identity.verifiable_addresses` would leave
        // status empty and throw a bogus "Unable to…" error even though
        // the account was created. Match UIKit's two-path resolve exactly:
        //   1. Start from `session.identity.verifiable_addresses.last.status`.
        //   2. If empty → search `signUpIdentity.verifiable_addresses` for a
        //      "completed" entry and use that.
        //   3. Otherwise → still check `session.identity.verifiable_addresses`
        //      for a "completed" entry so it wins over a non-terminal "last".
        var status = parsed.session?.identity?.verifiableAddresses?.last?.status ?? ""
        if status.isEmpty {
            if let completed = parsed.signUpIdentity?.verifiableAddresses?
                .first(where: { ($0.status ?? "").lowercased() == "completed" })?.status {
                status = completed
            }
        } else {
            if let completed = parsed.session?.identity?.verifiableAddresses?
                .first(where: { ($0.status ?? "").lowercased() == "completed" })?.status {
                status = completed
            }
        }

        // Flow expired is surfaced via `error.reason` — match UIKit and
        // bubble the Ory-supplied reason string verbatim.
        if let reason = parsed.error?.reason,
           !reason.isEmpty,
           OryMessageMatcher.isFlowExpired(reason) {
            throw AppError.network(reason)
        }

        // "User already exists" is delivered as a ui.messages entry (NOT in
        // `error.reason`). Map it to the canonical constant so the UI shows
        // a stable, translatable string instead of Ory's raw wording.
        if let uiMsg = parsed.ui?.messages?.first?.text,
           OryMessageMatcher.matchesUserAlreadyExists(uiMsg) {
            throw AppError.network(Constants.userAlreadyExists)
        }

        // UIKit only treats "completed" as success here (not "sent"); "sent"
        // means the OTP was dispatched but the identity isn't verified yet,
        // so accepting it would register unverified users.
        guard status.lowercased() == "completed" else {
            let msg = parsed.ui?.messages?.first?.text ?? Constants.signUpError
            throw AppError.network(msg)
        }

        // Persist everything to UserDefaultsClass — same as UIKit registration
        // success branch (sendRegisterationOtpWithOry completion → stores
        // session token / name / email / phone / dob via UserDefaultsClass).
        // Prefer `session.identity` when present, otherwise fall back to
        // `signUpIdentity` — some Ory responses carry identity info only at
        // the top level right after registration.
        let identityResp = parsed.session?.identity ?? parsed.signUpIdentity
        let traitsResp = identityResp?.traits
        UserDefaultsClass.storeSessionToken(parsed.sessionToken)
        UserDefaultsClass.storeSessionId(parsed.session?.sessionId)
        UserDefaultsClass.storeUserId(identityResp?.identityId)
        UserDefaultsClass.storeName(traitsResp?.name?.first ?? fullName)
        UserDefaultsClass.storePhone(traitsResp?.phone ?? phone)
        UserDefaultsClass.storeEmail(traitsResp?.email ?? email)
        UserDefaultsClass.storeDoB(traitsResp?.dob ?? dobStr)

        return UserProfile(
            id: identityResp?.identityId ?? UUID().uuidString,
            firstName: traitsResp?.name?.first ?? fullName,
            lastName: "",
            email: traitsResp?.email ?? email,
            phone: traitsResp?.phone ?? phone,
            countryCode: ""
        )
    }

    // MARK: - Profile / catalog (unchanged from MockAPIClient for now)

    func fetchProfile() async throws -> UserProfile {
        // Reads whatever the last verifyOtp / verifyRegistrationOtp stored
        // locally so the home screen always has SOMETHING to show even if
        // the network is down. Real UIKit does a POST to my/profile here —
        // TODO: port MyProfileApiService.getProfile when MyProfile screen is
        // fully ported.
        UserProfile(
            id: UserDefaultsClass.getUserId() ?? "me",
            firstName: UserDefaultsClass.getName() ?? "",
            lastName: "",
            email: UserDefaultsClass.getEmail() ?? "",
            phone: UserDefaultsClass.getPhone() ?? "",
            countryCode: UserDefaultsClass.getCountryName() ?? ""
        )
    }

    func updateProfile(_ profile: UserProfile) async throws {
        // TODO: wire to my/profile PATCH endpoint when MyProfile screen is fully ported.
    }

    /// Ports MyProfileApiService.getProfile().
    /// Endpoint: GET {recipesBaseURL}my/profile
    /// Fetches full profile (name, email, DOB, profile picture URL) and stores in UserDefaults.
    /// Called after login success to sync full profile data.
    func fetchAndSyncProfile() async {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { return }
        let urlStr = Self.recipesBaseURL + "my/profile"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // 1:1 with UIKit `NetworkingUtility.validateResponse` — a 401
            // OR a 200 whose body contains "expired session token" both
            // mean the Ory session has lapsed. Hand off to the shared
            // handler (deduped across concurrent 401s) and bail so we
            // don't try to decode an empty / error body as a profile.
            if await SessionExpirationCheck.inspectAndHandle(response: response, data: data) {
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[OryAPIClient] Profile fetch failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }

            // Decode profile response matching UIKit MyProfileModel
            struct ProfileResponse: Decodable {
                let full_name: String?
                let email: String?
                let date_of_birth: String?
                let phone: String?
                let profile_picture: ProfilePicture?
                let country: String?

                struct ProfilePicture: Decodable {
                    let url: String?
                }
            }

            let profile = try JSONDecoder().decode(ProfileResponse.self, from: data)

            // Store to UserDefaults (ports MyProfileApiService getProfile callback)
            if let name = profile.full_name, !name.isEmpty {
                UserDefaultsClass.storeName(name)
            }
            if let email = profile.email, !email.isEmpty {
                UserDefaultsClass.storeEmail(email)
            }
            if let dob = profile.date_of_birth, !dob.isEmpty {
                UserDefaultsClass.storeDoB(dob)
            }
            if let picUrl = profile.profile_picture?.url, !picUrl.isEmpty {
                UserDefaultsClass.storeProfileImage(picUrl)
            }
            if let country = profile.country, !country.isEmpty {
                // Don't stomp the user's login-time picker selection.
                // UIKit `MyProfileViewController+ProfileSetup` only
                // writes the server country when no local one is
                // stored, so an account with a stale "USA" default on
                // the backend doesn't override an India user's flag
                // every time the profile fetches. Preserve that
                // semantics: write the server value only when the
                // local slot is empty.
                if (UserDefaultsClass.getCountryName() ?? "").isEmpty {
                    UserDefaultsClass.storeCountryName(country)
                }
            }

            // Update observable store so UI refreshes.
            //
            // Hop to the main actor first: the preceding
            // `try await URLSession.shared.data(for:)` resumes its
            // continuation on URLSession's background queue, and
            // `UserProfileStore.reload()` mutates eight `@Published`
            // properties (`name`, `email`, `phone`, `dob`,
            // `profileImageURL`, `countryName`, `sessionToken`,
            // `userId`). Without the hop Combine fires
            // "Publishing changes from background threads is not
            // allowed" once per non-empty field on every successful
            // post-login profile fetch.
            await MainActor.run {
                UserProfileStore.shared.reload()
            }
            print("[OryAPIClient] Profile fetched: \(profile.full_name ?? "N/A")")
        } catch {
            print("[OryAPIClient] Profile fetch error: \(error)")
        }
    }

    // MARK: - Recipe & Mixlist API
    //
    // Ports MixlistApiServices.getCacheRecipes() and getMixlist().
    // Real endpoints from EnvironmentConfig:
    //   Base: https://defteros-service-47447659942.us-central1.run.app/api/v1/
    //   Recipes: cache/recipes?timestamp=
    //   Mixlists: cache/mixlists?timestamp=

    private static let recipesBaseURL = "https://defteros-service-47447659942.us-central1.run.app/api/v1/"

    /// Helper: creates an authenticated URLRequest matching UIKit's
    /// `NetworkingUtility.createRequest(includeAuth: true)` which adds
    /// `Authorization: Bearer {sessionToken}` to every API call.
    ///
    /// UIKit ALWAYS sets the Authorization header — even when the
    /// token is an empty string, UIKit sends the literal `"Bearer "`
    /// (with trailing space). Previous SwiftUI port conditionally
    /// skipped the header when the token was empty, which some
    /// servers treat as an authentication-not-attempted code path
    /// (different from `"Bearer "` with no trailing token) and can
    /// respond with 401 / empty bodies to the recipes + mixlists
    /// endpoints. The conditional skip manifested as "data isn't
    /// coming" on screens like Explore Recipes / Cocktail Kits
    /// whenever the token was briefly empty (e.g. during a
    /// restore-session race on app launch).
    ///
    /// Always setting the header mirrors UIKit byte-for-byte and
    /// keeps the server's auth branch consistent.
    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        let token = UserDefaultsClass.getSessionToken() ?? ""
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func fetchRecipes() async throws -> [Recipe] {
        // Ports MixlistApiServices.getCacheRecipes with timestamp-based incremental sync
        let lastTimestamp = UserDefaults.standard.integer(forKey: "updatedDataTimeStampForCacheRecipeData")
        let timestampParam = lastTimestamp > 0 ? "\(lastTimestamp)" : ""
        let urlStr = Self.recipesBaseURL + "cache/recipes?timestamp=\(timestampParam)"
        print("[OryAPIClient] Fetching recipes from: \(urlStr)")
        guard let url = URL(string: urlStr) else { return [] }

        // UIKit: NetworkingUtility.createRequest(includeAuth: true) adds Bearer token
        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        // Session-expired check must run BEFORE the status-code guard.
        // Without this, a 401 on the recipes endpoint just falls into the
        // `return []` branch and the user sees an empty Explore screen
        // instead of the "Your session has expired…" alert that UIKit shows.
        if await SessionExpirationCheck.inspectAndHandle(response: response, data: data) {
            return []
        }
        guard let httpResponse = response as? HTTPURLResponse else { return [] }
        print("[OryAPIClient] Recipes response status: \(httpResponse.statusCode), bytes: \(data.count)")

        guard httpResponse.statusCode == 200 else { return [] }

        // Resilient decode: try full array first, then per-item fallback.
        // A single malformed recipe shouldn't fail the entire fetch.
        let decoder = JSONDecoder()
        do {
            let apiRecipes = try decoder.decode([APIRecipe].self, from: data)
            print("[OryAPIClient] Decoded \(apiRecipes.count) recipes from API")
            return apiRecipes.compactMap { r in
                guard r.id != nil && !(r.id?.isEmpty ?? true) else { return nil }
                return r.toRecipe()
            }
        } catch {
            // Try decoding as array of optional items (skip bad ones)
            print("[OryAPIClient] Full array decode failed, trying per-item: \(error)")
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("[OryAPIClient] JSON has \(jsonArray.count) items, decoding individually")
                var results: [Recipe] = []
                for item in jsonArray {
                    if let itemData = try? JSONSerialization.data(withJSONObject: item),
                       let recipe = try? decoder.decode(APIRecipe.self, from: itemData),
                       let id = recipe.id, !id.isEmpty {
                        results.append(recipe.toRecipe())
                    }
                }
                print("[OryAPIClient] Recovered \(results.count) recipes via per-item decode")
                return results
            }
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "N/A"
            print("[OryAPIClient] Recipe decode FAILED completely: \(preview)")
            return []
        }
    }

    func fetchMixlists() async throws -> [Mixlist] {
        // Ports MixlistApiServices.getMixlist with timestamp-based incremental sync
        let lastTimestamp = UserDefaults.standard.integer(forKey: "updatedDataTimeStampForMixlistData")
        let timestampParam = lastTimestamp > 0 ? "\(lastTimestamp)" : ""
        let urlStr = Self.recipesBaseURL + "cache/mixlists?timestamp=\(timestampParam)"
        print("[OryAPIClient] Fetching mixlists from: \(urlStr)")
        guard let url = URL(string: urlStr) else { return [] }

        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        // Matches the recipes endpoint — a 401 here has to fire the
        // session-expired alert, not silently return [].
        if await SessionExpirationCheck.inspectAndHandle(response: response, data: data) {
            return []
        }
        guard let httpResponse = response as? HTTPURLResponse else { return [] }
        print("[OryAPIClient] Mixlists response status: \(httpResponse.statusCode), bytes: \(data.count)")

        guard httpResponse.statusCode == 200 else { return [] }

        let decoder = JSONDecoder()
        do {
            let apiMixlists = try decoder.decode([APIMixlist].self, from: data)
            print("[OryAPIClient] Decoded \(apiMixlists.count) mixlists from API")
            return apiMixlists.compactMap { m in
                guard m.id != nil && !(m.id?.isEmpty ?? true) else { return nil }
                return m.toMixlist()
            }
        } catch {
            print("[OryAPIClient] Full mixlist array decode failed, trying per-item: \(error)")
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("[OryAPIClient] JSON has \(jsonArray.count) items, decoding individually")
                var results: [Mixlist] = []
                for item in jsonArray {
                    if let itemData = try? JSONSerialization.data(withJSONObject: item),
                       let mixlist = try? decoder.decode(APIMixlist.self, from: itemData),
                       let id = mixlist.id, !id.isEmpty {
                        results.append(mixlist.toMixlist())
                    }
                }
                print("[OryAPIClient] Recovered \(results.count) mixlists via per-item decode")
                return results
            }
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "N/A"
            print("[OryAPIClient] Mixlist decode FAILED completely: \(preview)")
            return []
        }
    }

    /// Ports FavoriteRecipeApiService.getFavouritesListApi().
    /// Endpoint: GET my/cache/recipes/favorites?timestamp=
    func fetchFavorites() async throws -> [RecipeID] {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { return [] }

        let lastTimestamp = UserDefaults.standard.integer(forKey: "updatedDataTimeStampForFavourites")
        let timestampParam = lastTimestamp > 0 ? "\(lastTimestamp)" : ""
        let urlStr = Self.recipesBaseURL + "my/cache/recipes/favorites?timestamp=\(timestampParam)"
        guard let url = URL(string: urlStr) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if await SessionExpirationCheck.inspectAndHandle(response: response, data: data) {
            return []
        }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("[OryAPIClient] Favourites fetch failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            return []
        }

        // Response is array of {cocktail_recipe_id, favorite}
        struct FavouriteItem: Decodable {
            let cocktail_recipe_id: String?
            let favorite: Bool?
        }
        do {
            let favItems = try JSONDecoder().decode([FavouriteItem].self, from: data)
            let timestamp = Int(Date().timeIntervalSince1970)
            UserDefaults.standard.set(timestamp, forKey: "updatedDataTimeStampForFavourites")
            print("[OryAPIClient] Decoded \(favItems.count) favourites from API")
            return favItems.compactMap {
                guard $0.favorite == true, let id = $0.cocktail_recipe_id else { return nil }
                return RecipeID(id)
            }
        } catch {
            print("[OryAPIClient] Favourites decode failed: \(error)")
            return []
        }
    }

    /// Ports FavoriteRecipeApiService.likeUnlikeApi().
    /// POST/DELETE my/recipes/{recipeId}/favorites
    func toggleFavoriteOnServer(recipeId: String, isFavourite: Bool) async {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { return }
        let urlStr = Self.recipesBaseURL + "my/recipes/\(recipeId)/favorites"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = isFavourite ? "POST" : "DELETE"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[OryAPIClient] Toggle favourite \(isFavourite ? "LIKE" : "UNLIKE") for \(recipeId): HTTP \(status)")
        } catch {
            print("[OryAPIClient] Toggle favourite failed: \(error)")
        }
    }

    // MARK: - My Drinks API (1:1 port of FavoriteRecipeApiService.getMyDrinksApi)

    func fetchMyDrinks(offset: Int, isBarsys360Connected: Bool) async throws -> MyDrinksDataModel {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else {
            return MyDrinksDataModel(data: [], total: 0, limit: 20, offset: 0)
        }
        // UIKit: AppAPI.getMyRecipesApi = "my/recipes" (NOT "my-recipes")
        let urlStr = Self.recipesBaseURL + "my/recipes?offset=\(offset)&barsys360=\(isBarsys360Connected)"
        guard let url = URL(string: urlStr) else {
            throw AppError.network("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        if await SessionExpirationCheck.inspectAndHandle(response: response, data: data) {
            // UIKit short-circuits the caller with an error once the
            // expired-session alert is queued, so the Favourites tab
            // doesn't try to render a stale empty page under the alert.
            throw AppError.network(Constants.expiredSessionToken)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[OryAPIClient] fetchMyDrinks offset=\(offset): HTTP \(status)")

        guard status == 200 else {
            throw AppError.network("HTTP \(status)")
        }

        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(APIMyDrinksResponse.self, from: data)
        let apiRecipes: [APIRecipe] = apiResponse.data ?? []
        // Mark every recipe from the my-recipes endpoint as a My Drink.
        // UIKit stores these in the separate `cocktails_recipes` table;
        // our in-memory storage uses the `isMyDrinkFavourite` flag to
        // distinguish them from Barsys Recipes. Without this flag the
        // fallback path in FavoritesView (filter { isMyDrinkFavourite == true })
        // returns empty on API failure / app restart.
        let recipes: [Recipe] = apiRecipes.map {
            var r = $0.toRecipe()
            // Use the API's per-row `favorite` flag (1:1 with UIKit
            // `MixlistModel.isMyDrinkFavourite = "favorite"`). Default
            // to `true` ONLY when the server omits the field — this
            // preserves the previous "treat any my-recipes row as a
            // favourite by default" fallback for older payloads while
            // letting fresh responses honour the real toggle state, so
            // an unfavourited My Drink no longer reappears as
            // favourited after a cache reload / app restart.
            r.isMyDrinkFavourite = $0.favorite ?? true
            return r
        }
        return MyDrinksDataModel(
            data: recipes,
            total: apiResponse.total,
            limit: apiResponse.limit,
            offset: apiResponse.offset
        )
    }

    /// Ports FavoriteRecipeApiService.deleteReceipe().
    func deleteMyDrink(recipeId: String) async throws {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { throw AppError.invalidCredentials }
        // UIKit: AppAPI.getMyRecipesApi + "/{id}" = "my/recipes/{id}"
        let urlStr = Self.recipesBaseURL + "my/recipes/\(recipeId)"
        guard let url = URL(string: urlStr) else { throw AppError.network("Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[OryAPIClient] deleteMyDrink \(recipeId): HTTP \(status)")
        guard status == 200 || status == 201 || status == 204 else {
            throw AppError.network("HTTP \(status)")
        }
    }

    /// 1:1 port of FavoriteRecipeApiService.saveRecipe_Or_UpdateRecipe()
    /// (FavoriteRecipeApiService.swift L25-129).
    ///
    /// **URL & method** (UIKit L34-53):
    ///   • mode == .update && !isCustomizing → PATCH /my/recipes/{id}
    ///   • else                              → POST  /my/recipes
    ///
    /// **Body construction strategy** (UIKit L57-103):
    ///   1. Encode the FULL Recipe model with `JSONEncoder` so EVERY
    ///      Codable field (id, name, slug, description, image, glassware,
    ///      tags, instructions, ingredients, etc.) lands in the payload.
    ///   2. Convert to a mutable [String: Any] dictionary.
    ///   3. Override the `image` key per the priority rules below.
    ///   4. Strip server-managed / unsupported keys before sending.
    ///
    /// The previous SwiftUI port hand-built the payload from a small set
    /// of explicit keys, which dropped `tags`, `ice`, `mixing_technique`,
    /// the rich `glassware` object, and the full Ingredient encoding
    /// (including `substitutes`). The server returned 4xx because the
    /// payload was incomplete — surfacing as the "Unable to save recipe"
    /// error in the UI even when the request reached the backend.
    ///
    /// **Image priority** (UIKit L67-79):
    ///   1. isCustomizing && recipe.image.url non-empty && image == nil
    ///         → reuse existing recipe.image.url
    ///   2. mode == .update && recipe.image.url non-empty
    ///         → reuse existing recipe.image.url
    ///   3. otherwise → base64 the new image with prefix
    ///         `Constants.sourceTypeBase64Str` (= "data:image/png;base64,")
    ///         OR empty string if no image was supplied.
    ///
    /// **Stripped keys** (UIKit L82-94):
    ///   • `tags` (only if empty)
    ///   • `created_at`
    ///   • `variations`
    ///   • `mixing_technique`
    ///   • `ice`
    ///   • `isFavourite`
    ///   • `id` + `updated_at` (only when mode == .create)
    ///
    /// **Computed key**: `barsys_360_compatible` — true when the count
    /// of non-garnish / non-additional ingredients is ≤ 6 (UIKit L95-97).
    ///
    /// **Instructions split** (UIKit L28-32): if `recipe.instructions`
    /// has only one entry, split it on " | " into multiple steps so the
    /// server stores them as a list, not a single concatenated string.
    func saveOrUpdateMyDrink(recipe: Recipe, image: Data?, isCustomizing: Bool) async throws {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { throw AppError.invalidCredentials }

        // Mutable copy so we can apply the UIKit instructions split.
        var workingRecipe = recipe

        // UIKit L28-32: split `recipe.instructions[0]` on " | " when the
        // array has only one entry. Preserves multi-step recipes coming
        // from the BarBot AI which arrive joined with " | ".
        if workingRecipe.instructions.count <= 1 {
            workingRecipe.instructions = workingRecipe.instructions.first?
                .components(separatedBy: " | ") ?? []
        }

        // UIKit L57-58: sort ingredients alphabetically (case-insensitive).
        if let ingredients = workingRecipe.ingredients {
            workingRecipe.ingredients = ingredients.sorted {
                $0.name.lowercased() < $1.name.lowercased()
            }
        }

        // UIKit L34-53: URL + HTTP method.
        let isUpdate = !isCustomizing && !workingRecipe.id.value.isEmpty
        let endpoint = isUpdate
            ? "my/recipes/\(workingRecipe.id.value)"
            : "my/recipes"
        let httpMethod = isUpdate ? "PATCH" : "POST"
        let urlStr = Self.recipesBaseURL + endpoint
        guard let url = URL(string: urlStr) else { throw AppError.network("Invalid URL") }

        // UIKit L60-64: encode the WHOLE Recipe Codable, then convert to
        // a mutable dictionary so we can patch image / strip keys / add
        // computed flags. This guarantees parity with the server's
        // expected schema for EVERY field declared on Recipe — not just
        // the handful we'd remember to whitelist by hand.
        let encoded = try JSONEncoder().encode(workingRecipe)
        guard var params = try JSONSerialization.jsonObject(with: encoded, options: []) as? [String: Any] else {
            throw AppError.network("Encode failed")
        }

        // UIKit L65-79: image priority.
        //
        // `Constants.sourceTypeBase64Str = "data:image/png;base64,"`
        // (UIKit Constants.swift L310). UIKit uses the PNG mime even
        // though `UIImage.toBase64()` returns JPEG bytes — the server
        // accepts either, so we match the UIKit literal exactly.
        let base64Prefix = "data:image/png;base64,"
        let existingURL = (workingRecipe.image?.url ?? "")
        let imageURL: String
        if isCustomizing && !existingURL.isEmpty && image == nil {
            imageURL = existingURL
        } else if isUpdate && !existingURL.isEmpty {
            imageURL = existingURL
        } else if let imageData = image {
            imageURL = base64Prefix + imageData.base64EncodedString()
        } else {
            imageURL = ""
        }
        params["image"] = ["alt": "iOS", "url": imageURL]

        // UIKit L81-83: strip empty `tags`.
        if let tags = params["tags"] as? [String], tags.isEmpty {
            params.removeValue(forKey: "tags")
        } else if let tags = params["tags"] as? [Any], tags.isEmpty {
            params.removeValue(forKey: "tags")
        }

        // UIKit L85-89: strip server-managed / unsupported keys.
        params.removeValue(forKey: "created_at")
        params.removeValue(forKey: "variations")
        params.removeValue(forKey: "mixing_technique")
        params.removeValue(forKey: "ice")
        params.removeValue(forKey: "isFavourite")

        // UIKit L91-94: for create mode, also drop `updated_at` and `id`
        // so the server generates them.
        if !isUpdate {
            params.removeValue(forKey: "updated_at")
            params.removeValue(forKey: "id")
        }

        // UIKit L95-97: barsys_360_compatible flag. Excludes garnish
        // + BOTH additional variants (singular + plural) to match
        // UIKit's SQL filter.
        let baseCount = (workingRecipe.ingredients ?? []).filter {
            let primary = ($0.category?.primary ?? "").lowercased()
            return primary != "garnish" && primary != "additional" && primary != "additionals"
        }.count
        params["barsys_360_compatible"] = baseCount <= 6

        // UIKit uses `.prettyPrinted` (L102) for the body — matches that
        // so the wire format is byte-identical when comparing payloads
        // during debugging.
        let body = try JSONSerialization.data(withJSONObject: params, options: [.prettyPrinted])

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false   // UIKit L107
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[OryAPIClient] saveOrUpdateMyDrink \(httpMethod) \(endpoint): HTTP \(status)")
        // UIKit L120-127: only 200 / 201 are success.
        guard status == 200 || status == 201 else {
            throw AppError.network("HTTP \(status)")
        }
    }

    // MARK: - Ingredient image detection
    //
    // 1:1 port of UIKit `UploadIngredientsImage.uploadImageAndGetIngredientsResponse`
    // (UploadIngredientsImage.swift L13-68).
    //
    // Endpoint: POST {baseUrlForBarBotActionCard}image/multipart
    // Headers : Authorization: Bearer <session>, Content-Type: multipart/form-data,
    //           Accept: application/json
    // Body    : multipart form-data with text part `session_id`=`session_id`
    //           and file part `image` (jpeg quality 0.7, filename imagefile.jpg).
    // Response: [IngredientListResponseModel] — array whose first element
    //           contains `ingredients: [StationIngredientFromImageModel]`.
    private static let barBotActionCardBaseURL = "https://ci.bond-mvp1.barsys.com/api/"

    func uploadIngredientImage(_ image: Data) async throws -> [IngredientFromImage] {
        try await uploadMultipart(
            image: image,
            decode: [IngredientListResponse<IngredientFromImage>].self
        ).first?.ingredients ?? []
    }

    // MARK: - Full recipe fetch (BarBot AI recipe polling)
    //
    // 1:1 port of UIKit `BarBotApiService.getFullRecipeApi(fullRecipeId:)`
    // (BarBotApiService.swift L169-227).
    //
    // Endpoint: GET `{recipesBaseURL}my/recipes/{fullRecipeId}`
    //
    // Behaviour:
    //   • HTTP 400-404  → throw `FullRecipeError.wait` (UIKit returns
    //                     the literal "wait" string in completion)
    //   • HTTP 2xx      → decode APIRecipe → apply 5ml floor on every
    //                     ingredient (matching UIKit L203-216) → return
    //                     with `id = ""` to mark it as a not-yet-saved
    //                     BarBot recipe
    //   • Other errors  → throw `FullRecipeError.failed(message:)`
    //
    // The UIKit layer additionally runs an oz→ml conversion when the
    // unit contains "oz" (`ounceValue = 0.033814`). We apply the same
    // transformation so SwiftUI sees the identical quantity numbers.
    func fetchFullRecipe(fullRecipeId: String) async throws -> Recipe {
        let urlStr = Self.recipesBaseURL + "my/recipes/\(fullRecipeId)"
        guard let url = URL(string: urlStr) else {
            throw FullRecipeError.failed(message: Constants.invalidUrlTitle)
        }
        let request = authenticatedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            // Inline literal to avoid redeclaration conflicts with
            // `Constants.noResponseFromServer` seen during build.
            throw FullRecipeError.failed(message: "No response received from the server.")
        }
        // UIKit `BarBotApiService.swift` L194-196:
        //   if statusCode >= 400 && statusCode <= 404 { completion(nil, "wait") }
        if http.statusCode >= 400 && http.statusCode <= 404 {
            throw FullRecipeError.wait
        }
        guard http.statusCode == 200 else {
            throw FullRecipeError.failed(message: Constants.ingredientUpdateError)
        }
        do {
            let api = try JSONDecoder().decode(APIRecipe.self, from: data)
            var recipe = api.toRecipe()
            // Apply 5 ml floor to every ingredient — matches UIKit
            // `BarBotApiService.swift` L203-216. Convert oz→ml when
            // the unit contains "oz" so the quantity is always in the
            // canonical ml scale before the UI consumes it.
            recipe.ingredients = recipe.ingredients?.map { ing in
                var copy = ing
                let isOz = (copy.unit.lowercased().contains("oz"))
                if isOz {
                    // 0.033814 = NumericConstants.ounceConversionFactor (UIKit).
                    let q = copy.quantity ?? 0
                    let converted = max(5.0, q / 0.033814)
                    copy.quantity = converted
                    copy.unit = "oz"
                } else if (copy.quantity ?? 0) < 5.0 {
                    copy.quantity = 5.0
                }
                return copy
            }
            // UIKit passes `id = ""` when handing the recipe to
            // RecipePageViewController with `.barBotRecipe` context —
            // signals "AI recipe, not yet saved to My Drinks".
            recipe = Recipe(
                id: RecipeID(""),
                name: recipe.name,
                description: recipe.description,
                image: recipe.image,
                ice: recipe.ice,
                ingredients: recipe.ingredients,
                instructions: recipe.instructions,
                mixingTechnique: recipe.mixingTechnique,
                glassware: recipe.glassware,
                tags: recipe.tags,
                ingredientNames: recipe.ingredientNames,
                isFavourite: recipe.isFavourite,
                barsys360Compatible: recipe.barsys360Compatible,
                slug: recipe.slug,
                userId: recipe.userId,
                createdAt: recipe.createdAt
            )
            return recipe
        } catch let error as FullRecipeError {
            throw error
        } catch {
            throw FullRecipeError.failed(message: Constants.ingredientUpdateError)
        }
    }

    func uploadIngredientImageForMyBar(_ image: Data) async throws -> [MyBarIngredientFromImage] {
        try await uploadMultipart(
            image: image,
            decode: [IngredientListResponse<MyBarIngredientFromImage>].self
        ).first?.ingredients ?? []
    }

    /// Shared multipart upload — the two callers differ only in the
    /// response decoding model.
    private func uploadMultipart<T: Decodable>(image: Data, decode: T.Type) async throws -> T {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { throw AppError.invalidCredentials }

        let urlStr = Self.barBotActionCardBaseURL + "image/multipart"
        guard let url = URL(string: urlStr) else { throw AppError.network("Invalid URL") }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body = Data()
        let lineBreak = "\r\n"

        // text part: session_id=session_id (UIKit param literally uses this string)
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"session_id\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("session_id\(lineBreak)".data(using: .utf8)!)

        // file part: image
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"imagefile.jpg\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(image)
        body.append(lineBreak.data(using: .utf8)!)

        // closing boundary
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[OryAPIClient] uploadIngredientImage: HTTP \(status)")
        guard status == 200 || status == 201 else {
            throw AppError.network("HTTP \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Ports FavoriteRecipeApiService.likeUnlikeApi().
    func likeUnlike(recipeId: String, isLike: Bool) async throws -> String {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { throw AppError.invalidCredentials }
        let urlStr = Self.recipesBaseURL + "my/recipes/\(recipeId)/favorites"
        guard let url = URL(string: urlStr) else { throw AppError.network("Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = isLike ? "POST" : "DELETE"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[OryAPIClient] likeUnlike \(isLike ? "LIKE" : "UNLIKE") \(recipeId): HTTP \(status)")
        guard status == 200 || status == 201 || status == 204 else {
            throw AppError.network("HTTP \(status)")
        }
        return isLike ? Constants.likeSuccessMessage : Constants.unlikeSuccessMessage
    }

    // MARK: - My Drinks Response Model

    private struct APIMyDrinksResponse: Decodable {
        var data: [APIRecipe]?
        var total, limit, offset: Int?
    }

    // MARK: - API Response Models
    //
    // Decodable wrappers matching the exact JSON schema from the Barsys API.
    // These are separate from the SwiftUI domain models to handle any naming
    // differences or nested structures.

    private struct APIRecipe: Decodable {
        let id: String?
        let name: String?
        let description: String?
        let image: APIImage?
        let ice: String?
        let ingredients: [APIIngredient]?
        let instructions: [String]?
        let mixingTechnique: String?
        let glassware: APIGlassware?
        let tags: [String]?
        let createdAt: String?
        let updatedAt: String?
        let ingredientNames: String?
        let isFavourite: Bool?
        let barsys360Compatible: Bool?
        let slug: String?
        let userId: String?
        /// 1:1 with UIKit `MixlistModel.swift:87`
        /// `case isMyDrinkFavourite = "favorite"` — the
        /// `my/recipes` API hands back a `"favorite"` boolean per
        /// row indicating whether the user has currently
        /// favourited this My Drink. Decoding it here lets
        /// `fetchMyDrinks` propagate the real per-row state into
        /// `Recipe.isMyDrinkFavourite` instead of unconditionally
        /// assuming `true`, which was masking unfavourite state
        /// across cache reloads / app restarts.
        let favorite: Bool?

        // JSON from API uses snake_case: created_at, updated_at,
        // barsys_360_compatible, ingredient_names, user_id, full_recipe_id
        enum CodingKeys: String, CodingKey {
            case id, name, description, image, ice, ingredients, instructions
            case mixingTechnique
            case glassware, tags
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case ingredientNames = "ingredient_names"
            case isFavourite
            case barsys360Compatible = "barsys_360_compatible"
            case slug
            case userId = "user_id"
            case favorite
        }

        func toRecipe() -> Recipe {
            let ingNames = ingredientNames ?? ingredients?.compactMap(\.name).joined(separator: ", ")
            return Recipe(
                id: RecipeID(id ?? UUID().uuidString),
                name: name,
                description: description,
                image: image.map { ImageModel(url: $0.url, alt: $0.alt) },
                ice: ice,
                ingredients: ingredients?.map { $0.toIngredient() },
                instructions: instructions ?? [],
                mixingTechnique: mixingTechnique,
                glassware: glassware.map { Glassware(type: $0.type, chilled: $0.chilled, rimmed: $0.rimmed, notes: $0.notes) },
                tags: tags,
                ingredientNames: ingNames,
                isFavourite: isFavourite ?? false,
                barsys360Compatible: barsys360Compatible,
                slug: slug,
                userId: userId,
                // Propagate the API `created_at` so `CatalogService.allRecipes()`
                // can sort newest-first (matches UIKit SQL `ORDER BY createdAt DESC`).
                createdAt: createdAt
            )
        }
    }

    private struct APIMixlist: Decodable {
        let id: String?
        let name: String?
        let description: String?
        let tags: [String]?
        let createdAt: String?
        let updatedAt: String?
        let recipes: [APIRecipe]?
        let isDeleted: Bool?
        let image: APIImage?
        let barsys360Compatible: Bool?
        let slug: String?

        enum CodingKeys: String, CodingKey {
            case id, name, description, tags, recipes, image, slug
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case isDeleted = "is_deleted"
            case barsys360Compatible = "barsys_360_compatible"
        }

        func toMixlist() -> Mixlist {
            let ingNames = recipes?.flatMap { $0.ingredients?.compactMap(\.name) ?? [] }
                .removingDuplicates()
                .joined(separator: ", ")
            var m = Mixlist(
                id: MixlistID(id ?? UUID().uuidString),
                name: name,
                description: description,
                tags: tags,
                recipes: recipes?.map { $0.toRecipe() },
                image: image.map { ImageModel(url: $0.url, alt: $0.alt) },
                barsys360Compatible: barsys360Compatible,
                slug: slug,
                ingredientNames: ingNames
            )
            // Propagate the API `created_at` so `CatalogService.allMixlists()`
            // can sort newest-first (matches UIKit SQL `ORDER BY m.createdAt DESC`).
            m.createdAt = createdAt
            return m
        }
    }

    private struct APIImage: Decodable {
        let url: String?
        let alt: String?
    }

    private struct APIIngredient: Decodable {
        let name: String?  // Made optional — a single null name would crash entire array decode
        let unit: String?
        let notes: String?
        let quantity: Double?
        let perishable: Bool?
        let substitutes: [String]?
        let ingredientOptional: Bool?
        let category: APICategory?

        enum CodingKeys: String, CodingKey {
            case name, unit, notes, quantity, perishable, substitutes, category
            case ingredientOptional = "optional"
        }

        func toIngredient() -> Ingredient {
            Ingredient(
                name: name ?? "",
                unit: unit ?? "ML",
                notes: notes,
                category: category.map { IngredientCategory(primary: $0.primary, secondary: $0.secondary) },
                quantity: quantity,
                perishable: perishable,
                substitutes: substitutes,
                ingredientOptional: ingredientOptional
            )
        }
    }

    private struct APICategory: Decodable {
        let primary: String?
        let secondary: String?
    }

    private struct APIGlassware: Decodable {
        let type: String?
        let chilled: Bool?
        let rimmed: String?
        let notes: String?
    }

    // MARK: - Internal helpers

    /// Mirrors `getFlowIdForRegisterAndLogin` — fetches the Ory flow id and
    /// extracts the csrf_token from `ui.nodes[].attributes`.
    private func fetchFlowId(endpoint: String) async throws -> (flowId: String, csrf: String) {
        guard let url = URL(string: "\(Endpoint.baseUrlOry)\(endpoint)") else {
            throw AppError.network(Constants.unknownError)
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.network(Constants.loginError)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let flowId = json["id"] as? String,
            let ui = json["ui"] as? [String: Any],
            let nodes = ui["nodes"] as? [[String: Any]]
        else {
            throw AppError.network(Constants.loginError)
        }

        var csrf = ""
        for node in nodes {
            if let attrs = node["attributes"] as? [String: Any],
               let name = attrs["name"] as? String,
               name == "csrf_token",
               let value = attrs["value"] as? String {
                csrf = value
                break
            }
        }
        return (flowId, csrf)
    }

    /// POST a JSON body to an Ory URL and decode the response into
    /// `LoginSignUpResponseModel` (the same model the UIKit app uses).
    private func postOry(url: URL, body: [String: Any]) async throws -> LoginSignUpResponseModel {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("No response received from the server.")
        }
        // Ory returns 200 on success and 400 on validation errors with the
        // same response shape — decode regardless of status, then inspect.
        do {
            let parsed = try JSONDecoder().decode(LoginSignUpResponseModel.self, from: data)
            // 5xx is always an error.
            if http.statusCode >= 500 {
                throw AppError.network(Constants.unableToConnectToServer)
            }
            return parsed
        } catch let appErr as AppError {
            throw appErr
        } catch {
            throw AppError.network("Unable to process the response. Please try again.")
        }
    }
}

// MARK: - LoginSignUpResponseModel (port of the UIKit model)
//
// Decodes the Ory login/registration response. Field names + CodingKeys
// are 1:1 with BarsysApp/Controllers/Login/LoginSignUpResponseModel.swift.

struct LoginSignUpResponseModel: Codable {
    let session: OrySession?
    let sessionToken: String?
    let ui: OryUI?
    let signUpIdentity: OryIdentity?
    let sessionIdForTestUser: String?
    let error: OryResponseError?

    enum CodingKeys: String, CodingKey {
        case signUpIdentity = "identity"
        case session
        case sessionToken = "session_token"
        case ui
        case error
        case sessionIdForTestUser = "id"
    }
}

struct OryResponseError: Codable {
    let reason: String?
}

struct OryUI: Codable {
    let messages: [OryMessage]?
    let nodes: [OryNode]?
}

struct OryNode: Codable {
    let messages: [OryMessage]?
}

struct OryMessage: Codable {
    let text: String?
}

struct OrySession: Codable {
    let identity: OryIdentity?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case identity
        case sessionId = "id"
    }
}

struct OryIdentity: Codable {
    let traits: OryTraits?
    let verifiableAddresses: [OryVerifiableAddress]?
    let identityId: String?

    enum CodingKeys: String, CodingKey {
        case traits
        case verifiableAddresses = "verifiable_addresses"
        case identityId = "id"
    }
}

struct OryTraits: Codable {
    let email: String?
    let phone: String?
    let name: OryName?
    let dob: String?
}

struct OryName: Codable {
    let first: String?
}

struct OryVerifiableAddress: Codable {
    let id: String?
    let status: String?
    let verified: Bool?
}

// MARK: - OryMessageMatcher
//
// Mirrors `ResponseMessageMatcher.identifyMessageType` from the UIKit app.
// Identifies common Ory response messages so we can map them to user-facing
// strings.

enum OryMessageKind {
    case otpSent
    case accountNotFound
    case invalidPhone
    case other
}

enum OryMessageMatcher {
    static func identify(_ text: String?) -> OryMessageKind {
        guard let t = text?.lowercased(), !t.isEmpty else { return .other }
        if t.contains("an email containing a code has been sent")
            || t.contains("a code has been sent")
            || t.contains("otp")
            && (t.contains("sent") || t.contains("delivered")) {
            return .otpSent
        }
        if t.contains("account does not exist")
            || t.contains("account not found")
            || t.contains("identifier does not exist") {
            return .accountNotFound
        }
        if t.contains("not valid tel") || t.contains("invalid phone") {
            return .invalidPhone
        }
        return .other
    }

    static func isFlowExpired(_ text: String?) -> Bool {
        guard let t = text?.lowercased() else { return false }
        return t.contains("flow expired") || t.contains("expired self-service flow")
    }

    /// Mirrors `ResponseMessageMatcher.matchesUserAlreadyExistsPattern` from
    /// the UIKit app — any Ory ui.messages text that indicates the
    /// identifier (phone or email) is already registered. Used by
    /// `verifyRegistrationOtp` to map the raw Ory wording to a stable
    /// `Constants.userAlreadyExists` string.
    static func matchesUserAlreadyExists(_ text: String?) -> Bool {
        guard let t = text?.lowercased() else { return false }
        return t.contains("account with the same identifier")
            || t.contains("already exists")
            || t.contains("identifier already exists")
            || t.contains("user with this email")
            || t.contains("user with this phone")
            || t.contains("this identifier is already")
    }
}
