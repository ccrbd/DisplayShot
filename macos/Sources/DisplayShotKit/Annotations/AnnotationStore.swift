import Foundation

/// Ordered annotation list with sequential undo/redo of additions and removals.
/// Removals made between `beginGroup()` and `endGroup()` (one eraser stroke) undo together.
final class AnnotationStore {
    enum Change {
        case add(Annotation)
        /// Removed annotations with the index each had at the moment it was removed, in removal order.
        case remove([(index: Int, annotation: Annotation)])
    }

    private(set) var items: [Annotation] = []
    private var undoStack: [Change] = []
    private var redoStack: [Change] = []
    private var openGroup: [(index: Int, annotation: Annotation)]?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { items.isEmpty }

    func add(_ annotation: Annotation) {
        items.append(annotation)
        undoStack.append(.add(annotation))
        redoStack.removeAll()
    }

    func item(id: UUID) -> Annotation? { items.first { $0.id == id } }

    /// Replaces an annotation in place (move/resize/rotate an emoji). Not a separate undo step.
    func replace(id: UUID, with annotation: Annotation) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i] = annotation
    }

    func beginGroup() { openGroup = [] }

    func endGroup() {
        if let group = openGroup, !group.isEmpty {
            undoStack.append(.remove(group))
            redoStack.removeAll()
        }
        openGroup = nil
    }

    /// Removes one annotation; undoable on its own, or as part of the open group.
    func remove(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: i)
        if openGroup != nil {
            openGroup!.append((i, removed))
        } else {
            undoStack.append(.remove([(i, removed)]))
            redoStack.removeAll()
        }
    }

    @discardableResult
    func undo() -> Bool {
        guard let change = undoStack.popLast() else { return false }
        switch change {
        case .add(let a):
            items.removeAll { $0.id == a.id }
        case .remove(let removed):
            // Reinsert in reverse removal order so every recorded index is valid again.
            for entry in removed.reversed() { items.insert(entry.annotation, at: min(entry.index, items.count)) }
        }
        redoStack.append(change)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let change = redoStack.popLast() else { return false }
        switch change {
        case .add(let a):
            items.append(a)
        case .remove(let removed):
            let ids = Set(removed.map { $0.annotation.id })
            items.removeAll { ids.contains($0.id) }
        }
        undoStack.append(change)
        return true
    }

    func clear() {
        items.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        openGroup = nil
    }
}
