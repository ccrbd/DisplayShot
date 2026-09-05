import Foundation

/// Ordered annotation list with sequential undo/redo.
final class AnnotationStore {
    private(set) var items: [Annotation] = []
    private var redoStack: [Annotation] = []

    var canUndo: Bool { !items.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { items.isEmpty }

    func add(_ annotation: Annotation) {
        items.append(annotation)
        redoStack.removeAll()
    }

    @discardableResult
    func undo() -> Bool {
        guard let last = items.popLast() else { return false }
        redoStack.append(last)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        items.append(next)
        return true
    }

    func clear() {
        items.removeAll()
        redoStack.removeAll()
    }
}
