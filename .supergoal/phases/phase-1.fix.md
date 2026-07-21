SUPERGOAL_PHASE_START
Phase: 1 fix — Correct the shared-state regression fixture
Task: Seed the prior durable SharedStepData before exercising a failed goal save
Mandatory commands: phase-1 targeted xcodebuild command
Acceptance criteria: 1
Evidence required: failed-save test observes the unchanged 9,000 goal in service, persistence, and shared state
Depends on phases: none

Scope is restricted to the failing phase-1 test fixture. Do not touch unrelated files or production behavior.

Acceptance criterion: the original phase-1 verification passes after explicitly seeding the durable shared snapshot that the failed save must preserve.
