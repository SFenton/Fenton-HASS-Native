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

/// Loads the camera for the expanded notification: Home Assistant's MJPEG stream at once (plain HTTP with the
/// token, so it works even when the websocket can't connect), and its HLS stream when that comes up, which then
/// takes over. The first to deliver frames turns on the Live badge.
@MainActor
@Observable
final class CameraNotificationModel {
    var title = ""
    var snapshot: UIImage?
    var player: AVPlayer?
    var isLive = false
    var failed = false
    /// What the model is doing, shown in debug builds.
    var status = "starting"
    private var connection: HassConnection?
    private var observation: NSKeyValueObservation?
    private var mjpeg: Task<Void, Never>?
    private let trace = PushTrace.shared

    func start(entityID: String) {
        let store = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup)
        guard let credentials = store.load() else {
            note("not signed in")
            failed = true
            return
        }
        let tokens = TokenManager(store: store)
        mjpeg = Task { await streamMJPEG(entityID: entityID, server: credentials.server, tokens: tokens) }
        startHLS(entityID: entityID, server: credentials.server, tokens: tokens)
    }

    func stop() {
        mjpeg?.cancel()
        player?.pause()
        connection?.disconnect()
    }

    private func note(_ text: String) {
        status = text
        trace.record("content: \(text)")
    }

    // MARK: - MJPEG

    private func streamMJPEG(entityID: String, server: HassServer, tokens: TokenManager) async {
        do {
            let token = try await tokens.validAccessToken()
            var request = URLRequest(url: server.url("/api/camera_proxy_stream/\(entityID)"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let stream = MJPEGDataStream(request: request)
            defer { stream.cancel() }
            var scanner = MJPEGFrameScanner()
            var started = false
            // The delegate hands over each network read (kilobytes), not a byte at a time.
            for try await event in stream.events {
                switch event {
                case let .response(code):
                    note("mjpeg HTTP \(code)")
                    guard code == 200 else { return }
                    started = true
                case let .data(chunk):
                    guard started else { continue }
                    if let frame = scanner.append(chunk).last, player == nil || !isLive, let image = UIImage(data: frame) {
                        snapshot = image
                        if !isLive { isLive = true; note("mjpeg live") }
                    }
                }
            }
        } catch is CancellationError {
        } catch {
            note("mjpeg failed \(type(of: error)) \((error as NSError).code)")
        }
    }

    // MARK: - HLS

    private func startHLS(entityID: String, server: HassServer, tokens: TokenManager) {
        let connection = HassConnection(server: server, tokens: tokens, store: EntityStore(),
                                        snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory
                                            .appendingPathComponent("notification-snapshot.json")))
        self.connection = connection
        connection.connect(subscribingToStates: false)
        Task {
            do {
                let path = try await connection.cameraStreamPath(entityId: entityID)
                trace.record("content: hls path received")
                guard let url = CameraStreamEndpoints.hlsURL(path: path, baseURL: server.baseURL) else { return }
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                observation = item.observe(\.status) { [weak self] item, _ in
                    let ready = item.status == .readyToPlay
                    let reason = item.error.map { "\(($0 as NSError).domain) \(($0 as NSError).code)" } ?? ""
                    Task { @MainActor in
                        guard let self else { return }
                        if ready {
                            self.player = player
                            self.isLive = true
                            self.mjpeg?.cancel()
                            self.note("hls playing")
                        } else if item.status == .failed {
                            self.trace.record("content: hls failed \(reason)")
                        }
                    }
                }
                player.play()
                hlsPlayer = player
            } catch {
                trace.record("content: hls request failed \(type(of: error))")
            }
        }
    }

    /// Holds the HLS player while it loads, before it is shown.
    private var hlsPlayer: AVPlayer?
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
            #if DEBUG
            Text(model.status)
                .font(.caption2.monospaced())
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            #endif
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


/// A streaming GET delivered as whole network reads through a `URLSessionDataDelegate`.
private final class MJPEGDataStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case response(Int)
        case data(Data)
    }

    let events: AsyncThrowingStream<Event, Error>
    private let continuation: AsyncThrowingStream<Event, Error>.Continuation
    private var session: URLSession?

    init(request: URLRequest) {
        (events, continuation) = AsyncThrowingStream.makeStream()
        super.init()
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        continuation.finish()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        continuation.yield(.response((response as? HTTPURLResponse)?.statusCode ?? 0))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled { continuation.finish(throwing: error) } else { continuation.finish() }
    }
}
