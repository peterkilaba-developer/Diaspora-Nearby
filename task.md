# DiasporaNearby Task Tracker

## Active Tasks
- [ ] **Data Model Audit**
    - [x] Audit `users` collection vs `ProfileData`
    - [x] Audit `communities` collection vs `Community`
    - [x] Audit `events` collection vs `Event`
    - [x] Audit `points_transactions` vs `PointsTransaction`
    - [x] Audit `referral_codes`
- [x] **DSP Earning & Trust Logic Implementation**
    - [x] Create `DSP_EARNING_MODEL.md` specification.
    - [x] Refactor `PointsService` to use new reward values (1200 welcome, 120 Msg, etc).
    - [x] Implement "Justice System" (Rejection penalties).
    - [x] Fix compilation errors in `PointsService` (restore missing methods).
    - [x] Fix `UserPoints` model missing field.
    - [x] Implement `TrustService` "Trust Slider" logic (Backend & UI).
    - [x] Implement "Trust-Anchored Decay" logic.
    - [x] Implement "Bereavement Fund" protocol.
    - [x] Implement "Vouching" visualization.
    - [x] Enforce PoCT Eligibility (10k DSP, Complete Profile, 50 Trust Score).
    - [x] Refine Bereavement Fund (Rebranding, Verified Proxies, Strict Joining).
- [x] **DSP UI/UX Refinement**
    - [x] Update `DiasporaCryptoScreen` with latest landing page copy.
    - [x] Update `PointsSystemScreen` with referral card and TGE progress.
    - [x] Integrate `ExplorationProgressCard`.
    - [x] Add "View Detailed Earning Guide" modal.
    - [x] Update `ShareInviteScreen` rewards and add TGE progress bar.
    - [x] Implement auto-generation of referral codes on landing.
- [x] **Community Tribute & TGE Preparation**
    - [x] Update `Community` model with `points` and `walletAddress`.
    - [x] Implement 1% Tribute Logic in `PointsService`.
    - [x] Enhance `PointsRepository` with community transaction support.
    - [x] Define Token Allocation Table (Founders, Team, Treasury).
    - [x] Complete `DSP_TGE_FEASIBILITY.md` study.
- [ ] **Integrating Elections into Chat**
    - [x] Locate chat screen and header implementation.
    - [x] Verify "Pillar Elections" menu item in `_showMoreMenu`.
    - [x] Verify link to `PillarSelectionScreen` for voting.
    - [ ] Perform final verification and polish UI/UX.

## Completed Audits
- [x] Integrate Location and Education fields in `CompleteProfileForm`.
- [x] Final code review and verification of all QR/Profile flows.
- [x] Profile Completeness Getter implementation.
- [x] Relationship-based verification blocking.
- [x] Verification/Vouching daily limits enforcement.

## Phase 8: Refactor for DRY
- [x] Create implementation plan for unified `UserProfileForm`.
- [x] Extract `UserProfileForm` logic from `UserProfileEditor`.
- [x] Incorporate validation and "missing fields" highlighting into `UserProfileForm`.
- [x] Update `UserProfileEditor` to use the new `UserProfileForm`.
- [x] Update `ProfileQRCodeDialog` and `CompleteProfileModal` to use `UserProfileForm`.
- [x] Delete `CompleteProfileForm.dart`.
- [x] Verify both "Complete Profile" and "Edit Profile" flows.
- [x] Refine Education fields (Google Places, Dropdowns) and add safe area padding.
- [x] Add "No School" checkbox and hide/show fields logic.
- [x] Fix Degree dropdown overflow and update title to "School/College/University".
- [x] Remove "Since Birth" from Graduation Year dropdown.
