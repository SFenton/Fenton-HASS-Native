import Foundation
@testable import HassCore
import Testing

struct CameraStreamStateTests {
    @Test func startsConnectingTheFirstMode() {
        let state = CameraStreamState()
        #expect(state.mode == .webRTC)
        #expect(state.phase == .connecting)
    }

    @Test func firstFrameGoesLiveOnlyForTheCurrentMode() {
        var state = CameraStreamState()
        state.firstFrame(.hls)
        #expect(state.phase == .connecting, "a stale HLS frame must not mark WebRTC live")
        state.firstFrame(.webRTC)
        #expect(state.phase == .live)
    }

    @Test func failureFallsBackThenStops() {
        var state = CameraStreamState()
        state.failed(.webRTC)
        #expect(state.mode == .hls)
        #expect(state.phase == .connecting)
        state.failed(.webRTC)
        #expect(state.mode == .hls, "a stale WebRTC failure is ignored")
        state.failed(.hls)
        #expect(state.phase == .failed)
        #expect(state.mode == nil)
    }

    @Test func dropWhileLiveFallsBack() {
        var state = CameraStreamState()
        state.firstFrame(.webRTC)
        state.failed(.webRTC)
        #expect(state.mode == .hls)
        #expect(state.phase == .connecting)
    }

    @Test func restartReturnsToTheFirstMode() {
        var state = CameraStreamState()
        state.failed(.webRTC)
        state.failed(.hls)
        state.restart()
        #expect(state.mode == .webRTC)
        #expect(state.phase == .connecting)
    }

    @Test func noModesMeansFailed() {
        var state = CameraStreamState(modes: [])
        #expect(state.phase == .failed)
        #expect(state.mode == nil)
        state.restart()
        #expect(state.phase == .failed)
    }

    /// HLS waits out Home Assistant's cold-stream warm-up (about 10 to 13 s) before falling back.
    @Test func hlsGetsALongerFirstFrameBudgetThanWebRTC() {
        #expect(CameraStreamMode.webRTC.firstFrameTimeout == .seconds(10))
        #expect(CameraStreamMode.hls.firstFrameTimeout > .seconds(15))
    }
}

struct CameraStreamEndpointTests {
    let base = URL(string: "https://ha.example.com")!

    @Test func hlsPathResolvesAgainstTheServer() {
        let url = CameraStreamEndpoints.hlsURL(path: "/api/hls/abc/master_playlist.m3u8", baseURL: base)
        #expect(url?.absoluteString == "https://ha.example.com/api/hls/abc/master_playlist.m3u8")
    }

    @Test func webRTCSocketKeepsTheSignatureAndAddsTheStream() {
        let url = CameraStreamEndpoints.webRTCSocketURL(
            signedPath: "/api/webrtc/ws?authSig=eyJ.a-b_c.d",
            streamId: "front_door",
            baseURL: base
        )
        #expect(url?.absoluteString == "wss://ha.example.com/api/webrtc/ws?authSig=eyJ.a-b_c.d&url=front_door")
    }

    @Test func webRTCSocketUsesWsForHttpAndEscapesTheStream() {
        let url = CameraStreamEndpoints.webRTCSocketURL(
            signedPath: "/api/webrtc/ws?authSig=x",
            streamId: "rtsp://cam/a&b",
            baseURL: URL(string: "http://192.168.1.2:8123")!
        )
        #expect(url?.scheme == "ws")
        #expect(url?.absoluteString.hasSuffix("&url=rtsp://cam/a%26b") == true)
    }

    @Test func webRTCSocketRejectsOtherSchemes() {
        #expect(CameraStreamEndpoints.webRTCSocketURL(signedPath: "/x", streamId: "a", baseURL: URL(string: "ftp://h")!) == nil)
    }
}

struct WebRTCSignalTests {
    @Test func roundTripsEveryMessage() {
        for signal in [WebRTCSignal.offer("v=0\r\n"), .answer("v=0"), .candidate("candidate:1 1 udp 1 1.2.3.4 5 typ host"), .error("no stream")] {
            #expect(WebRTCSignal(text: signal.encoded()) == signal)
        }
    }

    @Test func encodesTheGo2rtcShape() throws {
        let json = try #require(JSONSerialization.jsonObject(with: Data(WebRTCSignal.offer("sdp").encoded().utf8)) as? [String: String])
        #expect(json == ["type": "webrtc/offer", "value": "sdp"])
    }

    @Test func ignoresUnknownAndMalformedMessages() {
        #expect(WebRTCSignal(text: #"{"type":"mse","value":"avc1"}"#) == nil)
        #expect(WebRTCSignal(text: "not json") == nil)
        #expect(WebRTCSignal(text: #"{"value":"x"}"#) == nil)
    }

    @Test func missingValueDecodesEmpty() {
        #expect(WebRTCSignal(text: #"{"type":"webrtc/candidate"}"#) == .candidate(""))
    }
}
