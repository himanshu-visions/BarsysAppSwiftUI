//
//  AuthFlowView.swift
//  BarsysAppSwiftUI
//
//  Container for the pre-authenticated flow. Replaces AuthCoordinator.
//

import SwiftUI

struct AuthFlowView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            LoginView(path: $path)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp: SignUpView(path: $path)
                    // 1:1 port of UIKit WebViewController — custom
                    // 50pt black header + white back button + bold
                    // 16pt white title, system nav + tab bar hidden,
                    // offline alert on load failure.
                    // Title derived from URL: terms-of-service →
                    // "Terms of Service", privacy-policy → "Privacy
                    // Policy". Matches UIKit's `showWebView(urlStr:title:)`
                    // call sites in SignUpViewController+FormValidation L72-74.
                    case .web(let url):
                        BarsysWebView(url: url, title: authWebTitle(for: url))
                    }
                }
        }
    }
}

enum AuthRoute: Hashable {
    case signUp
    case web(URL)
}

/// 1:1 port of UIKit `SignUpViewController+FormValidation.swift` L72-74
/// — maps the tapped legal URL back to the title shown in the web view.
/// SignUp only opens Terms + Privacy links (the other WebViewURLs are
/// only reachable from the side menu after login), so two branches
/// suffice here.
private func authWebTitle(for url: URL) -> String {
    let s = url.absoluteString
    if s == WebViewURLs.termsOfUseWebUrl { return "Terms of Service" }
    if s == WebViewURLs.privacyWebUrl    { return "Privacy Policy" }
    return ""
}
