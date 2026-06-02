import Foundation

/// Stable identity for a node in an ``ExcelModel`` graph.
///
/// Identity is UUID-based and decoupled from cell positions.
/// Cell references are assigned at export time by a layout strategy.
public struct NodeRef: Hashable, Sendable {

    /// Human-readable label for this node.
    public let label: String

    private let id: UUID

    /// Creates a new node reference with the given label.
    ///
    /// Each call produces a unique identity, even for identical labels.
    ///
    /// - Parameter label: A human-readable name for the node.
    public init(label: String) {
        self.label = label
        self.id = UUID()
    }

    /// Returns whether two node references share the same identity.
    public static func == (lhs: NodeRef, rhs: NodeRef) -> Bool {
        lhs.id == rhs.id
    }

    /// Hashes the node's unique identity into the given hasher.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
