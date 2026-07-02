import Foundation

enum RouterDecisionStoreError: Error {
    case routeNotFound
    case approvalExpired
    case approvalReplayed
    case approvalMismatch
}

final class RouterDecisionStore: ObservableObject {
    @Published private(set) var records: [RouterDecisionRecord] = []

    private let queue = DispatchQueue(label: "dooyou.router.store")
    private let fileURL: URL
    private var apiTokenHash: String?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? appSupportDirectoryURL().appendingPathComponent("router-decisions.json")
        load()
    }

    func setAPITokenHash(_ hash: String?) {
        queue.sync {
            apiTokenHash = hash
            saveLocked()
        }
    }

    func list() -> [RouterDecisionRecord] {
        queue.sync { records.sorted { $0.updatedAtUTC > $1.updatedAtUTC } }
    }

    func get(routeId: String) -> RouterDecisionRecord? {
        queue.sync { records.first { $0.routeId == routeId } }
    }

    @discardableResult
    func upsert(decision: RouterDecision) -> RouterDecisionRecord {
        let safe = decision.safeRecord()
        queue.sync {
            if let idx = records.firstIndex(where: { $0.routeId == safe.routeId }) {
                records[idx] = safe
            } else {
                records.append(safe)
            }
            saveLocked()
        }
        return safe
    }

    @discardableResult
    func recordApproval(_ response: ApprovalResponse) throws -> RouterDecisionRecord {
        try queue.sync {
            guard let idx = records.firstIndex(where: { $0.routeId == response.routeId }) else {
                throw RouterDecisionStoreError.routeNotFound
            }
            try validate(response, against: records[idx])
            records[idx].approvalStatus = response.decision
            records[idx].approvalDecidedAtUTC = response.decidedAtUTC
            records[idx].tokenIdHash = response.tokenIdHash ?? records[idx].tokenIdHash
            records[idx].lastApprovalResponseHash = response.responseHash
            records[idx].lastApprovalDecision = response.decision
            records[idx].lastApprovalSourceSurface = response.sourceSurface
            records[idx].dispatchAllowed = false
            records[idx].updatedAtUTC = response.decidedAtUTC
            saveLocked()
            return records[idx]
        }
    }

    private func validate(_ response: ApprovalResponse, against record: RouterDecisionRecord) throws {
        guard record.approvalRequired, record.approvalStatus == "pending" else {
            throw RouterDecisionStoreError.approvalMismatch
        }
        guard response.decision == "approve" || response.decision == "reject" else {
            throw RouterDecisionStoreError.approvalMismatch
        }
        guard response.oneTime.consumed == false else {
            throw RouterDecisionStoreError.approvalReplayed
        }
        guard !response.responseId.isEmpty, !response.oneTime.nonce.isEmpty, !response.responseHash.isEmpty else {
            throw RouterDecisionStoreError.approvalMismatch
        }
        guard let expires = response.expiresAtUTC,
              let expiryDate = ISO8601DateFormatter().date(from: expires) else {
            throw RouterDecisionStoreError.approvalMismatch
        }
        if expiryDate < Date() {
            throw RouterDecisionStoreError.approvalExpired
        }
        guard let recordPolicyVersion = record.policyVersion,
              let responsePolicyVersion = response.policyVersion,
              responsePolicyVersion == recordPolicyVersion,
              let recordDomainRegistryHash = record.domainRegistryHash,
              let responseDomainRegistryHash = response.domainRegistryHash,
              responseDomainRegistryHash == recordDomainRegistryHash else {
            throw RouterDecisionStoreError.approvalMismatch
        }
        guard response.eventId == record.eventId,
              response.tokenIdHash == record.tokenIdHash,
              response.originalDecisionHash == record.decisionHash,
              response.normalizedCommandHash == record.normalizedCommandHash,
              response.actor.kind == "owner",
              routerSHA256Hex(response.actor.id) == routerSHA256Hex(routerOwnerID),
              response.sourceSurface == "dooyou_api" else {
            throw RouterDecisionStoreError.approvalMismatch
        }
    }

    func ingestEventData(_ data: Data) throws -> RouterDecisionRecord {
        let decoder = JSONDecoder()
        let decision = try decoder.decode(RouterDecision.self, from: data)
        return upsert(decision: decision)
    }

    func ingestApprovalData(_ data: Data) throws -> RouterDecisionRecord {
        let decoder = JSONDecoder()
        let response = try decoder.decode(ApprovalResponse.self, from: data)
        return try recordApproval(response)
    }

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let cache = try? JSONDecoder().decode(RouterCacheFile.self, from: data) else { return }
            apiTokenHash = cache.apiTokenHash
            records = cache.records
        }
    }

    private func saveLocked() {
        let cache = RouterCacheFile(
            schemaVersion: 1,
            updatedAtUTC: ISO8601DateFormatter().string(from: Date()),
            apiTokenHash: apiTokenHash,
            records: records
        )
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Store failures must not crash the menu-bar app or leak route payloads.
        }
    }
}

func routerSelfTestStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("dooyou-router-selftest-")
        .appendingPathExtension(UUID().uuidString)
        .appendingPathComponent("router-decisions.json")
}
