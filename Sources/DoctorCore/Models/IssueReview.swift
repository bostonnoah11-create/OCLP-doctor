import Foundation

public enum FindingKind: String, Codable, Sendable {
    case recordedProblem = "Recorded problem"
    case compatibilityReview = "Compatibility review"
    case evidenceGap = "Evidence gap"
}

public enum FindingPriority: String, Codable, Sendable {
    case high = "High", medium = "Medium", low = "Low"
}

public struct IssueSource: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
}

public struct IssueFinding: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let nextSteps: [String]
    public let kind: FindingKind
    public let priority: FindingPriority
    public let sources: [IssueSource]
    public let evidence: [Evidence]
    public let relatedPage: String
}

public struct KnownIssue: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let upstreamStatus: String
    public let summary: String
    public let scope: String
    public let reviewedOn: String
    public let nextSteps: [String]
    public let sources: [IssueSource]
}

public struct IssueReview: Codable, Equatable, Sendable {
    public let reviewedOn: String
    public let findings: [IssueFinding]
    public let catalog: [KnownIssue]
}

extension SystemInfo {
    /// Local evaluation against a dated, bundled catalog. No network requests or recovery actions.
    public var issueReview: IssueReview { IssueReviewEngine.review(self) }
}
