// Sources/Encore/Domain/Entities/Campaign.swift
//
// Campaign domain entity.
//

import Foundation

// =============================================================================
// MARK: - Campaign
// =============================================================================


/// Offer is now a Campaign directly - represents an eligible campaign for this user.
internal typealias Offer = Campaign

/// Campaign information
internal struct Campaign {
    let id: String
    let name: String
    let payoutAmount: Double?
    let targetCountries: [String]?
    let destinationUrl: String
    let startDate: Date
    let endDate: Date?
    let priority: Int?
    let newPrice: String?
    let oldPrice: String?
    let organization: Organization
    let creatives: [Creative]
    
    init(dto: DTO.Offers.Campaign) {
        self.id = dto.id
        self.name = dto.name
        self.payoutAmount = dto.payoutAmount
        self.targetCountries = dto.targetCountries
        self.destinationUrl = dto.destinationUrl
        self.startDate = dto.startDate
        self.endDate = dto.endDate
        self.priority = dto.priority
        self.newPrice = dto.newPrice
        self.oldPrice = dto.oldPrice
        self.organization = dto.organization.map { Organization(dto: $0) } ?? Organization(id: dto.organizationId, name: dto.name)
        self.creatives = dto.creatives?.map { Creative(dto: $0) } ?? []
    }
    
    // MARK: - Business Logic
    
    /// Primary active creative (first active in list)
    var primaryCreative: Creative? {
        creatives.first { $0.isActive }
    }
    
    /// Advertiser name (shorthand for organization.name)
    var advertiserName: String {
        organization.name
    }
    
    /// Display title from primary creative, fallback to campaign name
    var displayTitle: String {
        primaryCreative?.title ?? name
    }
    
    /// Description from primary creative
    var displayDescription: String? {
        primaryCreative?.description
    }
    
    /// Advertiser description (alias for displayDescription, legacy compatibility)
    var creativeAdvertiserDescription: String? {
        displayDescription
    }
    
    /// Logo URL from primary creative
    var displayLogoUrl: String? {
        primaryCreative?.logoUrl
    }
    
    /// Primary image URL from primary creative
    var displayPrimaryImageUrl: String? {
        primaryCreative?.primaryImageUrl
    }
    
    /// CTA text with fallback default
    var displayCtaText: String {
        primaryCreative?.ctaText ?? "Claim Offer"
    }
    
    /// Destination URL from primary creative (for tracking URL construction)
    var displayDestinationUrl: String? {
        primaryCreative?.destinationUrl
    }
    
    /// Tracking parameters from primary creative
    var displayTrackingParameters: [String: Any]? {
        primaryCreative?.trackingParameters
    }
    
    /// Full instructions from primary creative
    var displayInstructions: [Instruction] {
        primaryCreative?.instructions ?? []
    }
    
    /// Quick instructions from primary creative
    var displayQuickInstructions: String? {
        primaryCreative?.quickInstructions
    }
}


