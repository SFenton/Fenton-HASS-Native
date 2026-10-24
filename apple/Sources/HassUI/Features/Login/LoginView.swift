import FentonActivityModel
import HassCore
import HassDesign
import HassTelemetry
import SwiftUI

/// Native username/password sign-in through Home Assistant's login flow (owner design, 2026-10-17;
/// `.agents/platforms/apple/auth.md`, "Sign-in screen").
///
/// Always dark, on a radial glow. The server is fixed, so the screen is a bare house-and-heart mark, the name, one line, a glass
/// module with the two fields, and the Sign In capsule. A session that ended shows the welcome back variant instead: the person's
/// monogram, the account read-only, only the password to type. Errors are plain sentences, inline; a server that cannot be
/// reached gets a card with the raw reason one tap away. On iPad and the unfolded Duo the form is a centred column no wider than
/// ``SignInStyle/columnWidth``.
///
/// `playsIntro` runs the launch sequence (the glow fades up, the mark springs in, the title and then the form rise) and is for
/// a cold launch only; Reduce Motion cross-fades the same pieces.
struct LoginView: View {
    /// Called with fresh tokens on success.
    var onSignedIn: @MainActor (HassServer, AuthTokens) throws -> Void
    /// Called after Use a Different Account has cleared the remembered account.
    var onUseDifferentAccount: () -> Void
    var playsIntro: Bool
    /// Called once the intro has started, so the session does not play it again.
    var onIntroPlayed: () -> Void

    @State private var model: LoginModel
    @State private var stage: Stage
    @FocusState private var focus: LoginField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The saved app icon, which colours the mark.
    private let icon = SignInStyle.savedIcon()

    /// How far the intro has got. Everything is shown when there is no intro.
    private struct Stage: Equatable {
        var glow: Bool
        var mark: Bool
        var markScale: CGFloat
        var title: Bool
        var form: Bool

        static let hidden = Stage(glow: false, mark: false, markScale: MotionTokens.Intro.markStart, title: false, form: false)
        static let shown = Stage(glow: true, mark: true, markScale: 1, title: true, form: true)
    }

    /// Creates the screen.
    /// - Parameters:
    ///   - model: The fields and sign-in flow (tests pass one on a stubbed session).
    ///   - playsIntro: Whether to play the launch sequence.
    ///   - onUseDifferentAccount: Called when the person leaves the welcome back sign-in for a fresh one.
    ///   - onSignedIn: Called with fresh tokens on success.
    init(model: LoginModel = LoginModel(), playsIntro: Bool = false, onIntroPlayed: @escaping () -> Void = {},
         onUseDifferentAccount: @escaping () -> Void = {}, onSignedIn: @escaping @MainActor (HassServer, AuthTokens) throws -> Void) {
        _model = State(initialValue: model)
        _stage = State(initialValue: playsIntro ? .hidden : .shown)
        self.playsIntro = playsIntro
        self.onIntroPlayed = onIntroPlayed
        self.onUseDifferentAccount = onUseDifferentAccount
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        ZStack {
            SignInGround(glow: stage.glow ? 1 : 0)
            GeometryReader { proxy in
                ScrollView {
                    column
                        .frame(maxWidth: SignInStyle.columnWidth)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        // The screen is one named group for assistive technologies; its controls keep their own labels.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sign in")
        // Dark throughout, like the app it opens.
        .preferredColorScheme(.dark)
        .onAppear {
            model.prefillForDebugTesting()
            signInByItself()
        }
        .task { playIntro() }
        .onChange(of: model.passwordFocusToken) { focus = .password }
        .onChange(of: model.failure) { _, failure in
            if let failure { AccessibilityNotification.Announcement(failure.announcement).post() }
        }
    }

    // MARK: Layout

    private var column: some View {
        VStack(spacing: 0) {
            Spacer(minLength: HassTokens.Spacing.xl)
            LoginHeader(mode: model.mode, icon: icon, markScale: stage.markScale, markShown: stage.mark,
                        titleShown: stage.title, titleRise: reduceMotion ? 0 : MotionTokens.Intro.titleRise)
            Spacer().frame(height: HassTokens.Spacing.xl + HassTokens.Spacing.s)
            VStack(spacing: HassTokens.Spacing.l) {
                form
                Spacer(minLength: HassTokens.Spacing.xl)
                Text(LoginCopy.footnote)
                    .font(.footnote)
                    .foregroundStyle(HassTokens.Surface.secondaryOnWallpaper)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("login.footnote")
            }
            .opacity(stage.form ? 1 : 0)
            .offset(y: stage.form || reduceMotion ? 0 : MotionTokens.Intro.formRise)
        }
        .padding(.horizontal, HassTokens.Spacing.xl)
        .padding(.bottom, HassTokens.Spacing.l)
    }

    private var form: some View {
        VStack(spacing: HassTokens.Spacing.l) {
            if let failure = model.failure, let title = failure.cardTitle, let message = failure.cardBody {
                LoginFailureCard(title: title, message: message, detail: failure.detail)
            }
            LoginFieldsModule(model: model, focus: $focus, onSubmit: submit)
            if let message = model.failure?.inlineMessage {
                LoginInlineError(message: message)
            }
            signInButton
            if case .welcomeBack = model.mode {
                Button(action: useDifferentAccount) {
                    Text(LoginCopy.differentAccount)
                        .font(.body)
                        .foregroundStyle(Color(rgb: SignInStyle.link))
                        .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("login.differentAccount")
            }
        }
        .animation(MotionTokens.quick, value: model.failure)
    }

    private var signInButton: some View {
        Button(action: submit) {
            HStack(spacing: HassTokens.Spacing.s) {
                if model.isWorking {
                    ArcSpinner(.inline)
                        // A turning arc keeps XCUITest from ever seeing the app idle (each tap then waits a minute), so
                        // journeys hold it still; the button's label and value still say it is busy.
                        .environment(\.arcSpinnersPaused, ProcessInfo.processInfo.environment["FENTON_UITEST_RESET"] == "1")
                        .accessibilityHidden(true)
                }
                Text(model.buttonTitle)
            }
        }
        .buttonStyle(PrimaryButtonStyle(pressedScale: 0.96))
        // Working keeps the button solid (the label says so); the model ignores a second press.
        .disabled(!model.canSubmit && !model.isWorking)
        // The arc is silent; the button says it is busy.
        .accessibilityValue(model.busyValue)
        .accessibilityIdentifier("login.submit")
    }

    /// Debug builds only: `FENTON_AUTOSIGNIN=1` presses Sign In by itself once the prefilled fields are in (after
    /// `FENTON_AUTOSIGNIN_DELAY` seconds, 2.5 by default, so the intro and its measurement are over), so a launch cost run
    /// signs in with no test driving the app.
    private func signInByItself() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["FENTON_AUTOSIGNIN"] == "1" else { return }
        let delay = environment["FENTON_AUTOSIGNIN_DELAY"].flatMap(Double.init) ?? 2.5
        Task {
            try? await Task.sleep(for: .seconds(delay))
            submit()
        }
        #endif
    }

    private func useDifferentAccount() {
        withAnimation(MotionTokens.quick) { model.useDifferentAccount() }
        onUseDifferentAccount()
    }

    private func submit() {
        focus = nil
        model.submit(onSignedIn: onSignedIn)
    }

    // MARK: Intro

    /// The launch sequence, about 1.2 s (owner, 2026-10-17): the glow fades up, the mark springs in (0.86 to 1.03 to 1), the
    /// title and subtitle fade up 10 pt, then the form rises 28 pt. Reduce Motion shows the same pieces in one 0.35 s
    /// cross-fade. No keyboard comes up by itself.
    private func playIntro() {
        guard playsIntro, stage != .shown else { return }
        onIntroPlayed()
        Telemetry.beginTracked(Telemetry.Name.intro)
        if reduceMotion {
            withAnimation(MotionTokens.crossFade) { stage = .shown } completion: { Telemetry.endTracked(Telemetry.Name.intro) }
            return
        }
        // One timeline, each piece delayed on its own animation; the mark settles when its rise completes.
        withAnimation(MotionTokens.Intro.glow) { stage.glow = true }
        withAnimation(MotionTokens.Intro.markRise.delay(MotionTokens.Intro.markDelay)) {
            stage.mark = true
            stage.markScale = MotionTokens.Intro.markPeak
        } completion: {
            withAnimation(MotionTokens.emphasized) { stage.markScale = 1 }
        }
        withAnimation(MotionTokens.Intro.title.delay(MotionTokens.Intro.titleDelay)) { stage.title = true }
        withAnimation(MotionTokens.Intro.form.delay(MotionTokens.Intro.formDelay)) {
            stage.form = true
        } completion: {
            Telemetry.endTracked(Telemetry.Name.intro)
        }
    }
}
