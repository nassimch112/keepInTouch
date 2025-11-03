# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-11-03
### Added
- MVP with People, Interactions, Due/Upcoming list, search, swipe actions with undo.
- Background scheduling and notifications (daily + per-person nudges).
- Calendar tab with dot indicators, Today button, device calendar overlay.
- Stats screen (totals, initiator split, leaderboard).
- Device calendar import (idempotent, date range, calendar selection).
- Settings: reminders, haptics, theme presets, calendar toggle, export JSON.
- Onboarding splash; double-back-to-exit; safe permission flows.

### Fixed
- Calendar cell overflow with device events badge.
- Splash opacity clamp; permission reliability across OEMs.

### Changed
- Calendar person cards redesigned to clean ListTile style.