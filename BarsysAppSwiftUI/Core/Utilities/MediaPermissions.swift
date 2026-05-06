import AVFoundation
import Photos
import UIKit

// MARK: - Media permissions helper
//
// 1:1 port of UIKit `ImagePickerViewController.swift`'s pre-flight
// permission flow (L91-213). UIKit always called
// `checkAuthorizationAndShowCamera` / `checkAuthorizationAndShowPhotos`
// BEFORE presenting `UIImagePickerController` — without that gate,
// iOS hands back a `UIImagePickerController` whose preview is a
// black surface (camera) or whose picker has no items (photos)
// because the underlying APIs silently fail when access is denied.
//
// The SwiftUI port previously presented `BarBotImagePicker` directly
// from the action-sheet callbacks, skipping the gate — surfacing as
// the "camera shows a black screen" / "nothing happens when I tap
// camera" reports across BarBot, Add Ingredient, Edit Recipe,
// MyProfile and MyBar. This file restores the gate.

/// Static helpers around `AVCaptureDevice` (camera) and
/// `PHPhotoLibrary` (photos) — performs the permission check, runs
/// the system request when status is `.notDetermined`, and reports
/// back on the main queue with a single `granted` boolean. Treat
/// `.limited` photo access as granted so the user can still pick
/// from the subset of photos they whitelisted (UIKit
/// `checkAuthorizationAndShowPhotos` walks straight into the
/// `UIImagePickerController` once `requestAuthorization` returns,
/// regardless of whether the new status is `.authorized` or
/// `.limited`).
enum MediaPermissions {
    static func requestCamera(_ completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    static func requestPhotoLibrary(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Deep-link into the Settings app's row for this bundle id —
    /// 1:1 port of UIKit `openSettingsForApp()`
    /// (UIViewController+Settings.swift L11-15).
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - AlertQueue convenience: gated picker presentation
//
// Wraps `MediaPermissions.requestX` so the call site reads as a
// single line:
//
//     env.alerts.requestCameraAccess {
//         imagePickerPresentation = .init(source: .camera)
//     }
//
// On grant → `onGranted` fires.
// On deny → a two-button popup is shown via the existing
//   `AlertQueue.show(...)` overlay (rendered by
//   `LoadingOverlayModifier` at the app root), with one button that
//   deep-links to Settings. Button order matches UIKit
//   `ImagePickerViewController.checkAuthorizationAndShowCamera` /
//   `checkAuthorizationAndShowPhotos` exactly:
//
//   • Camera denied  → primary "Cancel" (left, tinted, no-op),
//                      secondary "Go to settings" (right, opens Settings)
//   • Photos denied  → primary "Go to settings" (left, tinted, opens Settings),
//                      secondary "Cancel" (right, no-op)
//
//   The button-position swap between camera and photos mirrors UIKit
//   verbatim (the older app codes them in different orders inside
//   `showCustomAlertMultipleButtons` calls — see ImagePickerViewController.swift
//   L95 vs L176). Don't "fix" the asymmetry; QA signed off on it.
extension AlertQueue {
    func requestCameraAccess(onGranted: @escaping () -> Void) {
        MediaPermissions.requestCamera { [weak self] granted in
            guard let self else { return }
            if granted {
                onGranted()
            } else {
                self.show(
                    title: Constants.appNeedsCameraAccess,
                    primaryTitle: ConstantButtonsTitle.cancelButtonTitle,
                    secondaryTitle: ConstantButtonsTitle.goToSettingsTitle,
                    onSecondary: { MediaPermissions.openAppSettings() }
                )
            }
        }
    }

    func requestPhotoLibraryAccess(onGranted: @escaping () -> Void) {
        MediaPermissions.requestPhotoLibrary { [weak self] granted in
            guard let self else { return }
            if granted {
                onGranted()
            } else {
                self.show(
                    title: Constants.appNeedsGalleryAccess,
                    primaryTitle: ConstantButtonsTitle.goToSettingsTitle,
                    secondaryTitle: ConstantButtonsTitle.cancelButtonTitle,
                    onPrimary: { MediaPermissions.openAppSettings() }
                )
            }
        }
    }
}
