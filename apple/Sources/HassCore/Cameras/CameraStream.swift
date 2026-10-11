import Foundation

// MARK: - Modes

/// How a camera plays live video, in preference order.
public enum CameraStreamMode: String, Sendable, CaseIterable {
    /// Low latency through go2rtc, signalled over the WebRTC integration's `/api/webrtc/ws`
    /// (`SFenton/WebRTC`, the same path the web `webrtc-camera-sfenton` card uses).
    case webRTC
    /// Home Assistant's own HLS stream (`camera/stream`): a few seconds behind, but needs nothing beyond core.
    case hls

    /// How long this mode may take to show its first frame before the next mode is tried.
    ///
    /// Home Assistant holds the first HLS playlist request until a cold stream has its first segment
    /// (9.5 to 12.7 s on the Home cameras, measured 2026-10-10), so HLS gets a longer budget than WebRTC.
    public var firstFrameTimeout: Duration {
        switch self {
        case .webRTC: .seconds(10)
        case .hls: .seconds(25)
        }
    }
}

// MARK: - State

/// The live-video state machine for one camera view: try each mode in order and fall back on failure.
///
/// The view keeps the snapshot on screen until ``phase`` is ``Phase/live``, so a slow or failed stream
/// never blanks the camera.
public struct CameraStreamState: Equatable, Sendable {
    /// Where the stream is.
    public enum Phase: Equatable, Sendable {
        /// The current mode is connecting; the snapshot stays up.
        case connecting
        /// The current mode is showing frames.
        case live
        /// Every mode failed; the snapshot stays up with a retry.
        case failed
    }

    /// Modes to try, in order.
    public let modes: [CameraStreamMode]
    /// Current phase.
    public private(set) var phase: Phase
    private var index = 0

    /// Creates a state that starts connecting the first mode.
    /// - Parameter modes: Modes to try, in order. Empty means no live video.
    public init(modes: [CameraStreamMode] = CameraStreamMode.allCases) {
        self.modes = modes
        phase = modes.isEmpty ? .failed : .connecting
    }

    /// The mode being connected or shown; `nil` once every mode failed.
    public var mode: CameraStreamMode? { phase == .failed ? nil : modes[index] }

    /// The current mode showed its first frame. Events for any other mode are stale and ignored.
    public mutating func firstFrame(_ mode: CameraStreamMode) {
        guard mode == self.mode, phase == .connecting else { return }
        phase = .live
    }

    /// The current mode failed (or dropped while live): move to the next mode, or to ``Phase/failed``.
    public mutating func failed(_ mode: CameraStreamMode) {
        guard mode == self.mode else { return }
        if index + 1 < modes.count {
            index += 1
            phase = .connecting
        } else {
            phase = .failed
        }
    }

    /// Starts over from the first mode (retry, or returning to the foreground).
    public mutating func restart() {
        index = 0
        phase = modes.isEmpty ? .failed : .connecting
    }
}

// MARK: - Endpoints

/// URLs for camera streams on a Home Assistant server.
public enum CameraStreamEndpoints {
    /// The WebRTC integration's signalling socket, signed with `auth/sign_path` before connecting.
    public static let webRTCSocketPath = "/api/webrtc/ws"

    /// Resolves the tokenized playlist path `camera/stream` returns (`/api/hls/<token>/master_playlist.m3u8`).
    /// - Parameters:
    ///   - path: The returned path.
    ///   - baseURL: The server origin.
    /// - Returns: The absolute playlist URL.
    public static func hlsURL(path: String, baseURL: URL) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Builds the signalling websocket URL for a go2rtc stream.
    /// - Parameters:
    ///   - signedPath: `auth/sign_path` output for ``webRTCSocketPath`` (`/api/webrtc/ws?authSig=…`).
    ///   - streamId: The go2rtc stream name, e.g. `front_door`.
    ///   - baseURL: The server origin.
    /// - Returns: A `ws`/`wss` URL with the stream appended as `url=`.
    public static func webRTCSocketURL(signedPath: String, streamId: String, baseURL: URL) -> URL? {
        guard let absolute = URL(string: signedPath, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let stream = streamId.addingPercentEncoding(withAllowedCharacters: allowed) ?? streamId
        let existing = components.percentEncodedQuery.map { $0 + "&" } ?? ""
        components.percentEncodedQuery = existing + "url=" + stream
        return components.url
    }
}

// MARK: - Signalling

/// One message on the WebRTC integration's signalling socket (go2rtc's JSON protocol).
public enum WebRTCSignal: Equatable, Sendable {
    /// Our SDP offer.
    case offer(String)
    /// The server's SDP answer.
    case answer(String)
    /// A trickled ICE candidate line (`candidate:…`), either direction.
    case candidate(String)
    /// The server could not open the stream.
    case error(String)

    /// Encodes the message as the JSON text the socket expects.
    public func encoded() -> String {
        let (type, value): (String, String) = switch self {
        case let .offer(sdp): ("webrtc/offer", sdp)
        case let .answer(sdp): ("webrtc/answer", sdp)
        case let .candidate(line): ("webrtc/candidate", line)
        case let .error(message): ("error", message)
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["type": type, "value": value])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes a message from the socket. Unknown types (e.g. go2rtc's `mse`) return `nil`.
    /// - Parameter text: The JSON text.
    public init?(text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        let value = object["value"] as? String ?? ""
        switch type {
        case "webrtc/offer": self = .offer(value)
        case "webrtc/answer": self = .answer(value)
        case "webrtc/candidate": self = .candidate(value)
        case "error": self = .error(value)
        default: return nil
        }
    }
}
