import XCTest
@testable import Tailly

final class TaillyTests: XCTestCase {
    func testJSONValueEncodes() throws { XCTAssertEqual(String(data: try JSONEncoder().encode(JSONValue.object(["id": .int(42)])), encoding: .utf8), "{\"id\":42}") }
}
