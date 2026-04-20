import Foundation
import SwiftUI

/// In-memory snapshot of a GitHub Projects v2 board. Not persisted.
struct KanbanBoard: Equatable {
    let projectNodeId: String
    let projectTitle: String
    let projectURL: String
    let columns: [KanbanColumn]
    let fetchedAt: Date

    var totalOpenIssues: Int {
        columns.reduce(0) { $0 + $1.cards.count }
    }
}

struct KanbanColumn: Equatable, Identifiable {
    let id: String         // option id, or "__no_status__" for synthetic
    let name: String
    let color: Color
    let cards: [KanbanCard]
}

struct KanbanCard: Equatable, Identifiable {
    let id: String         // project item id
    let issueNumber: Int
    let title: String
    let body: String
    let issueURL: String
    let state: String      // OPEN | CLOSED
    let labels: [KanbanLabel]
}

struct KanbanLabel: Equatable {
    let name: String
    let color: Color
}

extension Color {
    /// Map a GitHub Projects v2 single-select option color enum to a SwiftUI Color.
    /// GitHub returns strings like "GREEN", "BLUE", "PURPLE", "RED", "ORANGE", "YELLOW", "PINK", "GRAY".
    init(githubOptionColor: String) {
        switch githubOptionColor.uppercased() {
        case "GREEN":  self = Color(red: 0.18, green: 0.75, blue: 0.47)
        case "BLUE":   self = Color(red: 0.26, green: 0.59, blue: 0.98)
        case "PURPLE": self = Color(red: 0.55, green: 0.37, blue: 0.96)
        case "RED":    self = Color(red: 0.95, green: 0.36, blue: 0.38)
        case "ORANGE": self = Color(red: 0.98, green: 0.60, blue: 0.20)
        case "YELLOW": self = Color(red: 0.98, green: 0.82, blue: 0.20)
        case "PINK":   self = Color(red: 0.96, green: 0.42, blue: 0.72)
        case "GRAY":   self = Color(red: 0.55, green: 0.57, blue: 0.62)
        default:       self = Color(red: 0.55, green: 0.57, blue: 0.62)
        }
    }

    /// Parse a 6-char hex string (as returned for GitHub issue labels, no '#').
    init(githubLabelHex: String) {
        var hex = githubLabelHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
