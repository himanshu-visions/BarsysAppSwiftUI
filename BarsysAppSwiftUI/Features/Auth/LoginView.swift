//
//  LoginView.swift
//  BarsysAppSwiftUI
//
//  Direct port of BarsysApp/Controllers/Login/LoginViewController.swift
//  + LoginViewModel.swift + LoginViewController+OTP.swift, with the visual
//  layout pulled from BarsysApp/StoryBoards/Base.lproj/User.storyboard.
//
//  Storyboard structure (from User.storyboard, view "2M2-tY-vNi"):
//
//    UIImageView (loginBackgroundImage, scaleAspectFill, fills entire view)
//      └ container "7z7-nd-N4L" (overlays the background)
//          ├ UIImageView splashAppIcon (219x20 @ top:94, centered horizontally)
//          ├ UILabel "Log in to explore smart cocktail recipes and effortless
//          │          drink-making with Barsys."  (system 13pt appBlackColor,
//          │          centered, 0 lines, 45pt left/right, top:20 below logo)
//          └ Login card "FTr-d8-3bm" (333 wide, 30pt margins, bottom:50)
//              ├ "Log in with your Phone Number" (boldSystem 12pt appBlackColor)
//              ├ Phone stack:
//              │     [flag (34pt)] [downArrowSmall] [code (17pt light)]
//              │     [phone TextField (18pt light, "Phone no.", numberPad)]
//              │     1pt silverGrayColor underline
//              ├ Email stack (hidden by default)
//              ├ OTP view (hidden until OTP sent):
//              │     "OTP" label
//              │     6 OtpTextField boxes (square, paleBlueGrayColor border,
//              │     roundCorners 10, 1pt border)
//              │     "Didn't receive a verification code? Resend"
//              ├ Login button (lightSilverColor bg, appBlackColor title,
//              │     boldSystem 12pt, 43pt height, roundCorners 8,
//              │     title "Login with OTP" → "Login")
//              └ "Don't have an account? Create one"
//

import SwiftUI

// MARK: - Login view model (ports LoginViewModel.swift)

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var loginMethod: LoginMethod = .phone
    @Published var phone: String = ""
    @Published var otp: String = ""
    @Published var otpSent: Bool = false
    @Published var timeRemaining: Int = 0
    @Published var isTimerRunning: Bool = false
    @Published var allCountries: [Country] = []
    @Published var selectedCountry: Country = .unitedStates
    @Published var isWorking: Bool = false
    @Published var phoneError: String? = nil

    private var timer: Timer?

    init() {
        loadCountries()
    }

    /// Ports LoginViewModel.loadCountries() — reads Countries.json and selects
    /// the country matching the device's region code.
    func loadCountries() {
        let list = CountryLoader.loadAll()
        allCountries = list
        let regionCode = Self.deviceRegionCode()
        if let match = list.first(where: { $0.code.lowercased() == regionCode }) {
            selectedCountry = match
        } else if let us = list.first(where: { $0.code == "US" }) {
            selectedCountry = us
        }
    }

    static func deviceRegionCode() -> String {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier.lowercased() ?? "us"
        } else {
            return Locale.current.regionCode?.lowercased() ?? "us"
        }
    }

    // MARK: - Computed properties (mirror LoginViewModel.swift)

    var countryFlag: String { selectedCountry.flag }
    var countryDialCodeDisplay: String { "+\(selectedCountry.dialCode)" }
    var formattedPhone: String { "+\(selectedCountry.dialCode)\(phone)" }

    var timerDisplayText: String {
        let secs = String(format: "%02d", timeRemaining)
        return "00:\(secs) sec"
    }

    /// Ports LoginViewModel.isPhoneNumberValid(_:)
    func validatePhone() -> (isValid: Bool, errorMessage: String?) {
        if phone.isEmpty { return (false, Constants.pleaseEnterPhoneNumber) }
        if phone.count < 8 || phone.count > 16 { return (false, Constants.invalidPhoneNumber) }
        return (true, nil)
    }

    /// Ports LoginViewModel.isOtpValid(_:)
    var isOtpValid: Bool { otp.count == 6 && otp.allSatisfy(\.isNumber) }

    /// Ports LoginViewModel.isTestPhoneNumber(_:)
    func isTestPhoneNumber() -> Bool {
        formattedPhone == Constants.testPhoneNumber
    }

    // MARK: - Timer (ports startTimer/stopTimer/updateTimer)

    func startTimer() {
        stopTimerInternal()
        isTimerRunning = true
        timeRemaining = 60
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.timeRemaining > 0 else {
                    self.stopTimerInternal()
                    return
                }
                self.timeRemaining -= 1
            }
        }
    }

    private func stopTimerInternal() {
        isTimerRunning = false
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Network actions (port sendOtp / verifyOtp / verifyTestUser)

    func sendOtp(api: APIClient,
                 alerts: AlertQueue,
                 analytics: AnalyticsService,
                 isResend: Bool = false) async {
        let validation = validatePhone()
        guard validation.isValid else {
            phoneError = validation.errorMessage
            alerts.show(message: validation.errorMessage ?? Constants.invalidPhoneNumber)
            return
        }
        phoneError = nil
        isWorking = true
        defer { isWorking = false }

        // Test phone shortcut: skip the API and immediately show the OTP view.
        if isTestPhoneNumber() {
            if !isResend {
                analytics.track(TrackEventName.tapLoginGetOTP.rawValue,
                                properties: ["phone_number": formattedPhone])
            }
            otpSent = true
            startTimer()
            alerts.show(message: Constants.otpSentSuccessfully)
            return
        }

        do {
            try await api.sendOtp(phone: formattedPhone)
            if !isResend {
                analytics.track(TrackEventName.tapLoginGetOTP.rawValue,
                                properties: ["phone_number": formattedPhone])
            } else {
                analytics.track(TrackEventName.tapLoginResend.rawValue,
                                properties: ["phone_number": formattedPhone])
            }
            otpSent = true
            startTimer()
            alerts.show(message: Constants.otpSentSuccessfully)
        } catch {
            analytics.track(TrackEventName.loginUnsuccessfulOTP.rawValue,
                            properties: ["phone_number": formattedPhone])
            alerts.show(message: error.localizedDescription)
        }
    }

    func verifyOtp(auth: AuthService,
                   alerts: AlertQueue,
                   analytics: AnalyticsService,
                   onSuccess: @escaping () -> Void) async {
        guard isOtpValid else {
            alerts.show(message: Constants.invalidOTP)
            return
        }
        isWorking = true
        defer { isWorking = false }

        // Test phone path
        if isTestPhoneNumber() {
            if otp != Constants.testPhoneNumberOtp {
                otp = ""
                alerts.show(message: Constants.invalidOTP)
                return
            }
            try? await auth.verifyOtp(phone: formattedPhone, code: otp)
            analytics.track(TrackEventName.loginSuccessFul.rawValue,
                            properties: ["phone_number": formattedPhone])
            onSuccess()
            return
        }

        do {
            try await auth.verifyOtp(phone: formattedPhone, code: otp)
            analytics.track(TrackEventName.loginSuccessFul.rawValue,
                            properties: ["phone_number": formattedPhone])
            onSuccess()
        } catch {
            analytics.track(TrackEventName.loginUnsuccessfulOTP.rawValue,
                            properties: ["phone_number": formattedPhone])
            otp = ""
            alerts.show(message: error.localizedDescription)
        }
    }

    /// User edited the phone number after OTP was sent — reset OTP state and
    /// flip the button title back to "Login with OTP".
    func resetOtpState() {
        otp = ""
        otpSent = false
        stopTimerInternal()
    }
}

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = LoginViewModel()
    @Binding var path: NavigationPath

    @State private var showCountryPicker = false
    @FocusState private var focusedField: FocusField?
    @Environment(\.colorScheme) private var colorScheme

    /// Fields that can hold the keyboard focus — matches the UIKit setupToolbar
    /// outlets (txtPhoneNumber + txtOtp1…6).
    enum FocusField: Hashable {
        case phone
        case otp
    }

    var body: some View {
        // Two-layer design:
        //
        //   1. Background layer — own `.ignoresSafeArea(.all)` so the image
        //      always covers the full screen, never zooms, never moves.
        //
        //   2. Content layer — a ScrollView that wraps the entire screen so
        //      the user can scroll the whole layout when the keyboard is up.
        //      A tap anywhere outside the form dismisses the keyboard. A
        //      keyboard accessory toolbar (Cancel / Done) mirrors the UIKit
        //      `setupToolbar()` behaviour.
        ZStack {

            // 1. Background layer (own safe-area override)
            backgroundLayer

            // 2. Content layer — scrollable, keyboard-aware
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Splash logo (storyboard: 219x20, top:94).
                        // The PNG is a dark wordmark on transparency — invert
                        // it in dark mode so it reads white on the dark
                        // surface. Light mode keeps the original pixels.
                        Image("splashAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 219, height: 20)
                            .invertedInDarkMode(colorScheme == .dark)
                            .padding(.top, 94)

                        // Tagline
                        Text("Log in to explore smart cocktail recipes and effortless drink-making with Barsys.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color("appBlackColor"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 45)
                            .padding(.top, 20)

                        Spacer(minLength: 32)

                        // Bottom login card
                        loginCard
                            .padding(.horizontal, 30)
                            .padding(.bottom, 50)
                    }
                    // Make the VStack fill the screen height so the Spacer
                    // actually pushes the login card down — otherwise the
                    // ScrollView would collapse the Spacer to zero.
                    .frame(minHeight: proxy.size.height)
                    // Tap anywhere on the content layer outside the form to
                    // dismiss the keyboard. `contentShape` makes empty areas
                    // inside the VStack tappable too.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        focusedField = nil
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                // Animate loginCard appearance/OTP expansion smoothly.
                .animation(.easeInOut(duration: 0.25), value: viewModel.otpSent)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selected: $viewModel.selectedCountry)
        }
        // Keyboard accessory toolbar (ports BarsysApp/Controllers/Login/
        // LoginViewController+Toolbar.setupToolbar). Uses the shared
        // `keyboardDoneCancelToolbar` modifier so the styling stays in
        // sync with every other Cancel+Done accessory in the app —
        // notably the iOS 26 glass variant swaps the text labels for
        // `xmark` / `checkmark` icons.
        .keyboardDoneCancelToolbar(onDone: {
            focusedField = nil
        }, onCancel: {
            focusedField = nil
        })
        .onAppear {
            // 1:1 with UIKit `UIViewController+Navigation.swift` L14-19:
            //   if UIApplication.shared.topViewController() is LoginViewController {
            //       NetworkingUtility.resetExpirationFlag()
            //       return
            //   }
            // Once the user is back on the Login screen, a subsequent
            // Ory session can safely raise a fresh "session expired"
            // alert. Without this reset the dedup flag would stay
            // stuck `true` after the first expiration and swallow
            // every future 401 until the app is relaunched.
            SessionExpirationHandler.shared.reset()
        }
    }

    /// Standalone background image layer. Wrapped in its OWN ZStack with
    /// `.ignoresSafeArea(.all)` so it covers the full screen including the
    /// keyboard region — and crucially, this safe-area override does NOT
    /// propagate to the sibling content layer in `body`, so the form still
    /// gets normal keyboard avoidance.
    @ViewBuilder
    private var backgroundLayer: some View {
        GeometryReader { proxy in
            Group {
                if colorScheme == .dark {
                    // `loginBackgroundImage` has no dark variant and is a
                    // light glass artwork; leaving it in dark mode renders
                    // near-white adaptive text unreadable. Swap for the
                    // adaptive `primaryBackgroundColor` (dark surface) so the
                    // existing adaptive text/border colors stay legible.
                    // Light mode continues to render the original image.
                    Color("primaryBackgroundColor")
                } else {
                    Image("loginBackgroundImage")
                        .resizable()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea(.all)
        .allowsHitTesting(false)
    }

    // MARK: - Login card (mirrors FTr-d8-3bm in storyboard)

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 18) {

            Text("Log in with your Phone Number")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color("appBlackColor"))
                .padding(.top, 8)
                .padding(.leading, 5)

            phoneRow

            if viewModel.otpSent {
                otpSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Primary action button (lightSilverColor background, 43pt, 8pt corner)
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

            // "Don't have an account? Create one"
            HStack(spacing: 0) {
                Spacer()
                Text("Don't have an account? ")
                    .font(.system(size: 11))
                    .foregroundStyle(Color("silverGrayColor"))
                Button {
                    env.analytics.track(TrackEventName.tapLoginCreateAccount.rawValue)
                    path.append(AuthRoute.signUp)
                } label: {
                    Text("Create one")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color("appBlackColor"))
                }
                Spacer()
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Color.clear)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.otpSent)
    }

    // MARK: - Phone row

    private var phoneRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                // Country flag + arrow + dial code (matches storyboard pu5-jL-CIJ stack)
                Button {
                    hideKeyboard()
                    showCountryPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedCountry.flag)
                            .font(.system(size: 28))
                        // Chevron PNG ships as a dark asset — invert in dark
                        // mode so it stays visible against the dark surface.
                        Image("downArrowSmall")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14)
                            .foregroundStyle(Color("appBlackColor"))
                            .invertedInDarkMode(colorScheme == .dark)
                        Text(viewModel.countryDialCodeDisplay)
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .buttonStyle(.plain)

                // Phone number text field — placeholder "Phone no."
                TextField("Phone no.", text: $viewModel.phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(height: 40)
                    .onChange(of: viewModel.phone) { newValue in
                        // Re-implements the editing-while-OTP-shown rule from
                        // LoginViewController.textField(_:shouldChangeCharactersIn:)
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue {
                            viewModel.phone = digits
                        }
                        if digits.count > NumericConstants.maxPhoneNumCharacterCount {
                            viewModel.phone = String(digits.prefix(NumericConstants.maxPhoneNumCharacterCount))
                        }
                        if !digits.isEmpty {
                            viewModel.phoneError = nil
                            if viewModel.otpSent { viewModel.resetOtpState() }
                        }
                    }
            }
            .padding(.horizontal, 5)

            // Underline (1pt silverGrayColor)
            Rectangle()
                .fill(Color("silverGrayColor"))
                .frame(height: 1)
                .padding(.horizontal, 5)

            if let err = viewModel.phoneError {
                Text(err)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color("errorLabelColor"))
                    .padding(.horizontal, 5)
            }
        }
    }

    // MARK: - OTP section
    //
    // Storyboard layout (CWe-79-tux):
    //   ┌──────────────────────────────────────────────────────┐
    //   │  OTP                  ▢ ▢ ▢ ▢ ▢ ▢                    │  ← row 1
    //   │  00:60 sec     Didn't receive a verification code? Resend  │  ← row 2
    //   └──────────────────────────────────────────────────────┘
    //
    // Row 2 layout matches `Gim-T1-oxd`:
    //   - Timer label `iCc-N5-XNW` LEFT, only visible when timer > 0
    //   - Resend stack `pfF-Ew-cie` RIGHT, ALWAYS visible. Faded (alpha 0.5,
    //     silverGrayColor text) while running, full alpha + appBlackColor when
    //     timer expired — exactly enableDisableResendButton(isEnable:).

    private var otpSection: some View {
        VStack(spacing: 12) {
            // Row 1: OTP label + 6 square boxes
            HStack(alignment: .center, spacing: 12) {
                Text("OTP")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color("silverGrayColor"))
                OTPBoxField(code: $viewModel.otp)
            }
            .padding(.horizontal, 5)

            // Row 2: timer (LEFT) + "Didn't receive…? Resend" (RIGHT)
            HStack(alignment: .center) {
                if viewModel.timeRemaining > 0 {
                    Text(viewModel.timerDisplayText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color("silverGrayColor"))
                } else {
                    // Empty placeholder when timer is done so Resend stays
                    // right-aligned consistently.
                    Color.clear.frame(width: 1, height: 1)
                }

                Spacer()

                resendStack
                    .opacity(viewModel.timeRemaining > 0 ? 0.5 : 1.0)
                    .disabled(viewModel.timeRemaining > 0)
            }
            .padding(.horizontal, 5)
        }
    }

    /// Stack matching `pfF-Ew-cie`: "Didn't receive a verification code? " + "Resend"
    private var resendStack: some View {
        HStack(spacing: 0) {
            Text("Didn't receive a verification code? ")
                .font(.system(size: 11))
                .foregroundStyle(viewModel.timeRemaining > 0
                                 ? Color("silverGrayColor")
                                 : Color("silverGrayColor"))
            Button {
                Task {
                    await viewModel.sendOtp(api: env.api,
                                            alerts: env.alerts,
                                            analytics: env.analytics,
                                            isResend: true)
                }
            } label: {
                Text("Resend")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.timeRemaining > 0
                                     ? Color("silverGrayColor")
                                     : Color("appBlackColor"))
            }
        }
    }

    // MARK: - Primary button title + tap handling
    //
    // Mirrors LoginViewController.loginWithOtpAction(_:): if button title is
    // "Login with OTP" → send OTP, otherwise → verify OTP.

    private var primaryButtonTitle: String {
        viewModel.otpSent ? "Login" : "Login with OTP"
    }

    private func handlePrimaryTap() {
        hideKeyboard()
        Task {
            if viewModel.otpSent {
                await viewModel.verifyOtp(auth: env.auth,
                                          alerts: env.alerts,
                                          analytics: env.analytics) {
                    // Fetch data then navigate — Task needed because onSuccess is sync
                    Task {
                        await env.onLoginSuccessAsync()
                        router.didLogin(hasSeenTutorial: env.preferences.hasSeenTutorial)
                    }
                }
            } else {
                await viewModel.sendOtp(api: env.api,
                                        alerts: env.alerts,
                                        analytics: env.analytics)
            }
        }
    }
}

// MARK: - Helpers

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    /// Applies `colorInvert()` only when `active` is true — used by Login /
    /// SignUp to flip the dark PNG assets (splashAppIcon, downArrowSmall,
    /// tickIcon) to white in dark mode while leaving light mode untouched.
    @ViewBuilder
    func invertedInDarkMode(_ active: Bool) -> some View {
        if active {
            self.colorInvert()
        } else {
            self
        }
    }
}
