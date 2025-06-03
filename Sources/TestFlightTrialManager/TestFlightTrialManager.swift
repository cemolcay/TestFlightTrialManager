import Foundation
import UIKit

/// Configuration for TestFlightTrialManager
public struct TrialConfiguration {
    /// Trial duration in seconds
    public let trialDuration: TimeInterval
    
    /// Password for unlocking beta mode
    public let password: String?
    
    /// Custom UserDefaults suite name
    public let userDefaultsSuiteName: String?
    
    /// Enable TestFlight simulation mode (DEBUG only)
    #if DEBUG
    public let simulationMode: Bool
    #endif
    
    /// Default configuration with 15 minutes trial
    public static let `default` = TrialConfiguration(
        trialDuration: 15 * 60,
        password: nil,
        userDefaultsSuiteName: nil,
        simulationMode: false
    )
    
    /// Initialize trial configuration
    /// - Parameters:
    ///   - trialDuration: Trial duration in seconds (default: 15 minutes)
    ///   - password: Password for unlocking beta mode
    ///   - userDefaultsSuiteName: Custom UserDefaults suite name
    ///   - simulationMode: Enable TestFlight simulation for development (DEBUG only)
    public init(
        trialDuration: TimeInterval = 15 * 60,
        password: String? = nil,
        userDefaultsSuiteName: String? = nil,
        simulationMode: Bool = false
    ) {
        self.trialDuration = trialDuration
        self.password = password
        self.userDefaultsSuiteName = userDefaultsSuiteName
        #if DEBUG
        self.simulationMode = simulationMode
        #endif
    }
}
public enum AppState {
    case production        // Released app store version
    case trial            // Active trial mode (TestFlight public beta)
    case expiredTrial     // Trial has expired
    case beta             // Unlocked beta mode (invited TestFlight users)
}

/// Notification names for trial events
public extension Notification.Name {
    static let trialDidExpire = Notification.Name("TestFlightTrialManager.trialDidExpire")
    static let trialTimeDidUpdate = Notification.Name("TestFlightTrialManager.trialTimeDidUpdate")
    static let trialStateDidChange = Notification.Name("TestFlightTrialManager.trialStateDidChange")
    static let trialCountdownPaused = Notification.Name("TestFlightTrialManager.trialCountdownPaused")
    static let trialCountdownResumed = Notification.Name("TestFlightTrialManager.trialCountdownResumed")
}

/// Keys for UserInfo in notifications
public struct TrialNotificationKeys {
    public static let remainingTime = "remainingTime"
    public static let newState = "newState"
    public static let previousState = "previousState"
    public static let totalPausedDuration = "totalPausedDuration"
}

/// Main singleton class for managing TestFlight trial functionality
public final class TestFlightTrialManager {
    
    // MARK: - Singleton
    public static var shared: TestFlightTrialManager = TestFlightTrialManager(configuration: .default)
    
    // MARK: - Private Properties
    private var timer: Timer?
    private var userDefaults: UserDefaults
    private var trialDuration: TimeInterval
    private var configuredPassword: String?
    private let configuration: TrialConfiguration
    
    #if DEBUG
    private var isSimulatingTestFlight: Bool
    #endif
    
    // MARK: - UserDefaults Keys
    private struct Keys {
        static let trialStartTime = "TestFlightTrial.startTime"
        static let trialDuration = "TestFlightTrial.duration"
        static let isTrialUnlocked = "TestFlightTrial.isUnlocked"
        static let configuredPassword = "TestFlightTrial.password"
        static let hasTrialStarted = "TestFlightTrial.hasStarted"
        static let isPaused = "TestFlightTrial.isPaused"
        static let pausedTime = "TestFlightTrial.pausedTime"
        static let lastPauseTime = "TestFlightTrial.lastPauseTime"
        static let totalPausedDuration = "TestFlightTrial.totalPausedDuration"
    }
    
    // MARK: - Public Properties
    
    /// Current state of the application
    public private(set) var currentState: AppState {
        didSet {
            if oldValue != currentState {
                NotificationCenter.default.post(
                    name: .trialStateDidChange,
                    object: self,
                    userInfo: [
                        TrialNotificationKeys.newState: currentState,
                        TrialNotificationKeys.previousState: oldValue
                    ]
                )
            }
        }
    }
    
    /// Remaining trial time in seconds (excluding paused time)
    public var remainingTrialTime: TimeInterval {
        guard isInTestFlight() && !isTrialUnlocked else { return 0 }
        
        let startTime = userDefaults.double(forKey: Keys.trialStartTime)
        guard startTime > 0 else { return trialDuration }
        
        let now = Date().timeIntervalSince1970
        let totalPausedDuration = self.totalPausedDuration
        
        // If currently paused, don't count the current pause session yet
        let currentSessionPausedTime: TimeInterval
        if isTrialPaused {
            let lastPauseTime = userDefaults.double(forKey: Keys.lastPauseTime)
            currentSessionPausedTime = max(0, now - lastPauseTime)
        } else {
            currentSessionPausedTime = 0
        }
        
        let totalElapsed = now - startTime
        let activeElapsed = totalElapsed - totalPausedDuration - currentSessionPausedTime
        
        return max(0, trialDuration - activeElapsed)
    }
    
    /// Whether trial countdown is currently paused
    public var isTrialPaused: Bool {
        return userDefaults.bool(forKey: Keys.isPaused)
    }
    
    /// Total time the trial has been paused (in seconds)
    public var totalPausedDuration: TimeInterval {
        return userDefaults.double(forKey: Keys.totalPausedDuration)
    }
    
    /// Whether trial mode is currently active
    public var isInTrialMode: Bool {
        return currentState == .trial
    }
    
    /// Whether trial has been unlocked with password
    public var isTrialUnlocked: Bool {
        return userDefaults.bool(forKey: Keys.isTrialUnlocked)
    }
    
    // MARK: - Initialization
    
    /// Initialize with configuration
    /// - Parameter configuration: Trial configuration
    public init(configuration: TrialConfiguration) {
        self.configuration = configuration
        self.trialDuration = configuration.trialDuration
        self.configuredPassword = configuration.password
        
        // Set up UserDefaults
        if let suiteName = configuration.userDefaultsSuiteName,
           let customDefaults = UserDefaults(suiteName: suiteName) {
            self.userDefaults = customDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        
        #if DEBUG
        self.isSimulatingTestFlight = configuration.simulationMode
        #endif
        
        self.currentState = .production
        
        // Save configuration to UserDefaults
        userDefaults.set(configuration.trialDuration, forKey: Keys.trialDuration)
        if let password = configuration.password {
            userDefaults.set(password, forKey: Keys.configuredPassword)
        }
        
        updateCurrentState()
        startTimerIfNeeded()
    }
    
    /// Configure the shared instance with new configuration
    /// - Parameter configuration: New trial configuration
    public static func configure(with configuration: TrialConfiguration) {
        shared = TestFlightTrialManager(configuration: configuration)
    }
    
    private init() {
        // Private init to prevent direct instantiation
        fatalError("Use TestFlightTrialManager(configuration:) or configure(with:) instead")
    }
    
    // MARK: - Public Configuration Methods
    
    /// Set the password for unlocking beta mode
    /// - Parameter password: The password string
    public func setPassword(_ password: String) {
        self.configuredPassword = password
        userDefaults.set(password, forKey: Keys.configuredPassword)
    }
    
    // MARK: - Trial Management
    
    /// Start the trial if in TestFlight and not already unlocked
    public func startTrialIfNeeded() {
        guard isInTestFlight() && !isTrialUnlocked else { return }
        
        let hasStarted = userDefaults.bool(forKey: Keys.hasTrialStarted)
        if !hasStarted {
            userDefaults.set(Date().timeIntervalSince1970, forKey: Keys.trialStartTime)
            userDefaults.set(true, forKey: Keys.hasTrialStarted)
            userDefaults.set(false, forKey: Keys.isPaused) // Start unpaused
            updateCurrentState()
            startTimerIfNeeded()
        }
    }
    
    /// Reset the trial time (for testing purposes)
    public func resetTrialTime() {
        userDefaults.removeObject(forKey: Keys.trialStartTime)
        userDefaults.removeObject(forKey: Keys.hasTrialStarted)
        userDefaults.removeObject(forKey: Keys.isPaused)
        userDefaults.removeObject(forKey: Keys.pausedTime)
        userDefaults.removeObject(forKey: Keys.lastPauseTime)
        userDefaults.removeObject(forKey: Keys.totalPausedDuration)
        updateCurrentState()
        startTimerIfNeeded()
    }
    
    /// Pause the trial countdown (call when app goes to background)
    public func pauseTrialCountdown() {
        guard isInTestFlight() && !isTrialUnlocked && currentState == .trial else { return }
        guard !isTrialPaused else { return } // Already paused
        
        userDefaults.set(true, forKey: Keys.isPaused)
        userDefaults.set(Date().timeIntervalSince1970, forKey: Keys.lastPauseTime)
        
        stopTimer()
        
        // Post notification
        NotificationCenter.default.post(
            name: .trialCountdownPaused,
            object: self
        )
        
        print("⏸️ Trial countdown paused")
    }
    
    /// Resume the trial countdown (call when app comes to foreground)
    public func resumeTrialCountdown() {
        guard isInTestFlight() && !isTrialUnlocked else { return }
        guard isTrialPaused else { return } // Not paused
        
        // Calculate and accumulate paused duration
        let lastPauseTime = userDefaults.double(forKey: Keys.lastPauseTime)
        if lastPauseTime > 0 {
            let pausedDuration = Date().timeIntervalSince1970 - lastPauseTime
            let totalPaused = userDefaults.double(forKey: Keys.totalPausedDuration)
            userDefaults.set(totalPaused + pausedDuration, forKey: Keys.totalPausedDuration)
        }
        
        userDefaults.set(false, forKey: Keys.isPaused)
        userDefaults.removeObject(forKey: Keys.lastPauseTime)
        
        updateCurrentState()
        startTimerIfNeeded()
        
        // Post notification
        NotificationCenter.default.post(
            name: .trialCountdownResumed,
            object: self,
            userInfo: [
                TrialNotificationKeys.remainingTime: remainingTrialTime,
                TrialNotificationKeys.totalPausedDuration: totalPausedDuration
            ]
        )
        
        print("▶️ Trial countdown resumed (total paused: \(Int(totalPausedDuration))s)")
    }
    
    /// Unlock trial mode with password
    /// - Parameter enteredPassword: The password entered by user
    /// - Returns: True if password is correct and trial is unlocked
    @discardableResult
    public func unlockTrial(with enteredPassword: String) -> Bool {
        guard let configuredPassword = self.configuredPassword,
              enteredPassword == configuredPassword else {
            return false
        }
        
        userDefaults.set(true, forKey: Keys.isTrialUnlocked)
        updateCurrentState()
        stopTimer()
        
        return true
    }
    
    /// Lock the trial (remove unlock status)
    public func lockTrial() {
        userDefaults.set(false, forKey: Keys.isTrialUnlocked)
        updateCurrentState()
        startTimerIfNeeded()
    }
    
    // MARK: - TestFlight Detection
    
    /// Check if the app is running in TestFlight environment (or simulated TestFlight in debug mode)
    /// - Returns: True if running in TestFlight or simulation mode
    public func isInTestFlight() -> Bool {
        #if DEBUG
        if isSimulatingTestFlight {
            return true
        }
        #endif
        
        #if targetEnvironment(simulator)
        return false // Simulators can't be TestFlight
        #else
        return isAppStoreReceiptSandbox() && !hasEmbeddedMobileProvision()
        #endif
    }
    
    private func hasEmbeddedMobileProvision() -> Bool{
        if let _ = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") {
            return true
        }
        return false
    }
    
    private func isAppStoreReceiptSandbox() -> Bool {
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL {
            if appStoreReceiptURL.lastPathComponent == "sandboxReceipt" {
                // Receipt exists, likely not a debug build
                #if DEBUG
                return false // Debug builds can also have sandboxReceipt
                #else
                return true
                #endif
            }
        }
        return false
    }
    
    // MARK: - Private Methods
    
    private func updateCurrentState() {
        let previousState = currentState
        
        if !isInTestFlight() {
            currentState = .production
        } else if isTrialUnlocked {
            currentState = .beta
        } else if remainingTrialTime <= 0 && userDefaults.bool(forKey: Keys.hasTrialStarted) {
            currentState = .expiredTrial
        } else {
            currentState = .trial
        }
        
        // Auto-start trial if we just detected TestFlight and haven't started yet
        if currentState == .trial && !userDefaults.bool(forKey: Keys.hasTrialStarted) {
            startTrialIfNeeded()
        }
    }
    
    private func startTimerIfNeeded() {
        guard currentState == .trial && !isTrialPaused else {
            stopTimer()
            return
        }
        
        stopTimer() // Stop existing timer
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let remaining = self.remainingTrialTime
            
            // Post time update notification
            NotificationCenter.default.post(
                name: .trialTimeDidUpdate,
                object: self,
                userInfo: [
                    TrialNotificationKeys.remainingTime: remaining,
                    TrialNotificationKeys.totalPausedDuration: self.totalPausedDuration
                ]
            )
            
            // Check if trial expired
            if remaining <= 0 {
                self.handleTrialExpiration()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func handleTrialExpiration() {
        stopTimer()
        updateCurrentState()
        
        // Post expiration notification
        NotificationCenter.default.post(
            name: .trialDidExpire,
            object: self
        )
    }
    
    deinit {
        stopTimer()
    }
}

// MARK: - Development & Testing Methods

#if DEBUG
public extension TestFlightTrialManager {
    
    /// Enable or disable TestFlight simulation mode (DEBUG only)
    /// - Parameter enabled: Whether to simulate TestFlight environment
    func simulateTestFlight(_ enabled: Bool) {
        isSimulatingTestFlight = enabled
        updateCurrentState()
        
        if enabled {
            startTimerIfNeeded()
        } else {
            stopTimer()
        }
        
        print("🧪 TestFlight simulation: \(enabled ? "ENABLED" : "DISABLED")")
    }
    
    /// Check if currently simulating TestFlight (DEBUG only)
    var isSimulatingTestFlightMode: Bool {
        return isSimulatingTestFlight
    }
    
    /// Simulate different app states for testing (DEBUG only)
    /// - Parameter state: The state to simulate
    func simulateState(_ state: AppState) {
        switch state {
        case .production:
            simulateTestFlight(false)
            
        case .trial:
            simulateTestFlight(true)
            lockTrial() // Ensure not unlocked
            resetTrialTime()
            startTrialIfNeeded()
            
        case .expiredTrial:
            simulateTestFlight(true)
            lockTrial() // Ensure not unlocked
            // Set start time to past to simulate expired trial
            userDefaults.set(Date().timeIntervalSince1970 - trialDuration - 1, forKey: Keys.trialStartTime)
            userDefaults.set(true, forKey: Keys.hasTrialStarted)
            
        case .beta:
            simulateTestFlight(true)
            if let password = configuredPassword {
                unlockTrial(with: password)
            } else {
                // Force unlock even without password for testing
                userDefaults.set(true, forKey: Keys.isTrialUnlocked)
            }
        }
        
        updateCurrentState()
        print("🧪 Simulated state: \(state)")
    }
    
    /// Set a custom trial duration for testing (DEBUG only)
    /// - Parameter seconds: Trial duration in seconds
    func setTestTrialDuration(_ seconds: TimeInterval) {
        trialDuration = seconds
        userDefaults.set(seconds, forKey: Keys.trialDuration)
        updateCurrentState()
        startTimerIfNeeded()
        print("🧪 Trial duration set to: \(Int(seconds)) seconds")
    }
    
    /// Reset all trial data and simulation state (DEBUG only)
    func resetAllTrialData() {
        stopTimer()
        
        // Reset trial data
        userDefaults.removeObject(forKey: Keys.trialStartTime)
        userDefaults.removeObject(forKey: Keys.hasTrialStarted)
        userDefaults.removeObject(forKey: Keys.isTrialUnlocked)
        userDefaults.removeObject(forKey: Keys.isPaused)
        userDefaults.removeObject(forKey: Keys.pausedTime)
        userDefaults.removeObject(forKey: Keys.lastPauseTime)
        userDefaults.removeObject(forKey: Keys.totalPausedDuration)
        
        // Reset simulation
        isSimulatingTestFlight = false
        
        updateCurrentState()
        print("🧪 All trial data reset")
    }
    
    /// Print current trial debug information (DEBUG only)
    func printDebugInfo() {
        print("🧪 === TestFlight Trial Manager Debug Info ===")
        print("🧪 Current State: \(currentState)")
        print("🧪 Is TestFlight (Real): \(Bundle.main.appStoreReceiptURL?.path.contains("sandboxReceipt") == true)")
        print("🧪 Is TestFlight (Simulated): \(isSimulatingTestFlight)")
        print("🧪 Is TestFlight (Combined): \(isInTestFlight())")
        print("🧪 Trial Duration: \(Int(trialDuration)) seconds")
        print("🧪 Remaining Time: \(Int(remainingTrialTime)) seconds (\(formattedRemainingTime))")
        print("🧪 Is Trial Unlocked: \(isTrialUnlocked)")
        print("🧪 Has Trial Started: \(userDefaults.bool(forKey: Keys.hasTrialStarted))")
        print("🧪 Is Trial Paused: \(isTrialPaused)")
        print("🧪 Total Paused Duration: \(Int(totalPausedDuration)) seconds")
        print("🧪 Trial Start Time: \(userDefaults.double(forKey: Keys.trialStartTime))")
        print("🧪 Configured Password: \(configuredPassword != nil ? "SET" : "NOT SET")")
        print("🧪 ==========================================")
    }
    
    /// Quick setup for common testing scenarios (DEBUG only)
    struct TestingHelpers {
        
        /// Create a configuration for testing active trial with short duration
        public static func shortTrialConfig() -> TrialConfiguration {
            return TrialConfiguration(
                trialDuration: 60,          // 1 minute
                password: "test123",
                simulationMode: true
            )
        }
        
        /// Create a configuration for testing expired trial
        public static func expiredTrialConfig() -> TrialConfiguration {
            return TrialConfiguration(
                trialDuration: 60,
                password: "test123",
                simulationMode: true
            )
        }
        
        /// Create a configuration for testing beta unlock
        public static func betaConfig() -> TrialConfiguration {
            return TrialConfiguration(
                trialDuration: 60,
                password: "test123",
                simulationMode: true
            )
        }
        
        /// Create a configuration for very quick testing
        public static func quickTestConfig() -> TrialConfiguration {
            return TrialConfiguration(
                trialDuration: 10,          // 10 seconds
                password: "quick",
                simulationMode: true
            )
        }
        
        /// Setup short trial scenario
        public static func setupShortTrial() {
            TestFlightTrialManager.configure(with: shortTrialConfig())
            TestFlightTrialManager.shared.simulateState(.trial)
            print("🧪 Setup: Short trial (1 minute)")
        }
        
        /// Setup expired trial scenario
        public static func setupExpiredTrial() {
            TestFlightTrialManager.configure(with: expiredTrialConfig())
            TestFlightTrialManager.shared.simulateState(.expiredTrial)
            print("🧪 Setup: Expired trial")
        }
        
        /// Setup beta unlocked scenario
        public static func setupBetaUnlocked() {
            TestFlightTrialManager.configure(with: betaConfig())
            TestFlightTrialManager.shared.simulateState(.beta)
            print("🧪 Setup: Beta unlocked")
        }
        
        /// Setup very quick test scenario
        public static func setupQuickTest() {
            TestFlightTrialManager.configure(with: quickTestConfig())
            TestFlightTrialManager.shared.simulateState(.trial)
            print("🧪 Setup: Quick test (10 seconds)")
        }
    }
}
#endif

// MARK: - UI Convenience Methods

#if canImport(UIKit)
import UIKit

public extension TestFlightTrialManager {
    
    /// Present a password prompt alert from the given view controller
    /// - Parameters:
    ///   - viewController: The view controller to present the alert from
    ///   - title: Custom title for the alert (optional)
    ///   - message: Custom message for the alert (optional)
    ///   - placeholder: Custom placeholder for the text field (optional)
    ///   - completion: Optional completion handler called with success/failure result
    func presentPasswordPrompt(
        from viewController: UIViewController,
        title: String = "Enter Beta Code",
        message: String = "Enter your beta access code to unlock full features",
        placeholder: String = "Beta code",
        completion: ((Bool) -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = placeholder
            textField.isSecureTextEntry = true
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        let unlockAction = UIAlertAction(title: "Unlock", style: .default) { [weak self] _ in
            guard let self = self,
                  let password = alert.textFields?.first?.text,
                  !password.isEmpty else {
                self?.presentInvalidPasswordAlert(from: viewController, completion: completion)
                return
            }
            
            if self.unlockTrial(with: password) {
                self.presentSuccessAlert(from: viewController, completion: completion)
            } else {
                self.presentInvalidPasswordAlert(from: viewController, completion: completion)
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion?(false)
        }
        
        alert.addAction(unlockAction)
        alert.addAction(cancelAction)
        
        // Set default action for better UX
        alert.preferredAction = unlockAction
        
        viewController.present(alert, animated: true)
    }
    
    /// Present success alert after successful password unlock
    /// - Parameters:
    ///   - viewController: The view controller to present the alert from
    ///   - title: Custom title for the success alert
    ///   - message: Custom message for the success alert
    ///   - completion: Optional completion handler
    private func presentSuccessAlert(
        from viewController: UIViewController,
        title: String = "Success!",
        message: String = "Beta access unlocked. You now have full access to all features.",
        completion: ((Bool) -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?(true)
        })
        
        viewController.present(alert, animated: true)
    }
    
    /// Present error alert for invalid password
    /// - Parameters:
    ///   - viewController: The view controller to present the alert from
    ///   - title: Custom title for the error alert
    ///   - message: Custom message for the error alert
    ///   - completion: Optional completion handler
    private func presentInvalidPasswordAlert(
        from viewController: UIViewController,
        title: String = "Invalid Code",
        message: String = "The beta code you entered is incorrect. Please try again.",
        completion: ((Bool) -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        let tryAgainAction = UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            // Present the password prompt again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.presentPasswordPrompt(from: viewController, completion: completion)
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion?(false)
        }
        
        alert.addAction(tryAgainAction)
        alert.addAction(cancelAction)
        
        alert.preferredAction = tryAgainAction
        
        viewController.present(alert, animated: true)
    }
    
    /// Present trial status information alert
    /// - Parameters:
    ///   - viewController: The view controller to present the alert from
    ///   - showUnlockOption: Whether to show unlock option for trial/expired states
    ///   - completion: Optional completion handler
    func presentTrialStatusAlert(
        from viewController: UIViewController,
        showUnlockOption: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        let title: String
        let message: String
        var showUnlock = showUnlockOption
        
        switch currentState {
        case .production:
            title = "Production Version"
            message = "You are using the production version of the app."
            showUnlock = false
            
        case .trial:
            title = "Trial Mode"
            message = "You are in trial mode with \(formattedRemainingTime) remaining."
            
        case .expiredTrial:
            title = "Trial Expired"
            message = "Your trial period has ended. Enter a beta code to unlock full access or upgrade to the full version."
            
        case .beta:
            title = "Beta Access"
            message = "You have full beta access with all features unlocked."
            showUnlock = false
        }
        
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        if showUnlock {
            alert.addAction(UIAlertAction(title: "Enter Beta Code", style: .default) { [weak self] _ in
                self?.presentPasswordPrompt(from: viewController, completion: completion)
            })
        }
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?(false)
        })
        
        viewController.present(alert, animated: true)
    }
}
#endif

// MARK: - Convenience Extensions

public extension TestFlightTrialManager {
    
    /// Formatted remaining time string (MM:SS)
    var formattedRemainingTime: String {
        let time = Int(remainingTrialTime)
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formatted total paused time string (MM:SS)
    var formattedPausedTime: String {
        let time = Int(totalPausedDuration)
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Check if trial is active (not expired, not unlocked, and not paused)
    var isTrialActive: Bool {
        return currentState == .trial && remainingTrialTime > 0 && !isTrialPaused
    }
    
    /// Check if trial is running (active or paused but not expired)
    var isTrialRunning: Bool {
        return currentState == .trial && remainingTrialTime > 0
    }
    
    /// Check if app is in any kind of beta mode (TestFlight)
    var isInBetaMode: Bool {
        return isInTestFlight()
    }
    
    /// Trial status description for UI display
    var trialStatusDescription: String {
        switch currentState {
        case .production:
            return "Production Version"
        case .trial:
            if isTrialPaused {
                return "Trial Paused - \(formattedRemainingTime) remaining"
            } else {
                return "Trial Active - \(formattedRemainingTime) remaining"
            }
        case .expiredTrial:
            return "Trial Expired"
        case .beta:
            return "Beta Access Unlocked"
        }
    }
}

// Sources/TestFlightTrialManager/TrialView+SwiftUI.swift

#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI View for displaying trial status
@available(iOS 14.0, macOS 10.15, *)
public struct TrialStatusView: View {
    @StateObject private var trialObserver = TrialObserver()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            switch TestFlightTrialManager.shared.currentState {
            case .production:
                Text("Production Version")
                    .foregroundColor(.primary)
                
            case .trial:
                VStack(spacing: 8) {
                    Text("Trial Mode")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Text("Time Remaining: \(TestFlightTrialManager.shared.formattedRemainingTime)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
            case .expiredTrial:
                Text("Trial Expired")
                    .foregroundColor(.red)
                    .font(.headline)
                
            case .beta:
                Text("Beta Version (Unlocked)")
                    .foregroundColor(.green)
                    .font(.headline)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Observable object for SwiftUI integration
@available(iOS 14.0, macOS 10.15, *)
public class TrialObserver: ObservableObject {
    @Published public var currentState: AppState
    @Published public var remainingTime: TimeInterval
    
    public init() {
        self.currentState = TestFlightTrialManager.shared.currentState
        self.remainingTime = TestFlightTrialManager.shared.remainingTrialTime
        
        NotificationCenter.default.addObserver(
            forName: .trialStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let newState = notification.userInfo?[TrialNotificationKeys.newState] as? AppState {
                self?.currentState = newState
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .trialTimeDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let time = notification.userInfo?[TrialNotificationKeys.remainingTime] as? TimeInterval {
                self?.remainingTime = time
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

#endif
