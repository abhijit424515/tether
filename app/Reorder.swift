// Pure priority-list reordering. Kept separate from the UI so it can be tested without launching the app.

enum Reorder {
    /// Move the item at `from` so it ends up at index `to`. Out-of-range or no-op moves return the
    /// list untouched, so callers can hand over raw gesture math without pre-checking it.
    static func moved(_ list: [String], from: Int, to: Int) -> [String] {
        guard list.indices.contains(from), list.indices.contains(to), from != to else { return list }
        var list = list
        list.insert(list.remove(at: from), at: to)
        return list
    }

    /// Where a row dragged by `offset` points, in whole row heights, clamped to the list.
    static func target(from: Int, offset: Double, rowHeight: Double, count: Int) -> Int {
        guard count > 0, rowHeight > 0 else { return from }
        let moved = from + Int((offset / rowHeight).rounded())
        return min(max(moved, 0), count - 1)
    }
}
