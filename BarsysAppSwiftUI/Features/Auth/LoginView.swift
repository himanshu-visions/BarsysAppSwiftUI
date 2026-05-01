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
        // Re-entry guard — same rationale as
        // `SignUpViewModel.sendRegistrationOtp`: bail if a previous
        // Get-OTP task is still running so rapid double-taps can't
        // stack identical validation alerts. The button has
        // `.disabled(viewModel.isWorking)`, but validation runs
        // BEFORE `isWorking` was previously flipped, so multiple
        // queued taps all hit the early-return alert path. Setting
        // `isWorking = true` up-front and resetting on validation
        // failure closes that race.
        guard !isWorking else { return }
        isWorking = true
        let validation = validatePhone()
        guard validation.isValid else {
            // 1:1 with UIKit `LoginViewController.isLoginDetailsValid`
            // (LoginViewController.swift L443-457):
            //   if cleanedNumber.isEmpty {
            //       imgPhoneUnderLine.backgroundColor = .errorLabelColor
            //       lblErrorPhoneNumber.isHidden = false
            //       lblErrorPhoneNumber.text = Constants.pleaseEnterPhoneNumber
            //       return false
            //   } else if cleanedNumber.count < 8 || > 16 {
            //       lblErrorPhoneNumber.isHidden = false
            //       lblErrorPhoneNumber.text = Constants.invalidPhoneNumber
            //       imgPhoneUnderLine.backgroundColor = .errorLabelColor
            //       return false
            //   }
            // Phone validation is INLINE-ONLY — no `showDefaultAlert(...)`
            // call sits in this branch. The earlier "duplicate alert"
            // QA bug got mis-fixed by removing the inline label and
            // keeping the popup; the correct port is to keep the inline
            // label (red message + red underline) and DROP the popup.
            // The popup path stays for OTP errors (`isOtpValid` L463/467
            // shows `showDefaultAlert`).
            phoneError = validation.errorMessage
            HapticService.error()
            isWorking = false
            return
        }
        phoneError = nil
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
            // Mirrors UIKit's `HapticService.shared.error()` on the
            // OTP-send failure path before the network-error alert.
            HapticService.error()
            alerts.show(message: error.localizedDescription)
        }
    }

    func verifyOtp(auth: AuthService,
                   alerts: AlertQueue,
                   analytics: AnalyticsService,
                   onSuccess: @escaping () -> Void) async {
        guard isOtpValid else {
            // 1:1 with UIKit `LoginViewController+OTP.swift:86`:
            // `HapticService.shared.error()` on invalid-OTP guard.
            HapticService.error()
            alerts.show(message: Constants.invalidOTP)
            return
        }
        isWorking = true
        defer { isWorking = false }

        // Test phone path
        if isTestPhoneNumber() {
            if otp != Constants.testPhoneNumberOtp {
                otp = ""
                // Same UIKit error feedback as the real-OTP mismatch path.
                HapticService.error()
                alerts.show(message: Constants.invalidOTP)
                return
            }
            try? await auth.verifyOtp(phone: formattedPhone, code: otp)
            analytics.track(TrackEventName.loginSuccessFul.rawValue,
                            properties: ["phone_number": formattedPhone])
            // 1:1 with UIKit `AuthCoordinator.swift:60`:
            // `HapticService.shared.success()` fires on login-complete
            // before the coordinator advances.
            HapticService.success()
            onSuccess()
            return
        }

        do {
            try await auth.verifyOtp(phone: formattedPhone, code: otp)
            // Persist the country picked at login alongside the phone
            // — 1:1 with UIKit `verifyOTPForLoginOry` which writes
            // BOTH `storePhone(...)` AND `storeCountryName(...)` so
            // `MyProfileViewController+ProfileSetup.refreshProfile()`
            // can resolve the flag/dial-code without falling back to
            // `defaultCountrySelection` (USA). The SwiftUI
            // `OryAPIClient.verifyOtp` writes phone but not country
            // (the picker selection lives on the View only), so the
            // fix lands here in the LoginViewModel success path. If
            // the server's `/my/profile` response later returns a
            // non-empty country, `fetchAndSyncProfile` will overwrite
            // this with the server value — but only when the server
            // actually has one set (it won't clobber India with USA
            // when the account has no country recorded).
            UserDefaultsClass.storeCountryName(selectedCountry.name)
            analytics.track(TrackEventName.loginSuccessFul.rawValue,
                            properties: ["phone_number": formattedPhone])
            // 1:1 with UIKit `AuthCoordinator.swift:60`.
            HapticService.success()
            onSuccess()
        } catch {
            analytics.track(TrackEventName.loginUnsuccessfulOTP.rawValue,
                            properties: ["phone_number": formattedPhone])
            otp = ""
            // Mirrors UIKit's error-haptic before the OTP-failure alert.
            HapticService.error()
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
                            .frame(width: iPadValue(219, 440), height: iPadValue(20, 40))
                            .invertedInDarkMode(colorScheme == .dark)
                            .padding(.top, iPadValue(94, 130))

                        // Tagline
                        Text("Log in to explore smart cocktail recipes and effortless drink-making with Barsys.")
                            .font(.system(size: iPadValue(13, 17)))
                            .foregroundStyle(Color("appBlackColor"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, iPadValue(45, 80))
                            .padding(.top, iPadValue(20, 30))

                        Spacer(minLength: iPadValue(32, 50))

                        // Bottom login card — capped width on iPad so the
                        // narrow phone-style form stays centered instead of
                        // stretching edge-to-edge on the iPad canvas.
                        loginCard
                            .frame(maxWidth: iPadMaxWidth(540))
                            .padding(.horizontal, 30)
                            .padding(.bottom, iPadValue(50, 60))
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
        // Keyboard accessory toolbar (ports BarsysApp/Controllers/Login/
        // LoginViewController+Toolbar.setupToolbar). Uses the shared
        // `keyboardDoneCancelToolbar` modifier so the styling stays in
        // sync with every other Cancel+Done accessory in the app —
        // notably the iOS 26 glass variant swaps the text labels for
        // `xmark` / `checkmark` icons.
        //
        // CRITICAL ordering: `.keyboardDoneCancelToolbar` MUST sit
        // BEFORE `.toolbar(.hidden, for: .navigationBar)` and before
        // `.sheet(...)`. SwiftUI resolves toolbar placements against
        // the nearest enclosing context — when a sheet or a hidden
        // nav-bar modifier sits between the field and the
        // `.toolbar { ToolbarItemGroup(placement: .keyboard) }` call,
        // the keyboard placement can get re-rooted into a context that
        // doesn't render input accessories, leaving the Cancel/Done
        // bar missing on first tap (the QA "toolbar not coming"
        // report). Putting the keyboard toolbar first ensures it
        // attaches to the original view hierarchy that contains the
        // text fields.
        .keyboardDoneCancelToolbar(onDone: {
            focusedField = nil
        }, onCancel: {
            focusedField = nil
        })
        // Use the iOS 16+ `.toolbar(.hidden, for: .navigationBar)`
        // instead of the deprecated `.navigationBarHidden(true)` —
        // the former targets ONLY the navigation bar surface, leaving
        // the keyboard toolbar (`.keyboard` placement) untouched. The
        // older modifier could occasionally cascade and suppress
        // sibling toolbar items in the same view chain.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selected: $viewModel.selectedCountry)
        }
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
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        // iPad: preserve aspect ratio so the artwork is not
                        // stretched on the wider/squarer iPad canvas. The
                        // outer `.clipped()` crops any overflow.
                        Image("loginBackgroundImage")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image("loginBackgroundImage")
                            .resizable()
                    }
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
        VStack(alignment: .leading, spacing: iPadValue(18, 22)) {

            Text("Log in with your Phone Number")
                .font(.system(size: iPadValue(12, 16), weight: .bold))
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

            // "Don't have an account? Create one"
            HStack(spacing: 0) {
                Spacer()
                Text("Don't have an account? ")
                    .font(.system(size: iPadValue(11, 14)))
                    .foregroundStyle(Color("silverGrayColor"))
                Button {
                    // Hide keyboard FIRST so the dismiss animation
                    // settles before the SignUp screen pushes onto
                    // the navigation stack — otherwise the keyboard
                    // sliding down and the new screen sliding in
                    // happen simultaneously and read as a glitchy
                    // double-animation. The push is delayed a tick
                    // so iOS finishes the resignFirstResponder cycle
                    // before the navigation transition starts.
                    hideKeyboard()
                    focusedField = nil
                    env.analytics.track(TrackEventName.tapLoginCreateAccount.rawValue)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        path.append(AuthRoute.signUp)
                    }
                } label: {
                    Text("Create one")
                        .font(.system(size: iPadValue(11, 14), weight: .semibold))
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
                            .font(.system(size: iPadValue(28, 36)))
                        // Chevron PNG ships as a dark asset — invert in dark
                        // mode so it stays visible against the dark surface.
                        Image("downArrowSmall")
                            .resizable()
                            .scaledToFit()
                            .frame(width: iPadValue(14, 18))
                            .foregroundStyle(Color("appBlackColor"))
                            .invertedInDarkMode(colorScheme == .dark)
                        Text(viewModel.countryDialCodeDisplay)
                            .font(.system(size: iPadValue(17, 22), weight: .light))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                }
                .buttonStyle(.plain)

                // Phone number text field — placeholder "Phone no."
                TextField("Phone no.", text: $viewModel.phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    // Bind to the screen-level FocusState so the
                    // keyboard accessory toolbar (`.keyboardDoneCancelToolbar`)
                    // attaches reliably. Without an explicit
                    // `.focused(...)` link SwiftUI sometimes races the
                    // keyboard's appearance against the toolbar's
                    // attachment, leaving the Cancel/Done bar missing
                    // on the first tap into the field — the QA
                    // "toolbar not coming sometimes" report. Binding
                    // it gives SwiftUI an observable focus value to
                    // re-evaluate the toolbar against, plus lets the
                    // onDone/onCancel handlers actually resign focus
                    // (previously they set `focusedField = nil` while
                    // nothing was bound, so the line was a no-op).
                    .focused($focusedField, equals: .phone)
                    .font(.system(size: iPadValue(18, 22), weight: .light))
                    .foregroundStyle(Color("appBlackColor"))
                    .frame(height: iPadValue(40, 50))
                    // 1:1 with UIKit `LoginViewController+Accessibility.swift:19-20`:
                    // VoiceOver users hear the field's purpose + the OTP-flow hint.
                    .accessibilityLabel("Phone number")
                    .accessibilityHint("Enter your phone number to receive an OTP")
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

            // Underline — 1:1 with UIKit `imgPhoneUnderLine`
            // (LoginViewController.swift). Default state is the
            // `silverGrayColor` storyboard tint; on validation failure
            // UIKit flips the colour to `errorLabelColor` (lines 446
            // and 449/454) so the underline reads red while the
            // inline error label is shown.
            Rectangle()
                .fill(viewModel.phoneError == nil
                      ? Color("silverGrayColor")
                      : Color("errorLabelColor"))
                .frame(height: 1)
                .padding(.horizontal, 5)

            // 1:1 with UIKit `lblErrorPhoneNumber`
            // (LoginViewController.swift L23). System 13pt bold,
            // `errorLabelColor`, hidden by default and shown only when
            // `isLoginDetailsValid` flags an empty / invalid phone.
            // The earlier port removed this label thinking the popup
            // path was authoritative — UIKit ONLY surfaces phone
            // validation inline, so the label is restored here. SignUp
            // already follows this pattern (`SignUpView.phoneRow`
            // shows `viewModel.errorPhone` below the underline).
            if let err = viewModel.phoneError {
                Text(err)
                    .font(.system(size: iPadValue(13, 16), weight: .bold))
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
        VStack(spacing: iPadValue(12, 16)) {
            // Row 1: OTP label + 6 square boxes
            HStack(alignment: .center, spacing: iPadValue(12, 16)) {
                Text("OTP")
                    .font(.system(size: iPadValue(18, 22), weight: .light))
                    .foregroundStyle(Color("silverGrayColor"))
                OTPBoxField(code: $viewModel.otp)
            }
            .padding(.horizontal, 5)

            // Row 2: timer (LEFT) + "Didn't receive…? Resend" (RIGHT)
            HStack(alignment: .center) {
                if viewModel.timeRemaining > 0 {
                    Text(viewModel.timerDisplayText)
                        .font(.system(size: iPadValue(11, 14)))
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
                .font(.system(size: iPadValue(11, 14)))
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
                    .font(.system(size: iPadValue(11, 14), weight: .semibold))
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
                // Glass loader stays up across the entire verify →
                // profile fetch → catalog preload → navigation chain
                // (1:1 with the UIKit `showGlassLoader(message:)` that
                // wrapped LoginViewController+OTP.swift's verify path).
                // `env.auth.isAuthenticated` flips inside `auth.verifyOtp`
                // on the success path, so checking it after `verifyOtp`
                // returns tells us which branch ran without needing a
                // captured-var flag in the success closure.
                env.loading.show(Constants.loaderLoggingIn)
                await viewModel.verifyOtp(auth: env.auth,
                                          alerts: env.alerts,
                                          analytics: env.analytics) { }
                if env.auth.isAuthenticated {
                    await env.onLoginSuccessAsync()
                    router.didLogin()
                }
                env.loading.hide()
            } else {
                env.loading.show(Constants.loaderSendingOTP)
                await viewModel.sendOtp(api: env.api,
                                        alerts: env.alerts,
                                        analytics: env.analytics)
                env.loading.hide()
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

// MARK: - iPad sizing helper
//
// Login and Sign-Up are storyboard ports sized for an iPhone canvas; on
// iPad those phone-spec values look tiny against the larger screen. The
// helpers below pick a separate value when running on iPad and return
// the original iPhone value otherwise, so the existing iPhone layout
// stays bit-identical while iPad gets bumped fonts / frames / paddings.

/// Returns `pad` on iPad, `phone` on iPhone.
func iPadValue<T>(_ phone: T, _ pad: T) -> T {
    UIDevice.current.userInterfaceIdiom == .pad ? pad : phone
}

/// Returns `pad` on iPad, `.infinity` on iPhone — used to cap form-card
/// width on iPad so it doesn't stretch edge-to-edge on the wide canvas.
func iPadMaxWidth(_ pad: CGFloat) -> CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? pad : .infinity
}
