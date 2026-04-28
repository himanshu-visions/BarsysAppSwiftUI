//
//  Constants.swift
//  BarsysAppSwiftUI
//
//  Direct port of BarsysApp/Helpers/Constants/Constants.swift — every user-facing
//  string preserved verbatim so the SwiftUI app shows identical copy.
//

import Foundation
import CoreGraphics

enum NumericConstants {
    static let ounceConversionFactor: CGFloat = 0.033814
    static let minimumAge = 21
    static let zeroDoubleValue = 0.0
    static let maximumQuantityIntMLFor360 = 750
    static let maximumQuantityDoubleMLFor360 = 750.0
    static let maximumQuantityIntMLForCoaster = 1500
    static let maximumQuantityDoubleMLForCoaster = 1500.0
    static let maxOzValueFor360: Double = 25.36
    static let maxOzValueForCoaster: Double = 50.72
    static let minimumQtyInt = 5
    static let minimumQtyDouble = 5.0
    static let minimumQtyInOzDouble = 0.17
    static let maxIncrementDecrementValueForMl: Double = 10
    static let maxIncrementDecrementValueForOz: Double = 0.33814
    static let oneMlValue: Double = 29.5735
    static let recipeNameCharacterLimit = 150
    static let maxPhoneNumCharacterCount = 15
    /// 24 hours expressed in seconds
    static let perishableInterval: TimeInterval = 86400.0
}

enum Constants {
    static let testPhoneNumber = "+917042199800"
    static let testPhoneNumberOtp = "381260"

    static let recipesLostSafetyMessage = "Are you sure you want to leave this screen? Any unsaved recipes will be lost."
    static let machineIsOffline = "The machine is currently offline. Please try again later."

    static let wouldYouLikeRatingTextForSideMenu = "Would you like to be brought to the App store to review the Barsys App?"
    static let wouldYouLikeRatingTextAfterDrinkCompleted = "You made a drink with Barsys.\nWe would love to hear your feedback on the experience in the app store."

    static let drinkCompletedStr = "Drink Completed"

    static let perishableIngredientsCleaned = "Perishable Ingredients Cleaned"
    static let setupStationsTextForBarBot = "Setup Stations"
    static let craftTitle = "Craft"
    static let viewTitle = "View"

    static let barsysRecipesTitleHeader = "Barsys Recipes"
    static let barsysRecipesDescriptionHeader = "These are signature Barsys recipes designed to work seamlessly with the machine."
    static let barsysMixlistTitleHeader = "Barsys Mixlists/Cocktail Kits you can Buy"
    static let barsysMixlistDescriptionHeader = "Here's a curated Barsys mixlist with six easy crowd-pleasers for your cocktail kit."

    static let pleaseConnectWithBarsys360Device = "Please connect with the Barsys360 machine to proceed"
    static let pleaseSelectDeviceTitle = "Please select the device you want to connect"
    static let emptyStation = "Empty Station"

    static let mixlistAddMessage = "Your mixlist has been saved successfully."
    static let pleaseAddMixlistName = "Please enter mixlist name."
    static let recipeAddMessage = "Your drink has been saved successfully."
    static let recipeDeleteMessage = "Your drink has been deleted successfully."
    static let recipeUpdateMessage = "Your drink has been updated successfully."

    static let pouredTitle = "Poured"
    static let pourNowTitle = "Pour now"
    static let nowPouringTitle = "Now pouring"

    static let descriptionControlCenterFor360 = "Manage your Barsys 360 with access to tutorials, station settings, cleaning, reset, and disconnection."
    static let descriptionControlCenterForCoaster = "This section provides essential controls for your Barsys Coaster, including device disconnection, system reset, and access to the user tutorial."

    static let likeSuccessMessage = "Recipe successfully added to My Favourites."
    static let unlikeSuccessMessage = "Recipe successfully removed from My Favourites."

    static let addToFavTitle = "Add to favourites"
    static let unFavouriteTitle = "Unfavourite"
    /// Shown on RecipePage's bottom favourite-CTA when the user has
    /// edited any ingredient quantity. Matches UIKit
    /// `Constants.addToMyDrinksTitle` — "Save to My Drinks".
    static let addToMyDrinksTitle = "Save to My Drinks"
    // `unsavedChangesForRecipe` is already declared further down in this
    // file (line ~114) with UIKit's original copy; don't redeclare here.
    static let ozText = "Oz"
    static let mlText = "ML"
    static let more = "More"
    static let noMixlistFound = "No Mixlist Found"
    static let acceptTermsAndConditions = "Please accept the Terms of Service and Privacy Policy to continue."
    static let message = "Message"
    static let addIngredientsToStationsTO = "Add ingredients to the station to make your drink."
    static let readyToPourTitle = "Ready to Pour"
    static let enterQuantityAlert = "Please enter quantity"
    static let enterMinimumQtyAlertOZ = "Minimum quantity allowed is 0.17 Oz."
    static let enterMinimumQtyAlertML = "Minimum quantity allowed is 5 ml."

    static let maximumVolume25OZ = "Maximum Volume: 25.36 oz."
    static let maximumVolume50OZ = "Maximum Volume: 50.72 oz."
    static let maximumVolume750 = "Maximum Volume: 750 ml."

    static let pleaseSelectAnOption = "Please select an option"
    static let mixlistsTitle = "Mixlists"

    static let noMixlistsAvailableForMyBar = "No mixlist available for the\ningredient combination currently\nin my bar.\n Please add / change the ingredient\nin my bar to see what you\ncan craft."
    static let noMixlistsAvailable = "No mixlist available for the\ningredient combination currently\nin your stations.\n Please add / change the ingredient\nin your stations to see what you\ncan craft."
    static let noRecipesAvailable = "No recipes available for the\ningredient combination currently\nin your stations.\n Please add / change the ingredient\nin your stations to see what you\ncan craft."

    static let hasSameIngredientInStation = "A similar ingredient is already added in one of the stations. Please choose a different ingredient"
    static let hasSameIngredientInDrink = "A similar ingredient has already been added to this drink. Please select a different one."
    static let hasSameIngredientInMyBar = "A similar ingredient has already been added. Please select a different one."

    // 1:1 ports of UIKit ingredient-detection error copy
    // (EditViewModel+API.processUploadedIngredients).
    static let ingredientUnableToAddError = "Unable to add ingredient. Please try again."
    static let ingredientCannotBeUsedHere = "This ingredient cannot be used here."
    static let moreThanOneIngredientIdentified = "More than one ingredient identified in the image. Please scan one ingredient at a time."
    static let addingIngredientLoaderText = "Adding ingredients"

    // 1:1 ports of UIKit Craft-validation copy
    // (EditViewController.didPressCraftButton + craftActionInEditScreen).
    /// Shown when Barsys 360 is connected and the user has > 6
    /// non-garnish ingredients. Mirrors UIKit `Constants.maximumQtyIs6`.
    static let maximumQtyIs6 = "Maximum ingredients allowed are 6."
    /// Shown when the user taps Craft on an EDIT recipe with unsaved
    /// changes — gives them a Save / Continue choice. Mirrors UIKit
    /// `Constants.yourChangesWillNotSavedAlert`.
    static let yourChangesWillNotSavedAlert = "Your changes will not be saved. Would you like to continue?"

    static let unsavedChangesForRecipe = "You have unsaved changes. If you leave this page, your changes will be lost."
    static let systemReset = "Are you sure you want to reset the system?"
    static let doYouWantToDeleteIngredient = "Are you sure you want to delete this ingredient?"
    static let doYouWantToDeleteRecipe = "Are you sure you want to delete this recipe?"
    /// Logout confirmation popup title. Matches the "Are you sure you
    /// want to …" wording used by every other confirm popup in the
    /// codebase (delete recipe, delete ingredient, reset system, delete
    /// account) so the logout flow feels consistent with the rest of
    /// the app.
    static let doYouWantToLogout = "Are you sure you want to logout?"

    /// 1:1 with UIKit `Constants.expiredSessionToken` in
    /// `BarsysApp/Helpers/Constants/Constants.swift` — the exact string
    /// shown in the session-expired alert after a 401 is intercepted by
    /// `NetworkingUtility.triggerSessionExpirationLogout`. Both apps
    /// must use the same copy so QA screenshots still match.
    static let expiredSessionToken = "Your session has expired. Please log in again to continue."

    /// Glass-loader messages — 1:1 with UIKit
    /// `SignUpViewController+Actions.swift` (L21/L68 "Sending OTP",
    /// L99 "Registering") and `UIViewController+Navigation.swift` (L26/L57
    /// "Logging Out"). Hard-coded literals are kept here so the SwiftUI
    /// port and QA reference screenshots match without hunting through
    /// view code.
    static let loaderSendingOTP = "Sending OTP"
    static let loaderRegistering = "Registering"
    static let loaderLoggingIn = "Logging In"
    static let loaderLoggingOut = "Logging Out"
    static let loaderDeletingAccount = "Deleting Your Account"

    /// Shown once the sign-up OTP verifies — mirrors the UIKit
    /// `SuccessViewController` behaviour (brief confirmation before
    /// popping back to Login). UIKit presents a visual checkmark with a
    /// fade-in; SwiftUI surfaces the same intent via the custom success
    /// popup (`AlertQueue.showSuccess`).
    static let accountCreatedSuccessfully = "Your account has been created. Please log in to continue."

    /// Raw Ory payload marker — UIKit `ValidationsApiResponseError.expiredSessionToken`.
    /// Some 200-OK responses embed this in the body when the token has
    /// lapsed server-side, which UIKit also treats as a session-expired
    /// event. Keep in lower-case because UIKit does substring match.
    static let expiredSessionTokenBodyMarker = "expired session token"
    static let areYouSureYouWantToDeleteAccount = "Are you sure you want to\ndelete the account?"

    static let codeHasBeenSent = "A code has been sent"
    static let accountDoesNotExistStr = "account does not exist"
    static let notValidPhoneNumber = "not valid tel"
    static let pleaseEnterFullName = "Please enter your full name."
    static let pleaseEnterEmail = "Please enter your email."
    static let invalidEmail = "Invalid email address."
    static let pleaseEnterPhoneNumber = "Please enter your phone number."
    static let pleaseEnterValidPhoneNum = "Please enter valid phone number."
    static let invalidPhoneNumber = "Invalid phone no."
    static let pleaseEnterDob = "Please enter your date of birth."
    static let pleaseEnterOTP = "Please enter the OTP."

    static let unableToConnectToServer = "Unable to connect to the server. Please try again."
    // 1:1 with UIKit `Constants.swift` — invalid-URL message used by
    // `BarBotApiService.getFullRecipeApi`. `noResponseFromServer` and
    // `unableToProcessResponse` are intentionally NOT declared here;
    // some builds of the project appear to have another copy of those
    // identifiers in the compile unit (the compiler flagged
    // re-declaration on every decl we added here), so the two call
    // sites in OryAPIClient.swift now use inline literal strings
    // instead of shared constants.
    static let invalidUrlTitle = "Invalid URL."
    static let recipeLoadError = "Unable to load recipe details. Please try again."
    static let recipeSaveError = "Unable to save recipe. Please try again."
    static let recipeFavouriteError = "Unable to update favourite. Please try again."
    static let stationUpdateError = "Unable to update stations. Please try again."
    static let profileUpdateError = "Unable to update profile. Please try again."
    static let profileFetchError = "Unable to fetch profile data. Please try again."
    static let deviceRenameError = "Unable to rename device. Please try again."
    static let mixlistLoadError = "Unable to load mixlist. Please try again."
    static let ingredientScanError = "Unable to process ingredient scan. Please try again."
    static let loginError = "Unable to sign in. Please try again."
    static let signUpError = "Unable to create account. Please try again."
    static let ingredientUpdateError = "Unable to update ingredients. Please try again."
    static let internetConnectionMessage = "Please check your internet connection."
    static let otpSentSuccessfully = "An OTP has been sent to your phone number."
    static let accountDoesNotExist = "This account doesn't exist. Please sign up first."
    static let userAlreadyExists = "Account already exists."
    static let invalidOTP = "Invalid OTP."

    static let successTitle = "Success"
    static let errorTitle = "An Error Occurred"
    static let networkErrorTitle = "Connection Issue"
    static let bleErrorTitle = "Device Communication Error"
    static let unknownError = "An unexpected error occurred. Please try again or restart the app."

    static let logoutTitle = "Logout"

    static let tutorialsTextBarsys360 = "Watch the video for a step-by-step guide \non how to use your Barsys 360"
    static let tutorialsTextBarsysCoaster = "Watch the video for a step-by-step guide \non how to use your Barsys Coaster 2.0"
    static let tutorialsTextBarsysShaker = "Watch the video for a step-by-step guide \non how to use your Barsys Shaker"

    static let barsys360NameTitle = "Barsys 360"
    static let barsysCoasterTitle = "Coaster 2.0"
    static let barsysShakerTitle = "Barsys Shaker"

    static let placeGlass = "Place Glass..."
    static let placeGlassForBarBot = "Place Glass"
    static let removeGlassForBarBot = "Remove Glass"
    static let cleaningProcessMessage = "Your process status will be shown here."
    static let flushingInProgress = "Flushing in progress... "
    static let pourCleaningSolution = "Pour Cleaning Solution."
    static let cleaningInProgress = "Cleaning in progress"
    static let cleaningComplete = "Cleaning Complete."
    static let removeGlass = "Lift Glass"

    static let exploreMoreOptionsTitle = "Explore More Options."
    static let perishableDescriptionTitle = "Ingredients may be spoiled. Clean the machine before use."
    static let proceedToClean = "Proceed to clean"

    static let systemResetSuccess = "System Reset"
    static let insufficientIngredientQuantityFor360 = "Please check your station(s): one or more ingredients have insufficient quantity."
    static let lowIngredientQty = "Ingredient quantity low."
    static let continueSetupStations = "Continue to Station Setup to craft your selected Mixlist."
    static let selectedMixlistContainsMoreThanSixIngredients = "The selected mixlist contains more than 6 ingredients."
    static let connectingTo = "Connecting to"
    static let deviceNotConnected = "Device is not connected."
    static let searchingForDevice = "Searching for Device"
    static let deviceDetected = "Device detected"

    static let deviceDisconnectedTitle = "Device Disconnected"
    static let deviceDisconnectedMessage = "Your Barsys device has disconnected."
    static let deviceDisconnectedDuringCraftingMessage = "Your Barsys device disconnected during crafting. The current recipe has been stopped for safety."

    static let letsCraftRefreshingCocktailText = "Hello,\nLet's craft a refreshing\ncocktail for your perfect day."
    static let greatWhatOccasionStr = "Great! So what's the occasion?"
    static let placeGlassToBegin = "Place glass on device to begin"
    static let addCocktailName = "Add Cocktail\nName"
    static let addIngredientTitle = "Add ingredient"
    static let removeGlassToCancelTheDrink = "Remove glass to cancel the drink"
    static let removeGlassToCompleteTheDrink = "Remove glass from device to complete"
    static let inQueueStr = "In queue"
    static let emptyDoubleDash = "--"
    static let zeroDoubleStr = "0.0"
    static let zeroIntStr = "0"

    static let blueToothRequiredConnection = "To connect to devices, please enable Bluetooth in your settings."
    static let blueToothDisabled = "Bluetooth Disabled"
    static let restartBarysDevice = "The device name has been changed already.\n\nPlease restart your Barsys device to start crafting."

    static let cameraRequiredAuthorizationForQr = "The app needs access to your camera to scan QRCode."
    static let cameraRequiredAuthorizationForScanIngredients = "The app needs access to your camera to scan ingredients."
    static let openSettingsTitle = "Open Settings"
    static let fillStationsTitle = "Fill Stations"
    static let stationsTitle = "Stations"
    static let profileUpdateMessage = "Profile updated successfully."
    static let pleaseAddAtleastOneIngredient = "Add at least 1 ingredient to proceed"
    static let alreadyAddedInMyBarText = "(Already added in My Bar)"
    static let pleaseAddRecipeName = "Please enter recipe name."
    /// Validation copy shown on EditViewController when the ingredient
    /// list is empty. Matches UIKit `Constants.pleaseAddIngredients`.
    static let pleaseAddIngredients = "Please add at least one ingredient."
    /// Validation copy shown on EditViewController when every ingredient
    /// has a zero quantity. Matches UIKit `Constants.ingredientsCantBeZero`.
    static let ingredientsCantBeZero = "Ingredient quantities can't be zero."
    static let noResultsToDisplay = "No results to display."
    static let noResultsToDisplayForFavourates = "Anyone thirsty? Save some delicious recipes here to quickly craft later.."
    static let deleteTheAccountAlertMessage = "It is a permanent change and the account\ncannot be retrieved after the action."
    static let accountDeleteMessage = "Your account has been deleted successfully."

    // MARK: - Setup-Stations-from-Mixlist copy
    //
    // 1:1 port of UIKit strings used by `RecipeCraftingClass+StationSetup`.
    // Keep copy verbatim — the app's UX review signed off on these exact
    // sentences, so any drift (capitalisation, punctuation) reads as a
    // regression during QA.

    /// Shown on the first entry into the setup flow, over a blocking
    /// popup, to tell the user to physically pour ingredients into the
    /// machine's stations as per the mapping just displayed.
    static let pourIngredientsIntoMachine = "Pour ingredients into the machine as shown"

    /// Validation copy used by `craft360RecipeForUpdatedQuantity` when the
    /// recipe's ingredient can't be matched to any currently-filled
    /// station. Matches UIKit `Constants.ingredientDoesNotExistInStation`.
    static let ingredientDoesNotExistInStation = "Ingredient doesn't exist in station. Set up stations first."

    /// Validation copy shown by UIKit
    /// `checkBarsys360Craftability` + `craftCoasterRecipeWithUpdatedQuantity`
    /// when `baseAndMixerIngredientsArrWithUpdatedQuantity.count == 0`.
    /// Matches UIKit `Constants.ingredientsNotAvailableInRecipe`.
    static let ingredientsNotAvailableInRecipe = "Ingredient not available in recipe."

    /// Shown on the "Ingredients may be spoiled…" alert — the left
    /// button title for the Clean action.
    static let cleanAlertTitle = "Clean"

    /// Right-button title for alerts that acknowledge a non-blocking
    /// notice and dismiss back to the previous screen. UIKit value
    /// matches this case: "Okay" (capital O, lowercase rest).
    static let okayButtonTitle = "Okay"

    /// The left-side "Okay"-style positive title used in classical OK
    /// alerts ("OK" all caps). Matches UIKit `ConstantButtonsTitle.okButtonTitle`.
    static let okButtonTitle = "OK"

    /// Cancel button title used across the app. Matches UIKit
    /// `ConstantButtonsTitle.cancelButtonTitle`.
    static let cancelButtonTitleString = "Cancel"

    /// Continue button title for multi-step flows. Matches UIKit
    /// `ConstantButtonsTitle.continueTitle`.
    static let continueButtonTitleString = "Continue"

    /// Title of the Fill-Stations setup popup. Matches UIKit copy.
    static let proceedToFillStations = "Proceed to Fill Stations"
}

// MARK: - WebViewURLs
//
// 1:1 port of UIKit `ApiConstants.swift` L87-95. These URLs are opened
// by the SideMenu (FAQs, Contact us, Terms, Privacy Policy, About Us)
// and the DrinkComplete rating prompt (appStoreReviewUrl).
enum WebViewURLs {
    static let faqWebURL         = "https://barsys.com/faqs"
    static let contactUsWebUrl   = "https://barsys.com/contact-us"
    static let termsOfUseWebUrl  = "https://barsys.com/terms-of-service"
    static let privacyWebUrl     = "https://barsys.com/privacy-policy"
    static let aboutUsWebUrl     = "https://barsys.com/our-story"
    static let appStoreReviewUrl = "https://apps.apple.com/app/6511230498?action=write-review"

    /// 1:1 parity with `WebViewController.allowedHosts` (L25-32).
    /// Subsequent in-app navigation (after the initial URL) is
    /// restricted to these hosts; non-matches are cancelled so the
    /// WKNavigationDelegate doesn't drift onto arbitrary ad / tracker
    /// domains. External links on these pages open outside the app
    /// (via Safari) when the host doesn't match.
    static let allowedHosts: Set<String> = [
        "barsys.com",
        "www.barsys.com",
        "apps.apple.com",
        "bfrands.com",
        "www.bfrands.com",
        "bfrands.freshdesk.com"
    ]
}

enum ConstantButtonsTitle {
    static let okButtonTitle = "OK"
    static let cancelButtonTitle = "Cancel"
    static let dismissButtonTitle = "Dismiss"
    static let yesButtonTitle = "Yes"
    static let noButtonTitle = "No"
    /// 1:1 with UIKit `ConstantButtonsTitle.donotDeleteTitle`
    /// (Constants+UI.swift L32). Used as the TINTED (primary) cancel
    /// button on the delete-account confirmation popup.
    static let donotDeleteTitle = "Don't delete"
    static let continueButtonTitle = "Continue"
    static let discardButtonTitle = "Discard"
    static let keepEditingButtonTitle = "Keep Editing"
    static let saveButtonTitle = "Save"
    static let deleteButtonTitle = "Delete"
    /// 1:1 with UIKit `ConstantButtonsTitle.logoutButtonTitle`
    /// (Constants+UI.swift L20). NOTE the capital "O" — must stay
    /// "Log Out" (not "Log out") to match the UIKit popup text.
    static let logoutButtonTitle = "Log Out"
    static let yesPleaseButtonTitle = "Yes please!"
    static let noStayInAppButtonTitle = "No, stay in the app"
    // 1:1 with UIKit `Constants+UI.swift` L38 + L40 — used by
    // `MultipleIngredientsPopUp` (MyBar photo-upload flow).
    static let proceedButtonTitle = "Proceed"
    static let reUploadButtonTitle = "Reupload"
    // 1:1 with UIKit `Constants+UI.swift` L41 — used by the
    // "No mixlists available" alert in ReadyToPour.
    static let exploreButtonTitle = "Explore"
}

// MARK: - ReadyToPour empty-mixlists alert

extension Constants {
    /// 1:1 with UIKit `ReadyToPourListViewController+Search.swift` L72
    /// — title string of the alert shown when the Mixlists tab is
    /// empty. Offers an "Explore" CTA to navigate to MixlistViewController.
    /// The UIKit literal omits a space after the period; preserved
    /// verbatim for matching accessibility strings.
    static let noMixlistsTapExploreMessage =
        "No mixlists available.Tap Explore to find one you want to craft."
}

// MARK: - Pair-Device Prompt

extension Constants {
    /// 1:1 with UIKit `Constants.goToPairyourDeviceStr` (Constants.swift L294).
    /// Shown in the confirmation popup that precedes navigation to the
    /// Pair Your Device screen — same text, same casing as UIKit.
    static let goToPairyourDeviceStr = "Go to pair device screen, to connect device."
}

// MARK: - VideoURLConstants
//
// 1:1 port of UIKit `VideoURLConstants` (ApiConstants.swift L97-101).
// Tutorial videos hosted on `media.barsys.com` — used by:
//   • TutorialViewController (first-launch onboarding video)
//   • Control Center "Tutorial" menu item (device-specific video)
//   • DevicePairedViewModel.videoURLForConnectedDevice (DevicePaired tile)
enum VideoURLConstants {
    static let barsys360VideoUrl = "https://media.barsys.com/videos/Copy%20of%20Barsys%20360%20Instruction%20Video%20Horizontal.mp4"
    static let barsysCoasterUrl  = "https://media.barsys.com/videos/Coaster_Instructiom_H.mp4"
    static let barsysShakerUrl   = "https://media.barsys.com/videos/Shaker_Instructiom_H.mp4"
}

// MARK: - String → image URL helper
//
// 1:1 port of UIKit `String.getImageUrl()`
// (BarsysApp/Helpers/StringClass.swift L41-63), which every UIKit
// recipe / mixlist cell pipes the raw `image.url` field through
// before passing it to `sd_setImage(with:)`.
//
// Why a dedicated helper:
//   The API returns image URLs in the optimizeImage proxy format —
//   `https://api.barsys.com/api/optimizeImage?fileUrl=https://media.barsys.com/<path>`.
//   The `fileUrl` query value itself contains `:` and `/` characters
//   (and frequently spaces / unicode in the path) that MUST be
//   percent-encoded to produce a valid `URL`. UIKit handles this
//   by splitting the string at `fileUrl=` and re-attaching the
//   value through `URLComponents` + `URLQueryItem`, which performs
//   the encoding correctly.
//
//   The previous SwiftUI ports tried a naive
//   `replacingOccurrences(of: "https://storage.googleapis.com/...",
//                          with: "https://api.barsys.com/.../fileUrl=...")`
//   string substitution. This is wrong on two counts:
//     1. The server NO LONGER returns the `storage.googleapis.com`
//        prefix — it returns the optimizeImage URL directly — so
//        the substitution is a no-op and the unencoded URL is
//        passed straight to `URL(string:)`.
//     2. `URL(string:)` rejects (or silently corrupts) the
//        unencoded `fileUrl=https://media.barsys.com/...` query
//        value, leaving `AsyncImage` with a nil URL → row falls
//        through to the `myDrink` placeholder so EVERY row in
//        My Drinks / Explore / Mixlists / Crafting / Ready to Pour
//        shows the placeholder instead of the recipe image.
extension String {
    /// Ports UIKit `String.getImageUrl()`. Returns a properly
    /// percent-encoded `URL` for `optimizeImage?fileUrl=…` strings,
    /// or `URL(string:)` for plain URLs without the proxy.
    func getImageUrl() -> URL? {
        // 1:1 with UIKit: prefer the percent-DECODED form of the
        // string (so any pre-encoded characters are normalised
        // before we re-encode the fileUrl value), and fall back to
        // an encoded form if decoding fails.
        let original = self.removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? self
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        guard let original = original else { return nil }

        // Plain URL (no optimizeImage proxy) — pass straight through.
        guard let fileURLRange = original.range(of: "fileUrl=") else {
            return URL(string: original)
        }

        // Split the input at `fileUrl=`. The piece before it is
        // the optimizeImage endpoint (already a valid URL prefix
        // ending in `?`). The piece after it is the inner image
        // URL value, which gets re-attached as a URLQueryItem so
        // `:` / `/` / spaces / unicode in the path are properly
        // percent-encoded.
        let base = String(original[..<fileURLRange.lowerBound])
        let fileUrlValue = String(original[fileURLRange.upperBound...])

        var components = URLComponents(string: base)
        components?.queryItems = [
            URLQueryItem(name: "fileUrl", value: fileUrlValue)
        ]
        return components?.url
    }
}
