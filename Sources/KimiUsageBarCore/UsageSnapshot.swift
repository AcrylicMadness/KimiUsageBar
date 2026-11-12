import Foundation

public enum QuotaWindowKind: String, CaseIterable, Sendable {
    case fiveHour
    case weekly
    case monthly

    public var title: String {
        switch self {
        case .fiveHour: "5-hour limit"
        case .weekly: "Weekly limit"
        case .monthly: "Monthly limit"
        }
    }
}

public struct QuotaWindow: Equatable, Sendable {
    public let kind: QuotaWindowKind
    public let usedRatio: Double
    public let resetsAt: Date?

    public init(kind: QuotaWindowKind, usedRatio: Double, resetsAt: Date?) {
        self.kind = kind
        self.usedRatio = usedRatio
        self.resetsAt = resetsAt
    }

    public var clampedRatio: Double {
        guard usedRatio.isFinite else { return 0 }
        return min(1, max(0, usedRatio))
    }

    public var percentUsed: Int {
        Int((clampedRatio * 100).rounded())
    }

    public var remainingRatio: Double { 1 - clampedRatio }
}

public struct ExtraUsage: Equatable, Sendable {
    public let balanceCents: Int
    public let totalCents: Int
    public let monthlyChargeLimitEnabled: Bool
    public let monthlyChargeLimitCents: Int
    public let monthlyUsedCents: Int
    public let currency: String

    public init(
        balanceCents: Int,
        totalCents: Int,
        monthlyChargeLimitEnabled: Bool,
        monthlyChargeLimitCents: Int,
        monthlyUsedCents: Int,
        currency: String
    ) {
        self.balanceCents = balanceCents
        self.totalCents = totalCents
        self.monthlyChargeLimitEnabled = monthlyChargeLimitEnabled
        self.monthlyChargeLimitCents = monthlyChargeLimitCents
        self.monthlyUsedCents = monthlyUsedCents
        self.currency = currency
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let windows: [QuotaWindow]
    public let monthlyCodeRatio: Double?
    public let extraUsage: ExtraUsage?

    public init(
        windows: [QuotaWindow],
        monthlyCodeRatio: Double?,
        extraUsage: ExtraUsage?
    ) {
        self.windows = windows
        self.monthlyCodeRatio = monthlyCodeRatio
        self.extraUsage = extraUsage
    }

    public var primaryWindow: QuotaWindow? {
        windows.first { $0.kind == .fiveHour } ?? windows.first
    }
}

public enum UsagePayloadDecoder {
    public static func decode(_ data: Data) throws -> UsageSnapshot {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let windows = [
            window(kind: .fiveHour, entry: payload.usages?.limit5h),
            window(kind: .weekly, entry: payload.usages?.limit7d),
            window(kind: .monthly, entry: payload.usages?.limitMonthTotal)
        ].compactMap { $0 }

        return UsageSnapshot(
            windows: windows,
            monthlyCodeRatio: payload.usages?.limitMonthCode?.usedRatio.value,
            extraUsage: extraUsage(payload.boosterWallet)
        )
    }

    private static func window(kind: QuotaWindowKind, entry: QuotaEntry?) -> QuotaWindow? {
        guard let entry else { return nil }
        return QuotaWindow(
            kind: kind,
            usedRatio: entry.usedRatio.value,
            resetsAt: entry.resetTime.flatMap(parseDate)
        )
    }

    private static func extraUsage(_ wallet: BoosterWallet?) -> ExtraUsage? {
        guard let wallet,
              wallet.balance?.type == "BOOSTER",
              let amount = wallet.balance?.amount?.integerValue,
              amount > 0 else { return nil }

        let money = wallet.monthlyChargeLimit ?? wallet.monthlyUsed
        return ExtraUsage(
            balanceCents: fixedPointCents(wallet.balance?.amountLeft?.integerValue ?? 0),
            totalCents: fixedPointCents(amount),
            monthlyChargeLimitEnabled: wallet.monthlyChargeLimitEnabled ?? false,
            monthlyChargeLimitCents: wallet.monthlyChargeLimit?.priceInCents.integerValue ?? 0,
            monthlyUsedCents: wallet.monthlyUsed?.priceInCents.integerValue ?? 0,
            currency: money?.currency ?? "USD"
        )
    }

    private static func fixedPointCents(_ value: Int) -> Int {
        let cents = Double(value) / 1_000_000
        if cents > 0 && cents < 1 { return 1 }
        return Int(cents.rounded())
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct Payload: Decodable {
    let usages: Usages?
    let boosterWallet: BoosterWallet?
}

private struct Usages: Decodable {
    let limit5h: QuotaEntry?
    let limit7d: QuotaEntry?
    let limitMonthTotal: QuotaEntry?
    let limitMonthCode: QuotaEntry?

    enum CodingKeys: String, CodingKey {
        case limit5h = "limit_5h"
        case limit7d = "limit_7d"
        case limitMonthTotal = "limit_month_total"
        case limitMonthCode = "limit_month_code"
    }
}

private struct QuotaEntry: Decodable {
    let usedRatio: FlexibleNumber
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case usedRatio = "used_ratio"
        case resetTime = "reset_time"
    }
}

private struct BoosterWallet: Decodable {
    let balance: Balance?
    let monthlyChargeLimitEnabled: Bool?
    let monthlyChargeLimit: Money?
    let monthlyUsed: Money?
}

private struct Balance: Decodable {
    let type: String?
    let amount: FlexibleNumber?
    let amountLeft: FlexibleNumber?
}

private struct Money: Decodable {
    let priceInCents: FlexibleNumber
    let currency: String?
}

private struct FlexibleNumber: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = Double(try container.decode(String.self)) {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a number")
        }
    }

    var integerValue: Int? {
        guard value.isFinite else { return nil }
        return Int(value.rounded(.towardZero))
    }
}

public enum NotificationThresholds {
    public static let values = [25, 50, 75, 90]

    public static func crossed(from oldRatio: Double?, to newRatio: Double) -> [Int] {
        let oldPercentage = Int((max(0, oldRatio ?? 0) * 100).rounded(.down))
        let newPercentage = Int((max(0, newRatio) * 100).rounded(.down))
        return values.filter { $0 > oldPercentage && $0 <= newPercentage }
    }
}
