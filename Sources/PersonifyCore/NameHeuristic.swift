import Foundation

public struct NameMatch: Equatable, Sendable, Codable {
    public var matchedTerms: [String]

    public init(matchedTerms: [String]) {
        self.matchedTerms = matchedTerms
    }

    public var isLikelyRoomDevice: Bool { !matchedTerms.isEmpty }
}

/// Name hints drawn from published product names.
/// A room whose advertised name is only the controller's room name, such as "Lounge", will not match.
public enum RoomNameHeuristic {
    public static let terms: [String] = [
        "unitouch",
        "allure",
        "personify",
        "distech",
        "eclypse",
        "ecy-stat",
        "ecystat",
        "nlight",
        "multi-sensor",
        "multisensor",
        "resense",
        "uniwave",
    ]

    public static func match(_ name: String?) -> NameMatch {
        guard let name, !name.isEmpty else {
            return NameMatch(matchedTerms: [])
        }
        let folded = name.lowercased()
        return NameMatch(matchedTerms: terms.filter { folded.contains($0) })
    }
}
