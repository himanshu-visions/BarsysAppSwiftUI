//
//  MyBarScreens.swift
//  BarsysAppSwiftUI
//
//  1:1 port of UIKit `MyBarViewController` (Device.storyboard scene
//  `oSA-pi-fAK`). Reference files:
//    • Controllers/MyBar/MyBarViewController.swift               (layout, bindings, actions)
//    • Controllers/MyBar/MyBarViewController+TableView.swift     (table delegate + delete)
//    • Controllers/MyBar/MyBarViewModel.swift                    (state + API orchestration)
//    • Controllers/MyBar/MyBarApiService.swift                   (GET/POST/DELETE endpoints)
//    • Controllers/MyBar/MyBarIngredientsCell/*                  (cell xib + style)
//    • Helpers/ImagePicker/ImagePickerViewController.swift       (photo picker + camera flow)
//    • Helpers/UploadImage/UploadIngredientsImage.swift          (image → ingredient detection)
//    • Helpers/CustomViews/UIViewClass+GlassEffects.swift        (applyNeumorphicPillStyle)
//    • StoryBoards/Base.lproj/Device.storyboard lines 2000-2401
//
//  -------------------------------------------------------------------
//  VIEW HIERARCHY (frames from storyboard — 393×852 canvas)
//  -------------------------------------------------------------------
//
//  root (YsX-ua-Swl, bg primaryBackgroundColor)
//  └── container (eSD-FL-hZG, 393×617, safeArea pinned)
//      ├── nav bar (Cjb-m2-QZY, 393×60)                          ← SwiftUI toolbar
//      │     • back btn (hidden at runtime)
//      │     • device info (25×25 icon + 12pt "Barsys 360" label)
//      │     • glass pill (iOS 26+, 100×48 at trailing-24)
//      │     • favoriteIcon (30×30)
//      │     • profileIcon  (30×30)
//      │
//      ├── scrollView (b5B-Xu-RAP, 393×557)
//      │   └── content (F0s-hS-PFa, 393×325+)
//      │       • "My Bar"       — system 24pt, appBlackColor,  (24, 0)
//      │       • "INGREDIENTS"  — boldSystem 11pt, appBlackColor, top+17
//      │       • Liquor section (@83, 8pt stack spacing)
//      │             — header card `xxF-NZ-map` (353×50, 20pt margin,
//      //               **systemBackgroundColor** = pure white/black,
//      //               `roundCorners = 15`)
//      //                   "Liquor Ingredients" 16pt charcoalGray leading 16
//      //                   "(0)" 16pt pinkishGray trailing 16
//      │             — tableView `Ovv-hk-J38` (dynamic, rows 56pt estimated)
//      │       • Mixer section  (@166, same recipe, "Mixer Ingredients")
//      │
//      └── bottom bar (7le-Ya-rm2, 393×45 @y=572)
//            SWAPPED by `hasData`:
//              !hasData → [Upload from Photos, Take A Photo]
//               hasData → [Add ingredient, Show Recipes]
//            Every button: 168.67×45, 8pt spacing, 8pt corner radius
//              • Primary (trailing) — brandTanColor fill
//                    iOS 26+ `makeOrangeStyle()` (brand vertical gradient)
//              • Secondary (leading) — primaryBackgroundColor + 1pt border
//                    iOS 26+ `applyCancelCapsuleGradientBorderStyle()`
//
//  -------------------------------------------------------------------
//  CELL STYLE — `applyNeumorphicPillStyle` (UIViewClass+GlassEffects.swift
//  L143-158 with MyBarIngredientCell overrides):
//      cornerRadius   = BarsysCornerRadius.pill = 24
//      backgroundColor = .cellGrayBg             = #EDEDF0 (light) / #2C2C2E (dark)
//      shadowColor    = black @ 0.08
//      shadowOpacity  = 0.35   (effective alpha = 0.028)
//      shadowOffset   = (3, 3)
//      shadowRadius   = 5
//      borderWidth    = 1
//      borderColor    = white @ 0.85
//      masksToBounds  = false
//  Label "Amaretto" — 14pt system, **veryDarkGrayColor** (runtime override
//  in MyBarViewController+TableView.swift L38 overrides the xib default).
//  Delete button — 36×36 hit target, `deleteImg` 16×16, tint veryDarkGrayColor
//  (runtime override L39). No glass effect applied to cells.
//
//  -------------------------------------------------------------------
//  RUNTIME FLOW (MyBarViewController.swift + +TableView.swift)
//  -------------------------------------------------------------------
//
//  • viewDidLoad → fetchMyBarDataFromServer() → loader "Fetching Your Ingredients"
//  • hideUnhideTables()
//        tableLiqour.isHidden = !hasLiquor            (rows collapse)
//        tableMixer.isHidden  = !hasMixer
//        emptyStateStackView.isHidden = hasData        (swap bottom bar)
//        dataStateStackView.isHidden  = !hasData
//        lblLiqourCount.text = "(\(count))"            (always rendered)
//        lblMixerCount.text  = "(\(count))"
//  • Empty state bar:
//        "Upload from Photos" → uploadFromGalleryAction
//                             → checkAuthorizationAndShowPhotos()
//                             → UIImagePickerController(.photoLibrary)
//                             → didSelectImagesFromPhotos
//                             → UploadIngredientsImage.uploadImageAndGetIngredientsResponseForMyBar
//                             → processImageScanResults (filter base/mixer, dedupe)
//                             → multipleIngredientsPopUp (Proceed / Reupload)
//                             → POST /api/v1/my/bar (add)
//                             → appendConfirmedIngredients
//        "Take A Photo" → openScanIngredientsScreenForMyBar()
//                       → pushes ScanIngredientsViewController (AVFoundation camera)
//                       → callback onIngredientScannedForMyBar → appendScannedIngredients
//  • Data state bar:
//        "Add ingredient" → takePhotoForMyBar
//                         → showAddPhotoPopupForImagePicker(isFromMyBar: true)
//                         → custom AddPhotoPopupView with Camera / Upload
//                         → same post-pick path as above
//        "Show Recipes" → didPressShowRecipeAction
//                       → viewModel.buildAllowedIngredients()
//                       → viewModel.fetchMatchingRecipes(allowed:) (local DB)
//                       → RecipesCoordinator.showReadyToPour(recipes:allowedIngredientsForMyBar:)
//  • Delete row button → confirmation alert (Yes/No, title from
//        `Constants.doYouWantToDeleteIngredient`) → DELETE /api/v1/my/bar/{base|mixer}
//        → remove row from array → onDataReloaded
//
//  -------------------------------------------------------------------
//  PARITY CHECKLIST vs prior SwiftUI port — now EIGHT fixes in place:
//    1. Removed the wineglass SF-symbol empty state (UIKit has none).
//    2. Removed the search field (UIKit has none).
//    3. Neumorphic pill cell (24pt corner, cellGrayBg, shadow + sheen border).
//    4. Section headers always visible with "(0)" count badge.
//    5. TWO bottom-bar variants — swap based on `hasData`.
//    6. Text-only buttons (no SF-symbol labels).
//    7. "My Bar" 24pt title + "INGREDIENTS" 11pt bold subhead added.
//    8. Wired the photo-library + camera pickers to the upload flow so
//       ingredients detected via `env.api.uploadIngredientImageForMyBar`
//       are actually added to the bar — the earlier port short-circuited
//       both buttons to the QR-scanner route.

import SwiftUI

// MARK: - DetectedMyBarIngredient
//
// 1:1 with UIKit `MyBarIngredientModel` as used inside
// `MultipleIngredientsPopUpViewController`. Wraps the decoded
// `Ingredient` plus two flags the popup cell reads:
//   • `isExisting` ↔ UIKit `matchState == .existing` — grey text,
//                     "Already added in My Bar" caption, tap ignored.
//   • `isSelected` ↔ UIKit `selectedIngredientArray.contains(...)`
//                     — drives the filled / empty checkbox state.
// New rows default to selected; existing rows are always unselected
// (UIKit L115-118 initial seeding).
//
// Declared BEFORE `MyBarView` so every generic ForEach / Binding
// expression below can resolve the element type during type-check.
// Declaring it after the view exercises Swift's forward-reference
// machinery for generic view builders, which is fragile in long
// files and was emitting "Cannot find type in scope" here.
struct DetectedMyBarIngredient: Identifiable {
    let id = UUID()
    var ingredient: Ingredient
    let isExisting: Bool
    var isSelected: Bool
}

// MARK: - MyBarView

struct MyBarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var ble: BLEService

    // MARK: - Delete-confirmation state

    @State private var pendingDelete: Ingredient?
    @State private var deletePopup: BarsysPopup? = nil

    // MARK: - Photo-picker state (1:1 with UIKit ImagePickerViewController)

    /// Mirrors UIKit `showAddPhotoPopupForImagePicker` for the data-state
    /// "Add ingredient" button — Camera / Photos / Cancel action sheet.
    @State private var showAddPhotoDialog = false

    /// Drives the UIImagePickerController sheet. Wrapped in an Identifiable
    /// so we can use `.sheet(item:)` — presenting and configuring the sheet
    /// in a SINGLE atomic state change. A prior two-`@State` setup
    /// (`showPicker: Bool` + `pickerSource`) had a first-tap race where
    /// SwiftUI coalesced the two mutations and the sheet captured the
    /// stale default `.photoLibrary` source, opening Photos instead of
    /// the camera on first "Take a Photo" tap.
    @State private var pickerPresentation: PickerPresentation?

    /// Identifiable wrapper around `UIImagePickerController.SourceType` so
    /// it can drive `.sheet(item:)`. The `id` changes whenever a new
    /// picker is requested — forces SwiftUI to rebuild the sheet body
    /// with the fresh `source` every time.
    fileprivate struct PickerPresentation: Identifiable, Equatable {
        let id = UUID()
        let source: UIImagePickerController.SourceType
    }

    /// The picked image — observed to kick off the upload pipeline once
    /// the picker has dismissed (UIKit parity: `didSelectImagesFromPhotos`).
    @State private var pickedImage: UIImage?

    /// Blocks input during `uploadIngredientImageForMyBar` — reproduces
    /// UIKit `showGlassLoader(message: "Adding Ingredients")`.
    @State private var isUploading = false

    // MARK: - "Ingredient(s) found" popup state
    //
    // 1:1 with UIKit `MultipleIngredientsPopUpViewController`. Shown
    // after a successful image upload; lets the user check/uncheck
    // detected base/mixer ingredients before confirming.

    /// Full list of detected ingredients (existing + new). `new` rows
    /// are selectable; `existing` rows are greyed out and locked (UIKit
    /// `matchState == .existing` → checkbox disabled, "Already added"
    /// subtitle shown).
    @State private var detectedIngredients: [DetectedMyBarIngredient] = []

    /// Drives the custom glass popup.
    @State private var showIngredientsFoundPopup = false

    // MARK: - Derived state (ports MyBarViewModel computed properties)

    private var allIngredients: [Ingredient] {
        env.storage.myBarIngredients()
    }

    /// Ports `viewModel.liqourIngredientsArray` — `category.primary == "base"`.
    private var liquorIngredients: [Ingredient] {
        allIngredients
            .filter { ($0.category?.primary ?? "").lowercased() == "base" }
            .sorted { $0.name < $1.name }
    }

    /// Ports `viewModel.mixerIngredientsArray` — `category.primary == "mixer"`.
    private var mixerIngredients: [Ingredient] {
        allIngredients
            .filter { ($0.category?.primary ?? "").lowercased() == "mixer" }
            .sorted { $0.name < $1.name }
    }

    /// Ports `viewModel.hasData`.
    private var hasData: Bool {
        !liquorIngredients.isEmpty || !mixerIngredients.isEmpty
    }

    private var deviceIconName: String {
        if ble.isBarsys360Connected() { return "icon_barsys_360" }
        if ble.isCoasterConnected() { return "icon_barsys_coaster" }
        if ble.isBarsysShakerConnected() { return "icon_barsys_shaker" }
        return ""
    }
    private var deviceKindName: String {
        if ble.isBarsys360Connected() { return Constants.barsys360NameTitle }
        if ble.isCoasterConnected() { return Constants.barsysCoasterTitle }
        if ble.isBarsysShakerConnected() { return Constants.barsysShakerTitle }
        return ""
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            scrollContent
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("primaryBackgroundColor").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .chooseOptionsStyleNavBar()
        // Delete confirmation — 1:1 with UIKit alert (Yes destructive, No cancel).
        .barsysPopup($deletePopup, onPrimary: { confirmDelete() },
                                   onSecondary: { pendingDelete = nil })
        // Action sheet for "Add ingredient" (data state) — mirrors UIKit
        // `showAddPhotoPopupForImagePicker(isFromMyBar: true)` which
        // renders a custom popup with exactly these two choices.
        .confirmationDialog(
            Constants.pleaseSelectAnOption,
            isPresented: $showAddPhotoDialog,
            titleVisibility: .visible
        ) {
            // Button titles match UIKit `ConstantButtonsTitle.cameraTitle`
            // / `.photosTitle` (Constants+UI.swift L28-29).
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") { openPicker(source: .camera) }
            }
            Button("Photos") { openPicker(source: .photoLibrary) }
            Button(ConstantButtonsTitle.cancelButtonTitle, role: .cancel) {}
        }
        // UIImagePickerController — 1:1 with UIKit `presentPhotoLibrary` /
        // `presentCamera` branches of `checkAuthorizationAndShowPhotos` /
        // `checkAuthorizationAndShowCamera` in ImagePickerViewController.
        .sheet(item: $pickerPresentation) { presentation in
            BarBotImagePicker(image: $pickedImage, source: presentation.source)
                .ignoresSafeArea()
        }
        // 1:1 with UIKit `didSelectImagesFromPhotos` — runs upload once
        // the picker is gone. The 0.25s delay matches the pattern
        // Edit-recipe uses (RecipesScreens.swift L1995) to avoid racing
        // the sheet-dismiss transition.
        .onChange(of: pickedImage) { newImage in
            guard let image = newImage else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                uploadAndProcessMyBarImage(image)
                pickedImage = nil
            }
        }
        // Glass loader — 1:1 with UIKit `showGlassLoader(message:)`.
        .overlay {
            if isUploading {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(Constants.addingIngredientLoaderText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color("appBlackColor"))
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                }
                .transition(.opacity)
            }
        }
        // "Ingredient(s) found" glass popup — 1:1 with UIKit
        // `MultipleIngredientsPopUpViewController`. Rendered on top of
        // the loader so the transition out → popup in matches UIKit.
        .overlay {
            if showIngredientsFoundPopup {
                ingredientsFoundPopup
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isUploading)
        .animation(.easeInOut(duration: 0.25), value: showIngredientsFoundPopup)
    }

    // MARK: - Ingredient(s) found popup (glass card)
    //
    // 1:1 with UIKit `MultipleIngredientsPopUpViewController`
    // (Controllers/AlertDialogs/MultipleIngredientsPopUpViewController.swift):
    //
    //   • Centered glass card (cornerRadius: medium = 12)
    //   • Dark scrim at 50% alpha (UIKit L99: viewTransparent = black@0.5)
    //   • Close X top-right
    //   • Title lblTitle, subTitle lblSubTitle
    //   • Scrollable list of rows, each 56pt with a checkbox + name
    //         — existing rows: grey text + "Already added in My Bar"
    //                          caption, checkbox disabled
    //         — new rows: veryDarkGrayColor text, checkbox toggleable
    //   • Error label "Please select at least one ingredient" when empty
    //   • Two buttons side-by-side:
    //         — LEFT ("Reupload") → `onCompleteAlertPopup("Continue")`
    //                                → re-opens photo picker (UIKit L163-169)
    //         — RIGHT ("Proceed") → `onRightAlertPopup(selections)`
    //                                → add ingredients (UIKit L146-155)
    //   • Right button: disabled (alpha 0.5) when selections.isEmpty

    @ViewBuilder
    private var ingredientsFoundPopup: some View {
        ZStack {
            // Dark scrim — UIKit viewTransparent backgroundColor black@0.5.
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { /* ignore taps on scrim — UIKit has a
                                   transparent button only for the X
                                   icon; scrim itself does nothing */ }

            ingredientsFoundCard
                .padding(.horizontal, 24)
        }
    }

    private var selectedCount: Int {
        detectedIngredients.filter { $0.isSelected && !$0.isExisting }.count
    }
    private var hasNewIngredients: Bool {
        detectedIngredients.contains { !$0.isExisting }
    }

    @ViewBuilder
    private var ingredientsFoundCard: some View {
        VStack(spacing: 0) {
            // Close button at top-right.
            HStack {
                Spacer()
                Button {
                    HapticService.light()
                    closeIngredientsFoundPopup()
                } label: {
                    Image("crossIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Color("appBlackColor"))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Title "Ingredient(s) found".
            Text("Ingredient(s) found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color("appBlackColor"))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            // Subtitle "Select ingredients to proceed".
            Text("Select ingredients to proceed")
                .font(.system(size: 14))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.bottom, 14)

            // Ingredient list — capped at 250pt like UIKit
            // `tblIngredientsHeightConstraint = 250` (L63-67).
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach($detectedIngredients) { $detected in
                        detectedIngredientRow($detected)
                    }
                }
            }
            .frame(maxHeight: 250)

            // Error label (UIKit L190-195).
            if selectedCount == 0 && hasNewIngredients {
                Text(Constants.pleaseAddAtleastOneIngredient)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("errorLabelColor"))
                    .padding(.top, 8)
            }

            // Bottom buttons — Reupload (secondary) + Proceed (primary).
            HStack(spacing: 8) {
                MyBarSecondaryButton(title: ConstantButtonsTitle.reUploadButtonTitle) {
                    closeIngredientsFoundPopup()
                    // UIKit L163-169 `onCompleteAlertPopup` →
                    // `showAddPhotoPopupForImagePicker(isFromMyBar: true)`.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showAddPhotoDialog = true
                    }
                }
                MyBarPrimaryButton(title: ConstantButtonsTitle.proceedButtonTitle) {
                    proceedWithSelectedIngredients()
                }
                .opacity(selectedCount > 0 ? 1.0 : 0.5)
                .disabled(selectedCount == 0)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 6)
        .background(
            // Glass card — `alertPopUpBackgroundStyle(cornerRadius: medium=12)`
            // (UIKit L73). On iOS 26 this resolves to the real UIGlassEffect,
            // on earlier iOS it falls back to white@0.95.
            ZStack {
                if #available(iOS 26.0, *) {
                    BarsysGlassPanelBackground(whiteTintAlpha: 0.20)
                        .clipShape(RoundedRectangle(cornerRadius: 12,
                                                    style: .continuous))
                } else {
                    // Pre-iOS 26 fallback: trait-resolved fill so light
                    // mode preserves the EXACT historical white@0.95
                    // pixels (bit-identical), and dark mode picks up an
                    // elevated dark surface fill so the popup sheet
                    // adapts naturally instead of being a stark white
                    // slab on the dark MyBar canvas.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark
                                ? UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 0.95) // dark surface @ 0.95
                                : UIColor.white.withAlphaComponent(0.95) // EXACT historical
                        }))
                }
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private func detectedIngredientRow(_ detected: Binding<DetectedMyBarIngredient>) -> some View {
        let d = detected.wrappedValue
        HStack(spacing: 12) {
            // Checkbox — matches UIKit MultipleIngredientCell.
            Button {
                // UIKit: existing rows ignore the tap (L172-174).
                guard !d.isExisting else { return }
                HapticService.light()
                detected.wrappedValue.isSelected.toggle()
            } label: {
                ZStack {
                    // Empty state: ring with border.
                    Circle()
                        .stroke(
                            d.isExisting
                                ? Color.gray.opacity(0.5)
                                : Color("craftButtonBorderColor"),
                            lineWidth: 1
                        )
                        .frame(width: 22, height: 22)
                    // Selected state: filled circle + check (matches
                    // UIKit `selectedIngredient` asset — brand orange dot).
                    if d.isSelected && !d.isExisting {
                        Circle()
                            .fill(Color("segmentSelectionColor"))
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.isSelected ? "Selected" : "Not selected")

            VStack(alignment: .leading, spacing: 2) {
                Text(d.ingredient.name)
                    .font(.system(size: 14))
                    .foregroundStyle(
                        d.isExisting
                            ? Color.gray
                            : Color("veryDarkGrayColor")
                    )
                if d.isExisting {
                    Text(Constants.alreadyAddedInMyBarText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !d.isExisting else { return }
            HapticService.light()
            detected.wrappedValue.isSelected.toggle()
        }
    }

    // MARK: - Popup actions

    /// Close the popup and reset state.
    private func closeIngredientsFoundPopup() {
        showIngredientsFoundPopup = false
        detectedIngredients = []
    }

    /// 1:1 with UIKit `rightButtonClicked(_:)` (MultipleIngredientsPopUp L146-155):
    ///   - If no selections: bail out (UIKit L149).
    ///   - Dismiss the popup.
    ///   - Call `onRightAlertPopup(selections)` which in MyBar becomes
    ///     `viewModel.addIngredientToServer(baseAndMixer:)` →
    ///     `appendConfirmedIngredients(cleanAction)`.
    private func proceedWithSelectedIngredients() {
        let selections = detectedIngredients.filter { $0.isSelected && !$0.isExisting }
        guard !selections.isEmpty else { return }
        HapticService.success()
        showIngredientsFoundPopup = false
        detectedIngredients = []
        // UIKit `appendConfirmedIngredients(models)` — append each to
        // the correct array (base → liqour, else → mixer).
        for detected in selections {
            env.storage.toggleMyBar(detected.ingredient)
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // "My Bar" — storyboard I7T-Sx-cTO (system 24pt, appBlackColor).
                Text("My Bar")
                    .font(.system(size: 24))
                    .foregroundStyle(Color("appBlackColor"))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, 24)

                // "INGREDIENTS" — storyboard QzL-Qa-gHP (boldSystem 11pt).
                Text("INGREDIENTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color("appBlackColor"))
                    .padding(.leading, 24)
                    .padding(.top, 17)

                // Liquor section — 24pt gap to "INGREDIENTS" (constraint I83-Rq-3Zf).
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeaderCard(title: "Liquor Ingredients",
                                       count: liquorIngredients.count)
                    if !liquorIngredients.isEmpty {
                        sectionList(liquorIngredients)
                    }
                }
                .padding(.top, 24)

                // Mixer section — 24pt gap to liquor stack (constraint SHH-J7-r30).
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeaderCard(title: "Mixer Ingredients",
                                       count: mixerIngredients.count)
                    if !mixerIngredients.isEmpty {
                        sectionList(mixerIngredients)
                    }
                }
                .padding(.top, 24)

                // Storyboard constraint 4i1-5v-7Lk: 100pt bottom padding
                // so the last ingredient row never hides behind the bar.
                Color.clear.frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section header card
    //
    // 1:1 port of storyboard `xxF-NZ-map` / `bdY-Oa-UBp` — a 50pt tall card
    // inset 20pt from the scroll edges, `roundCorners = 15`, backgroundColor
    // `systemBackgroundColor` (PURE white on light mode, PURE black on dark
    // mode — this is an iOS system color, NOT the app's
    // `primaryBackgroundColor`, which can be a slightly off-white tone).
    //
    // Inside:
    //   • Title "Liquor Ingredients" — system 16pt, charcoalGrayColor, leading 16pt
    //   • Count "(0)"                — system 16pt, pinkishGrayColor, trailing 16pt
    //
    // The card is ALWAYS visible — only the table below it hides when the
    // array is empty (`tblIngredient*.isHidden = !hasCount`). That's why
    // the count still shows "(0)" on an empty bar.

    @ViewBuilder
    private func sectionHeaderCard(title: String, count: Int) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color("charcoalGrayColor"))
                .padding(.leading, 16)
            Spacer(minLength: 0)
            Text("(\(count))")
                .font(.system(size: 16))
                .foregroundStyle(Color("pinkishGrayColor"))
                .padding(.trailing, 16)
        }
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) item\(count == 1 ? "" : "s")")
    }

    // MARK: - Section list
    //
    // UIKit uses a dynamic-height UITableView whose `contentSize` is
    // observed via KVO and piped into a height constraint so the table
    // fits its content. SwiftUI `ForEach` inside a `VStack` gives the
    // same intrinsic-sizing behaviour automatically, so we drop the
    // observer entirely.

    @ViewBuilder
    private func sectionList(_ items: [Ingredient]) -> some View {
        VStack(spacing: 4) {
            ForEach(items) { ingredient in
                ingredientCell(ingredient)
            }
        }
    }

    // MARK: - Ingredient cell — applyNeumorphicPillStyle
    //
    // Container (MyBarIngredientCell xib + applyCellStyle):
    //   • 286×48 inside a 318×56 cell, 16pt horizontal inset (we use
    //     `.padding(.horizontal, 16)` on the row).
    //   • cornerRadius: `BarsysCornerRadius.pill` = 24
    //   • backgroundColor: `.cellGrayBg` = #EDEDF0 light / #2C2C2E dark
    //     → SwiftUI `tertiaryBackgroundColor` matches exactly.
    //   • borderWidth: 1 · borderColor: white @ 0.85
    //   • shadow: black @ 0.08 · opacity 0.35 → effective alpha 0.028,
    //              radius 5, offset (3, 3)
    //   • masksToBounds: false (shadow renders outside)
    //
    // Label — 14pt system, veryDarkGrayColor (runtime override L38).
    // Delete — 36×36 hit target, `deleteImg` 16×16, veryDarkGrayColor tint.

    @ViewBuilder
    private func ingredientCell(_ ingredient: Ingredient) -> some View {
        HStack(spacing: 15) {
            Text(ingredient.name)
                .font(.system(size: 14))
                .foregroundStyle(Color("veryDarkGrayColor"))
                .lineLimit(0) // xib `numberOfLines = 0` → wrap freely
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

            Button {
                HapticService.light()
                pendingDelete = ingredient
                deletePopup = .confirm(
                    title: Constants.doYouWantToDeleteIngredient,
                    message: nil,
                    primaryTitle: ConstantButtonsTitle.yesButtonTitle,
                    secondaryTitle: ConstantButtonsTitle.noButtonTitle,
                    primaryFillColor: "segmentSelectionColor",
                    isCloseHidden: true
                )
            } label: {
                Image("deleteImg")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color("veryDarkGrayColor"))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 9)
            .accessibilityLabel("Delete \(ingredient.name)")
            .accessibilityHint("Removes this ingredient from your bar")
        }
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color("tertiaryBackgroundColor"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        // Two-layer shadow re-creates UIKit CALayer (offset 3,3, radius 5,
        // opacity 0.35 on black@0.08). SwiftUI `.shadow` multiplies the
        // color alpha by the opacity, so we pre-multiply to `black@0.028`.
        .shadow(color: Color.black.opacity(0.028), radius: 5, x: 3, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom action bar (swapped stackViews)

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            if hasData {
                HStack(spacing: 8) {
                    MyBarSecondaryButton(title: "Add ingredient") {
                        HapticService.light()
                        // UIKit `takePhotoForMyBar(_:)` →
                        // showAddPhotoPopupForImagePicker(isFromMyBar: true).
                        showAddPhotoDialog = true
                    }
                    MyBarPrimaryButton(title: "Show Recipes") {
                        HapticService.light()
                        showRecipesAction()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    MyBarSecondaryButton(title: "Upload from Photos") {
                        HapticService.light()
                        // UIKit `uploadFromGalleryAction:` →
                        // checkAuthorizationAndShowPhotos → .photoLibrary.
                        openPicker(source: .photoLibrary)
                    }
                    MyBarPrimaryButton(title: "Take A Photo") {
                        HapticService.light()
                        // UIKit `takeAPhotoAction:` →
                        // openScanIngredientsScreenForMyBar (full camera
                        // screen). With the dedicated scan screen still
                        // stubbed, we open the in-line camera picker
                        // directly — same end-to-end result: captured
                        // image goes through the ingredient-detection
                        // pipeline and lands in My Bar.
                        openPicker(source: .camera)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
        // UIKit bottom constraint (MyBarViewController.swift L88-90):
        //   iOS 26+  → 12.0pt (glass nav takes visual space of old inset)
        //   pre-26   → 37.0pt
        .padding(.bottom, bottomBarBottomInset)
    }

    private var bottomBarBottomInset: CGFloat {
        if #available(iOS 26.0, *) { 12 } else { 37 }
    }

    // MARK: - Toolbar (ports nav bar Cjb-m2-QZY)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // UIKit keeps the device-name label hidden (`lblDeviceName.isHidden
        // = true` at MyBarViewController.swift L153) and shows only the
        // 25×25 icon.
        if ble.isAnyDeviceConnected, !deviceIconName.isEmpty {
            ToolbarItem(placement: .principal) {
                DevicePrincipalIcon(assetName: deviceIconName,
                                    accessibilityLabel: deviceKindName)
            }
        }
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

    // MARK: - Photo picker helpers

    /// Opens the system picker with the requested source. Falls back to
    /// photo library when camera isn't available (simulator, restricted).
    private func openPicker(source: UIImagePickerController.SourceType) {
        let resolved: UIImagePickerController.SourceType
        if source == .camera, !UIImagePickerController.isSourceTypeAvailable(.camera) {
            resolved = .photoLibrary
        } else {
            resolved = source
        }
        // Single atomic state mutation — replaces the old two-step
        // `pickerSource = …; showPicker = true` that raced on first tap.
        pickerPresentation = PickerPresentation(source: resolved)
    }

    /// 1:1 with UIKit `didSelectImagesFromPhotos` (MyBarViewController
    /// L348-394):
    ///   1. Check connectivity — UIKit runs a Task that hits
    ///      ConnectionMonitor; we mirror by surfacing a generic alert
    ///      when the upload throws.
    ///   2. `showGlassLoader(message: "Adding Ingredients")`.
    ///   3. `UploadIngredientsImage().uploadImageAndGetIngredientsResponseForMyBar`.
    ///   4. `viewModel.processImageScanResults` — filter base/mixer,
    ///      dedupe against existing MyBar, build `[MyBarIngredientModel]`.
    ///   5. Present the multiple-ingredients popup (Proceed / Reupload).
    ///   6. On Proceed → `viewModel.addIngredientToServer(...)` →
    ///      `appendConfirmedIngredients`.
    ///
    private func uploadAndProcessMyBarImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            env.alerts.show(message: Constants.ingredientUpdateError)
            return
        }
        isUploading = true
        Task { @MainActor in
            do {
                let detected = try await env.api.uploadIngredientImageForMyBar(data)
                isUploading = false
                let (toShow, errorMessage) = processImageScanResults(detected)
                if let errorMessage, toShow.isEmpty {
                    env.alerts.show(message: errorMessage)
                    return
                }
                if toShow.isEmpty {
                    env.alerts.show(message: Constants.ingredientCannotBeUsedHere)
                    return
                }
                // Success — present the selection popup (UIKit
                // `addingredientPopUpShow(baseAndMixer:)` L396-417).
                detectedIngredients = toShow
                showIngredientsFoundPopup = true
            } catch {
                isUploading = false
                env.alerts.show(message: Constants.ingredientUpdateError)
            }
        }
    }

    /// 1:1 port of UIKit `MyBarViewModel.processImageScanResults`
    /// (L273-327). Same validation branches in the same order, and
    /// EXISTING ingredients are kept in the result with `matchState = .existing`
    /// so the popup can render them as grey/disabled rows (UIKit L315-320):
    ///
    ///   if exists in liquor/mixer → `cleaningFlow.matchState = .existing`
    ///                                → still appended
    ///   else                        → appended (new, selectable)
    ///
    ///   • nil / empty                              → ingredientCannotBeUsedHere
    ///   • only garnish / additional                → ingredientCannotBeUsedHere
    ///   • first item missing primary/secondary      → ingredientCannotBeUsedHere
    ///   • valid                                     → append with matchState
    private func processImageScanResults(
        _ detected: [MyBarIngredientFromImage]
    ) -> (ingredients: [DetectedMyBarIngredient], errorMessage: String?) {
        guard !detected.isEmpty else {
            return ([], Constants.ingredientCannotBeUsedHere)
        }

        // Keep only base / mixer entries — garnish & additional are
        // silently dropped (UIKit L278-280).
        let baseAndMixer = detected.filter {
            let p = ($0.category?.primary ?? "").lowercased()
            // UIKit SQL: NOT IN ('garnish','additionals','additional').
            return p != "garnish" && p != "additional" && p != "additionals"
        }
        if baseAndMixer.isEmpty {
            return ([], Constants.ingredientCannotBeUsedHere)
        }
        let first = baseAndMixer[0]
        let primary = first.category?.primary ?? ""
        let secondary = first.category?.secondary ?? ""
        if primary.isEmpty || secondary.isEmpty {
            return ([], Constants.ingredientCannotBeUsedHere)
        }

        // Dedup set — case-insensitive name match across liquor + mixer,
        // matching UIKit L315-320 check against `liqourIngredientsArray`
        // and `mixerIngredientsArray`.
        let existingNames = Set(allIngredients.map { $0.name.lowercased() })
        var result: [DetectedMyBarIngredient] = []
        for item in baseAndMixer {
            let name = item.name ?? ""
            guard !name.isEmpty else { continue }
            let category = IngredientCategory(
                primary: item.category?.primary,
                secondary: item.category?.secondary,
                flavourTags: nil
            )
            let ingredient = Ingredient(
                name: name,
                unit: Constants.mlText.lowercased(),
                notes: "",
                category: category,
                quantity: 0,
                perishable: item.perishable,
                substitutes: item.substitutes,
                ingredientOptional: false
            )
            let isExisting = existingNames.contains(name.lowercased())
            // UIKit MultipleIngredientsPopUp L115-118: new ingredients
            // default to SELECTED; existing ones are locked.
            result.append(DetectedMyBarIngredient(
                ingredient: ingredient,
                isExisting: isExisting,
                isSelected: !isExisting
            ))
        }
        return (result, nil)
    }

    // MARK: - Actions

    /// 1:1 with UIKit `didPressShowRecipeAction:`. Guards replicate
    /// the same empty / no-allowed alerts.
    private func showRecipesAction() {
        guard hasData else {
            env.alerts.show(message: Constants.ingredientUpdateError)
            return
        }
        let allowed = allIngredients.filter { ing in
            let p = ing.category?.primary ?? ""
            let s = ing.category?.secondary ?? ""
            return !p.isEmpty || !s.isEmpty
        }
        guard !allowed.isEmpty else {
            env.alerts.show(message: Constants.ingredientUpdateError)
            return
        }
        router.push(.exploreRecipes, in: .myBar)
    }

    /// 1:1 with UIKit delete-confirmation `Yes` branch.
    private func confirmDelete() {
        guard let ingredient = pendingDelete else { return }
        env.storage.toggleMyBar(ingredient)
        pendingDelete = nil
    }
}

// MARK: - MyBarPrimaryButton / MyBarSecondaryButton
//
// 1:1 with the four storyboard buttons (zVV, Avz, jrL, Nx2). Every
// button shares the same 168.67×45 frame and 8pt corner (iOS 26+
// swaps to capsule + gradient). They differ only in background:
//   • Primary (Take A Photo / Show Recipes) — `brandTanColor`
//     → iOS 26+ gets `makeOrangeStyle()` vertical brand gradient
//   • Secondary (Upload from Photos / Add ingredient)
//     — `primaryBackgroundColor` + 1pt `craftButtonBorderColor`
//     → iOS 26+ gets `applyCancelCapsuleGradientBorderStyle()`

private struct MyBarPrimaryButton: View {
    let title: String
    let action: () -> Void

    /// Reactive theme awareness — used ONLY to override the dark-mode
    /// brand-gradient asset back to the light-mode orange RGB. UIKit's
    /// `PrimaryOrangeButton.makeOrangeStyle()` always renders the
    /// brand orange gradient regardless of appearance, but the SwiftUI
    /// port's `brandGradientTop` / `brandGradientBottom` colour assets
    /// have a dark-appearance variant that resolves to dark grey /
    /// near-black — which made the "Take A Photo" / "Show Recipes"
    /// primary buttons render as invisible dark pills in dark mode.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(primaryFill)
                .clipShape(primaryShape)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var primaryFill: some View {
        if #available(iOS 26.0, *) {
            if colorScheme == .dark {
                // DARK MODE ONLY: bypass the asset-based colour
                // resolution and use the LIGHT-mode brand-orange RGB
                // values from `brandGradientTop` / `brandGradientBottom`
                // (peach → tan gradient). The asset's dark variant
                // renders as dark grey which makes the primary
                // button unreadable; the brand button should stay
                // orange in both appearances.
                LinearGradient(
                    colors: [
                        Color(red: 0.980, green: 0.878, blue: 0.800),
                        Color(red: 0.949, green: 0.761, blue: 0.631)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // Light mode: unchanged — uses the existing colour
                // assets so light-mode pixels stay bit-identical to
                // the existing UIKit-parity rendering.
                LinearGradient(
                    colors: [Color("brandGradientTop"), Color("brandGradientBottom")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            Color("brandTanColor")
        }
    }

    private var primaryShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct MyBarSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                // Preserve EXACT pure black in light mode (bit-identical
                // to the previous hard-coded `Color.black`); switch to
                // a near-white tone in dark mode for legibility on the
                // dark `Theme.Color.surface` capsule. Trait-resolved
                // at draw time → light pixels are unchanged.
                // Used by "Upload from Photos", "Add ingredient", and
                // "Re-Upload" — all share this component.
                .foregroundStyle(Color(UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
                        : UIColor.black // EXACT historical black
                }))
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .background(secondaryFill)
                .overlay(secondaryBorder)
                .clipShape(secondaryShape)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var secondaryFill: some View {
        if #available(iOS 26.0, *) {
            // `Theme.Color.surface` light = pure white sRGB(1, 1, 1),
            // bit-identical to the previous hard-coded `Color.white`,
            // so the iOS 26+ secondary capsule is the EXACT same white
            // pill in light mode. Dark mode picks up the elevated dark
            // surface (#2C2C2E) so the pill stops being a stark white
            // slab on the dark MyBar canvas.
            Theme.Color.surface
        } else {
            Color("primaryBackgroundColor")
        }
    }

    @ViewBuilder
    private var secondaryBorder: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9),
                                 Color("craftButtonBorderColor")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color("craftButtonBorderColor"), lineWidth: 1)
        }
    }

    private var secondaryShape: AnyShape {
        if #available(iOS 26.0, *) {
            return AnyShape(Capsule(style: .continuous))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - ScanIngredientsView (stub)
//
// Preserves the existing router route so any external callers still
// compile. The full AVFoundation camera + retake/submit port is a
// separate work item; the MyBar buttons now bypass this entirely by
// using the `BarBotImagePicker` sheet flow above.

struct ScanIngredientsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var scanned: String?

    var body: some View {
        ZStack {
            QRScannerView(onScan: { code in
                scanned = code
                env.alerts.show(message: "Scanned ingredient code: \(code)")
            }, onCancel: {
                dismiss()
            })
            .ignoresSafeArea()

            VStack {
                Spacer()
                Text("Point the camera at an ingredient barcode")
                    .font(Theme.Font.body(14))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.m)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Scan ingredient")
        .navigationBarTitleDisplayMode(.inline)
    }
}
