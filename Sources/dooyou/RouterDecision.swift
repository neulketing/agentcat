import Foundation
import CryptoKit

func routerSHA256Hex(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

let routerOwnerID = "5747637837"

struct RouterActor: Codable {
    var kind: String
    var id: String
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case kind, id
        case displayName = "display_name"
    }
}

struct RouterNormalizedIntent: Codable {
    var kind: String
    var confidence: String?
    var normalizedCommandHash: String?

    enum CodingKeys: String, CodingKey {
        case kind, confidence
        case normalizedCommandHash = "normalized_command_hash"
    }
}

struct RouterApprovalInfo: Codable {
    var required: Bool
    var reasons: [String]
    var status: String
    var tokenIdHash: String?
    var requestedAtUTC: String?
    var expiresAtUTC: String?
    var decidedAtUTC: String?

    enum CodingKeys: String, CodingKey {
        case required, reasons, status
        case tokenIdHash = "token_id_hash"
        case requestedAtUTC = "requested_at_utc"
        case expiresAtUTC = "expires_at_utc"
        case decidedAtUTC = "decided_at_utc"
    }
}

struct RouterReadiness: Codable {
    var state: String
    var blockers: [String]
}

struct RouterDispatchSummary: Codable {
    var target: String
    var allowed: Bool
}

struct RouterVerificationSummary: Codable {
    var expectation: String
    var receiptRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case expectation
        case receiptRequired = "receipt_required"
    }
}

struct RouterWritebackSummary: Codable {
    var hermesPath: String?
    var receiptPath: String?
    var decisionNotePath: String?
    var secretPolicy: String?

    enum CodingKeys: String, CodingKey {
        case hermesPath = "hermes_path"
        case receiptPath = "receipt_path"
        case decisionNotePath = "decision_note_path"
        case secretPolicy = "secret_policy"
    }
}

struct RouterProjection: Codable {
    var title: String
    var subtitle: String
    var statusBadge: String
    var riskBadge: String
    var primaryAction: String
    var secondaryActions: [String]
    var routeCardKind: String
    var policyVersion: String? = nil
    var domainRegistryHash: String? = nil

    enum CodingKeys: String, CodingKey {
        case title, subtitle
        case statusBadge = "status_badge"
        case riskBadge = "risk_badge"
        case primaryAction = "primary_action"
        case secondaryActions = "secondary_actions"
        case routeCardKind = "route_card_kind"
        case policyVersion = "policy_version"
        case domainRegistryHash = "domain_registry_hash"
    }
}

struct RouterMissionDraft: Codable {
    var id: String?
    var acceptanceSummary: [String]?
    var forbiddenSummary: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case acceptanceSummary = "acceptance_summary"
        case forbiddenSummary = "forbidden_summary"
    }
}

struct RouterUserStatus: Codable {
    var state: String
    var message: String?
}

struct RouterFailure: Codable {
    var state: String
    var reason: String?
}

struct RouterDecision: Codable, Identifiable {
    var schemaVersion: Int
    var routeId: String
    var eventId: String
    var createdAtUTC: String
    var updatedAtUTC: String
    var decisionHash: String
    var policyVersion: String? = nil
    var domainRegistryHash: String? = nil
    var actor: RouterActor
    var sourceSurface: String
    var sourceRef: String?
    var normalizedIntent: RouterNormalizedIntent
    var lane: String
    var risk: String
    var priority: Int
    var boundaries: [String: String]
    var approval: RouterApprovalInfo
    var readiness: RouterReadiness
    var dispatch: RouterDispatchSummary
    var missionDraft: RouterMissionDraft?
    var verification: RouterVerificationSummary
    var writeback: RouterWritebackSummary
    var dooyouProjection: RouterProjection
    var userStatus: RouterUserStatus
    var failure: RouterFailure

    var id: String { routeId }

    enum CodingKeys: String, CodingKey {
        case lane, risk, priority, boundaries, approval, readiness, dispatch, verification, writeback, failure
        case schemaVersion = "schema_version"
        case routeId = "route_id"
        case eventId = "event_id"
        case createdAtUTC = "created_at_utc"
        case updatedAtUTC = "updated_at_utc"
        case decisionHash = "decision_hash"
        case policyVersion = "policy_version"
        case domainRegistryHash = "domain_registry_hash"
        case actor
        case sourceSurface = "source_surface"
        case sourceRef = "source_ref"
        case normalizedIntent = "normalized_intent"
        case missionDraft = "mission_draft"
        case dooyouProjection = "dooyou_projection"
        case userStatus = "user_status"
    }

    func safeRecord() -> RouterDecisionRecord {
        RouterDecisionRecord(
            routeId: routeId,
            eventId: eventId,
            createdAtUTC: createdAtUTC,
            updatedAtUTC: updatedAtUTC,
            decisionHash: decisionHash,
            policyVersion: policyVersion,
            domainRegistryHash: domainRegistryHash,
            sourceSurface: sourceSurface,
            actorKind: actor.kind,
            actorIdHash: routerSHA256Hex(actor.id),
            intentKind: normalizedIntent.kind,
            normalizedCommandHash: normalizedIntent.normalizedCommandHash,
            lane: lane,
            risk: risk,
            priority: priority,
            status: userStatus.state,
            statusMessage: userStatus.message,
            failureState: failure.state,
            failureReason: failure.reason,
            approvalRequired: approval.required,
            approvalStatus: approval.status,
            approvalReasons: approval.reasons,
            tokenIdHash: approval.tokenIdHash,
            approvalRequestedAtUTC: approval.requestedAtUTC,
            approvalExpiresAtUTC: approval.expiresAtUTC,
            approvalDecidedAtUTC: approval.decidedAtUTC,
            dispatchTarget: dispatch.target,
            dispatchAllowed: dispatch.allowed,
            readinessState: readiness.state,
            readinessBlockers: readiness.blockers,
            verificationExpectation: verification.expectation,
            receiptRequired: verification.receiptRequired,
            hermesPath: writeback.hermesPath,
            receiptPath: writeback.receiptPath,
            decisionNotePath: writeback.decisionNotePath,
            projection: dooyouProjection,
            lastApprovalResponseHash: nil,
            lastApprovalDecision: nil,
            lastApprovalSourceSurface: nil
        )
    }
}

struct ApprovalOneTime: Codable {
    var nonce: String
    var consumed: Bool
}

struct ApprovalResponse: Codable {
    var schemaVersion: Int
    var responseId: String
    var routeId: String
    var eventId: String
    var tokenContext: String?
    var tokenIdHash: String?
    var originalDecisionHash: String
    var normalizedCommandHash: String?
    var policyVersion: String? = nil
    var domainRegistryHash: String? = nil
    var actor: RouterActor
    var sourceSurface: String
    var issuedAtUTC: String?
    var expiresAtUTC: String?
    var decidedAtUTC: String
    var decision: String
    var oneTime: ApprovalOneTime
    var responseHash: String

    enum CodingKeys: String, CodingKey {
        case actor, decision
        case schemaVersion = "schema_version"
        case responseId = "response_id"
        case routeId = "route_id"
        case eventId = "event_id"
        case tokenContext = "token_context"
        case tokenIdHash = "token_id_hash"
        case originalDecisionHash = "original_decision_hash"
        case normalizedCommandHash = "normalized_command_hash"
        case policyVersion = "policy_version"
        case domainRegistryHash = "domain_registry_hash"
        case sourceSurface = "source_surface"
        case issuedAtUTC = "issued_at_utc"
        case expiresAtUTC = "expires_at_utc"
        case decidedAtUTC = "decided_at_utc"
        case oneTime = "one_time"
        case responseHash = "response_hash"
    }
}

struct RouterDecisionRecord: Codable, Identifiable {
    var id: String { routeId }
    var routeId: String
    var eventId: String
    var createdAtUTC: String
    var updatedAtUTC: String
    var decisionHash: String
    var policyVersion: String? = nil
    var domainRegistryHash: String? = nil
    var sourceSurface: String
    var actorKind: String
    var actorIdHash: String
    var intentKind: String
    var normalizedCommandHash: String?
    var lane: String
    var risk: String
    var priority: Int
    var status: String
    var statusMessage: String?
    var failureState: String
    var failureReason: String?
    var approvalRequired: Bool
    var approvalStatus: String
    var approvalReasons: [String]
    var tokenIdHash: String?
    var approvalRequestedAtUTC: String?
    var approvalExpiresAtUTC: String?
    var approvalDecidedAtUTC: String?
    var dispatchTarget: String
    var dispatchAllowed: Bool
    var readinessState: String
    var readinessBlockers: [String]
    var verificationExpectation: String
    var receiptRequired: Bool?
    var hermesPath: String?
    var receiptPath: String?
    var decisionNotePath: String?
    var projection: RouterProjection
    var lastApprovalResponseHash: String?
    var lastApprovalDecision: String?
    var lastApprovalSourceSurface: String?
}

struct RouterCacheFile: Codable {
    var schemaVersion: Int
    var updatedAtUTC: String
    var apiTokenHash: String?
    var records: [RouterDecisionRecord]
}
