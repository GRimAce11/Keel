//
//  NetworkMonitor.swift
//  __PROJECT_NAME__
//

import Foundation
import Network
import Observation

/// Connectivity, observable from any view.
///
/// `isConnected` reflects the OS routing table — it says an interface is
/// available, not that the internet is reachable. A captive portal reports
/// satisfied. If the app needs certainty, add a lightweight reachability ping
/// on top and expose it as a second property.
@Observable
@MainActor
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var isExpensive: Bool = false
    private(set) var hasCompletedInitialCheck: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "__BUNDLE_ID__.network.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor calls back on its own queue; hop to the main actor
            // before touching observable state.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.hasCompletedInitialCheck = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
