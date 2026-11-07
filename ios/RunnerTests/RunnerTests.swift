import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  @MainActor
  func testCodefestGemmaFromPrivateContainer() async throws {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodefestAI")
    guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("receipt.json").path) else {
      throw XCTSkip("Optional real-model test requires the verified developer model in the private App container.")
    }
    let completed = expectation(description: "Native Gemma returns local text")
    let service = CodefestAI()
    service.handle(FlutterMethodCall(methodName: "generate", arguments: ["requestId": String(repeating: "a", count: 32), "prompt": "Say hello in one short sentence."])) { value in
      let reply = value as? [String: Any]
      XCTAssertEqual(reply?["status"] as? String, "success")
      XCTAssertFalse((reply?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 90)
  }

}
