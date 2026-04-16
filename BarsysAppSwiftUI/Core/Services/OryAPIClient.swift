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

        let addresses = parsed.session?.identity?.verifiableAddresses ?? []
        let status = addresses.first(where: { $0.status?.lowercased() == "completed" })?.status
            ?? addresses.last?.status
            ?? ""

        guard status.lowercased() == "completed" || status.lowercased() == "sent" else {
            let msg = parsed.ui?.messages?.first?.text ?? Constants.signUpError
            throw AppError.network(msg)
        }

        // Persist everything to UserDefaultsClass — same as UIKit registration
        // success branch (sendRegisterationOtpWithOry completion → stores
        // session token / name / email / phone / dob via UserDefaultsClass).
        let traitsResp = parsed.session?.identity?.traits
        UserDefaultsClass.storeSessionToken(parsed.sessionToken)
        UserDefaultsClass.storeSessionId(parsed.session?.sessionId)
        UserDefaultsClass.storeUserId(parsed.session?.identity?.identityId)
        UserDefaultsClass.storeName(traitsResp?.name?.first ?? fullName)
        UserDefaultsClass.storePhone(traitsResp?.phone ?? phone)
        UserDefaultsClass.storeEmail(traitsResp?.email ?? email)
        UserDefaultsClass.storeDoB(traitsResp?.dob ?? dobStr)

        return UserProfile(
            id: parsed.session?.identity?.identityId ?? UUID().uuidString,
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
                UserDefaultsClass.storeCountryName(country)
            }

            // Update observable store so UI refreshes
            UserProfileStore.shared.reload()
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
    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        let token = UserDefaultsClass.getSessionToken() ?? ""
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
            r.isMyDrinkFavourite = true
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

    /// Ports FavoriteRecipeApiService.saveRecipe_Or_UpdateRecipe().
    ///
    /// UIKit decision logic:
    ///   • isCustomizing == true → POST /my/recipes (create new from existing)
    ///   • isCustomizing == false && recipeID exists → PATCH /my/recipes/{id}
    ///   • isCustomizing == false && no recipeID → POST /my/recipes (brand new)
    ///
    /// Request body: Recipe JSON with image as base64. UIKit removes
    /// `created_at`, `variations`, `mixing_technique`, `ice`, `isFavourite`
    /// and computes `barsys_360_compatible` (non-garnish ingredients <= 6).
    func saveOrUpdateMyDrink(recipe: Recipe, image: Data?, isCustomizing: Bool) async throws {
        let sessionToken = UserDefaultsClass.getSessionToken() ?? ""
        guard !sessionToken.isEmpty else { throw AppError.invalidCredentials }

        // Determine HTTP method + URL (matches UIKit L34-47)
        let isUpdate = !isCustomizing && !recipe.id.value.isEmpty
        let endpoint = isUpdate
            ? "my/recipes/\(recipe.id.value)"
            : "my/recipes"
        let httpMethod = isUpdate ? "PATCH" : "POST"
        let urlStr = Self.recipesBaseURL + endpoint
        guard let url = URL(string: urlStr) else { throw AppError.network("Invalid URL") }

        // Build JSON payload (matches UIKit L48-107)
        var params: [String: Any] = [:]
        params["name"] = recipe.name ?? ""
        params["description"] = recipe.description ?? ""
        params["slug"] = recipe.slug ?? ""

        // Image handling (UIKit L72-95): base64 or existing URL
        var imageDict: [String: String] = ["alt": "iOS"]
        if let imageData = image {
            imageDict["url"] = "data:image/jpeg;base64," + imageData.base64EncodedString()
        } else if let existingUrl = recipe.image?.url, !existingUrl.isEmpty {
            imageDict["url"] = existingUrl
        } else {
            imageDict["url"] = ""
        }
        params["image"] = imageDict

        // Ingredients — sorted alphabetically (UIKit L57)
        let sortedIngredients = (recipe.ingredients ?? []).sorted {
            $0.name.lowercased() < $1.name.lowercased()
        }
        params["ingredients"] = sortedIngredients.map { ing -> [String: Any] in
            var d: [String: Any] = ["name": ing.name]
            d["unit"] = ing.unit ?? ""
            d["quantity"] = ing.quantity ?? 0
            d["notes"] = ing.notes ?? ""
            d["perishable"] = ing.perishable ?? false
            d["optional"] = ing.ingredientOptional ?? false
            if let cat = ing.category {
                d["category"] = [
                    "primary": cat.primary ?? "",
                    "secondary": cat.secondary ?? ""
                ]
            }
            return d
        }

        // barsys_360_compatible — UIKit L96: non-garnish/non-additional <= 6
        let baseCount = sortedIngredients.filter {
            let p = ($0.category?.primary ?? "").lowercased()
            return p != "garnish" && p != "additional"
        }.count
        params["barsys_360_compatible"] = baseCount <= 6

        // Glassware
        if let g = recipe.glassware {
            params["glassware"] = [
                "type": g.type ?? "",
                "chilled": g.chilled ?? false,
                "rimmed": g.rimmed ?? false,
                "notes": g.notes ?? ""
            ]
        }

        // Instructions
        params["instructions"] = recipe.instructions

        // Remove `id` for create mode (UIKit L106)
        if !isUpdate {
            params.removeValue(forKey: "id")
        }

        let body = try JSONSerialization.data(withJSONObject: params)

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[OryAPIClient] saveOrUpdateMyDrink \(httpMethod) \(endpoint): HTTP \(status)")
        guard status == 200 || status == 201 else {
            throw AppError.network("HTTP \(status)")
        }
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
            throw AppError.network(Constants.noResponseFromServer)
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
            throw AppError.network(Constants.unableToProcessResponse)
        }
    }
}

// MARK: - Constants additions

extension Constants {
    static let unableToProcessResponse = "Unable to process the response. Please try again."
    static let noResponseFromServer = "No response received from the server."
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
}
