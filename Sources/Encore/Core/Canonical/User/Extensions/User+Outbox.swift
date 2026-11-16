// Sources/Encore/Core/Canonical/User/User+Outbox.swift
//
// Domain-specific OutboxJob factories for User operations.
// Keeps infrastructure (Outbox) decoupled from domain knowledge.

import Foundation

// MARK: - User Outbox Jobs

extension OutboxJob {
    
    /// Create a job for POST /users (user init)
    static func userInit(userId: String, attributes: UserAttributes?) -> OutboxJob {
        let payload = DTO.Users.InitRequest(
            userId: userId,
            attributes: bounded(attributes).map { DTO.Users.InitAttributes(email: $0.email, name: $0.name) }
        )
        return OutboxJob(request: OutboxRequest(path: "users", method: "POST", body: payload))
    }
    
    /// Create a job for PATCH /users/identify
    static func userIdentify(currentUserId: String, newUserId: String, attributes: UserAttributes?) -> OutboxJob {
        let payload = DTO.Users.IdentifyRequest(
            currentUserId: currentUserId,
            newUserId: newUserId,
            attributes: bounded(attributes).map { DTO.Users.IdentifyAttributes(email: $0.email, name: $0.name) }
        )
        return OutboxJob(request: OutboxRequest(path: "users/identify", method: "PATCH", body: payload))
    }

    /// The route's `z.string().email()` fails the whole call on a bad address, so a bad one is dropped instead.
    /// Nil when nothing is left to send. Mirrors Android's `boundedEmail`.
    private static func bounded(_ attributes: UserAttributes?) -> (email: String?, name: String?)? {
        let trimmed = attributes?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = trimmed?.range(of: emailShape, options: .regularExpression) == nil ? nil : trimmed
        let name = attributes?.fullName
        return email == nil && name == nil ? nil : (email, name)
    }

    private static let emailShape = #"^[A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*@([A-Za-z0-9][A-Za-z0-9-]*\.)+[A-Za-z]{2,}$"#
}
