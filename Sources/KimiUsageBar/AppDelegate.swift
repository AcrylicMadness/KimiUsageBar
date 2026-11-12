import AppKit
import Combine
import SwiftUI
import KimiUsageBarCore

@main
enum KimiUsageBarApp {
    static func main() {
        if CommandLine.arguments.contains("--check") {
            Task {
                do {
                    let snapshot = try await UsageClient().fetchUsage(region: KimiEndpoint.preferredRegion)
                    for window in snapshot.windows {
                        print("\(window.kind.title): \(window.percentUsed)% used")
                    }
                    if snapshot.windows.isEmpty {
                        print("No quota windows returned")
                    }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.contentViewController = NSHostingController(rootView: UsagePopoverView(store: store))

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Kimi usage")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        cancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
        store.start()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
        updateStatusItem()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Task { await store.refresh() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if let primary = store.snapshot?.primaryWindow {
            button.title = " \(primary.percentUsed)%"
            let configuration = NSImage.SymbolConfiguration(paletteColors: [color(for: primary.clampedRatio)])
            button.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Kimi usage")?
                .withSymbolConfiguration(configuration)
            button.image?.isTemplate = false
        } else {
            button.title = store.isLoading ? " …" : " —"
            button.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Kimi usage")
            button.image?.isTemplate = true
        }
        button.contentTintColor = nil
    }

    private func color(for ratio: Double) -> NSColor {
        if ratio >= 0.9 { return .systemRed }
        if ratio >= 0.7 { return .systemOrange }
        return .systemGreen
    }
}
