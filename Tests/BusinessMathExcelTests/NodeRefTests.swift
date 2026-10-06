import Foundation
import Testing
@testable import BusinessMathExcel

@Suite struct NodeRefTests {

    @Test func storesLabel() {
        let ref = NodeRef(label: "Revenue")
        #expect(ref.label == "Revenue")
    }

    @Test func sameInstanceIsEqual() {
        let ref = NodeRef(label: "Revenue")
        #expect(ref == ref)
    }

    @Test func differentInstancesAreNotEqual() {
        let a = NodeRef(label: "Revenue")
        let b = NodeRef(label: "Revenue")
        #expect(a != b)
    }

    @Test func hashableAsDictionaryKey() {
        let ref = NodeRef(label: "Rate")
        var dict: [NodeRef: Int] = [:]
        dict[ref] = 42
        #expect(dict[ref] == 42)
    }

    @Test func distinctRefsProduceDistinctHashes() {
        let a = NodeRef(label: "A")
        let b = NodeRef(label: "A")
        let set: Set<NodeRef> = [a, b]
        #expect(set.count == 2)
    }

    @Test func sendableConformance() async {
        let ref = NodeRef(label: "Test")
        // Crossing into a Task is what requires Sendable; the compiler is the
        // assertion. Reading the label back shows the value that crossed is the
        // one that was sent.
        let label = await Task { ref.label }.value
        #expect(label == "Test")
    }
}
