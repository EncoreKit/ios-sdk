// Sources/Encore/Core/Infrastructure/Experiments/Extensions/Experiment+Outbox.swift
//
// Outbox job factory for experiment exposure events.
// Routes through POST /events (analytics-api → BigQuery) with reliable outbox delivery.

import Foundation

extension OutboxJob {
    
    /// Create an outbox job for experiment exposure tracking.
    /// Uses appAccountId as distinct_id for stable NCL join key.
    static func experimentExposure(
        appAccountId: String,
        experiment: String,
        cohort: Cohort,
        assignmentVersion: Int
    ) -> OutboxJob {
        let timestamp = Date()
        let eventName = ExperimentExposureEvent.eventName
        let eventId = EventEnvelope.generateEventId(eventName: eventName, distinctId: appAccountId, timestamp: timestamp)
        
        let properties: [String: Any] = [
            "experiment": experiment,
            "cohort": cohort.rawValue,
            "assignment_version": assignmentVersion,
            "sdk_version": Encore.sdkVersion,
            "app_bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "platform": "ios",
            "app_account_id": appAccountId
        ]
        
        let body = DTO.Analytics.IngestEvent(
            event_id: eventId,
            event_name: eventName,
            event_timestamp: timestamp,
            distinct_id: appAccountId,
            properties: properties.nonEmpty.map { .init(additionalProperties: $0.asOpenAPIProperties) }
        )
        
        return OutboxJob(request: OutboxRequest(path: "events", method: "POST", body: body), clientTarget: .olap)
    }
}
