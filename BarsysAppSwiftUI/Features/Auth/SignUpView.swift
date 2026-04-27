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
        guard isSignUpDetailsValid(alerts: alerts) else { return }
        isWorking = true
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
                        Image("signUpBg")
                            .resizable()
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
                            .frame(width: 219, height: 20)
                            .invertedInDarkMode(colorScheme == .dark)
                            .padding(.top, 94)

                        Text("Let's create your account")
                            .font(.system(size: 13))
                            .foregroundStyle(Color("appBlackColor"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 45)
                            .padding(.top, 20)

                        formCard
                            .padding(.horizontal, 30)
                            .padding(.top, 60)
                            .padding(.bottom, 30)
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
        .navigationBarBackButtonHidden(true)
        // Keyboard accessory toolbar — ports SignUpViewController+TextFieldDelegate.setupToolbar
        // (Cancel + flexibleSpace + Done over phone / name / email /
        // OTP fields). Shared modifier swaps text labels for
        // `xmark` / `checkmark` icons on iOS 26 glass.
        .keyboardDoneCancelToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    env.analytics.track(TrackEventName.tapSignupLogIn.rawValue)
                    viewModel.stopTimerInternal()
                    path.removeLast()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color("appBlackColor"))
                }
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selected: Binding(
                get: { viewModel.selectedCountry ?? .unitedStates },
                set: { viewModel.selectedCountry = $0 }
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
        VStack(alignment: .leading, spacing: 18) {

            Text("Sign up with your Phone Number")
                .font(.system(size: 12, weight: .bold))
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 43)
                .background(Color("lightSilverColor"))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(viewModel.isWorking)
            .padding(.top, 4)

            // Already have an account? Log in
            HStack(spacing: 0) {
                Spacer()
                Text("Already have an account? ")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("silverGrayColor"))
                Button {
                    env.analytics.track(TrackEventName.tapSignupLogIn.rawValue)
                    viewModel.stopTimerInternal()
                    path.removeLast()
                } label: {
                    Text("Log in")
                        .font(.system(size: 11, weight: .semibold))
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
                        Text(viewModel.countryFlag).font(.system(size: 28))
                        Image("downArrowSmall")
                            .resizable().scaledToFit().frame(width: 14)
                            .foregroundStyle(Color("appBlackColor"))
                            .invertedInDarkMode(colorScheme == .dark)
                        Text(viewModel.countryDialCodeDisplay)
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .buttonStyle(.plain)

                TextField("Phone no.", text: $viewModel.phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(height: 40)
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
                    .font(.system(size: 13, weight: .bold))
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
        VStack(spacing: 12) {
            // Row 1: OTP label + boxes
            HStack(alignment: .center, spacing: 12) {
                Text("OTP")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color("silverGrayColor"))
                OTPBoxField(code: $viewModel.otp)
            }
            .padding(.horizontal, 5)

            // Row 2: timer LEFT + Resend RIGHT
            HStack(alignment: .center) {
                if viewModel.isTimerRunning && viewModel.timeLimit > 0 {
                    Text(viewModel.timerDisplayText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("silverGrayColor"))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }

                Spacer()

                let isResendEnabled = !(viewModel.isTimerRunning && viewModel.timeLimit > 0)
                HStack(spacing: 0) {
                    Text("Didn't receive a verification code? ")
                        .font(.system(size: 11))
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
                            .font(.system(size: 11, weight: .semibold))
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
        HStack(alignment: .top, spacing: 10) {
            Button {
                viewModel.isTermsAccepted.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color("brandTanColor"),
                                lineWidth: viewModel.isTermsAccepted ? 4 : 2)
                        .frame(width: 22, height: 22)
                    if viewModel.isTermsAccepted {
                        // Tick PNG is dark — invert in dark mode so the
                        // checkmark stays visible inside the tan outline box.
                        Image("tickIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .invertedInDarkMode(colorScheme == .dark)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            termsAttributedText
                .font(.system(size: 11))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .onTapGesture {
                    env.analytics.track(TrackEventName.tapSignupTermsOfService.rawValue)
                    // 1:1 port of UIKit `SignUpViewController+FormValidation.swift`
                    // L72-74: open the Terms URL in the IN-APP web view
                    // (matching the custom 50pt black header + white
                    // back button chrome), not an external Safari tab.
                    if let url = URL(string: WebViewURLs.termsOfUseWebUrl) {
                        path.append(AuthRoute.web(url))
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
        let prefix = Text("By continuing, you agree to our ").foregroundColor(black)
        let terms = Text("Terms of Service")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(black)
        let and = Text(" and ").foregroundColor(black)
        let privacy = Text("Privacy Policy")
            .font(.system(size: 11, weight: .bold))
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
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color("appBlackColor"))
                .frame(height: 40)
                .padding(.horizontal, 5)

            Rectangle()
                .fill(error == nil ? Color("paleBlueGrayColor") : Color("errorLabelColor"))
                .frame(height: 1)
                .padding(.horizontal, 5)

            if let err = error {
                Text(err)
                    .font(.system(size: 13, weight: .bold))
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
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(text.isEmpty
                                         ? Color("inputPlaceholderColor")
                                         : Color("appBlackColor"))
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(Color("silverGrayColor"))
                }
                .frame(height: 40)
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
                    .font(.system(size: 13, weight: .bold))
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
