import FamiliarCore
import Foundation
import Supabase

/// Geräte-Tokens und Live Activities für Mitteilungen (Migration 0012). Schreiben nur per RPC.
final class SupabaseDeviceRepository: DeviceRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func registerDevice(token: String, environment: PushEnvironment, pushToStartToken: String?,
                        appVersion: String?, timezone: String?) async throws(FamiliarError) {
        let params = RegisterDeviceParams(token: token, environment: environment, pushToStartToken: pushToStartToken,
                                          appVersion: appVersion, timezone: timezone)
        _ = try await perform {
            try await client.rpc("register_device", params: params).execute()
        }
    }

    func unregisterDevice(token: String) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("unregister_device", params: ["p_apns_token": token]).execute()
        }
    }

    func registerLiveActivity(taskID: UUID, deviceToken: String, activityID: String,
                              updateToken: String) async throws(FamiliarError) {
        let params = RegisterActivityParams(taskID: taskID, deviceToken: deviceToken, activityID: activityID,
                                            updateToken: updateToken)
        _ = try await perform {
            try await client.rpc("register_live_activity", params: params).execute()
        }
    }

    func endLiveActivity(deviceToken: String, activityID: String) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("end_live_activity", params: ["p_apns_token": deviceToken, "p_activity_id": activityID])
                .execute()
        }
    }
}

private struct RegisterDeviceParams: Encodable {
    let token: String
    let environment: PushEnvironment
    let pushToStartToken: String?
    let appVersion: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case token = "p_apns_token"
        case environment = "p_environment"
        case pushToStartToken = "p_push_to_start_token"
        case appVersion = "p_app_version"
        case timezone = "p_timezone"
    }
}

private struct RegisterActivityParams: Encodable {
    let taskID: UUID
    let deviceToken: String
    let activityID: String
    let updateToken: String

    enum CodingKeys: String, CodingKey {
        case taskID = "p_task_id"
        case deviceToken = "p_apns_token"
        case activityID = "p_activity_id"
        case updateToken = "p_update_token"
    }
}
