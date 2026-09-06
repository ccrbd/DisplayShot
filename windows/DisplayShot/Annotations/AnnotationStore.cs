namespace DisplayShot.Annotations;

/// <summary>Ordered annotation list with sequential undo/redo of additions and removals.
/// Removals between BeginGroup/EndGroup (one eraser stroke) undo together.</summary>
public sealed class AnnotationStore
{
    private abstract record Change;
    private sealed record AddChange(Annotation Annotation) : Change;
    /// <summary>Removed annotations with the index each had when removed, in removal order.</summary>
    private sealed record RemoveChange(IReadOnlyList<(int Index, Annotation Annotation)> Removed) : Change;

    private readonly List<Annotation> _items = new();
    private readonly Stack<Change> _undo = new();
    private readonly Stack<Change> _redo = new();
    private List<(int Index, Annotation Annotation)>? _group;

    public IReadOnlyList<Annotation> Items => _items;
    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;
    public bool IsEmpty => _items.Count == 0;

    public void Add(Annotation annotation)
    {
        _items.Add(annotation);
        _undo.Push(new AddChange(annotation));
        _redo.Clear();
    }

    public Annotation? Item(Guid id) => _items.FirstOrDefault(a => a.Id == id);

    /// <summary>Replaces an annotation in place (move/resize/rotate an emoji). Not a separate undo step.</summary>
    public void Replace(Guid id, Annotation annotation)
    {
        var i = _items.FindIndex(a => a.Id == id);
        if (i >= 0) _items[i] = annotation;
    }

    public void BeginGroup() => _group = new List<(int, Annotation)>();

    public void EndGroup()
    {
        if (_group is { Count: > 0 } g)
        {
            _undo.Push(new RemoveChange(g.ToList()));
            _redo.Clear();
        }
        _group = null;
    }

    /// <summary>Removes one annotation; undoable alone or as part of the open group.</summary>
    public void Remove(Guid id)
    {
        var i = _items.FindIndex(a => a.Id == id);
        if (i < 0) return;
        var removed = _items[i];
        _items.RemoveAt(i);
        if (_group is not null) _group.Add((i, removed));
        else { _undo.Push(new RemoveChange(new[] { (i, removed) })); _redo.Clear(); }
    }

    public bool Undo()
    {
        if (_undo.Count == 0) return false;
        var change = _undo.Pop();
        switch (change)
        {
            case AddChange add: _items.RemoveAll(a => a.Id == add.Annotation.Id); break;
            case RemoveChange rm:
                // Reinsert in reverse removal order so every recorded index is valid again.
                foreach (var (index, annotation) in Enumerable.Reverse(rm.Removed)) _items.Insert(Math.Min(index, _items.Count), annotation);
                break;
        }
        _redo.Push(change);
        return true;
    }

    public bool Redo()
    {
        if (_redo.Count == 0) return false;
        var change = _redo.Pop();
        switch (change)
        {
            case AddChange add: _items.Add(add.Annotation); break;
            case RemoveChange rm:
                var ids = rm.Removed.Select(e => e.Annotation.Id).ToHashSet();
                _items.RemoveAll(a => ids.Contains(a.Id));
                break;
        }
        _undo.Push(change);
        return true;
    }

    public void Clear()
    {
        _items.Clear();
        _undo.Clear();
        _redo.Clear();
        _group = null;
    }
}
