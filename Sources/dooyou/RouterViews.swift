import SwiftUI
import AppKit

private func routerStatusColor(_ status: String) -> Color {
    switch status {
    case "ready_to_dispatch", "ready", "verified", "approved": return DooyouStyle.success
    case "pending_approval", "pending": return DooyouStyle.warning
    case "blocked", "expired", "rejected", "downgraded": return DooyouStyle.error
    case "running": return DooyouStyle.info
    default: return .secondary
    }
}

private func routerRiskColor(_ risk: String) -> Color {
    switch risk {
    case "live-gated", "high": return DooyouStyle.error
    case "medium": return DooyouStyle.warning
    case "low": return DooyouStyle.success
    default: return .secondary
    }
}

struct RouterStatusStrip: View {
    @ObservedObject var store: RouterDecisionStore
    var openDashboard: () -> Void

    private var records: [RouterDecisionRecord] { store.records }
    private var pending: Int { records.filter { $0.approvalRequired && $0.approvalStatus == "pending" }.count }
    private var blocked: Int { records.filter { ["blocked", "expired", "downgraded", "rejected"].contains($0.status) || $0.failureState != "none" }.count }

    var body: some View {
        Button(action: openDashboard) {
            HStack(spacing: 8) {
                Image(systemName: pending > 0 ? "exclamationmark.shield.fill" : "shield.checkered")
                    .foregroundStyle(pending > 0 ? DooyouStyle.warning : DooyouStyle.success)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("라우터")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusCapsule(text: pending > 0 ? "승인 \(pending)" : "대기", color: pending > 0 ? DooyouStyle.warning : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background((pending > 0 ? DooyouStyle.warning : DooyouStyle.success).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Router/Approvals 대시보드 열기")
    }

    private var summary: String {
        if records.isEmpty { return "결정 없음" }
        if pending > 0 { return "승인 대기 \(pending)개 · 차단 \(blocked)개" }
        return "총 \(records.count)개 · 차단 \(blocked)개"
    }
}

struct RouterDashboardSection: View {
    @ObservedObject var store: RouterDecisionStore

    private var records: [RouterDecisionRecord] { store.records.sorted { $0.updatedAtUTC > $1.updatedAtUTC } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Router Decisions")
                    .font(.headline)
                Spacer()
                StatusCapsule(text: "\(records.count)개", color: records.isEmpty ? .secondary : DooyouStyle.info)
            }
            if records.isEmpty {
                emptyState
            } else {
                ForEach(records) { record in
                    RouterDecisionCard(record: record)
                }
            }
        }
        .padding(12)
        .background(DooyouStyle.surfaceElevated.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("아직 라우터 결정이 없습니다.")
                .font(.callout)
                .fontWeight(.semibold)
            Text("PUG/Hermes 어댑터가 RouterDecision safe projection을 보내면 여기에 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RouterDecisionCard: View {
    let record: RouterDecisionRecord

    private var needsApproval: Bool { record.approvalRequired && record.approvalStatus == "pending" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(routerStatusColor(record.status))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.projection.title)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text(record.projection.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(record.routeId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusCapsule(text: record.status, color: routerStatusColor(record.status))
                    StatusCapsule(text: record.risk, color: routerRiskColor(record.risk))
                }
            }

            if !record.approvalReasons.isEmpty {
                Text("승인 사유: \(record.approvalReasons.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if needsApproval {
                    Button("승인") { (NSApp.delegate as? AppDelegate)?.submitRouterApproval(routeId: record.routeId, approve: true) }
                        .buttonStyle(.borderedProminent)
                    Button("거절") { (NSApp.delegate as? AppDelegate)?.submitRouterApproval(routeId: record.routeId, approve: false) }
                        .buttonStyle(.bordered)
                } else {
                    StatusCapsule(text: record.approvalStatus, color: routerStatusColor(record.approvalStatus))
                }
                Spacer()
                if let hermesPath = record.hermesPath {
                    Button("Hermes") { copy(hermesPath) }
                        .buttonStyle(.bordered)
                        .help(hermesPath)
                }
                if let receipt = record.receiptPath {
                    Button("Receipt") { copy(receipt) }
                        .buttonStyle(.bordered)
                        .help(receipt)
                }
                Button("ID 복사") { copy(record.routeId) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(routerRiskColor(record.risk).opacity(0.18), lineWidth: 1))
    }

    private var iconName: String {
        if needsApproval { return "hand.raised.fill" }
        if record.failureState != "none" { return "exclamationmark.triangle.fill" }
        return "point.topleft.down.curvedto.point.bottomright.up"
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

enum RouterUISelfTest {
    static func run() throws {
        let projection = RouterProjection(
            title: "Pending approval",
            subtitle: "Safe projected subtitle",
            statusBadge: "pending_approval",
            riskBadge: "medium",
            primaryAction: "approve",
            secondaryActions: ["reject", "copy_route_id"],
            routeCardKind: "approval"
        )
        let record = RouterDecisionRecord(
            routeId: "route_ui_selftest",
            eventId: "event_ui_selftest",
            createdAtUTC: "2026-07-01T00:00:00Z",
            updatedAtUTC: "2026-07-01T00:00:00Z",
            decisionHash: "hash",
            sourceSurface: "test_fixture",
            actorKind: "owner",
            actorIdHash: routerSHA256Hex(routerOwnerID),
            intentKind: "build",
            normalizedCommandHash: "cmdhash",
            lane: "build",
            risk: "medium",
            priority: 50,
            status: "pending_approval",
            statusMessage: "approval required",
            failureState: "approval_required",
            failureReason: "destructive_cleanup",
            approvalRequired: true,
            approvalStatus: "pending",
            approvalReasons: ["destructive_cleanup"],
            tokenIdHash: "tokenhash",
            approvalRequestedAtUTC: "2026-07-01T00:00:00Z",
            approvalExpiresAtUTC: "2026-07-01T00:10:00Z",
            approvalDecidedAtUTC: nil,
            dispatchTarget: "gajae_direct",
            dispatchAllowed: false,
            readinessState: "target_ready",
            readinessBlockers: [],
            verificationExpectation: "focused_test",
            receiptRequired: true,
            hermesPath: "06_Meta/router-decisions/route_ui_selftest.md",
            receiptPath: "receipts/route_ui_selftest.json",
            decisionNotePath: nil,
            projection: projection,
            lastApprovalResponseHash: nil,
            lastApprovalDecision: nil,
            lastApprovalSourceSurface: nil
        )
        _ = RouterDecisionCard(record: record).body
        let tempStore = RouterDecisionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("router-ui-selftest.json"))
        _ = RouterStatusStrip(store: tempStore, openDashboard: {}).body
        _ = RouterDashboardSection(store: tempStore).body
    }
}
