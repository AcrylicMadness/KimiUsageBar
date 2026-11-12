import SwiftUI
import AppKit
import KimiUsageBarCore

struct UsagePopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = store.errorMessage {
                        errorView(errorMessage)
                    }

                    if let snapshot = store.snapshot {
                        ForEach(snapshot.windows, id: \.kind) { window in
                            QuotaWindowView(window: window, monthlyCodeRatio: snapshot.monthlyCodeRatio)
                        }

                        if let extraUsage = snapshot.extraUsage {
                            ExtraUsageView(extraUsage: extraUsage)
                        }
                    } else if store.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking your usage…")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 36)
                    } else if store.errorMessage == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "moon.stars")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No usage yet")
                                .font(.headline)
                            Text("Refresh to load your Kimi Code limits.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .frame(minHeight: 280, maxHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kimi Usage")
                    .font(.headline)
                Text(store.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Kimi Code plan limits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("Refresh usage")
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            DisclosureGroup("Settings", isExpanded: $showSettings) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Region", selection: $store.region) {
                        ForEach(KimiRegion.allCases) { region in
                            Text(region.title).tag(region)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Auto-refresh", selection: $store.refreshInterval) {
                        Text("Every minute").tag(60.0)
                        Text("Every 5 minutes").tag(300.0)
                        Text("Every 15 minutes").tag(900.0)
                    }
                    .pickerStyle(.menu)

                    Toggle("Usage notifications", isOn: $store.notificationsEnabled)
                    Toggle("Launch at login", isOn: $store.launchAtLogin)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
            HStack {
                Button("Kimi Console") {
                    NSWorkspace.shared.open(store.region.consoleURL)
                }
                .buttonStyle(.link)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct QuotaWindowView: View {
    let window: QuotaWindow
    let monthlyCodeRatio: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(window.percentUsed)%")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }

            UsageProgressView(ratio: window.clampedRatio, color: color)

            HStack {
                Text("\(window.percentUsed)% used")
                Spacer()
                if let resetsAt = window.resetsAt {
                    Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                } else {
                    Text("\(Int(window.remainingRatio * 100))% left")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if window.kind == .monthly, let monthlyCodeRatio {
                let code = min(1, max(0, monthlyCodeRatio))
                let kimi = min(1, max(0, window.clampedRatio - code))
                HStack(spacing: 12) {
                    Label("\(Int(code * 100))% Kimi Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    Label("\(Int(kimi * 100))% Kimi", systemImage: "bubble.left")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var color: Color {
        if window.clampedRatio >= 0.9 { return .red }
        if window.clampedRatio >= 0.7 { return .orange }
        return .green
    }
}

private struct UsageProgressView: View {
    let ratio: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(5, geometry.size.width * ratio))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Usage")
        .accessibilityValue("\(Int(ratio * 100)) percent")
    }
}

private struct ExtraUsageView: View {
    let extraUsage: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Extra Usage", systemImage: "bolt.fill")
                .font(.subheadline.weight(.medium))
            HStack {
                Text("Balance")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(money(extraUsage.balanceCents))
                    .fontWeight(.medium)
            }
            if extraUsage.monthlyChargeLimitEnabled {
                HStack {
                    Text("Spent this month")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(money(extraUsage.monthlyUsedCents)) of \(money(extraUsage.monthlyChargeLimitCents))")
                }
            }
        }
        .font(.callout)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func money(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = extraUsage.currency
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents)¢"
    }
}
