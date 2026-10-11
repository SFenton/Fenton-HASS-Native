import HassUI
import SwiftUI
import UIKit

@main
struct FentonHomeApp: App {
    @UIApplicationDelegateAdaptor(FentonHomeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Supplies supported orientations only: iPhone stays portrait (Info.plist), iPad keeps all four, and a
/// device with a hinge (iPhone Duo) rotates folded or unfolded (owner, 2026-10-10).
final class FentonHomeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        FentonOrientationSupport.mask(for: window)
    }
}
