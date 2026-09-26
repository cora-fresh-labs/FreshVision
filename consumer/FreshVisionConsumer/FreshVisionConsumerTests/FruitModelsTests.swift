import XCTest

@testable import FreshVisionConsumer

final class FruitModelsTests: XCTestCase {
  func testSupportedFruitsRemainTheConsumerFive() {
    XCTAssertEqual(
      Set(FruitKind.allCases.map(\.rawValue)),
      ["apple", "avocado", "banana", "grapes", "strawberries"])
  }

  func testVerdictStringsAreTheProductContract() {
    XCTAssertEqual(
      FruitVerdict.allCases.map(\.rawValue),
      [
        "Buy — ready now",
        "Buy — ripe in 2–3 days",
        "Skip — overripe",
        "Skip — underripe",
        "Skip — damaged",
      ])
  }

  func testOnlyBuyVerdictsAreMarkedBuy() {
    XCTAssertTrue(FruitVerdict.readyNow.isBuy)
    XCTAssertTrue(FruitVerdict.ripeSoon.isBuy)
    XCTAssertFalse(FruitVerdict.overripe.isBuy)
    XCTAssertFalse(FruitVerdict.underripe.isBuy)
    XCTAssertFalse(FruitVerdict.damaged.isBuy)
  }

  func testFailureMessagesArePlainEnglish() {
    let cases: [(AnalysisIssue, String)] = [
      (.noFruit, "I can’t see one piece of fruit. Try moving closer."),
      (.multipleFruits, "Show me one piece of fruit at a time."),
      (.poorLighting, "It’s too dark to judge. Move into better light."),
      (.unsupportedFruit, "I only know 5 fruits so far."),
    ]
    for (issue, expected) in cases {
      let response = FruitAnalysisResponse(
        supported: false, fruit: nil, verdict: nil, reason: expected, issue: issue, confidence: 0)
      XCTAssertEqual(response.shopperMessage, expected)
    }
  }
}
