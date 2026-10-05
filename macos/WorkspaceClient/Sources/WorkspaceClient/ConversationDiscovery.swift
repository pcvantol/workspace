import Foundation

enum ConversationModeFilter: String, CaseIterable {
    case all = "ALL"
    case business = "BUSINESS"
    case architecture = "ARCHITECTURE"
    case ux = "UX"
}

enum ConversationSortOrder: String, CaseIterable {
    case recentlyChanged = "RECENT"
    case title = "TITLE"
}

enum ConversationDiscovery {
    static func visible(_ conversations: [Conversation], search: String,
                        mode: ConversationModeFilter, sort: ConversationSortOrder) -> [Conversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = conversations.filter { conversation in
            (mode == .all || conversation.mode == mode.rawValue) &&
                (query.isEmpty || conversation.title.localizedCaseInsensitiveContains(query) ||
                 conversation.focus.localizedCaseInsensitiveContains(query))
        }
        return filtered.sorted { left, right in
            if sort == .title {
                let first = titleKey(left.title)
                let second = titleKey(right.title)
                if first != second { return first < second }
            } else {
                let first = timestamp(left.updated_at) ?? .distantPast
                let second = timestamp(right.updated_at) ?? .distantPast
                if first != second { return first > second }
            }
            return left.id < right.id
        }
    }

    private static func titleKey(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func timestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: value)
    }
}
