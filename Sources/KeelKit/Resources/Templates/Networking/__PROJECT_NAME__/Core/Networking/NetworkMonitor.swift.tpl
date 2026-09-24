//
//  NetworkMonitor.swift
//  __PROJECT_NAME__
//

import Foundation
import Network
import Observation

/// Connectivity, observable from any view.
///
/// Two signals, because neither is enough on its own:
///
/// - `isConnected` is the OS routing table, via `NWPathMonitor`. It reports an
///   interface appearing or disappearing immediately and costs nothing, but it
///   says a route exists — not that the internet is reachable. A captive
///   portal reports satisfied.
/// - `isReachable` is the answer to a real request to the API host, so it
///   catches the portal and the dead upstream that `isConnected` cannot. It
///   costs a request, so it runs only when the route changes, or when asked.
///
/// Use this to show a banner or gate a download. **Do not use it to decide
/// whether to send a request** — send it, and let `APIError` say what came
/// back. A pre-flight check is a second source of truth, already stale by the
/// time it is read, and it turns a VPN handoff into "no internet connection".
@Observable
@MainActor
final class NetworkMonitor {

    /// One per process: `NWPathMonitor` is a system subscription, and a second
    /// one costs a second of everything. It lives as long as the app, which is
    /// why nothing here pairs a `cancel()` with `start`.
    static let shared = NetworkMonitor()

    /// A route exists. Starts `true` so the first frame is not drawn as
    /// offline before `NWPathMonitor` has answered — `hasCompletedInitialCheck`
    /// says whether that is an answer yet or still the default.
    private(set) var isConnected: Bool = true

    /// The route is cellular, a hotspot, or otherwise metered. Gate anything
    /// large — a video, a prefetch, a background sync.
    private(set) var isExpensive: Bool = false

    /// The API host answered. `false` while `isConnected` is `true` is the
    /// captive portal: a route to the coffee shop, no route past it.
    private(set) var isReachable: Bool = true

    private(set) var hasCompletedInitialCheck: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "__BUNDLE_ID__.network.monitor")
    private let probeSession: URLSession
    private var isProbing = false

    private init() {
        // Ephemeral and tight: a probe still waiting after five seconds has
        // already failed to be useful, and a cached 200 would answer for a
        // network that has since gone.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        probeSession = URLSession(configuration: configuration)

        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            let isExpensive = path.isExpensive
            // NWPathMonitor calls back on its own queue; hop to the main actor
            // before touching observable state.
            Task { @MainActor [weak self] in
                self?.pathChanged(isConnected: isConnected, isExpensive: isExpensive)
            }
        }
        monitor.start(queue: queue)
    }

    /// Asks the API host whether it can actually be reached, and publishes the
    /// answer as `isReachable`.
    ///
    /// Called automatically whenever the route changes. Call it yourself when
    /// the app returns to the foreground, or behind a "Try again" button —
    /// those are the other two moments the answer can have gone stale.
    func check() async {
        // Concurrent calls collapse into the one already running: a foreground
        // and a route change land together more often than not.
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }

        guard isConnected else {
            publish(isReachable: false)
            return
        }

        let host = URLConstants.API.base
        var request = URLRequest(url: host)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await probeSession.data(for: request)
            // Any answer from the host that was asked proves traffic flows —
            // a 404 or a 405 to HEAD is still the server talking. A portal
            // answers too, but as itself, after a redirect URLSession has
            // already followed, so the host that replied is not the host that
            // was asked. (A transparent proxy answering in place is
            // indistinguishable from here; that needs an endpoint whose exact
            // response you know, such as one returning 204 and no body.)
            publish(isReachable: (response.url ?? host).host == host.host)
        } catch {
            publish(isReachable: false)
        }
    }

    private func pathChanged(isConnected: Bool, isExpensive: Bool) {
        let isFirstAnswer = !hasCompletedInitialCheck
        let didChange = self.isConnected != isConnected

        // @Observable publishes every assignment, not only every change, and
        // NWPathMonitor fires for interface changes that leave reachability
        // exactly as it was. Assigning unconditionally redraws every view
        // watching this, for nothing.
        if didChange { self.isConnected = isConnected }
        if self.isExpensive != isExpensive { self.isExpensive = isExpensive }
        if isFirstAnswer { hasCompletedInitialCheck = true }

        // A route just appeared or vanished. That, and the first answer of the
        // app's life, are the moments reachability is worth a request.
        guard isFirstAnswer || didChange else { return }
        Task { await check() }
    }

    private func publish(isReachable: Bool) {
        guard self.isReachable != isReachable else { return }
        self.isReachable = isReachable
    }
}
