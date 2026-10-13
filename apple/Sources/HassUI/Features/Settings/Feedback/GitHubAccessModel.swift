import Foundation
import HassCore
import Observation

/// State behind the GitHub Access page: the saved token's user, and checking a new token before it is
/// saved, so a mistyped or under-scoped token is caught here rather than on Submit.
@MainActor
@Observable
final class GitHubAccessModel {
    /// The check of a new token.
    enum Check: Equatable {
        case idle
        case verifying
        case failed(String)
    }

    /// The token being typed. Cleared once saved; never shown back.
    var tokenText = ""
    private(set) var access: GitHubAccess?
    private(set) var check: Check = .idle
    @ObservationIgnored private let services: FeedbackServices

    /// Creates the model from the saved access.
    init(services: FeedbackServices = .current) {
        self.services = services
        access = services.store.load()
    }

    /// Whether Save Token can run.
    var canSave: Bool {
        !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && check != .verifying
    }

    /// Verifies the typed token against the request repository and saves it.
    /// - Returns: True when it was saved.
    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        check = .verifying
        do {
            let verified = try await services.filer.verify(token: tokenText)
            try services.store.save(verified)
            access = verified
            tokenText = ""
            check = .idle
            return true
        } catch let error as FeedbackFilingError {
            check = .failed(error.errorDescription ?? "")
        } catch {
            check = .failed("The token couldn't be saved on this device. Try again.")
        }
        return false
    }

    /// Deletes the saved token from this device (and, through iCloud Keychain, the person's others).
    func remove() {
        services.store.clear()
        access = nil
        check = .idle
    }
}
