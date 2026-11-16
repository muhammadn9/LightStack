import Foundation

/// The one exercise order for browsing and picking lists: A to Z, case-insensitive and locale-aware.
/// Lists inside a workout, the plan preview and history detail keep their plan/logged order instead.
enum ExerciseSort {

    /// True when `lhs` comes before `rhs` in the A to Z order.
    static func isInOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    /// `items` sorted A to Z by `name`. Names that compare equal keep their incoming order.
    static func azSorted<T>(_ items: [T], by name: (T) -> String) -> [T] {
        items.enumerated().sorted { lhs, rhs in
            let order = name(lhs.element).localizedCaseInsensitiveCompare(name(rhs.element))
            if order == .orderedSame { return lhs.offset < rhs.offset }
            return order == .orderedAscending
        }.map(\.element)
    }

    static func azSorted(_ names: [String]) -> [String] {
        azSorted(names, by: { $0 })
    }

    /// Section letter for a name: its first letter upper-cased, or "#" for digits and symbols.
    static func sectionLetter(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let letter = String(first).uppercased()
        return letter.first?.isLetter == true ? letter : "#"
    }
}
