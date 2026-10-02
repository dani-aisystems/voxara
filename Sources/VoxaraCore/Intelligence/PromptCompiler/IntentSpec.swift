import Foundation

/// The structured meaning of a spoken request, before any destination-specific wording.
/// Every list item is a short imperative or statement in the speaker's own terms.
public struct IntentSpec: Codable, Sendable, Equatable {
    public var objective: String
    public var taskType: String
    public var context: [String]
    public var references: [String]
    public var inputs: [String]
    public var research: [String]
    public var workflow: [String]
    public var requirements: [String]
    public var constraints: [String]
    public var exclusions: [String]
    public var deliverable: String
    public var validation: [String]
    public var done: [String]

    public init(objective: String = "", taskType: String = "other", context: [String] = [], references: [String] = [],
                inputs: [String] = [], research: [String] = [], workflow: [String] = [], requirements: [String] = [],
                constraints: [String] = [], exclusions: [String] = [], deliverable: String = "",
                validation: [String] = [], done: [String] = []) {
        self.objective = objective
        self.taskType = taskType
        self.context = context
        self.references = references
        self.inputs = inputs
        self.research = research
        self.workflow = workflow
        self.requirements = requirements
        self.constraints = constraints
        self.exclusions = exclusions
        self.deliverable = deliverable
        self.validation = validation
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) -> [String] { (try? c.decodeIfPresent([String].self, forKey: key)) ?? [] }
        self.init(
            objective: (try? c.decodeIfPresent(String.self, forKey: .objective)) ?? "",
            taskType: (try? c.decodeIfPresent(String.self, forKey: .taskType)) ?? "other",
            context: list(.context), references: list(.references), inputs: list(.inputs), research: list(.research),
            workflow: list(.workflow), requirements: list(.requirements), constraints: list(.constraints),
            exclusions: list(.exclusions), deliverable: (try? c.decodeIfPresent(String.self, forKey: .deliverable)) ?? "",
            validation: list(.validation), done: list(.done)
        )
    }

    /// Section name → items, in a uniform shape for the renderer and grounding checker.
    public subscript(section: String) -> [String] {
        get {
            switch section {
            case "context": context
            case "references": references
            case "inputs": inputs
            case "research": research
            case "workflow": workflow
            case "requirements": requirements
            case "constraints": constraints
            case "exclusions": exclusions
            case "deliverable": deliverable.isEmpty ? [] : [deliverable]
            case "validation": validation
            case "done": done
            default: []
            }
        }
        set {
            switch section {
            case "context": context = newValue
            case "references": references = newValue
            case "inputs": inputs = newValue
            case "research": research = newValue
            case "workflow": workflow = newValue
            case "requirements": requirements = newValue
            case "constraints": constraints = newValue
            case "exclusions": exclusions = newValue
            case "deliverable": deliverable = newValue.first ?? ""
            case "validation": validation = newValue
            case "done": done = newValue
            default: break
            }
        }
    }

    public static let sections = ["context", "references", "inputs", "research", "workflow", "requirements",
                                  "constraints", "exclusions", "deliverable", "validation", "done"]

    public static var jsonSchema: [String: JSONValue] {
        func list(_ description: String) -> JSONValue {
            ["type": "array", "items": ["type": "string"], "description": .string(description)]
        }
        return [
            "type": "object",
            "properties": [
                "objective": ["type": "string", "description": "One sentence: the main thing the speaker wants done."],
                "taskType": ["type": "string", "enum": ["coding", "debugging", "research", "writing", "business", "planning", "design", "analysis", "other"]],
                "context": list("Background facts the speaker gave."),
                "references": list("Existing things to look at or use as a model, with how they should be used."),
                "inputs": list("Material, files, projects or data the work applies to."),
                "research": list("Things to find out or look up."),
                "workflow": list("Order-of-work instructions the speaker gave (e.g. check first, then change)."),
                "requirements": list("What the result must do or include."),
                "constraints": list("Limits and rules the speaker set."),
                "exclusions": list("Things that must NOT be done or changed."),
                "deliverable": ["type": "string", "description": "The form of the expected output, only if stated."],
                "validation": list("How the speaker wants the result checked."),
                "done": list("Completion criteria the speaker stated."),
            ],
            "required": ["objective", "taskType"],
        ]
    }
}
