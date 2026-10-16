import HassCore
import HassDesign
import ImageIO
import SwiftUI
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The camera viewer (web `CameraModalContent`): the camera's shared live stream with Snapshot, Sound and
/// Record controls under it.
///
/// Where the window may split (iPad and unfolded iPhone Duo in landscape) the video takes the leading half and
/// the controls stack in the trailing half (web `media-split`); everywhere else the controls sit in a row
/// under the video. HIG: Playing video (live content shows its state), Buttons (44 pt targets, labels under
/// icons), Sheets.
struct CameraViewer: View {
    var camera: HomeConfig.Camera
    /// Where the Record call goes; `nil` uses the app's connection.
    var caller: (any HassServiceCalling)?
    @Environment(HassConnection.self) private var connection
    @Environment(EntityStore.self) private var store
    @Environment(\.cameraStreamPool) private var poolOverride
    @Environment(\.dismiss) private var dismiss
    @State private var window = WindowMetrics()

    private var pool: CameraStreamPool { poolOverride ?? .shared }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let split = CameraViewerLayout.usesSplit(
                    window: window.size ?? proxy.size, isRegularWidth: window.isRegularWidth, container: proxy.size)
                Group {
                    if split {
                        // Fixed halves (inside the outer padding), so the video can never push into the controls.
                        let half = max((proxy.size.width - 3 * HassTokens.Spacing.l) / 2, 0)
                        HStack(alignment: .top, spacing: HassTokens.Spacing.l) {
                            video.frame(width: half)
                            ScrollView { controls(axis: .vertical) }
                                .frame(width: half)
                        }
                        // One container, so the layout identifier below doesn't replace the video's own.
                        .accessibilityElement(children: .contain)
                    } else {
                        ScrollView {
                            VStack(spacing: HassTokens.Spacing.xl) {
                                video
                                controls(axis: .horizontal)
                            }
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(HassTokens.Spacing.l)
                .accessibilityIdentifier(split ? "camera.layout.split" : "camera.layout.stacked")
            }
            .background { WindowMetricsReader(metrics: $window) }
            .modalChrome()
            .navigationTitle(camera.title)
            .inlineNavigationTitle()
            .toolbar { SheetCloseItem { dismiss() } }
        }
        // A page sheet on iPad, so landscape has room for the video beside the controls.
        .hassSheet(.page)
        // Cameras reopen muted, like the web's pooled cards.
        .onDisappear { pool.model(for: camera).setMuted(true) }
    }

    private var video: some View {
        CameraLiveView(camera: camera)
            .aspectRatio(camera.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
    }

    private func controls(axis: Axis) -> some View {
        CameraControls(camera: camera, model: pool.model(for: camera), caller: caller ?? connection,
                       isRecording: camera.recordingEntityId.map { store.entity($0).state?.state == "on" } ?? false,
                       axis: axis)
    }
}

// MARK: - Controls

/// Snapshot, Sound and Record (web `ActionPill`s in `CameraModalContent`).
struct CameraControls: View {
    var camera: HomeConfig.Camera
    var model: CameraLiveModel
    var caller: any HassServiceCalling
    var isRecording: Bool
    var axis: Axis
    @Environment(EntityStore.self) private var store
    @Environment(HassConnection.self) private var connection
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var snapshot = CameraSnapshotFeedback.idle
    @State private var showsPhotosDenied = false
    /// The tapped recording state, shown until Home Assistant reports it (rolled back if the script call fails).
    @State private var actions: OptimisticActions?

    var body: some View {
        // Accessibility sizes stack the controls: three across break their labels mid-word at AX5.
        let layout = axis == .horizontal && !typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: HassTokens.Spacing.m))
            : AnyLayout(VStackLayout(spacing: HassTokens.Spacing.m))
        layout {
            CameraControlButton(
                title: snapshot.title, symbol: snapshot.symbol, isActive: snapshot != .idle, tint: HassTokens.Ink.action,
                pulses: snapshot == .saving, accessibilityLabel: "Snapshot", accessibilityValue: snapshot.accessibilityValue,
                identifier: "camera.control.snapshot"
            ) { takeSnapshot() }
            .disabled(snapshot == .saving)
            CameraControlButton(
                title: model.isMuted ? "Muted" : "Sound On",
                symbol: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isActive: !model.isMuted, tint: HassTokens.Ink.action, pulses: false,
                accessibilityLabel: "Sound", accessibilityValue: model.isMuted ? "Off" : "On", isToggle: true,
                identifier: "camera.control.sound"
            ) { model.setMuted(!model.isMuted) }
            if let call = camera.recordCall {
                CameraControlButton(
                    title: recording ? "Recording" : "Record", symbol: "record.circle",
                    isActive: recording, tint: HassTokens.Ink.danger, pulses: recording,
                    accessibilityLabel: "Record", accessibilityValue: recording ? "Recording" : "Not recording", isToggle: true,
                    identifier: "camera.control.record"
                ) { record(call) }
                .sensoryFeedback(.impact(weight: .medium), trigger: recording)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(camera.title) camera controls")
        .sensoryFeedback(trigger: snapshot) { _, new in
            switch new {
            case .saved: .success
            case .failed: .error
            default: nil
            }
        }
        .alert("Allow Photos Access", isPresented: $showsPhotosDenied) {
            #if canImport(UIKit)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            #endif
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Snapshots are saved to your photo library. Allow Home to add photos in Settings.")
        }
    }

    // MARK: - Record

    /// Recording as shown: the pending tap, else the live `input_boolean`.
    private var recording: Bool {
        guard let id = camera.recordingEntityId, let shown = actions?.shown(id) else { return isRecording }
        return shown == "on"
    }

    private func record(_ call: ServiceCall) {
        guard let id = camera.recordingEntityId else {
            Task { try? await caller.call(call) } // No state to show: nothing to roll back.
            return
        }
        let actions = actions ?? OptimisticActions(store: store, rules: [id: .confirmation], caller: caller)
        self.actions = actions
        // The script toggles the recording; it can take a few seconds to report.
        actions.perform(call, showing: [OptimisticIntent(id, recording ? "off" : "on", revertAfter: .seconds(6))])
    }

    // MARK: - Snapshot

    private func takeSnapshot() {
        snapshot = .saving
        let frame = model.liveFrameSource()
        let fallbackURL = snapshotURL
        Task {
            let result = await CameraSnapshotSaver.save(frame: await frame?.image(), fallbackURL: fallbackURL)
            switch result {
            case .saved: snapshot = .saved
            case .denied:
                snapshot = .idle
                showsPhotosDenied = true
                return
            case .failed: snapshot = .failed
            }
            #if canImport(UIKit)
            UIAccessibility.post(notification: .announcement, argument: snapshot.accessibilityValue)
            #endif
            try? await Task.sleep(for: .seconds(2))
            snapshot = .idle
        }
    }

    /// The camera's still from Home Assistant, used when no live frame is playing.
    private var snapshotURL: URL? {
        guard let picture = store.entity(camera.entityId).state?.attributes["entity_picture"]?.string else { return nil }
        return URL(string: picture, relativeTo: connection.server.baseURL)?.absoluteURL
    }
}

/// What the Snapshot button shows (web `snapshotPulse`, here with the save's outcome).
enum CameraSnapshotFeedback: Equatable {
    case idle, saving, saved, failed

    var title: String {
        switch self {
        case .idle, .saving: "Snapshot"
        case .saved: "Saved"
        case .failed: "Not Saved"
        }
    }

    var symbol: String {
        switch self {
        case .idle, .saving: "camera.fill"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle: ""
        case .saving: "Saving"
        case .saved: "Saved to Photos"
        case .failed: "Couldn't save the snapshot"
        }
    }
}

/// One camera control: a circle over its label, the glyph tinted while on (direction G mockup n2 camera: Snapshot,
/// Audio and Record circles; HIG Buttons: labels under icons). The circle is the sheet's cell colour, not Liquid
/// Glass: these controls sit on the sheet ground under the video, not over it, and glass is for the navigation
/// layer (HIG: Materials).
struct CameraControlButton: View {
    var title: String
    var symbol: String
    var isActive: Bool
    var tint: Color
    var pulses: Bool
    var accessibilityLabel: String
    var accessibilityValue: String
    var isToggle = false
    var identifier: String
    var action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var circle: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: HassTokens.Spacing.s) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulses && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(isActive ? tint : HassTokens.Ink.primary)
                    .frame(width: max(circle, HassTokens.minTarget), height: max(circle, HassTokens.minTarget))
                    .background {
                        Circle()
                            .fill(HassTokens.Surface.sheetCell)
                            .overlay { if isActive { Circle().fill(tint.opacity(0.22)) } }
                    }
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HassTokens.Ink.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: HassTokens.minTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityInputLabels([accessibilityLabel, title])
        .accessibilityAddTraits(isToggle ? .isToggle : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Saving

/// Saves a camera snapshot to the photo library (web `saveScreenshot` downloads a JPEG).
enum CameraSnapshotSaver {
    enum Result: Equatable { case saved, denied, failed }

    /// Saves the live frame, or the camera's Home Assistant still when no frame is playing.
    static func save(frame: CGImage?, fallbackURL: URL?) async -> Result {
        var data = frame.flatMap(jpeg)
        if data == nil, let fallbackURL,
           let (still, response) = try? await URLSession.shared.data(from: fallbackURL),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            data = still
        }
        guard let data else { return .failed }
        #if canImport(Photos) && canImport(UIKit)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
        #else
        return .failed
        #endif
    }

    /// JPEG data for an image.
    static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

// MARK: - Layout

/// When the viewer splits video and controls (owner's split rules, `.agents/design/apple/split-view.md`).
enum CameraViewerLayout {
    /// The narrowest sheet that holds the video beside the controls.
    static let minimumSplitWidth: CGFloat = 640

    static func usesSplit(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumSplitWidth
    }
}
