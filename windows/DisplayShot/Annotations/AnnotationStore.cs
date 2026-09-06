namespace DisplayShot.Annotations;

/// <summary>Ordered annotation list with sequential undo/redo.</summary>
public sealed class AnnotationStore
{
    private readonly List<Annotation> _items = new();
    private readonly Stack<Annotation> _redo = new();

    public IReadOnlyList<Annotation> Items => _items;
    public bool CanUndo => _items.Count > 0;
    public bool CanRedo => _redo.Count > 0;
    public bool IsEmpty => _items.Count == 0;

    public void Add(Annotation annotation)
    {
        _items.Add(annotation);
        _redo.Clear();
    }

    public bool Undo()
    {
        if (_items.Count == 0) return false;
        var last = _items[^1];
        _items.RemoveAt(_items.Count - 1);
        _redo.Push(last);
        return true;
    }

    public bool Redo()
    {
        if (_redo.Count == 0) return false;
        _items.Add(_redo.Pop());
        return true;
    }

    public Annotation? Item(Guid id) => _items.FirstOrDefault(a => a.Id == id);

    /// <summary>Replaces an existing annotation in place (move/resize/rotate an emoji).</summary>
    public void Replace(Guid id, Annotation annotation)
    {
        var i = _items.FindIndex(a => a.Id == id);
        if (i >= 0) _items[i] = annotation;
    }

    public void Clear()
    {
        _items.Clear();
        _redo.Clear();
    }
}
