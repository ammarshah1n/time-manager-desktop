// SupabaseClient.swift — Timed Core
// ALL Supabase access goes through this file. Never import Supabase directly elsewhere.
// See: CLAUDE.md → Architecture Rules

import Foundation
import Supabase
import Dependencies
import os

// MARK: - Row Types

struct TaskDBRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let sourceType: String
    let bucketType: String
    let title: String
    let description: String?
    let status: String
    let priority: Int
    let dueAt: Date?
    let estimatedMinutesAi: Int?
    let estimatedMinutesManual: Int?
    let actualMinutes: Int?
    let estimateSource: String?
    let isDoFirst: Bool
    let isTransitSafe: Bool
    let isOverdue: Bool
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case sourceType = "source_type"
        case bucketType = "bucket_type"
        case title
        case description
        case status
        case priority
        case dueAt = "due_at"
        case estimatedMinutesAi = "estimated_minutes_ai"
        case estimatedMinutesManual = "estimated_minutes_manual"
        case actualMinutes = "actual_minutes"
        case estimateSource = "estimate_source"
        case isDoFirst = "is_do_first"
        case isTransitSafe = "is_transit_safe"
        case isOverdue = "is_overdue"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct EmailMessageRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let emailAccountId: UUID
    let graphMessageId: String
    let graphThreadId: String?
    let fromAddress: String
    let fromName: String?
    let subject: String
    let snippet: String?
    let receivedAt: Date
    let triageBucket: String?
    let triageConfidence: Float?
    let triageSource: String?
    let isQuestion: Bool
    let isQuickReply: Bool
    let isCcFyi: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case emailAccountId = "email_account_id"
        case graphMessageId = "graph_message_id"
        case graphThreadId = "graph_thread_id"
        case fromAddress = "from_address"
        case fromName = "from_name"
        case subject
        case snippet
        case receivedAt = "received_at"
        case triageBucket = "triage_bucket"
        case triageConfidence = "triage_confidence"
        case triageSource = "triage_source"
        case isQuestion = "is_question"
        case isQuickReply = "is_quick_reply"
        case isCcFyi = "is_cc_fyi"
    }
}

struct TriageCorrectionRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let emailMessageId: UUID
    let profileId: UUID
    let oldBucket: String
    let newBucket: String
    let fromAddress: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case emailMessageId = "email_message_id"
        case profileId = "profile_id"
        case oldBucket = "old_bucket"
        case newBucket = "new_bucket"
        case fromAddress = "from_address"
    }
}

struct DailyPlanRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let planDate: Date
    let availableMinutes: Int
    let totalPlannedMinutes: Int
    let status: String
    let moodContext: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case planDate = "plan_date"
        case availableMinutes = "available_minutes"
        case totalPlannedMinutes = "total_planned_minutes"
        case status
        case moodContext = "mood_context"
    }
}

struct PlanItemDBRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let planId: UUID
    let taskId: UUID
    let position: Int
    let estimatedMinutes: Int
    let bufferAfterMinutes: Int
    let rankReason: String?
    let isDone: Bool
    let doneAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case planId = "plan_id"
        case taskId = "task_id"
        case position
        case estimatedMinutes = "estimated_minutes"
        case bufferAfterMinutes = "buffer_after_minutes"
        case rankReason = "rank_reason"
        case isDone = "is_done"
        case doneAt = "done_at"
    }
}

struct BehaviourRuleRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let ruleKey: String
    let ruleType: String
    let ruleValueJson: Data
    let confidence: Float
    let sampleSize: Int
    let evidence: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case ruleKey = "rule_key"
        case ruleType = "rule_type"
        case ruleValueJson = "rule_value_json"
        case confidence
        case sampleSize = "sample_size"
        case evidence
        case isActive = "is_active"
    }
}

struct SenderRuleRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let fromAddress: String
    let ruleType: String

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case fromAddress = "from_address"
        case ruleType = "rule_type"
    }
}

struct VoiceCaptureRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let rawTranscript: String
    let status: String
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case rawTranscript = "raw_transcript"
        case status
        case capturedAt = "captured_at"
    }
}

struct WaitingItemRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let description: String
    let contactName: String?
    let contactEmail: String?
    let askedAt: Date
    let expectedBy: Date?
    let sourceType: String
    let status: String
    let followUpCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case description
        case contactName = "contact_name"
        case contactEmail = "contact_email"
        case askedAt = "asked_at"
        case expectedBy = "expected_by"
        case sourceType = "source_type"
        case status
        case followUpCount = "follow_up_count"
    }
}

struct PipelineRunRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let pipelineName: String
    let entityType: String?
    let entityId: UUID?
    let model: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let status: String
    let errorMessage: String?
    let startedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case pipelineName = "pipeline_name"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case status
        case errorMessage = "error_message"
        case startedAt = "started_at"
    }
}

struct BucketCompletionStat: Codable, Sendable {
    let bucketType: String
    let hourRange: String
    let completions: Int
    let deferrals: Int

    enum CodingKeys: String, CodingKey {
        case bucketType = "bucket_type"
        case hourRange = "hour_range"
        case completions, deferrals
    }
}

struct SenderLatencyRow: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let fromAddress: String
    let replyLatencyAvg: Double
    let sampleSize: Int

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case fromAddress = "from_address"
        case replyLatencyAvg = "reply_latency_avg"
        case sampleSize = "sample_size"
    }
}

struct BehaviourEventInsert: Codable, Sendable {
    let workspaceId: UUID
    let profileId: UUID
    let eventType: String
    let taskId: UUID
    let bucketType: String
    let hourOfDay: Int
    let dayOfWeek: Int
    let oldValue: String?
    let newValue: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case eventType = "event_type"
        case taskId = "task_id"
        case bucketType = "bucket_type"
        case hourOfDay = "hour_of_day"
        case dayOfWeek = "day_of_week"
        case oldValue = "old_value"
        case newValue = "new_value"
    }
}

// MARK: - Dependency Client

struct WorkspaceMemberRow: Codable, Identifiable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let profileId: UUID
    let role: String
    let email: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case profileId = "profile_id"
        case role
        case email
        case fullName = "full_name"
    }
}

struct SupabaseClientDependency: Sendable {
    var fetchTasks: @Sendable (UUID, UUID, [String]) async throws -> [TaskDBRow] = { _, _, _ in [] }
    var upsertTask: @Sendable (TaskDBRow) async throws -> Void = { _ in }
    var updateTaskStatus: @Sendable (UUID, String, Int?) async throws -> Void = { _, _, _ in }
    var fetchEmailMessages: @Sendable (UUID, String, Int) async throws -> [EmailMessageRow] = { _, _, _ in [] }
    var updateEmailBucket: @Sendable (UUID, String, Float?) async throws -> Void = { _, _, _ in }
    var insertTriageCorrection: @Sendable (TriageCorrectionRow) async throws -> Void = { _ in }
    var fetchDailyPlan: @Sendable (UUID, UUID, Date) async throws -> DailyPlanRow? = { _, _, _ in nil }
    var upsertDailyPlan: @Sendable (DailyPlanRow) async throws -> Void = { _ in }
    var upsertPlanItems: @Sendable ([PlanItemDBRow]) async throws -> Void = { _ in }
    var fetchBehaviourRules: @Sendable (UUID) async throws -> [BehaviourRuleRow] = { _ in [] }
    var fetchSenderRules: @Sendable (UUID, UUID) async throws -> [SenderRuleRow] = { _, _ in [] }
    var insertVoiceCapture: @Sendable (VoiceCaptureRow) async throws -> Void = { _ in }
    var fetchWaitingItems: @Sendable (UUID, UUID) async throws -> [WaitingItemRow] = { _, _ in [] }
    var logPipelineRun: @Sendable (PipelineRunRow) async throws -> Void = { _ in }
    var upsertEmailMessage: @Sendable (EmailMessageRow) async throws -> Void = { _ in }

    /// Fetches bucket completion stats for Thompson sampling (workspaceId, profileId).
    var fetchBucketStats: @Sendable (UUID, UUID) async throws -> [BucketCompletionStat] = { _, _ in [] }

    /// Inserts a behaviour event for the learning loop.
    var insertBehaviourEvent: @Sendable (BehaviourEventInsert) async throws -> Void = { _ in }

    /// Upserts a sender rule: (workspaceId, profileId, fromAddress, ruleType).
    /// ruleType is one of: "inbox_always", "black_hole", "later", "delegate".
    var upsertSenderRule: @Sendable (UUID, UUID, String, String) async throws -> Void = { _, _, _, _ in }

    /// Upserts sender reply latency: (workspaceId, profileId, fromAddress, avgLatencyMinutes, sampleSize).
    /// Used by the reply latency social graph to persist importance signals.
    var upsertSenderLatency: @Sendable (UUID, UUID, String, Double, Int) async throws -> Void = { _, _, _, _, _ in }

    /// Updates tasks.actual_minutes — triggers trg_insert_estimation_history which auto-inserts to estimation_history.
    var updateTaskActualMinutes: @Sendable (UUID, Int) async throws -> Void = { _, _ in }

    /// Upserts a bucket estimate: (workspaceId, profileId, bucketType, meanMinutes, sampleCount).
    /// Syncs local EMA posterior to Supabase for cross-device consistency.
    var upsertBucketEstimate: @Sendable (UUID, UUID, String, Double, Int) async throws -> Void = { _, _, _, _, _ in }

    // MARK: - Realtime
    var subscribeToTaskChanges: @Sendable (_ workspaceId: UUID, _ onChange: @escaping @Sendable () -> Void) async -> Void = { _, _ in }

    // MARK: - Sharing
    var insertWorkspaceInvite: @Sendable (UUID, UUID) async throws -> Void = { _, _ in }
    var fetchWorkspaceMembers: @Sendable (UUID) async throws -> [WorkspaceMemberRow] = { _ in [] }
    var deleteWorkspaceMember: @Sendable (UUID) async throws -> Void = { _ in }
}

// MARK: - DependencyKey

extension SupabaseClientDependency: DependencyKey {
    static let liveValue: SupabaseClientDependency = .live()
    static let testValue: SupabaseClientDependency = .init()
}

extension DependencyValues {
    var supabaseClient: SupabaseClientDependency {
        get { self[SupabaseClientDependency.self] }
        set { self[SupabaseClientDependency.self] = newValue }
    }
}

// MARK: - Live Implementation

extension SupabaseClientDependency {
    static func live() -> SupabaseClientDependency {
        let urlString = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "https://fpmjuufefhtlwbfinxlx.supabase.co"
        let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""

        // Detect placeholder / invalid URLs
        let isPlaceholder = urlString.contains("fake.supabase.co")
        guard let url = URL(string: urlString), !isPlaceholder else {
            TimedLogger.supabase.warning("Supabase not configured — running in local-only mode")
            return SupabaseClientDependency()
        }

        TimedLogger.supabase.info("Supabase client initialised for \(url.host ?? "unknown", privacy: .public)")
        let client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)

        return SupabaseClientDependency(
            fetchTasks: { workspaceId, profileId, status in
                let rows: [TaskDBRow] = try await client
                    .from("tasks")
                    .select()
                    .eq("workspace_id", value: workspaceId)
                    .eq("profile_id", value: profileId)
                    .in("status", values: status)
                    .order("due_at", ascending: true, nullsFirst: false)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
                return rows
            },
            upsertTask: { task in
                try await client
                    .from("tasks")
                    .upsert(task, onConflict: "id")
                    .execute()
            },
            updateTaskStatus: { taskId, status, actualMinutes in
                struct TaskStatusUpdate: Encodable {
                    let status: String
                    let actualMinutes: Int?
                    let updatedAt: String
                    enum CodingKeys: String, CodingKey {
                        case status
                        case actualMinutes = "actual_minutes"
                        case updatedAt = "updated_at"
                    }
                }
                let payload = TaskStatusUpdate(
                    status: status,
                    actualMinutes: actualMinutes,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
                try await client
                    .from("tasks")
                    .update(payload)
                    .eq("id", value: taskId)
                    .execute()
            },
            fetchEmailMessages: { workspaceId, bucket, limit in
                let rows: [EmailMessageRow] = try await client
                    .from("email_messages")
                    .select()
                    .eq("workspace_id", value: workspaceId)
                    .eq("triage_bucket", value: bucket)
                    .order("received_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
                return rows
            },
            updateEmailBucket: { messageId, bucket, confidence in
                struct EmailBucketUpdate: Encodable {
                    let triageBucket: String
                    let triageConfidence: Float?
                    let updatedAt: String
                    enum CodingKeys: String, CodingKey {
                        case triageBucket = "triage_bucket"
                        case triageConfidence = "triage_confidence"
                        case updatedAt = "updated_at"
                    }
                }
                let payload = EmailBucketUpdate(
                    triageBucket: bucket,
                    triageConfidence: confidence,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
                try await client
                    .from("email_messages")
                    .update(payload)
                    .eq("id", value: messageId)
                    .execute()
            },
            insertTriageCorrection: { correction in
                try await client
                    .from("email_triage_corrections")
                    .insert(correction)
                    .execute()
            },
            fetchDailyPlan: { workspaceId, profileId, date in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let dateStr = formatter.string(from: date)
                let rows: [DailyPlanRow] = try await client
                    .from("daily_plans")
                    .select()
                    .eq("workspace_id", value: workspaceId)
                    .eq("profile_id", value: profileId)
                    .eq("plan_date", value: dateStr)
                    .limit(1)
                    .execute()
                    .value
                return rows.first
            },
            upsertDailyPlan: { plan in
                try await client
                    .from("daily_plans")
                    .upsert(plan, onConflict: "id")
                    .execute()
            },
            upsertPlanItems: { items in
                try await client
                    .from("plan_items")
                    .upsert(items, onConflict: "id")
                    .execute()
            },
            fetchBehaviourRules: { profileId in
                let rows: [BehaviourRuleRow] = try await client
                    .from("behaviour_rules")
                    .select()
                    .eq("profile_id", value: profileId)
                    .eq("is_active", value: true)
                    .order("confidence", ascending: false)
                    .execute()
                    .value
                return rows
            },
            fetchSenderRules: { workspaceId, profileId in
                let rows: [SenderRuleRow] = try await client
                    .from("sender_rules")
                    .select()
                    .eq("workspace_id", value: workspaceId)
                    .eq("profile_id", value: profileId)
                    .execute()
                    .value
                return rows
            },
            insertVoiceCapture: { capture in
                try await client
                    .from("voice_captures")
                    .insert(capture)
                    .execute()
            },
            fetchWaitingItems: { workspaceId, profileId in
                let rows: [WaitingItemRow] = try await client
                    .from("waiting_items")
                    .select()
                    .eq("workspace_id", value: workspaceId)
                    .eq("profile_id", value: profileId)
                    .not("status", operator: .in, value: "(resolved,cancelled)")
                    .order("created_at", ascending: true)
                    .execute()
                    .value
                return rows
            },
            logPipelineRun: { run in
                try await client
                    .from("ai_pipeline_runs")
                    .insert(run)
                    .execute()
            },
            upsertEmailMessage: { message in
                try await client
                    .from("email_messages")
                    .upsert(message, onConflict: "graph_message_id")
                    .execute()
            },
            fetchBucketStats: { workspaceId, profileId in
                let rows: [BucketCompletionStat] = try await client
                    .from("bucket_completion_stats")
                    .select()
                    .eq("workspace_id", value: workspaceId)
                    .eq("profile_id", value: profileId)
                    .execute()
                    .value
                return rows
            },
            insertBehaviourEvent: { event in
                try await client
                    .from("behaviour_events")
                    .insert(event)
                    .execute()
            },
            upsertSenderRule: { workspaceId, profileId, fromAddress, ruleType in
                let row = SenderRuleRow(
                    id: UUID(),
                    workspaceId: workspaceId,
                    profileId: profileId,
                    fromAddress: fromAddress,
                    ruleType: ruleType
                )
                try await client
                    .from("sender_rules")
                    .upsert(row, onConflict: "workspace_id,profile_id,from_address")
                    .execute()
            },
            upsertSenderLatency: { workspaceId, profileId, fromAddress, avgLatencyMinutes, sampleSize in
                let row = SenderLatencyRow(
                    id: UUID(),
                    workspaceId: workspaceId,
                    profileId: profileId,
                    fromAddress: fromAddress,
                    replyLatencyAvg: avgLatencyMinutes,
                    sampleSize: sampleSize
                )
                try await client
                    .from("sender_latencies")
                    .upsert(row, onConflict: "workspace_id,profile_id,from_address")
                    .execute()
            },
            updateTaskActualMinutes: { taskId, actualMinutes in
                struct ActualMinutesUpdate: Encodable {
                    let actualMinutes: Int
                    let updatedAt: String
                    enum CodingKeys: String, CodingKey {
                        case actualMinutes = "actual_minutes"
                        case updatedAt = "updated_at"
                    }
                }
                let payload = ActualMinutesUpdate(
                    actualMinutes: actualMinutes,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
                try await client
                    .from("tasks")
                    .update(payload)
                    .eq("id", value: taskId)
                    .execute()
            },
            upsertBucketEstimate: { workspaceId, profileId, bucketType, meanMinutes, sampleCount in
                struct BucketEstimateRow: Encodable {
                    let id: UUID
                    let workspaceId: UUID
                    let profileId: UUID
                    let bucketType: String
                    let meanMinutes: Double
                    let sampleCount: Int
                    let updatedAt: String
                    enum CodingKeys: String, CodingKey {
                        case id
                        case workspaceId = "workspace_id"
                        case profileId = "profile_id"
                        case bucketType = "bucket_type"
                        case meanMinutes = "mean_minutes"
                        case sampleCount = "sample_count"
                        case updatedAt = "updated_at"
                    }
                }
                let row = BucketEstimateRow(
                    id: UUID(),
                    workspaceId: workspaceId,
                    profileId: profileId,
                    bucketType: bucketType,
                    meanMinutes: meanMinutes,
                    sampleCount: sampleCount,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
                try await client
                    .from("bucket_estimates")
                    .upsert(row, onConflict: "workspace_id,profile_id,bucket_type")
                    .execute()
            },
            subscribeToTaskChanges: { workspaceId, onChange in
                let channel = client.channel("tasks:\(workspaceId.uuidString)")

                let insertions = channel.postgresChange(
                    InsertAction.self,
                    schema: "public",
                    table: "tasks",
                    filter: .eq("workspace_id", value: workspaceId)
                )
                let updates = channel.postgresChange(
                    UpdateAction.self,
                    schema: "public",
                    table: "tasks",
                    filter: .eq("workspace_id", value: workspaceId)
                )
                let deletes = channel.postgresChange(
                    DeleteAction.self,
                    schema: "public",
                    table: "tasks",
                    filter: .eq("workspace_id", value: workspaceId)
                )

                try? await channel.subscribeWithError()

                Task {
                    for await _ in insertions { onChange() }
                }
                Task {
                    for await _ in updates { onChange() }
                }
                Task {
                    for await _ in deletes { onChange() }
                }
            },
            insertWorkspaceInvite: { workspaceId, inviteCode in
                struct InviteInsert: Encodable {
                    let id: UUID
                    let workspaceId: UUID
                    let code: String
                    enum CodingKeys: String, CodingKey {
                        case id
                        case workspaceId = "workspace_id"
                        case code
                    }
                }
                let payload = InviteInsert(
                    id: UUID(),
                    workspaceId: workspaceId,
                    code: inviteCode.uuidString
                )
                try await client
                    .from("workspace_invites")
                    .insert(payload)
                    .execute()
            },
            fetchWorkspaceMembers: { workspaceId in
                let rows: [WorkspaceMemberRow] = try await client
                    .from("workspace_members")
                    .select("id, workspace_id, profile_id, role, profiles(email, full_name)")
                    .eq("workspace_id", value: workspaceId)
                    .execute()
                    .value
                return rows
            },
            deleteWorkspaceMember: { memberId in
                try await client
                    .from("workspace_members")
                    .delete()
                    .eq("id", value: memberId)
                    .execute()
            }
        )
    }
}
