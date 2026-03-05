# Changelog

All notable changes to the Encore Swift SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.7] - 2026-01-07

### Added
- 

### Changed
- 

### Fixed
- Fixed PostHog events not being sent when the app also uses PostHog 


## [1.2.6] - 2025-12-12

### Added
- Added in a bunch more events for analytics 

### Changed
- Removed instructions under offers

### Fixed
- 


## [1.2.5] - 2025-12-05

### Added
- Allow developers to change Entitlement Type/Duration and Appearance SDK  

### Changed
- 

### Fixed
- 


## [1.2.4] - 2025-12-05

### Added
- Allow developers to change Entitlement Type/Duration and Appearance SDK  

### Changed
- 

### Fixed
- 


## [1.2.4] - 2025-12-04

### Added
- Increased capability to customize the UI and appearance of the Encore modal via title composability and accenting.

### Changed
- 

### Fixed
- 

## [1.2.3] - 2025-11-12

### Added
- Interactive release script with semantic versioning
- Automated changelog management
- IAP integration for iOS 15+ with StoreKit 2
- Modular OfferSheet architecture with separate files for better maintainability
- Centralized style guide (`OfferSheetStyles`) for consistent design tokens

### Changed
- Refactored `OfferSheetView` into modular components (6 focused files)
- Improved Safari dismissal handling with single source of truth (`.onDisappear`)
- Enhanced completion handler to coordinate with dismiss animations

### Fixed
- Safari sheet dismissal now properly triggers completion handler
- Carousel card dimensions remain consistent across sheet detents
- Instructions text properly overflows without compressing carousel

## [1.1.2] - 2025-10-01

### Added
- Initial SDK release
- Offer presentation with SwiftUI (iOS 17+)
- Legacy UIKit support (iOS 13-16)
- Entitlement management system
- Analytics tracking integration
- Server-driven UI configuration

