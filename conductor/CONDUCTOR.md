# CONDUCTOR: Project Synchronization Protocol

## Strict Core Instructions
1.  **Source of Truth**: Always refer ONLY to the codebase and its comments for the current state of logic.
2.  **UI Data Fetching**: UI must always fetch from the database/services. If UI is wrong, the backend/code logic is likely wrong.
3.  **Documentation Warning**: DO NOT refer to MD files (Blueprint, Specs, etc.) for current logic as they are lagging. Refer to this Conductor or the code.
4.  **Implementation Alignment**: Update according to approved Implementation Plan artifacts.
5.  **Tracking**: Record all new approved and implemented changes in this directory.

## Approved & Implemented Changes
- **Model Transition**: 10-Epoch TGE Model (10x scaling per epoch).
- **Supply Cap**: 1 Quadrillion (1QD) Absolute Supply.
- **Allocation**: 50% User (Miner) / 50% Treasury split.
- **Genesis Gate (Individual)**: 100,000 DSP (TGE threshold).
- **TGE Efficiency**: Decile-based sliding scale (10% per 10 Trust points).

## Implemented UI Refinements
- [x] Dashboard: Expand Epoch Roadmap to 10 steps.
- [x] Dashboard: Fix `TGE Efficiency` display to match decile scale (30 Trust = 30%).
- [x] Dashboard: Update scale labels (1QD Supply, 100B Members).
- [x] Trust Tab: Update Efficiency Gate table to 10-step scale (Already correct in UI).
- [x] Global: Synchronize 100,000 DSP Genesis Gate label across all screens.

## Professional Development Setup (Implemented Feb 2026)
- [x] **Git Flow**: main/develop branching strategy with feature/bugfix/hotfix branches
- [x] **CI/CD Pipeline**: GitHub Actions for automated testing, analysis, and PR validation
- [x] **Interface Documentation**: Service contracts for core features (DSP, Community, Profile, Trust, Chat)
- [x] **Testing Framework**: Unit, widget, and integration tests with comprehensive test utilities
- [x] **Documentation**: CONTRIBUTING.md with workflow, test/README.md with testing guide

