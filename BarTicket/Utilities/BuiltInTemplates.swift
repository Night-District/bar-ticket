import Foundation

enum BuiltInTemplates: CaseIterable {
    case feature
    case bug

    var templateName: String {
        switch self {
        case .feature: return "Feature"
        case .bug:     return "Bug"
        }
    }

    var templateDescription: String {
        switch self {
        case .feature: return "A new capability, enhancement, or user-facing improvement"
        case .bug:     return "An unexpected error, crash, or incorrect behavior"
        }
    }

    var body: String {
        switch self {
        case .feature:
            return """
                # Feature Name

                ## User Story
                **As a** [user]
                **I want** [goal]
                **So that** [benefit]

                ## Acceptance Criteria
                - [ ] ...

                ## Tasks
                - [ ] ...

                ## Dependencies (Optional)
                - [ ] ...
                """
        case .bug:
            return """
                # Fix Name

                ## Bug Description
                Describe the issue and its impact.

                ## Steps to Reproduce
                1. ...

                ## Expected Behavior
                Describe what should happen instead.

                ## Tasks
                - [ ] ...
                """
        }
    }

    func toModel() -> IssueTemplate {
        IssueTemplate(name: templateName, description: templateDescription, body: body, isBuiltIn: true)
    }
}
