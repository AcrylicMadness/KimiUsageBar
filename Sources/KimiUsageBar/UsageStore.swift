import Foundation
import ServiceManagement
import UserNotifications
import KimiUsageBarCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var region: KimiRegion {
        didSet {
            defaults.set(region.rawValue, forKey: "region")
            Task { await refresh() }
        }
    }
    @Published var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
            scheduleTimer()
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                defaults.set(launchAtLogin, forKey: "launchAtLogin")
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
                errorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
            }
        }
    }

    private let client: UsageClient
    private let defaults: UserDefaults
    private var timer: Timer?
    private var previousPrimaryRatio: Double?

    init(client: UsageClient = UsageClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        region = KimiRegion(rawValue: defaults.string(forKey: "region") ?? "") ?? KimiEndpoint.preferredRegion
        refreshInterval = defaults.object(forKey: "refreshInterval") == nil
            ? 300 : defaults.double(forKey: "refreshInterval")
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") == nil
            ? true : defaults.bool(forKey: "notificationsEnabled")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        scheduleTimer()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await client.fetchUsage(region: region)
            if let previousPrimaryRatio, notificationsEnabled,
               let primary = snapshot.primaryWindow {
                notifyIfNeeded(from: previousPrimaryRatio, to: primary)
            }
            previousPrimaryRatio = snapshot.primaryWindow?.usedRatio
            self.snapshot = snapshot
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    private func notifyIfNeeded(from oldRatio: Double, to window: QuotaWindow) {
        guard let threshold = NotificationThresholds.crossed(from: oldRatio, to: window.usedRatio).last else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Kimi Code usage: \(threshold)%"
        content.body = "Your \(window.kind.title.lowercased()) is \(threshold)% used."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "usage-\(window.kind.rawValue)-\(threshold)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
