// Sources/Encore/Core/Infrastructure/Experiments/ExperimentManager.swift
//
// NCL cohort assignment: SHA256("<personKey>:<version>") % 100, cached per install in UserDefaults.
// personKey is the app account id, or the SDK user id when transaction linking is off.

import Foundation
import CryptoKit

// MARK: - Experiment Manager

/// NCL (Net Conversion Lift) cohort assignment: a pure function of `personKey` and
/// `assignmentVersion`, so nothing to reset; bumping the version server-side re-buckets everyone.
/// Keyed on the app account id the cohort holds across devices; on the user id it is per install.
internal final class ExperimentManager {
    
    // MARK: - Dependencies
    
    private let repository: ExperimentRepository
    
    // MARK: - Initialization
    
    init(repository: ExperimentRepository) {
        self.repository = repository
    }
    
    // MARK: - Cohort Assignment
    
    /// `.notEnrolled` when `personKey` is nil (linking on, id unresolved), the experiment is off
    /// or config is missing; else the cached cohort for this version, or a fresh assignment.
    func getCohort() -> Cohort {
        guard userManager?.personKey != nil else {
            return .notEnrolled
        }
        
        guard let nclConfig = remoteConfigManager?.experiments?.ncl else {
            return .notEnrolled
        }
        
        guard nclConfig.enabled else {
            return .notEnrolled
        }
        
        let currentVersion = nclConfig.assignmentVersion
        
        if let stored = repository.getNCLAssignment(),
           stored.assignmentVersion == currentVersion {
            return stored.cohort
        }
        
        let cohort = assignCohort(rolloutPct: nclConfig.rolloutPct, version: currentVersion)
        let assignment = NCLAssignment(cohort: cohort, assignmentVersion: currentVersion)
        repository.saveNCLAssignment(assignment)
        
        Logger.info(.experiments, "Assigned cohort: \(cohort.rawValue) (version \(currentVersion), rollout \(nclConfig.rolloutPct)%)")
        return cohort
    }
    
    // MARK: - Hash (internal for testability)
    
    /// Deterministic cohort assignment: SHA256(personKey:version) % 100.
    /// CryptoKit SHA256 output is uniformly distributed; mod 100 has negligible bias.
    func assignCohort(personKey: String, rolloutPct: Int, version: Int) -> Cohort {
        let input = "\(personKey):\(version)"
        let digest = SHA256.hash(data: Data(input.utf8))
        
        let hashBytes = Array(digest.prefix(8))
        let hashValue = hashBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let bucket = Int(hashValue % 100)
        
        return bucket < rolloutPct ? .treatment : .control
    }
    
    /// Convenience that reads `personKey` from UserManager.
    private func assignCohort(rolloutPct: Int, version: Int) -> Cohort {
        guard let personKey = userManager?.personKey else { return .control }
        return assignCohort(personKey: personKey, rolloutPct: rolloutPct, version: version)
    }
}
