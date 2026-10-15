import AVFoundation
import HassCore
import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The expanded view of a camera notification (`fenton.camera`, `.agents/platforms/apple/push.md`): the attached
/// snapshot at once, then the camera live over Home Assistant's HLS stream, with the notification's own buttons.
///
/// Signs in with the refresh token the app shares through the app group, opens a commands-only websocket
/// (`HassConnection.connect(subscribingToStates: false)`) for `camera/stream`, and plays the tokenized playlist.
final class NotificationViewController: UIViewController, @preconcurrency UNNotificationContentExtension {
    private let model = CameraNotificationModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: CameraNotificationView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .black
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        guard let payload = PushPayload(userInfo: content.userInfo) else {
            PushTrace.shared.record("content: no fenton payload")
            return
        }
        PushTrace.shared.record("content: \(content.categoryIdentifier), \(content.attachments.count) attachments, entity \(payload.entityID ?? "-")")
        // Buttons per notification: the camera category is fixed, so its actions are set here.
        extensionContext?.notificationActions = payload.actions.map(\.notificationAction)
        model.title = content.title
        if let url = content.attachments.first?.url, url.startAccessingSecurityScopedResource() {
            model.snapshot = UIImage(contentsOfFile: url.path)
            url.stopAccessingSecurityScopedResource()
        }
        if let entity = payload.entityID { model.start(entityID: entity) }
    }

    /// Every button goes to the app, which opens links and fires `mobile_app_notification_action`.
    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        model.stop()
        completion(.dismissAndForwardAction)
    }
}

/// Loads the camera's stream for the expanded notification.
@MainActor
@Observable
final class CameraNotificationModel {
    var title = ""
    var snapshot: UIImage?
    var player: AVPlayer?
    var isLive = false
    var failed = false
    private var connection: HassConnection?
    private var observation: NSKeyValueObservation?

    func start(entityID: String) {
        let store = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup)
        guard let credentials = store.load() else {
            PushTrace.shared.record("content: not signed in")
            failed = true
            return
        }
        let connection = HassConnection(server: credentials.server, tokens: TokenManager(store: store), store: EntityStore(),
                                        snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory
                                            .appendingPathComponent("notification-snapshot.json")))
        self.connection = connection
        connection.connect(subscribingToStates: false)
        Task {
            do {
                let path = try await connection.cameraStreamPath(entityId: entityID)
                PushTrace.shared.record("content: stream path received")
                guard let url = CameraStreamEndpoints.hlsURL(path: path, baseURL: credentials.server.baseURL) else {
                    failed = true
                    return
                }
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                observation = item.observe(\.status) { [weak self] item, _ in
                    let ready = item.status == .readyToPlay, broken = item.status == .failed
                    let reason = item.error.map { "\(($0 as NSError).domain) \(($0 as NSError).code)" } ?? ""
                    Task { @MainActor in
                        if ready { self?.isLive = true; PushTrace.shared.record("content: playing") }
                        if broken { self?.failed = true; PushTrace.shared.record("content: player failed \(reason)") }
                    }
                }
                self.player = player
                player.play()
            } catch {
                PushTrace.shared.record("content: stream request failed \(type(of: error))")
                failed = true
            }
        }
    }

    func stop() {
        player?.pause()
        connection?.disconnect()
    }
}

/// The snapshot, then the live player over it, with a Live badge once frames arrive.
struct CameraNotificationView: View {
    let model: CameraNotificationModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let snapshot = model.snapshot {
                Image(uiImage: snapshot).resizable().scaledToFit()
            }
            if let player = model.player {
                PlayerLayerView(player: player).opacity(model.isLive ? 1 : 0)
            }
            badge.padding(10)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isLive ? "\(model.title), live camera" : "\(model.title), camera snapshot")
    }

    @ViewBuilder
    private var badge: some View {
        if model.isLive {
            Label("Live", systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.red, in: .capsule)
        } else if !model.failed {
            ProgressView().tint(.white)
        }
    }
}

/// An `AVPlayerLayer` that fills its view (SwiftUI's `VideoPlayer` adds controls a glance doesn't need).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
