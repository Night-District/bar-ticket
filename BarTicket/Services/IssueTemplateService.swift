import Foundation
import SwiftData

enum IssueTemplateService {

    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<IssueTemplate>())) ?? 0
        guard count == 0 else { return }
        for template in BuiltInTemplates.allCases {
            context.insert(template.toModel())
        }
        try? context.save()
        print("[BarTicket] Seeded \(BuiltInTemplates.allCases.count) built-in issue templates")
    }

    static func fetchAll(context: ModelContext) -> [IssueTemplate] {
        (try? context.fetch(FetchDescriptor<IssueTemplate>())) ?? []
    }
}
