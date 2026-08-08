// Self-check for Reorder. Run: ./app/test.sh
import Foundation

private func expect(_ desc: String, _ got: [String], _ want: [String]) {
    guard got == want else {
        print("FAIL: \(desc)\n  wanted \(want)\n  got    \(got)")
        exit(1)
    }
    print("ok: \(desc)")
}

private func expect(_ desc: String, _ got: Int, _ want: Int) {
    guard got == want else {
        print("FAIL: \(desc) — wanted \(want), got \(got)")
        exit(1)
    }
    print("ok: \(desc)")
}

@main
struct ReorderTests {
    static func main() {
        let list = ["A", "B", "C", "D"]

        expect("move down", Reorder.moved(list, from: 0, to: 2), ["B", "C", "A", "D"])
        expect("move up", Reorder.moved(list, from: 3, to: 1), ["A", "D", "B", "C"])
        expect("swap with the row below", Reorder.moved(list, from: 0, to: 1), ["B", "A", "C", "D"])
        expect("move to the top", Reorder.moved(list, from: 3, to: 0), ["D", "A", "B", "C"])
        expect("move to the bottom", Reorder.moved(list, from: 0, to: 3), ["B", "C", "D", "A"])
        expect("same index changes nothing", Reorder.moved(list, from: 1, to: 1), list)
        expect("out-of-range source changes nothing", Reorder.moved(list, from: 9, to: 1), list)
        expect("out-of-range destination changes nothing", Reorder.moved(list, from: 1, to: 9), list)
        expect("empty list survives", Reorder.moved([], from: 0, to: 1), [])

        // Gesture math: 30pt rows, so half a row of travel rounds to the next slot.
        expect("no travel stays put", Reorder.target(from: 1, offset: 0, rowHeight: 30, count: 4), 1)
        expect("under half a row stays put", Reorder.target(from: 1, offset: 14, rowHeight: 30, count: 4), 1)
        expect("over half a row moves one down", Reorder.target(from: 1, offset: 16, rowHeight: 30, count: 4), 2)
        expect("two rows up", Reorder.target(from: 3, offset: -60, rowHeight: 30, count: 4), 1)
        expect("dragged past the top clamps", Reorder.target(from: 1, offset: -900, rowHeight: 30, count: 4), 0)
        expect("dragged past the bottom clamps", Reorder.target(from: 1, offset: 900, rowHeight: 30, count: 4), 3)
        expect("empty list is a no-op", Reorder.target(from: 0, offset: 90, rowHeight: 30, count: 0), 0)

        print("all passed")
    }
}
