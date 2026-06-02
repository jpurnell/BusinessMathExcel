import XCTest
@testable import BusinessMathExcel

final class NodeRefTests: XCTestCase {

    func testStoresLabel() {
        let ref = NodeRef(label: "Revenue")
        XCTAssertEqual(ref.label, "Revenue")
    }

    func testSameInstanceIsEqual() {
        let ref = NodeRef(label: "Revenue")
        XCTAssertEqual(ref, ref)
    }

    func testDifferentInstancesAreNotEqual() {
        let a = NodeRef(label: "Revenue")
        let b = NodeRef(label: "Revenue")
        XCTAssertNotEqual(a, b)
    }

    func testHashableAsDictionaryKey() {
        let ref = NodeRef(label: "Rate")
        var dict: [NodeRef: Int] = [:]
        dict[ref] = 42
        XCTAssertEqual(dict[ref], 42)
    }

    func testDistinctRefsProduceDistinctHashes() {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "A")
        let set: Set<NodeRef> = [a, b]
        XCTAssertEqual(set.count, 2)
    }

    func testSendableConformance() {
        let ref = NodeRef(label: "Test")
        let expectation = expectation(description: "sendable")
        Task {
            _ = ref.label
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}
