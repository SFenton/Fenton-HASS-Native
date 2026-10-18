import Foundation
import HassCore
import HassTelemetry
import Observation

/// The words on the sign-in screen, in one place so the view, the model and the tests agree.
enum LoginCopy {
    static let appName = "S+H"
    static let subtitle = "Sign in to your Home Assistant"
    static let signInTitle = "Sign In"
    static let busyTitle = "Signing In…"
    static let retryTitle = "Try Again"
    static let footnote = "Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password."
    static let wrongCredentials = "That username and password don't match. Check them and try again."
    static let twoStepUnsupported = "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant."
    static let unreachableTitle = "Can't reach Home right now"
    static let unreachableBody = "Check that this phone is online. If it is, Home Assistant may be restarting; try again in a minute."
    static let failedTitle = "Sign-in didn't work"
    static let failedBody = "Something went wrong while signing in. Try again; if it keeps happening, the details may say why."
    static let detailsTitle = "Details"
    static let welcomeSubtitle = "Your sign-in ended. Enter your password to pick up where you left off."
    static let differentAccount = "Use a Different Account"

    static func welcomeBack(_ firstName: String) -> String { "Welcome back, \(firstName)" }
}
