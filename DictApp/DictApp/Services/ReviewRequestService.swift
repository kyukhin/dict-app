// ReviewRequestService.swift
// Owns the smart-trigger heuristic for the in-app review prompt (Issue #12).
//
// Separation of concerns: this service decides WHETHER to prompt; the view layer
// decides HOW. Apple's `RequestReviewAction` is `@Environment`-bound and only
// callable from a SwiftUI `View`, so the actual `requestReview()` invocation
// lives in `DefinitionView`; the service just answers `shouldRequestReview()`.
//
// All counters persist through the `KeyValueStore` seam (Issue #6) so they
// survive launches. Foreground time is the sum of *banked* `.active` intervals
// (persisted) plus the *in-progress* interval (time since the app last became
// active). Counting the in-progress interval matters: the decision is evaluated
// from a definition view while the app is still active, so a user who never
// backgrounds the app would otherwise never pass the time gate. `now` is
// injectable so the clock is mockable in tests.

import Foundation

final class ReviewRequestService {
    static let shared = ReviewRequestService()

    /// At least this many definition views before any prompt is eligible.
    static let minSuccessfulSearches = 5

    /// Escalating cumulative active-foreground thresholds, in seconds. One prompt
    /// opportunity per threshold, at most one per session (Issue #12 Decisions:
    /// "once per session at most; Apple's annual cap handles long-term throttle").
    static let foregroundThresholds: [TimeInterval] = [30, 600, 3600]   // 30s · 10min · 60min

    private let store: KeyValueStore
    private let launchArguments: [String]
    private let now: () -> Date

    /// In-memory flag, resets every launch — enforces the once-per-session cap.
    private var promptFiredThisSession = false

    /// Start of the current uninterrupted `.active` interval, or nil between
    /// intervals. In-memory: the running interval is counted live (see
    /// `inProgressForegroundSeconds`) and banked when the app resigns active.
    private var activeSince: Date?

    // Persisted keys (namespaced; not touched by any other consumer).
    private let searchCountKey = "review_successful_search_count"
    private let foregroundSecondsKey = "review_cumulative_foreground_seconds"
    private let attemptsMadeKey = "review_attempts_made"
    private let promptFiredKey = "review_prompt_fired"

    /// Injectable for tests (in-memory `KeyValueStore`, explicit arguments, and a
    /// controllable clock); production uses `UserDefaults.standard`, the real
    /// process arguments, and the wall clock.
    init(store: KeyValueStore = UserDefaults.standard,
         launchArguments: [String] = CommandLine.arguments,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.launchArguments = launchArguments
        self.now = now
    }

    // MARK: - Persisted counters (Int/Double/Bool via the string seam)

    /// Count of definition-view appearances ("successful searches"). Read-only;
    /// mutated through `recordDefinitionView()`.
    var successfulSearchCount: Int {
        Int(store.string(forKey: searchCountKey) ?? "") ?? 0
    }

    /// Foreground seconds already banked to the store (excludes the in-progress
    /// interval).
    private var bankedForegroundSeconds: TimeInterval {
        Double(store.string(forKey: foregroundSecondsKey) ?? "") ?? 0
    }

    /// Elapsed time in the current `.active` interval, or 0 if not active.
    private var inProgressForegroundSeconds: TimeInterval {
        guard let activeSince else { return 0 }
        return max(0, now().timeIntervalSince(activeSince))
    }

    /// Total cumulative active-foreground time: banked + in-progress. This is
    /// what the heuristic gates on.
    var cumulativeForegroundSeconds: TimeInterval {
        bankedForegroundSeconds + inProgressForegroundSeconds
    }

    private var attemptsMade: Int {
        get { Int(store.string(forKey: attemptsMadeKey) ?? "") ?? 0 }
        set { store.set(String(newValue), forKey: attemptsMadeKey) }
    }

    /// Once-per-install latch: set once the three-attempt schedule is exhausted.
    private var reviewPromptFired: Bool {
        get { store.string(forKey: promptFiredKey) == "1" }
        set { store.set(newValue ? "1" : "0", forKey: promptFiredKey) }
    }

    // MARK: - Recording

    /// A definition view appeared — this project's definition of a "successful
    /// search" (Issue #12 Decisions).
    func recordDefinitionView() {
        store.set(String(successfulSearchCount + 1), forKey: searchCountKey)
    }

    /// The app became active (scene phase `.active`). Starts a foreground
    /// interval; idempotent so a rapid .active→.inactive→.active bounce doesn't
    /// reset an interval that's already running.
    func foregroundDidBecomeActive() {
        if activeSince == nil { activeSince = now() }
    }

    /// The app left the active phase. Banks the elapsed interval so it persists.
    func foregroundDidResignActive() {
        guard let activeSince else { return }
        bankForeground(now().timeIntervalSince(activeSince))
        self.activeSince = nil
    }

    /// Directly bank a foreground duration. Used by the resign path above and by
    /// tests that want to seed banked time without the clock.
    func recordForeground(duration: TimeInterval) {
        bankForeground(duration)
    }

    private func bankForeground(_ duration: TimeInterval) {
        guard duration > 0 else { return }   // ignore non-positive (clock glitch)
        store.set(String(bankedForegroundSeconds + duration), forKey: foregroundSecondsKey)
    }

    // MARK: - Decision

    /// Whether the view should invoke `requestReview()` now. Pure read — calling
    /// it has no side effects; the view calls `markPromptFired()` only if it acts.
    func shouldRequestReview() -> Bool {
        if launchArguments.contains("-disableReviewPrompt") { return false }
        if reviewPromptFired { return false }                       // schedule exhausted
        if promptFiredThisSession { return false }                  // once per session
        if successfulSearchCount < Self.minSuccessfulSearches { return false }
        let nextAttempt = attemptsMade
        guard nextAttempt < Self.foregroundThresholds.count else { return false }
        return cumulativeForegroundSeconds >= Self.foregroundThresholds[nextAttempt]
    }

    /// Record that the view fired the prompt: consume this session and this
    /// threshold, and latch the once-per-install stop after the final attempt.
    /// Call immediately before `requestReview()` in the view.
    func markPromptFired() {
        promptFiredThisSession = true
        attemptsMade += 1
        if attemptsMade >= Self.foregroundThresholds.count {
            reviewPromptFired = true
        }
    }

    /// Clear all persisted review state. Wired to the `-resetData` launch path so
    /// UI-test runs start from a clean slate (counters otherwise persist across
    /// launches and could accumulate past the threshold mid-suite).
    func resetPersistedState() {
        store.removeObject(forKey: searchCountKey)
        store.removeObject(forKey: foregroundSecondsKey)
        store.removeObject(forKey: attemptsMadeKey)
        store.removeObject(forKey: promptFiredKey)
        // NOTE: deliberately does NOT touch `activeSince`. This runs under the
        // `-resetData` launch path *during* app init — after the app root's
        // `.task` has already started the foreground interval — so clearing it
        // here would silently stop foreground time ever accruing (the scene
        // stays active, so no later edge restarts it) and the prompt would never
        // fire. `activeSince` is in-memory session state, not persisted state.
    }
}
