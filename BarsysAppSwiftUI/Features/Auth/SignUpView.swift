//
//  SignUpView.swift
//  BarsysAppSwiftUI
//
//  Direct port of:
//   - BarsysApp/Controllers/SignUp/SignUpViewController.swift (319 lines)
//   - BarsysApp/Controllers/SignUp/SignUpViewController+Actions.swift
//   - BarsysApp/Controllers/SignUp/SignUpViewController+FormValidation.swift
//   - BarsysApp/Controllers/SignUp/SignUpViewModel.swift (339 lines)
//   - BarsysApp/StoryBoards/Base.lproj/User.storyboard scene "iIU-S8-J7R"
//
//  Storyboard layout (scene id "iIU-S8-J7R"):
//
//    UIImageView (signUpBg, scaleAspectFill, fills entire view)
//      └ Tap-to-dismiss container "a0N-Lu-saQ" (tag 786)
//          ├ UIImageView splashAppIcon (219x20, top:94, centered)
//          ├ UILabel "Let's create your account"
//          │     (system 13pt appBlackColor, 0 lines, centered, top:134)
//          └ Form card "aGx-KU-YNQ" (333 wide, 30pt margins, top:336.66)
//              ├ "Sign up with your Phone Number" (boldSystem 12pt appBlackColor)
//              ├ Full Name field (light 18pt, "Your Full Name", paleBlueGray underline)
//              ├ Email field (light 18pt, "Your Email", emailAddress kb)
//              ├ DOB field (light 18pt, "MM/DD/YYYY", date picker input)
//              ├ Phone row (flag + downArrowSmall + dial code + phone field)
//              ├ OTP view (hidden until OTP sent): label + 6 OtpTextField boxes
//              │     + "Didn't receive a verification code? Resend" + timer
//              ├ Terms checkbox (22x22) + textView with attributed
//              │     "By continuing, you agree to our Terms of Service and
//              │     Privacy Policy."  (Helvetica 11pt, links bold, appBlackColor)
//              ├ "Get OTP" button (lightSilverColor bg, appBlackColor title,
//              │     boldSystem 12pt, 43pt height, 8pt corner) — switches to "Register"
//              └ "Already have an account? Log in" (11pt + semibold 11pt)
//
//  Validation order (mirrors SignUpViewModel.isSignUpDetailsValid):
//   1. fullName not empty
//   2. email not empty + valid format
//   3. dob not empty
//   4. age >= minimumAgeForCountry (selectedCountry.age, default 21)
//   5. phone not empty
//   6. phone 8–16 digits
//   7. terms accepted
//

import SwiftUI

// MARK: - Validation field enum (ports SignUpValidationField)

enum SignUpValidationField {
    case fullName, email, dob, phone
}

// MARK: - SignUp view model (ports SignUpViewModel.swift)

@MainActor
final class SignUpViewModel: ObservableObject {

    // Form state
    @Published var fullName: String = ""
    @Published var email: String = ""
    @Published var phone: String = ""
    @Published var dob: Date? = nil
    @Published var dobText: String = ""    // displayed as "MM/dd/yyyy"
    @Published var isTermsAccepted: Bool = false

    // Country
    @Published var allCountries: [Country] = []
    @Published var selectedCountry: Country? = .unitedStates

    // OTP / timer
    @Published var otp: String = ""
    @Published var otpSent: Bool = false
    @Published var timeLimit: Int = 60
    @Published var isTimerRunning: Bool = false
    @Published var isWorking: Bool = false

    // Per-field validation errors (mirrors handleValidationError)
    @Published var errorFullName: String? = nil
    @Published var errorEmail: String? = nil
    @Published var errorDob: String? = nil
    @Published var errorPhone: String? = nil

    private var timer: Timer?

    // MARK: - Computed (mirrors view model)

    var countryFlag: String { selectedCountry?.flag ?? "🇺🇸" }
    var countryDialCodeDisplay: String { "+\(selectedCountry?.dial_code ?? "1")" }

    /// Ports SignUpViewModel.minimumAgeForCountry — selectedCountry.age or 21.
    var minimumAgeForCountry: Int {
        Int(selectedCountry?.age ?? "0") ?? NumericConstants.minimumAge
    }

    var formattedPhone: String {
        let code = selectedCountry?.dial_code ?? "1"
        return "+\(code)\(phone)"
    }

    var timerDisplayText: String {
        let secs = String(format: "%02d", timeLimit)
        return "00:\(secs) sec"
    }

    var initialTimerText: String { "01:00 min" }

    init() {
        loadCountries()
    }

    /// Ports SignUpViewModel.loadCountries() — read Countries.json + match Locale region.
    func loadCountries() {
        let list = CountryLoader.loadAll()
        allCountries = list
        let regionCode = LoginViewModel.deviceRegionCode()
        if let match = list.first(where: { $0.code.lowercased() == regionCode }) {
            selectedCountry = match
        }
    }

    /// Ports SignUpViewModel.setDob(from:)
    func setDob(_ date: Date) {
        dob = date
        let display = DateFormatter()
        display.dateFormat = "MM/dd/yyyy"
        display.locale = Locale(identifier: "en_US")
        dobText = display.string(from: date)
        errorDob = nil
    }

    func clearAllErrors() {
        errorFullName = nil
        errorEmail = nil
        errorDob = nil
        errorPhone = nil
    }

    /// Ports SignUpViewModel.isSignUpDetailsValid — same order, same messages.
    func isSignUpDetailsValid(alerts: AlertQueue) -> Bool {
        clearAllErrors()
        let fullNameStr = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailStr = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNumber = phone

        // 1:1 with UIKit `SignUpViewController+FormValidation.swift:40`:
        // a single error haptic fires when ANY validation rule fails.
        // Encoded once via `defer` so each early-`return false` below
        // doesn't need its own line — `validationFailed` is set to
        // `true` whenever we exit before reaching the terminal
        // `return true` on line below.
        var validationFailed = true
        defer { if validationFailed { HapticService.error() } }

        if fullNameStr.isEmpty {
            errorFullName = Constants.pleaseEnterFullName
            return false
        }
        if emailStr.isEmpty {
            errorEmail = Constants.pleaseEnterEmail
            return false
        }
        if !isValidEmail(emailStr) {
            errorEmail = Constants.invalidEmail
            return false
        }
        if dobText.isEmpty {
            errorDob = Constants.pleaseEnterDob
            return false
        }
        let years = Calendar.current.dateComponents([.year],
                                                    from: dob ?? Date(),
                                                    to: Date()).year ?? 0
        if years < minimumAgeForCountry {
            errorDob = "You must be at least \(minimumAgeForCountry)+ years old to use this app."
            return false
        }
        if cleanedNumber.isEmpty {
            errorPhone = Constants.pleaseEnterPhoneNumber
            return false
        }
        if cleanedNumber.count < 8 || cleanedNumber.count > 16 {
            errorPhone = Constants.invalidPhoneNumber
            return false
        }
        if !isTermsAccepted {
            alerts.show(message: Constants.acceptTermsAndConditions)
            return false
        }
        validationFailed = false
        return true
    }

    var isOtpValid: Bool {
        otp.count == 6 && otp.allSatisfy(\.isNumber)
    }

    /// 1:1 with `String.isValidEmail()` from BarsysApp/Helpers/StringClass.swift —
    /// note the 2–4 character TLD limit, NOT 2+.
    private func isValidEmail(_ s: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,4}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: s)
    }

    /// Mirrors `setOtpFieldsEmpty()` + the side-effects from
    /// `textField:shouldChangeCharactersIn:` — when the user edits any of the
    /// pre-OTP fields, the OTP view is hidden, the OTP boxes are cleared, and
    /// the button title flips back to "Get OTP".
    func resetOtpStateForFieldEdit() {
        otp = ""
        otpSent = false
        stopTimerInternal()
    }

    // MARK: - Field length limits (matches SignUpViewController+TextFieldDelegate)

    /// Email max 130 chars. Returns the value clamped if needed.
    func clampEmail(_ new: String) -> String {
        new.count > 130 ? String(new.prefix(130)) : new
    }

    /// Full name max 130 chars.
    func clampFullName(_ new: String) -> String {
        new.count > 130 ? String(new.prefix(130)) : new
    }

    /// Phone numeric only, max NumericConstants.maxPhoneNumCharacterCount = 15.
    func clampPhone(_ new: String) -> String {
        let digits = new.filter(\.isNumber)
        return digits.count > NumericConstants.maxPhoneNumCharacterCount
            ? String(digits.prefix(NumericConstants.maxPhoneNumCharacterCount))
            : digits
    }

    // MARK: - Timer

    func startTimer() {
        stopTimerInternal()
        timeLimit = 60
        isTimerRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.timeLimit > 0 {
                    self.timeLimit -= 1
                } else {
                    self.stopTimerInternal()
                }
            }
        }
    }

    func stopTimerInternal() {
        isTimerRunning = false
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Network actions

    /// Ports signUpGetOtpAction(_:) — first tap sends OTP, then becomes "Register".
    func sendRegistrationOtp(api: APIClient,
                             alerts: AlertQueue,
                             analytics: AnalyticsService,
                             isResend: Bool = false) async {
        // Re-entry guard — bail immediately if a previous Get-OTP
        // task is still running. Without this, rapid taps on the
        // "Get OTP" button stack identical validation alerts on top
        // of one another (QA: "Sign Up > The validation alert for
        // the Terms and Conditions and Privacy Policy appears twice,
        // overlapping, when the Get OTP button is tapped multiple
        // times"). The button has `.disabled(viewModel.isWorking)`,
        // but the previous order — validate FIRST, then set
        // `isWorking = true` AFTER — left a race window where every
        // queued tap reached `isSignUpDetailsValid(...)` (which
        // surfaces the validation alert) before any of them flipped
        // the flag. Guarding on `isWorking` at the top closes that
        // window, and the `isWorking = true` set BEFORE validation
        // ensures every subsequent tap (button-disable race or
        // not) takes the early-return branch.
        guard !isWorking else { return }
        isWorking = true
        guard isSignUpDetailsValid(alerts: alerts) else {
            isWorking = false
            return
        }
        defer { isWorking = false }
        do {
            // If the live OryAPIClient is wired, use the dedicated registration
            // endpoint with full traits (matches sendRegisterationOtpWithOry).
            // Otherwise fall back to the generic sendOtp() shape.
            if let ory = api as? OryAPIClient {
                try await ory.sendRegistrationOtp(fullName: fullName,
                                                  email: email,
                                                  phone: formattedPhone,
                                                  dobStr: dobYearMonthDay)
            } else {
                try await api.sendOtp(phone: formattedPhone)
            }
            if isResend {
                analytics.track(TrackEventName.tapSignupResend.rawValue)
            } else {
                analytics.track(TrackEventName.tapSignupGetOTP.rawValue)
            }
            otpSent = true
            startTimer()
            alerts.show(message: Constants.otpSentSuccessfully)
        } catch let appErr as AppError {
            analytics.track(TrackEventName.signupUnsuccessfulOTP.rawValue)
            alerts.show(message: appErr.errorDescription ?? Constants.signUpError)
        } catch {
            analytics.track(TrackEventName.signupUnsuccessfulOTP.rawValue)
            alerts.show(message: error.localizedDescription)
        }
    }

    /// Ports verifyOtpToRegister — verify code then register.
    func verifyOtpToRegister(api: APIClient,
                             auth: AuthService,
                             alerts: AlertQueue,
                             analytics: AnalyticsService,
                             onSuccess: @escaping () -> Void) async {
        guard isSignUpDetailsValid(alerts: alerts), isOtpValid else {
            alerts.show(message: Constants.invalidOTP)
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            if let ory = api as? OryAPIClient {
                // IMPORTANT: Ory self-service registration returns the
                // identity but does NOT create a session — the server
                // sends no `session_token`. UIKit mirrors this by NOT
                // auto-signing the user in: after verify success,
                // `SuccessViewController` fades in briefly and the nav
                // stack pops back to Login so the user re-authenticates
                // via phone+OTP to MINT a real session.
                //
                // The previous SwiftUI port called
                // `auth.applySignedInProfile(profile)` here, which
                // flipped `isAuthenticated = true` and minted a
                // placeholder UUID as the session token when Ory
                // returned `nil`. The RootView then transitioned to
                // `.main`, CatalogService.preload fired authenticated
                // `cache/recipes` + `cache/mixlists` requests with the
                // fake UUID bearer token, the server replied 401, and
                // `SessionExpirationHandler` kicked the user to Login
                // with the "Your session has expired…" alert — the
                // exact bug the user reported.
                //
                // Fix: discard the returned `UserProfile` here and let
                // `SignUpView`'s success closure pop the user back to
                // Login. OryAPIClient has already persisted name /
                // email / phone / DOB to UserDefaults via its own
                // `verifyRegistrationOtp` so the Login screen can
                // pre-fill fields if desired on a subsequent attempt.
                _ = try await ory.verifyRegistrationOtp(fullName: fullName,
                                                        email: email,
                                                        phone: formattedPhone,
                                                        otp: otp,
                                                        dobStr: dobYearMonthDay)
            } else {
                // Mock backend path — no real session concept, so
                // retaining the previous flow keeps unit tests green.
                try await auth.signUp(firstName: firstNameComponent(),
                                      lastName: lastNameComponent(),
                                      email: email,
                                      phone: formattedPhone,
                                      dob: dob)
            }
            analytics.track(TrackEventName.tapSignupRegister.rawValue)
            stopTimerInternal()
            onSuccess()
        } catch let appErr as AppError {
            analytics.track(TrackEventName.signupUnsuccessfulOTP.rawValue)
            otp = ""
            alerts.show(message: appErr.errorDescription ?? Constants.signUpError)
        } catch {
            analytics.track(TrackEventName.signupUnsuccessfulOTP.rawValue)
            otp = ""
            alerts.show(message: error.localizedDescription)
        }
    }

    /// "yyyy-MM-dd" date string used by the Ory backend (matches DateFormatConstants).
    private var dobYearMonthDay: String {
        guard let dob else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: dob)
    }

    private func firstNameComponent() -> String {
        let parts = fullName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.first.map(String.init) ?? ""
    }

    private func lastNameComponent() -> String {
        let parts = fullName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.dropFirst().joined(separator: " ")
    }
}

// MARK: - SignUpView

struct SignUpView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = SignUpViewModel()
    @Binding var path: NavigationPath

    @State private var showCountryPicker = false
    @State private var showDatePicker = false
    @Environment(\.colorScheme) private var colorScheme

    /// Bound to the form's text fields so the keyboard accessory
    /// toolbar (`.keyboardDoneCancelToolbar`) attaches reliably.
    /// Without an explicit `.focused(...)` link SwiftUI sometimes
    /// races the keyboard appearance against the toolbar's
    /// attachment, leaving the Cancel/Done bar missing on the first
    /// tap into a field — the QA "toolbar not coming sometimes"
    /// report. Binding gives SwiftUI an observable focus value to
    /// re-evaluate the toolbar against.
    @FocusState private var focusedField: FocusField?

    enum FocusField: Hashable {
        case fullName, email, phone, otp
    }

    var body: some View {
        // Two-layer pattern identical to LoginView:
        //   1. Background — own `.ignoresSafeArea(.all)` so signUpBg never
        //      zooms or moves when the keyboard appears.
        //   2. Content — full-screen ScrollView so the user can scroll the
        //      whole layout while the keyboard is up. Tap outside dismisses
        //      the keyboard. Keyboard accessory toolbar mirrors the UIKit
        //      SignUpViewController+TextFieldDelegate.setupToolbar().
        ZStack {
            // 1. Background layer
            GeometryReader { proxy in
                Group {
                    if colorScheme == .dark {
                        // `signUpBg` has no dark variant and is a light
                        // artwork; in dark mode it collides with the
                        // adaptive near-white text. Swap for the adaptive
                        // `primaryBackgroundColor` dark surface. Light mode
                        // still renders the original image.
                        Color("primaryBackgroundColor")
                    } else {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            // iPad: preserve aspect ratio so the artwork is
                            // not stretched on the wider/squarer iPad
                            // canvas. The outer `.clipped()` crops overflow.
                            Image("signUpBg")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image("signUpBg")
                                .resizable()
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)

            // 2. Foreground content — scrollable
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Dark wordmark PNG — invert in dark mode so it reads
                        // as white on the dark surface. Light mode untouched.
                        Image("splashAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: iPadValue(219, 440), height: iPadValue(20, 40))
                            .invertedInDarkMode(colorScheme == .dark)
                            // Top padding tightens in dark mode so the
                            // inline cocktail artwork + form card + new
                            // account text all fit within the visible
                            // viewport. Light mode keeps the original
                            // 94pt iPhone / 220pt iPad — UNCHANGED.
                            .padding(.top, colorScheme == .dark
                                     ? iPadValue(30, 80)
                                     : iPadValue(94, 220))

                        Text("Let's create your account")
                            .font(.system(size: iPadValue(13, 17)))
                            .foregroundStyle(Color("appBlackColor"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, iPadValue(45, 80))
                            .padding(.top, iPadValue(20, 30))

                        // Dark-mode-only cocktail artwork placed between
                        // the "Let's create your account" tagline and the
                        // form card. Mirrors the same visual pattern used
                        // on the Login screen — light mode renders the
                        // full-screen `signUpBg` background only and
                        // never sees this inline asset.
                        //
                        // Two render paths because iPhone and iPad need
                        // different sizing strategies:
                        //
                        //   • iPhone: `.scaledToFit()` so the image
                        //     ALWAYS fits within its proposed frame —
                        //     no overflow possible. Width is bounded
                        //     by `.padding(.horizontal, 30)` (screen
                        //     width − 60pt) so the image sits clearly
                        //     inset from the screen edges. `.frame(
                        //     maxWidth: .infinity, alignment: .center)`
                        //     makes horizontal centering explicit.
                        //   • iPad: `.aspectRatio(.fill)` + 440pt
                        //     height capped at 640pt wide, mirroring
                        //     the Login screen's confirmed-correct
                        //     iPad sizing.
                        if colorScheme == .dark {
                            Group {
                                if UIDevice.current.userInterfaceIdiom == .pad {
                                    Image("signUpBackgroundImageDark")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 440)
                                        .frame(maxWidth: 640)
                                        .clipped()
                                } else {
                                    // iPhone: explicit height frame so the
                                    // image always has a definite render
                                    // size — `.scaledToFit()` alone in a
                                    // height-unbounded ScrollView context
                                    // can occasionally collapse to zero.
                                    // 30pt horizontal padding gives clear
                                    // leading + trailing margin against
                                    // the main view.
                                    Image("signUpBackgroundImageDark")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 240)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 30)
                                }
                            }
                            .padding(.top, iPadValue(20, 30))
                            .accessibilityHidden(true)
                        }

                        // Form card — capped width on iPad so the
                        // narrow phone-style form stays centered
                        // instead of stretching across the iPad canvas.
                        //
                        // Top padding: dark mode tightens to 20/30pt
                        // because the inline cocktail artwork above
                        // already provides visual breathing room
                        // between the tagline and the form. Light mode
                        // keeps the original 60/70pt — UNCHANGED.
                        formCard
                            .frame(maxWidth: iPadMaxWidth(540))
                            .padding(.horizontal, 30)
                            .padding(.top, colorScheme == .dark
                                     ? iPadValue(20, 30)
                                     : iPadValue(60, 70))
                            .padding(.bottom, iPadValue(30, 40))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                    // Tap-outside-to-dismiss: hits empty areas of the VStack
                    // and everything behind the form card.
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }
                }
                .scrollDismissesKeyboard(.interactively)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.otpSent)
            }
        }
        // Keyboard accessory toolbar — ports SignUpViewController+TextFieldDelegate.setupToolbar
        // (Cancel + flexibleSpace + Done over phone / name / email /
        // OTP fields). Shared modifier swaps text labels for
        // `xmark` / `checkmark` icons on iOS 26 glass.
        //
        // CRITICAL ordering: `.keyboardDoneCancelToolbar` MUST sit
        // BEFORE `.toolbar(.hidden, for: .navigationBar)` and before
        // `.sheet(...)`. SwiftUI resolves toolbar placements against
        // the nearest enclosing context — when a sheet or a hidden
        // nav-bar modifier sits between the field and the
        // `.toolbar { ToolbarItemGroup(placement: .keyboard) }` call,
        // the keyboard placement can get re-rooted into a context
        // that doesn't render input accessories, leaving the
        // Cancel/Done bar missing on first tap.
        .keyboardDoneCancelToolbar()
        // Hide the system navigation bar — use the iOS 16+
        // `.toolbar(.hidden, for: .navigationBar)` form (targets ONLY
        // the navigation bar surface) instead of the deprecated
        // `.navigationBarHidden(true)`, which could cascade and
        // suppress sibling toolbar items in the same chain.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selected: Binding(
                get: { viewModel.selectedCountry ?? .unitedStates },
                set: { newCountry in
                    // QA: when the user picks a country whose minimum
                    // age differs, the previously-shown age error
                    // ("You must be at least 18+ years old…") was
                    // sticking around even though the validation
                    // context just changed. The error message
                    // references the OLD country's age threshold and
                    // is no longer accurate, so clear it on every
                    // country change. The user can re-tap "Get OTP"
                    // to re-validate against the new minimum age.
                    if newCountry != viewModel.selectedCountry {
                        viewModel.errorDob = nil
                    }
                    viewModel.selectedCountry = newCountry
                }
            ))
        }
        .sheet(isPresented: $showDatePicker) {
            DateOfBirthPickerSheet(initial: viewModel.dob ?? defaultDob,
                                   maxDate: Date()) { picked in
                viewModel.setDob(picked)
                showDatePicker = false
            }
            .presentationDetents([.height(340)])
        }
    }

    private var defaultDob: Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: iPadValue(18, 22)) {

            Text("Sign up with your Phone Number")
                .font(.system(size: iPadValue(12, 16), weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
                .padding(.leading, 5)

            // Full name
            UnderlinedField(placeholder: "Your Full Name",
                            text: $viewModel.fullName,
                            error: viewModel.errorFullName,
                            keyboard: .default,
                            contentType: .name)
                // 1:1 with UIKit `SignUpViewController+Accessibility.swift:20`.
                .accessibilityLabel("Full name")
                .onChange(of: viewModel.fullName) { newValue in
                    let clamped = viewModel.clampFullName(newValue)
                    if clamped != newValue { viewModel.fullName = clamped }
                    viewModel.errorFullName = nil
                    // Mirrors textField:shouldChangeCharactersIn for txtFullName:
                    // editing the field while OTP is shown clears the OTP and
                    // flips the button title back to "Get OTP".
                    if viewModel.otpSent {
                        viewModel.resetOtpStateForFieldEdit()
                    }
                }

            // Email
            UnderlinedField(placeholder: "Your Email",
                            text: $viewModel.email,
                            error: viewModel.errorEmail,
                            keyboard: .emailAddress,
                            contentType: .emailAddress)
                // 1:1 with UIKit `SignUpViewController+Accessibility.swift:21`.
                .accessibilityLabel("Email address")
                .accessibilityHint("Enter a valid email address")
                .onChange(of: viewModel.email) { newValue in
                    let clamped = viewModel.clampEmail(newValue)
                    if clamped != newValue { viewModel.email = clamped }
                    viewModel.errorEmail = nil
                    if viewModel.otpSent {
                        viewModel.resetOtpStateForFieldEdit()
                    }
                }

            // DOB
            DOBField(text: viewModel.dobText,
                     error: viewModel.errorDob) {
                hideKeyboard()
                showDatePicker = true
            }
            // 1:1 with UIKit `SignUpViewController+Accessibility.swift:23`.
            .accessibilityLabel("Date of birth")
            .accessibilityHint("Tap to pick your date of birth")

            // Phone row (storyboard mirrors LoginViewController phone row)
            phoneRow

            if viewModel.otpSent {
                otpSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Terms checkbox + textView
            termsRow

            // Get OTP / Register button
            Button {
                handlePrimaryTap()
            } label: {
                ZStack {
                    if viewModel.isWorking {
                        ProgressView().tint(Color("appBlackColor"))
                    } else {
                        Text(primaryButtonTitle)
                            .font(.system(size: iPadValue(12, 16), weight: .bold))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: iPadValue(43, 54))
                .background(Color("lightSilverColor"))
                .clipShape(RoundedRectangle(cornerRadius: iPadValue(8, 10)))
            }
            .disabled(viewModel.isWorking)
            .padding(.top, 4)

            // Already have an account? Log in
            HStack(spacing: 0) {
                Spacer()
                Text("Already have an account? ")
                    .font(.system(size: iPadValue(11, 14)))
                    .foregroundStyle(Color("silverGrayColor"))
                Button {
                    // Hide keyboard FIRST so the dismiss animation
                    // settles before popping back to Login —
                    // otherwise the keyboard sliding down and the
                    // pop transition fire at the same time, reading
                    // as a glitchy double-animation. The pop is
                    // delayed a tick so iOS finishes the
                    // resignFirstResponder cycle first.
                    hideKeyboard()
                    env.analytics.track(TrackEventName.tapSignupLogIn.rawValue)
                    viewModel.stopTimerInternal()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        path.removeLast()
                    }
                } label: {
                    Text("Log in")
                        .font(.system(size: iPadValue(11, 14), weight: .semibold))
                        .foregroundStyle(Color("appBlackColor"))
                }
                Spacer()
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.otpSent)
    }

    // MARK: - Phone row (mirrors LoginView)

    private var phoneRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Button {
                    hideKeyboard()
                    showCountryPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.countryFlag).font(.system(size: iPadValue(28, 36)))
                        Image("downArrowSmall")
                            .resizable().scaledToFit().frame(width: iPadValue(14, 18))
                            .foregroundStyle(Color("appBlackColor"))
                            .invertedInDarkMode(colorScheme == .dark)
                        Text(viewModel.countryDialCodeDisplay)
                            .font(.system(size: iPadValue(17, 22), weight: .light))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .buttonStyle(.plain)

                TextField("Phone no.", text: $viewModel.phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: iPadValue(18, 22), weight: .light))
                    .foregroundStyle(Color("appBlackColor"))
                    // Caret tint — same rationale as the
                    // `UnderlinedField` fix above. Without an
                    // explicit `.tint(...)` the SwiftUI TextField
                    // inherits the app accent and the cursor can be
                    // invisible against the form surface.
                    .tint(Color("appBlackColor"))
                    .frame(height: iPadValue(40, 50))
                    .focused($focusedField, equals: .phone)
                    .onChange(of: viewModel.phone) { newValue in
                        let clamped = viewModel.clampPhone(newValue)
                        if clamped != newValue { viewModel.phone = clamped }
                        viewModel.errorPhone = nil
                        // Same OTP-reset behaviour as the txtPhoneNumber delegate.
                        if viewModel.otpSent {
                            viewModel.resetOtpStateForFieldEdit()
                        }
                    }
            }
            .padding(.horizontal, 5)

            Rectangle()
                .fill(viewModel.errorPhone == nil
                      ? Color("paleBlueGrayColor")
                      : Color("errorLabelColor"))
                .frame(height: 1)
                .padding(.horizontal, 5)

            if let err = viewModel.errorPhone {
                Text(err)
                    .font(.system(size: iPadValue(13, 16), weight: .bold))
                    .foregroundStyle(Color("errorLabelColor"))
                    .padding(.horizontal, 5)
            }
        }
    }

    // MARK: - OTP section
    //
    // Mirrors the same layout as Login (storyboard CWe-79-tux):
    //   - Row 1: "OTP" label + 6 square boxes
    //   - Row 2: timer LEFT + "Didn't receive…? Resend" stack RIGHT
    //   - Resend stack always visible, faded while timer running
    //     (matches enableDisableResendButton in SignUpViewController)

    private var otpSection: some View {
        VStack(spacing: iPadValue(12, 16)) {
            // Row 1: OTP label + boxes
            HStack(alignment: .center, spacing: iPadValue(12, 16)) {
                Text("OTP")
                    .font(.system(size: iPadValue(18, 22), weight: .light))
                    .foregroundStyle(Color("silverGrayColor"))
                OTPBoxField(code: $viewModel.otp)
            }
            .padding(.horizontal, 5)

            // Row 2: timer LEFT + Resend RIGHT
            HStack(alignment: .center) {
                if viewModel.isTimerRunning && viewModel.timeLimit > 0 {
                    Text(viewModel.timerDisplayText)
                        .font(.system(size: iPadValue(11, 14)))
                        .foregroundStyle(Color("silverGrayColor"))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }

                Spacer()

                let isResendEnabled = !(viewModel.isTimerRunning && viewModel.timeLimit > 0)
                HStack(spacing: 0) {
                    Text("Didn't receive a verification code? ")
                        .font(.system(size: iPadValue(11, 14)))
                        .foregroundStyle(Color("silverGrayColor"))
                    Button {
                        Task {
                            await viewModel.sendRegistrationOtp(api: env.api,
                                                                alerts: env.alerts,
                                                                analytics: env.analytics,
                                                                isResend: true)
                        }
                    } label: {
                        Text("Resend")
                            .font(.system(size: iPadValue(11, 14), weight: .semibold))
                            .foregroundStyle(isResendEnabled
                                             ? Color("appBlackColor")
                                             : Color("silverGrayColor"))
                    }
                    .disabled(!isResendEnabled)
                }
                .opacity(isResendEnabled ? 1.0 : 0.5)
            }
            .padding(.horizontal, 5)
        }
    }

    // MARK: - Terms row (storyboard "qFD-1z-eAX": checkbox 22x22 + textView)

    private var termsRow: some View {
        // iPad centers the checkbox vertically against the wrapped terms
        // text so the box sits in the middle of the multi-line block;
        // iPhone keeps `.top` alignment so the box lines up with the
        // first line on the original phone-width single-line layout.
        HStack(alignment: iPadValue(.top, .center), spacing: iPadValue(10, 14)) {
            Button {
                viewModel.isTermsAccepted.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: iPadValue(4, 6))
                        .stroke(Color("brandTanColor"),
                                lineWidth: viewModel.isTermsAccepted ? 4 : 2)
                        .frame(width: iPadValue(22, 28), height: iPadValue(22, 28))
                    if viewModel.isTermsAccepted {
                        // Tick PNG is dark — invert in dark mode so the
                        // checkmark stays visible inside the tan outline box.
                        Image("tickIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: iPadValue(14, 18), height: iPadValue(14, 18))
                            .invertedInDarkMode(colorScheme == .dark)
                    }
                }
            }
            .buttonStyle(.plain)
            // iPhone-only top nudge to align the box with the first line
            // of single-line terms text — on iPad the HStack is centered
            // so the offset is dropped.
            .padding(.top, iPadValue(CGFloat(2), 0))

            termsAttributedText
                .font(.system(size: iPadValue(11, 14)))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .onTapGesture {
                    // Hide keyboard FIRST so the dismiss animation
                    // settles before the web view pushes onto the
                    // navigation stack — same rationale as the
                    // "Create one" / "Log in" buttons. Without the
                    // delay the keyboard sliding down and the new
                    // screen sliding in fire simultaneously and read
                    // as a glitchy double-animation.
                    hideKeyboard()
                    focusedField = nil
                    env.analytics.track(TrackEventName.tapSignupTermsOfService.rawValue)
                    // 1:1 port of UIKit `SignUpViewController+FormValidation.swift`
                    // L72-74: open the Terms URL in the IN-APP web view
                    // (matching the custom 50pt black header + white
                    // back button chrome), not an external Safari tab.
                    if let url = URL(string: WebViewURLs.termsOfUseWebUrl) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            path.append(AuthRoute.web(url))
                        }
                    }
                }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
    }

    /// Builds the attributed terms-of-service text — split out so the Swift
    /// type-checker doesn't time out on a long `Text + Text + …` expression.
    private var termsAttributedText: Text {
        let black = Color("appBlackColor")
        let boldSize = iPadValue(CGFloat(11), CGFloat(14))
        let prefix = Text("By continuing, you agree to our ").foregroundColor(black)
        let terms = Text("Terms of Service")
            .font(.system(size: boldSize, weight: .bold))
            .foregroundColor(black)
        let and = Text(" and ").foregroundColor(black)
        let privacy = Text("Privacy Policy")
            .font(.system(size: boldSize, weight: .bold))
            .foregroundColor(black)
        let dot = Text(".").foregroundColor(black)
        return prefix + terms + and + privacy + dot
    }

    // MARK: - Primary button

    private var primaryButtonTitle: String {
        viewModel.otpSent ? "Register" : "Get OTP"
    }

    private func handlePrimaryTap() {
        hideKeyboard()
        Task {
            if viewModel.otpSent {
                // Glass loader — 1:1 with UIKit
                // `SignUpViewController+Actions.swift` L99
                // `showGlassLoader(message: "Registering")`. The
                // in-button ProgressView alone doesn't match UIKit's
                // full-screen blocking loader.
                env.loading.show(Constants.loaderRegistering)
                await viewModel.verifyOtpToRegister(api: env.api,
                                                    auth: env.auth,
                                                    alerts: env.alerts,
                                                    analytics: env.analytics) {
                    // 1:1 with UIKit post-register navigation
                    // (`AuthCoordinator.showSuccess(origin: .signUp)`
                    // → `SuccessViewController` fades in 0.45s →
                    // `popToRootViewController`): show a brief
                    // visual confirmation then AUTO-pop back to
                    // Login so the user can authenticate via
                    // phone+OTP and mint a real Ory session. The
                    // previous SwiftUI port tried to auto-log the
                    // user in with a UUID placeholder token (see
                    // `SignUpViewModel.verifyOtpToRegister` comment),
                    // which caused the "Choose Options → session
                    // expired → Login" bounce the user reported.
                    //
                    // Toast duration matches UIKit's fade timing
                    // (~0.45s animation + 0.15s settle + ~1s read);
                    // the pop itself fires at 0.8s so iOS has time
                    // to finish the push animation before replaying
                    // it in reverse.
                    env.loading.hide()
                    env.toast.show(Constants.accountCreatedSuccessfully,
                                   color: Color("successGreenColor"),
                                   duration: 2.5)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if path.count > 0 { path.removeLast() }
                    }
                }
                // Safety net — if verify threw, `onSuccess` is skipped
                // and the loader is still up. Hide it so the user can
                // correct the OTP and retry. `LoadingState.hide()` is
                // idempotent.
                env.loading.hide()
            } else {
                // UIKit `SignUpViewController+Actions.swift` L21/L68
                // `showGlassLoader(message: "Sending OTP")`.
                env.loading.show(Constants.loaderSendingOTP)
                await viewModel.sendRegistrationOtp(api: env.api,
                                                    alerts: env.alerts,
                                                    analytics: env.analytics)
                env.loading.hide()
            }
        }
    }
}

// MARK: - Reusable underlined field (matches storyboard text-field rows)

private struct UnderlinedField: View {
    let placeholder: String
    @Binding var text: String
    let error: String?
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .font(.system(size: iPadValue(18, 22), weight: .light))
                .foregroundStyle(Color("appBlackColor"))
                // Pin the caret colour to `appBlackColor` (adaptive:
                // dark in light mode, light in dark mode) so the
                // blinking cursor is always legible against the form
                // surface — matches the same fix applied to the
                // Login phone field's `UIKitTextField.tintColor`.
                // Without this the SwiftUI TextField inherits the
                // app accent and the caret can disappear into the
                // background.
                .tint(Color("appBlackColor"))
                .frame(height: iPadValue(40, 50))
                .padding(.horizontal, 5)

            Rectangle()
                .fill(error == nil ? Color("paleBlueGrayColor") : Color("errorLabelColor"))
                .frame(height: 1)
                .padding(.horizontal, 5)

            if let err = error {
                Text(err)
                    .font(.system(size: iPadValue(13, 16), weight: .bold))
                    .foregroundStyle(Color("errorLabelColor"))
                    .padding(.horizontal, 5)
            }
        }
    }
}

// MARK: - DOB field (read-only, opens picker on tap)

private struct DOBField: View {
    let text: String
    let error: String?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                HStack {
                    Text(text.isEmpty ? "MM/DD/YYYY" : text)
                        .font(.system(size: iPadValue(18, 22), weight: .light))
                        .foregroundStyle(text.isEmpty
                                         ? Color("inputPlaceholderColor")
                                         : Color("appBlackColor"))
                    Spacer()
                    Image(systemName: "calendar")
                        // iPad-only override — iPhone keeps the SF Symbol
                        // default (body style, Dynamic-Type aware) so users
                        // with custom text sizes see the same icon as before.
                        .iPadFont(.system(size: 22))
                        .foregroundStyle(Color("silverGrayColor"))
                }
                .frame(height: iPadValue(40, 50))
                .padding(.horizontal, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(error == nil ? Color("paleBlueGrayColor") : Color("errorLabelColor"))
                .frame(height: 1)
                .padding(.horizontal, 5)

            if let err = error {
                Text(err)
                    .font(.system(size: iPadValue(13, 16), weight: .bold))
                    .foregroundStyle(Color("errorLabelColor"))
                    .padding(.horizontal, 5)
            }
        }
    }
}

// MARK: - Date picker sheet (ports DatePickerManager)

struct DateOfBirthPickerSheet: View {
    let initial: Date
    let maxDate: Date
    let onConfirm: (Date) -> Void

    @State private var picked: Date
    @Environment(\.dismiss) private var dismiss

    init(initial: Date, maxDate: Date, onConfirm: @escaping (Date) -> Void) {
        self.initial = initial
        self.maxDate = maxDate
        self.onConfirm = onConfirm
        _picked = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("",
                           selection: $picked,
                           in: ...maxDate,
                           displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                Spacer()
            }
            // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
            // bit-identical to the previous hard-coded `Color.white`,
            // so light mode renders the EXACT same Date of Birth
            // picker. Dark mode picks up the elevated dark surface
            // (#2C2C2E) so the modal sheet adapts naturally instead
            // of being a stark white slab over the dark sign-up flow.
            .background(Theme.Color.surface)
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "xmark")
                        } else {
                            Text(ConstantButtonsTitle.cancelButtonTitle)
                        }
                    }
                    .tint(Color("appBlackColor"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onConfirm(picked) } label: {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "checkmark")
                        } else {
                            Text("Done").fontWeight(.semibold)
                        }
                    }
                    .tint(Color("appBlackColor"))
                }
            }
        }
    }
}
