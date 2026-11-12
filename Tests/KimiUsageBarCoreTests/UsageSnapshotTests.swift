import XCTest
@testable import KimiUsageBarCore

final class UsageSnapshotTests: XCTestCase {
    func testDecodesEveryQuotaWindowAndMonthlySplit() throws {
        let snapshot = try UsagePayloadDecoder.decode(Data("""
        {
          "usages": {
            "limit_5h": { "used_ratio": 0.42, "reset_time": "2026-11-12T20:00:00Z" },
            "limit_7d": { "used_ratio": "0.615", "reset_time": "2026-11-15T00:00:00.000Z" },
            "limit_month_total": { "used_ratio": 0.3 },
            "limit_month_code": { "used_ratio": 0.12 }
          },
          "boosterWallet": null
        }
        """.utf8))

        XCTAssertEqual(snapshot.windows.map(\.kind), [.fiveHour, .weekly, .monthly])
        XCTAssertEqual(snapshot.windows.map(\.percentUsed), [42, 62, 30])
        XCTAssertEqual(snapshot.monthlyCodeRatio, 0.12)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.extraUsage)
    }

    func testDecodesExtraUsageAndRoundsTinyBalancesUp() throws {
        let snapshot = try UsagePayloadDecoder.decode(Data("""
        {
          "usages": {},
          "boosterWallet": {
            "balance": {
              "type": "BOOSTER",
              "amount": 2500000000,
              "amountLeft": 500000
            },
            "monthlyChargeLimitEnabled": true,
            "monthlyChargeLimit": { "priceInCents": 10000, "currency": "CNY" },
            "monthlyUsed": { "priceInCents": "1250", "currency": "CNY" }
          }
        }
        """.utf8))

        XCTAssertEqual(snapshot.extraUsage, ExtraUsage(
            balanceCents: 1,
            totalCents: 2500,
            monthlyChargeLimitEnabled: true,
            monthlyChargeLimitCents: 10000,
            monthlyUsedCents: 1250,
            currency: "CNY"
        ))
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testIgnoresMissingAndDisabledWalletData() throws {
        let snapshot = try UsagePayloadDecoder.decode(Data("""
        {
          "usages": { "limit_5h": { "used_ratio": 0.05 } },
          "boosterWallet": {
            "balance": { "type": "BOOSTER", "amount": 0, "amountLeft": 0 }
          }
        }
        """.utf8))

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertNil(snapshot.extraUsage)
    }

    func testClampsInvalidRatiosForDisplay() {
        let window = QuotaWindow(kind: .fiveHour, usedRatio: 1.4, resetsAt: nil)
        XCTAssertEqual(window.percentUsed, 100)
        XCTAssertEqual(window.remainingRatio, 0)

        let negative = QuotaWindow(kind: .weekly, usedRatio: -0.2, resetsAt: nil)
        XCTAssertEqual(negative.percentUsed, 0)
        XCTAssertEqual(negative.remainingRatio, 1)
    }

    func testNotificationThresholdsOnlyCrossUpwardOnce() {
        XCTAssertEqual(NotificationThresholds.crossed(from: 0.24, to: 0.51), [25, 50])
        XCTAssertEqual(NotificationThresholds.crossed(from: 0.51, to: 0.52), [])
        XCTAssertEqual(NotificationThresholds.crossed(from: 0.90, to: 0.40), [])
        XCTAssertEqual(NotificationThresholds.crossed(from: nil, to: 0.91), [25, 50, 75, 90])
    }
}
