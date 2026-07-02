import Foundation
import Network

struct RouterHTTPResponse: Codable {
    var ok: Bool
    var status: String
    var message: String?
    var dispatchAllowed: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, status, message
        case dispatchAllowed = "dispatch_allowed"
    }
}

struct RouterHealthResponse: Codable {
    var ok: Bool
    var version: Int
    var app: String
    var status: String
    var authRequired: Bool
    var authConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case ok, version, app, status
        case authRequired = "auth_required"
        case authConfigured = "auth_configured"
    }
}

final class RouterAPI {
    private let store: RouterDecisionStore
    private let tokenHash: String?
    private let queue = DispatchQueue(label: "dooyou.router.api")
    private var listener: NWListener?
    private let port: UInt16

    init(store: RouterDecisionStore, token: String? = ProcessInfo.processInfo.environment["DOOYOU_ROUTER_API_TOKEN"], port: UInt16? = nil) {
        self.store = store
        let cleanToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tokenHash = cleanToken?.isEmpty == false ? routerSHA256Hex(cleanToken!) : nil
        self.port = port ?? UInt16(ProcessInfo.processInfo.environment["DOOYOU_ROUTER_API_PORT"] ?? "17681") ?? 17681
        self.store.setAPITokenHash(self.tokenHash)
    }

    func start() {
        do {
            let params = NWParameters.tcp
            let endpointPort = NWEndpoint.Port(rawValue: port)!
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: endpointPort)
            let listener = try NWListener(using: params, on: endpointPort)
            listener.service = nil
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            self.listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        guard case let NWEndpoint.hostPort(host, _) = connection.endpoint,
              isLoopback(host) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let response = self.route(data ?? Data())
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    func testResponse(for data: Data) -> Data {
        route(data)
    }

    @discardableResult
    // Trusted in-app approval controls share the same store validation/no-dispatch path as HTTP approvals.
    func submitApproval(routeId: String, approve: Bool) -> Bool {
        guard let record = store.get(routeId: routeId) else { return false }
        let now = ISO8601DateFormatter().string(from: Date())
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let response = ApprovalResponse(
            schemaVersion: 1,
            responseId: "resp_\(UUID().uuidString)",
            routeId: record.routeId,
            eventId: record.eventId,
            tokenContext: nil,
            tokenIdHash: record.tokenIdHash,
            originalDecisionHash: record.decisionHash,
            normalizedCommandHash: record.normalizedCommandHash,
            policyVersion: record.policyVersion,
            domainRegistryHash: record.domainRegistryHash,
            actor: RouterActor(kind: "owner", id: routerOwnerID, displayName: "owner"),
            sourceSurface: "dooyou_api",
            issuedAtUTC: now,
            expiresAtUTC: expiry,
            decidedAtUTC: now,
            decision: approve ? "approve" : "reject",
            oneTime: ApprovalOneTime(nonce: "nonce_\(UUID().uuidString)", consumed: false),
            responseHash: "local_\(UUID().uuidString)"
        )
        do {
            _ = try store.recordApproval(response)
            return true
        } catch {
            return false
        }
    }

    private func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address): return address.debugDescription == "127.0.0.1"
        case .ipv6(let address): return address.debugDescription == "::1"
        case .name(let name, _): return name == "localhost"
        @unknown default: return false
        }
    }

    private func route(_ data: Data) -> Data {
        guard let request = HTTPRequest(data: data) else {
            return jsonResponse(status: 400, RouterHTTPResponse(ok: false, status: "bad_request", message: "malformed request", dispatchAllowed: false))
        }
        if request.method == "GET", request.path == "/health" {
            return jsonResponse(status: 200, RouterHealthResponse(ok: true, version: 1, app: "dooyou", status: "running", authRequired: true, authConfigured: tokenHash != nil))
        }
        guard authorized(request.headers) else {
            return jsonResponse(status: 401, RouterHTTPResponse(ok: false, status: "unauthorized", message: "missing or invalid bearer token", dispatchAllowed: false))
        }
        if request.method == "GET", request.path == "/v1/router/decisions" {
            return jsonResponse(status: 200, store.list())
        }
        if request.method == "GET", request.path.hasPrefix("/v1/router/decisions/") {
            let routeId = String(request.path.dropFirst("/v1/router/decisions/".count))
            guard let record = store.get(routeId: routeId) else {
                return jsonResponse(status: 404, RouterHTTPResponse(ok: false, status: "not_found", message: "route not found", dispatchAllowed: false))
            }
            return jsonResponse(status: 200, record)
        }
        if request.method == "POST", request.path == "/v1/router/approvals" {
            do {
                _ = try store.ingestApprovalData(request.body)
                return jsonResponse(status: 202, RouterHTTPResponse(ok: true, status: "accepted", message: "approval metadata stored", dispatchAllowed: false))
            } catch {
                return jsonResponse(status: 400, RouterHTTPResponse(ok: false, status: "invalid_approval", message: "invalid approval envelope", dispatchAllowed: false))
            }
        }
        if request.method == "POST", request.path == "/v1/router/events" {
            do {
                let record = try store.ingestEventData(request.body)
                return jsonResponse(status: 202, RouterHTTPResponse(ok: true, status: "accepted", message: "safe projection stored for route \(record.routeId)", dispatchAllowed: false))
            } catch {
                return jsonResponse(status: 400, RouterHTTPResponse(ok: false, status: "invalid_event", message: "invalid RouterDecision envelope", dispatchAllowed: false))
            }
        }
        return jsonResponse(status: 404, RouterHTTPResponse(ok: false, status: "not_found", message: "unknown endpoint", dispatchAllowed: false))
    }

    private func authorized(_ headers: [String: String]) -> Bool {
        guard let tokenHash else { return false }
        guard let header = headers["authorization"], header.lowercased().hasPrefix("bearer ") else { return false }
        let token = String(header.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return routerSHA256Hex(token) == tokenHash
    }

    private func jsonResponse<T: Encodable>(status: Int, _ body: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = (try? encoder.encode(body)) ?? Data("{\"ok\":false}".utf8)
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "OK"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Content-Length: \(payload.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + payload
    }
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init?(data: Data) {
        guard let marker = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<marker.lowerBound]
        let bodyStart = marker.upperBound
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()
        path = String(parts[1])
        var parsed: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            parsed[key] = value
        }
        headers = parsed
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let availableBody = data[bodyStart...]
        body = Data(availableBody.prefix(contentLength == 0 ? availableBody.count : contentLength))
    }
}

enum RouterAPISelfTest {
    static func run() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dooyou-router-selftest-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("router-decisions.json")
        let store = RouterDecisionStore(fileURL: storeURL)
        let json = """
        {
          "schema_version":1,
          "route_id":"route_selftest",
          "event_id":"event_selftest",
          "created_at_utc":"2026-07-01T00:00:00Z",
          "updated_at_utc":"2026-07-01T00:00:00Z",
          "decision_hash":"hash",
          "policy_version":"pug-router-policy.v2",
          "domain_registry_hash":"registry-selftest-v1",
          "actor":{"kind":"owner","id":"5747637837","display_name":"owner"},
          "source_surface":"test_fixture",
          "source_ref":null,
          "normalized_intent":{"kind":"build","confidence":"deterministic","normalized_command_hash":"cmdhash"},
          "lane":"build",
          "risk":"medium",
          "priority":50,
          "boundaries":{"router_state":"required","dooyou_status":"required","dooyou_approval":"required","gajae_dispatch":"allowed_after_approval","hermes_writeback":"required"},
          "approval":{"required":true,"reasons":["destructive_cleanup"],"status":"pending","token_id_hash":"tokenhash","requested_at_utc":"2026-07-01T00:00:00Z","expires_at_utc":"2026-07-01T00:10:00Z","decided_at_utc":null},
          "readiness":{"state":"target_ready","blockers":[]},
          "dispatch":{"target":"gajae_direct","command_summary":"raw command must not persist","allowed":false},
          "mission_draft":{"id":"mission_selftest","objective_summary":"raw objective must not persist","acceptance_summary":["safe projection only"],"forbidden_summary":["direct dispatch"]},
          "verification":{"expectation":"focused_test","receipt_required":true},
          "writeback":{"hermes_path":"06_Meta/router-decisions/route_selftest.md","receipt_path":"receipts/r.json","decision_note_path":"notes/r.md","secret_policy":"none"},
          "dooyou_projection":{"title":"Safe title","subtitle":"Safe subtitle","status_badge":"pending_approval","risk_badge":"medium","primary_action":"approve","secondary_actions":["reject"],"route_card_kind":"approval","policy_version":"pug-router-policy.v2","domain_registry_hash":"registry-selftest-v1"},
          "user_status":{"state":"pending_approval","message":"approval required"},
          "failure":{"state":"approval_required","reason":"destructive_cleanup"}
        }
        """.data(using: .utf8)!
        let api = RouterAPI(store: store, token: "selftest-token", port: 17682)

        func http(_ method: String, _ path: String, token: String? = nil, body: Data = Data()) -> Data {
            var request = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
            if let token {
                request += "Authorization: Bearer \(token)\r\n"
            }
            if !body.isEmpty {
                request += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
            }
            request += "\r\n"
            return Data(request.utf8) + body
        }

        func responseBody(_ response: Data) -> String {
            let marker = Data("\r\n\r\n".utf8)
            guard let range = response.range(of: marker) else { return "" }
            return String(data: response[range.upperBound...], encoding: .utf8) ?? ""
        }

        let health = responseBody(api.testResponse(for: http("GET", "/health")))
        guard health.contains("\"auth_required\":true"), !health.contains("route_selftest") else {
            throw NSError(domain: "RouterAPISelfTest", code: 1)
        }

        let unauthorized = String(data: api.testResponse(for: http("GET", "/v1/router/decisions")), encoding: .utf8) ?? ""
        guard unauthorized.contains("401 Unauthorized"), !unauthorized.contains("route_selftest") else {
            throw NSError(domain: "RouterAPISelfTest", code: 2)
        }

        let accepted = String(data: api.testResponse(for: http("POST", "/v1/router/events", token: "selftest-token", body: json)), encoding: .utf8) ?? ""
        guard accepted.contains("202 Accepted"), accepted.contains("\"dispatch_allowed\":false") else {
            throw NSError(domain: "RouterAPISelfTest", code: 3)
        }

        let approvalJSON = """
        {
          "schema_version":1,
          "response_id":"resp_selftest",
          "route_id":"route_selftest",
          "event_id":"event_selftest",
          "token_context":"approval_selftest",
          "token_id_hash":"tokenhash",
          "original_decision_hash":"hash",
          "policy_version":"pug-router-policy.v2",
          "domain_registry_hash":"registry-selftest-v1",
          "normalized_command_hash":"cmdhash",
          "actor":{"kind":"owner","id":"5747637837","display_name":"owner"},
          "source_surface":"dooyou_api",
          "issued_at_utc":"2026-07-01T00:01:00Z",
          "expires_at_utc":"2999-07-01T00:10:00Z",
          "decided_at_utc":"2026-07-01T00:01:00Z",
          "decision":"approve",
          "one_time":{"nonce":"nonce_selftest","consumed":false},
          "response_hash":"responsehash"
        }
        """.data(using: .utf8)!

        let badApprovalJSON = String(data: approvalJSON, encoding: .utf8)!
            .replacingOccurrences(of: "\"source_surface\":\"dooyou_api\"", with: "\"source_surface\":\"telegram_dm\"")
            .data(using: .utf8)!
        let rejectedApproval = String(data: api.testResponse(for: http("POST", "/v1/router/approvals", token: "selftest-token", body: badApprovalJSON)), encoding: .utf8) ?? ""
        guard rejectedApproval.contains("400 Bad Request"), rejectedApproval.contains("\"dispatch_allowed\":false") else {
            throw NSError(domain: "RouterAPISelfTest", code: 4)
        }

        let missingExpiryApprovalJSON = String(data: approvalJSON, encoding: .utf8)!
            .replacingOccurrences(of: "\"expires_at_utc\":\"2999-07-01T00:10:00Z\"", with: "\"expires_at_utc\":null")
            .data(using: .utf8)!
        let rejectedMissingExpiry = String(data: api.testResponse(for: http("POST", "/v1/router/approvals", token: "selftest-token", body: missingExpiryApprovalJSON)), encoding: .utf8) ?? ""
        guard rejectedMissingExpiry.contains("400 Bad Request"), rejectedMissingExpiry.contains("\"dispatch_allowed\":false") else {
            throw NSError(domain: "RouterAPISelfTest", code: 5)
        }
        let badIdentityApprovalJSON = String(data: approvalJSON, encoding: .utf8)!
            .replacingOccurrences(of: "\"policy_version\":\"pug-router-policy.v2\"", with: "\"policy_version\":\"policy.v3\"")
            .data(using: .utf8)!
        let rejectedBadIdentity = String(data: api.testResponse(for: http("POST", "/v1/router/approvals", token: "selftest-token", body: badIdentityApprovalJSON)), encoding: .utf8) ?? ""
        guard rejectedBadIdentity.contains("400 Bad Request"), rejectedBadIdentity.contains("\"dispatch_allowed\":false") else {
            throw NSError(domain: "RouterAPISelfTest", code: 6)
        }


        let approved = String(data: api.testResponse(for: http("POST", "/v1/router/approvals", token: "selftest-token", body: approvalJSON)), encoding: .utf8) ?? ""
        guard approved.contains("202 Accepted"), approved.contains("\"dispatch_allowed\":false") else {
            throw NSError(domain: "RouterAPISelfTest", code: 5)
        }
        guard let record = store.get(routeId: "route_selftest"),
              record.routeId == "route_selftest",
              record.projection.title == "Safe title",
              record.policyVersion == "pug-router-policy.v2",
              record.domainRegistryHash == "registry-selftest-v1",
              record.projection.policyVersion == "pug-router-policy.v2",
              record.projection.domainRegistryHash == "registry-selftest-v1",
              record.dispatchAllowed == false,
              record.approvalStatus == "approve" else {
            throw NSError(domain: "RouterAPISelfTest", code: 6)
        }
        let saved = try Data(contentsOf: storeURL)
        let savedText = String(data: saved, encoding: .utf8) ?? ""
        guard !savedText.contains("raw command must not persist"), !savedText.contains("raw objective must not persist"), !savedText.contains("5747637837"), !savedText.contains("selftest-token") else {
            throw NSError(domain: "RouterAPISelfTest", code: 2)
        }
    }
}


enum RouterIntegrationSelfTest {
    static func run(decisionPath: String) throws -> String {
        let decisionURL = URL(fileURLWithPath: decisionPath)
        let data = try Data(contentsOf: decisionURL)
        let decision = try JSONDecoder().decode(RouterDecision.self, from: data)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dooyou-router-integration-selftest-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("router-decisions.json")
        let store = RouterDecisionStore(fileURL: storeURL)
        let record = try store.ingestEventData(data)
        guard record.routeId == decision.routeId,
              record.eventId == decision.eventId,
              record.status == decision.userStatus.state,
              record.approvalRequired == decision.approval.required,
              record.dispatchAllowed == decision.dispatch.allowed,
              record.hermesPath == decision.writeback.hermesPath,
              record.policyVersion == decision.policyVersion,
              record.domainRegistryHash == decision.domainRegistryHash,
              record.projection.statusBadge == decision.dooyouProjection.statusBadge,
              record.projection.policyVersion == decision.dooyouProjection.policyVersion,
              record.projection.domainRegistryHash == decision.dooyouProjection.domainRegistryHash else {
            throw NSError(domain: "RouterIntegrationSelfTest", code: 1)
        }
        let saved = try Data(contentsOf: storeURL)
        let savedText = String(data: saved, encoding: .utf8) ?? ""
        let forbidden = [
            "\"command_summary\"",
            "\"objective_summary\"",
            routerOwnerID,
            "raw command",
            "raw objective",
            "Bearer ",
            "sk-"
        ]
        guard forbidden.allSatisfy({ !savedText.contains($0) }) else {
            throw NSError(domain: "RouterIntegrationSelfTest", code: 2)
        }
        let result: [String: Any] = [
            "route_id": record.routeId,
            "status": record.status,
            "projection_status": record.projection.statusBadge,
            "policy_version": record.policyVersion ?? "",
            "domain_registry_hash": record.domainRegistryHash ?? "",
            "approval_required": record.approvalRequired,
            "dispatch_allowed": record.dispatchAllowed,
            "hermes_path": record.hermesPath ?? "",
            "safe_store_path": storeURL.path,
            "safe_store_redacted": true
        ]
        let out = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        return String(data: out, encoding: .utf8) ?? "{}"
    }
}
