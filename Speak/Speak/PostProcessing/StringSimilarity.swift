import Foundation

enum StringSimilarity {
    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let rows = lhsChars.count
        let cols = rhsChars.count

        if rows == 0 { return cols }
        if cols == 0 { return rows }

        var previous = Array(0 ... cols)
        var current = [Int](repeating: 0, count: cols + 1)

        for row in 1 ... rows {
            current[0] = row
            for col in 1 ... cols {
                let cost = lhsChars[row - 1] == rhsChars[col - 1] ? 0 : 1
                current[col] = min(
                    previous[col] + 1,
                    current[col - 1] + 1,
                    previous[col - 1] + cost
                )
            }
            previous = current
        }

        return current[cols]
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsLower = lhs.lowercased()
        let rhsLower = rhs.lowercased()
        let maxLen = max(lhsLower.count, rhsLower.count)
        guard maxLen > 0 else { return 1.0 }
        let dist = levenshtein(lhsLower, rhsLower)
        return max(0.0, 1.0 - Double(dist) / Double(maxLen))
    }

    static func isSimilar(_ lhs: String, _ rhs: String, threshold: Double = 0.4) -> Bool {
        similarity(lhs, rhs) >= threshold
    }
}
