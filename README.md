# TestFlightTrialManager

A comprehensive Swift package for managing trial modes in TestFlight beta distributions. This package allows you to provide time-limited trial access to public beta users while giving full access to invited beta testers through a password system.

## Features

- ✅ **Configuration-Based Setup**: Clean, explicit configuration with `TrialConfiguration`
- ✅ **Trial Duration Management**: Set custom trial periods (e.g., 15 minutes)
- ✅ **TestFlight Detection**: Automatically detects if running in TestFlight environment
- ✅ **Development Simulation**: Simulate TestFlight conditions during development (DEBUG only)
- ✅ **Password-Based Unlocking**: Allow invited beta users to unlock full access
- ✅ **State Management**: Track production, trial, expired trial, and beta states
- ✅ **Persistent Storage**: Uses UserDefaults with optional custom suite names
- ✅ **Notification System**: Real-time updates for trial events
- ✅ **Built-in UI Methods**: Ready-to-use password prompts and status alerts
- ✅ **SwiftUI Support**: Ready-to-use SwiftUI components
- ✅ **Timer Management**: Automatic countdown with expiration handling
- ✅ **Debug Utilities**: Comprehensive testing tools and scenarios

## Installation

### Swift Package Manager

Add this package to your Xcode project:

1. File → Add Package Dependencies
2. Enter the repository URL
3. Select version/branch
4. Add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/cemolcay/TestFlightTrialManager.git", from: "1.0.0")
]
```

## Quick Start

### 1. Configuration-Based Setup

In your `AppDelegate` or `SceneDelegate`:

```swift
import TestFlightTrialManager

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
    // Create trial configuration
    let config = TrialConfiguration(
        trialDuration: 15 * 60,                          // 15 minutes
        password: "beta2024",                            // Password for invited beta users
        userDefaultsSuiteName: "com.yourapp.trial"      // Optional custom UserDefaults suite
        #if DEBUG
        , simulationMode: true                           // Enable TestFlight simulation for development
        #endif
    )
    
    // Configure the manager
    TestFlightTrialManager.configure(with: config)
    
    // Start trial if in TestFlight and not unlocked
    TestFlightTrialManager.shared.startTrialIfNeeded()
    
    return true
}
```

### 2. Different Configuration Examples

```swift
// Minimal configuration
let config = TrialConfiguration(
    trialDuration: 10 * 60,  // 10 minutes
    password: "mybeta"
)

// Production configuration
let productionConfig = TrialConfiguration(
    trialDuration: 15 * 60,
    password: "prod_beta_2024",
    userDefaultsSuiteName: "com.myapp.trial"
)

// Development configuration with simulation
#if DEBUG
let devConfig = TrialConfiguration(
    trialDuration: 60,       // 1 minute for quick testing
    password: "dev123",
    simulationMode: true     // No need for actual TestFlight
)
#endif

// Apply configuration
TestFlightTrialManager.configure(with: config)
```

### 2. Listen for Trial Events

```swift
// Trial expiration
NotificationCenter.default.addObserver(forName: .trialDidExpire, object: nil, queue: .main) { _ in
    // Handle trial expiration - show upgrade screen, disable features, etc.
}

// State changes
NotificationCenter.default.addObserver(forName: .trialStateDidChange, object: nil, queue: .main) { notification in
    if let newState = notification.userInfo?[TrialNotificationKeys.newState] as? AppState {
        // Update UI based on new state
    }
}

// Time updates (every second during trial)
NotificationCenter.default.addObserver(forName: .trialTimeDidUpdate, object: nil, queue: .main) { notification in
    if let remaining = notification.userInfo?[TrialNotificationKeys.remainingTime] as? TimeInterval {
        // Update countdown display
    }
}
```

### 3. Feature Gating

```swift
func accessPremiumFeature() {
    let manager = TestFlightTrialManager.shared
    
    switch manager.currentState {
    case .production:
        // Check actual subscription status
        if UserSubscriptionManager.hasActiveSubscription {
            enableFeature()
        } else {
            showUpgradePrompt()
        }
    case .trial:
        if manager.isTrialActive {
            enableFeature()
        } else {
            showTrialExpiredMessage()
        }
    case .expiredTrial:
        showTrialExpiredMessage()
    case .beta:
        enableFeature() // Full access for beta users
    }
}
```

### 4. Password Unlock UI (Simple Method)

The easiest way to implement password unlock is using the built-in UI methods:

```swift
@IBAction func unlockButtonTapped(_ sender: UIButton) {
    // One-liner with automatic success/error handling
    TestFlightTrialManager.shared.presentPasswordPrompt(from: self) { success in
        if success {
            print("Beta access unlocked!")
            // UI updates automatically via notifications
        }
    }
}

// Or show a comprehensive status alert with unlock option
@IBAction func showStatusTapped(_ sender: UIButton) {
    TestFlightTrialManager.shared.presentTrialStatusAlert(from: self)
}
```

### 4. Password Unlock UI (Custom Implementation)

For custom UI implementation:

```swift
@IBAction func unlockButtonTapped(_ sender: UIButton) {
    let alert = UIAlertController(title: "Enter Beta Code", message: nil, preferredStyle: .alert)
    
    alert.addTextField { textField in
        textField.placeholder = "Beta code"
        textField.isSecureTextEntry = true
    }
    
    alert.addAction(UIAlertAction(title: "Unlock", style: .default) { _ in
        guard let password = alert.textFields?.first?.text else { return }
        
        if TestFlightTrialManager.shared.unlockTrial(with: password) {
            // Success! UI will update automatically via notifications
        } else {
            // Show error message
        }
    })
    
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
}
```

## API Reference

### AppState Enum

```swift
public enum AppState {
    case production     // App Store release version
    case trial         // Active trial mode (TestFlight public beta)
    case expiredTrial  // Trial has expired
    case beta          // Unlocked beta mode (invited TestFlight users)
}
```

### TrialConfiguration

```swift
public struct TrialConfiguration {
    public let trialDuration: TimeInterval
    public let password: String?
    public let userDefaultsSuiteName: String?
    #if DEBUG
    public let simulationMode: Bool
    #endif
    
    // Default configuration (15 minutes, no password)
    public static let `default`: TrialConfiguration
    
    // Initialize with custom settings
    public init(
        trialDuration: TimeInterval = 15 * 60,
        password: String? = nil,
        userDefaultsSuiteName: String? = nil
        #if DEBUG
        , simulationMode: Bool = false
        #endif
    )
}
```

### TestFlightTrialManager

#### Configuration

```swift
// Configure the shared instance
static func configure(with configuration: TrialConfiguration)

// Initialize with configuration (for custom instances)
init(configuration: TrialConfiguration)

// Set password for beta unlock
func setPassword(_ password: String)
```

#### Trial Management

```swift
// Start trial if needed
func startTrialIfNeeded()

// Reset trial time (for testing)
func resetTrialTime()

// Unlock with password
func unlockTrial(with enteredPassword: String) -> Bool

// Lock trial (remove unlock)
func lockTrial()
```

#### State Checking

```swift
// Check if in TestFlight
func isInTestFlight() -> Bool

// Current app state
var currentState: AppState { get }

// Trial status
var isInTrialMode: Bool { get }
var isTrialActive: Bool { get }
var isTrialUnlocked: Bool { get }

// Time remaining
var remainingTrialTime: TimeInterval { get }
var formattedRemainingTime: String { get }
```

#### UI Convenience Methods (UIKit)

```swift
// Present password prompt with automatic error/success handling
func presentPasswordPrompt(
    from viewController: UIViewController,
    title: String = "Enter Beta Code",
    message: String = "Enter your beta access code to unlock full features",
    placeholder: String = "Beta code",
    completion: ((Bool) -> Void)? = nil
)

// Present trial status information with optional unlock
func presentTrialStatusAlert(
    from viewController: UIViewController,
    showUnlockOption: Bool = true,
    completion: ((Bool) -> Void)? = nil
)
```

### Notifications

| Notification | UserInfo Keys | Description |
|--------------|---------------|-------------|
| `.trialDidExpire` | - | Posted when trial time expires |
| `.trialTimeDidUpdate` | `remainingTime: TimeInterval` | Posted every second during trial |
| `.trialStateDidChange` | `newState: AppState`<br>`previousState: AppState` | Posted when state changes |

## SwiftUI Integration

Use the provided `TrialStatusView` for easy SwiftUI integration:

```swift
import SwiftUI
import TestFlightTrialManager

struct ContentView: View {
    var body: some View {
        VStack {
            TrialStatusView()
            
            // Your app content
        }
    }
}
```

For custom UI, use `TrialObserver`:

```swift
struct CustomTrialView: View {
    @StateObject private var trialObserver = TrialObserver()
    
    var body: some View {
        VStack {
            Text("State: \(trialObserver.currentState)")
            Text("Time: \(Int(trialObserver.remainingTime))")
        }
    }
}
```

## How It Works

### TestFlight Detection

The package detects TestFlight environment by checking the app store receipt path:

```swift
func isInTestFlight() -> Bool {
    guard let path = Bundle.main.appStoreReceiptURL?.path else {
        return false
    }
    return path.contains("sandboxReceipt")
}
```

### State Logic

1. **Production**: Not running in TestFlight
2. **Trial**: In TestFlight, not unlocked, trial time remaining
3. **ExpiredTrial**: In TestFlight, not unlocked, trial time expired
4. **Beta**: In TestFlight, unlocked with password

### Data Persistence

All trial data is stored in UserDefaults:

- Trial start time
- Trial duration
- Unlock status
- Configured password
- Trial started flag

## Distribution Strategy

### For Public Beta (Trial Mode)
1. Upload build to TestFlight
2. Enable public beta testing
3. Users get limited trial access

### For Invited Beta (Full Access)
1. Same TestFlight build
2. Invite specific testers
3. Provide password to unlock full features
4. Testers enter password to get unrestricted access

## Testing & Development

### TestFlight Simulation (Configuration-Based)

Set up simulation mode directly in your configuration:

```swift
#if DEBUG
let config = TrialConfiguration(
    trialDuration: 60,        // 1 minute for quick testing
    password: "test123",      // Test password
    simulationMode: true      // Enable TestFlight simulation
)
TestFlightTrialManager.configure(with: config)

// Test different states
TestFlightTrialManager.shared.simulateState(.trial)
TestFlightTrialManager.shared.printDebugInfo()
#endif
```

### Development vs Production Configuration

```swift
func setupTrialManager() {
    #if DEBUG
    // Development configuration with simulation
    let config = TrialConfiguration(
        trialDuration: 30,           // 30 seconds for quick testing
        password: "dev123",          // Development password
        simulationMode: true         // Simulate TestFlight
    )
    #else
    // Production configuration
    let config = TrialConfiguration(
        trialDuration: 15 * 60,      // 15 minutes
        password: "beta2024",        // Production password
        userDefaultsSuiteName: "com.yourapp.trial"
        // simulationMode not available in release builds
    )
    #endif
    
    TestFlightTrialManager.configure(with: config)
}
```

### Quick Testing Scenarios

```swift
#if DEBUG
// Quick development setups
func setupQuickTesting() {
    let config = TrialConfiguration(
        trialDuration: 10,           // 10 seconds
        password: "quick",
        simulationMode: true
    )
    TestFlightTrialManager.configure(with: config)
    TestFlightTrialManager.shared.simulateState(.trial)
}

func setupExpiredTrialTesting() {
    let config = TrialConfiguration(
        trialDuration: 60,
        password: "test",
        simulationMode: true
    )
    TestFlightTrialManager.configure(with: config)
    TestFlightTrialManager.shared.simulateState(.expiredTrial)
}
#endif
```

### Debug Methods (Debug builds only)

```swift
#if DEBUG
// Enable/disable TestFlight simulation (set via configuration)
var isSimulatingTestFlightMode: Bool

// Simulate different states
func simulateState(_ state: AppState)

// Set short trial for testing
func setTestTrialDuration(_ seconds: TimeInterval)

// Reset all data
func resetAllTrialData()

// Debug information
func printDebugInfo()

// Testing helpers for configurations
TestFlightTrialManager.TestingHelpers.shortTrialConfig()
TestFlightTrialManager.TestingHelpers.quickTestConfig()
TestFlightTrialManager.TestingHelpers.setupShortTrial()
TestFlightTrialManager.TestingHelpers.setupQuickTest()
#endif
```

### Testing Scenarios

#### 1. **Development Testing** (Simulator/Device without TestFlight)
```swift
#if DEBUG
TestFlightTrialManager.shared.simulateTestFlight(true)
TestFlightTrialManager.TestingScenarios.shortTrial()
#endif
```

#### 2. **TestFlight Public Beta** 
- Install via public TestFlight link
- Verify trial starts automatically
- Test trial expiration flow

#### 3. **TestFlight Invited Beta**
- Install via invitation
- Test password unlock functionality
- Verify full access after unlock

#### 4. **App Store Build**
- Verify production state (no trial functionality)
- Ensure no TestFlight-specific features are active

## Best Practices

### 1. Trial Duration
- Start with shorter trials (15-30 minutes) to encourage quick decision-making
- Consider your app's core value proposition timing

### 2. Password Management
- Use meaningful but secure passwords
- Consider different passwords for different beta groups
- Document passwords clearly for beta testers

### 3. User Experience
- Show trial time prominently but not intrusively
- Provide clear upgrade/unlock paths
- Explain value proposition before trial expires

### 4. Feature Gating
- Gate premium features consistently
- Provide clear messaging about trial limitations
- Maintain core functionality during trial

## Troubleshooting

### Common Issues

**Trial not starting in TestFlight**
- Verify TestFlight detection is working: `isInTestFlight()`
- Check if trial was already started/expired
- Use `resetTrialTime()` for testing

**Password unlock not working**
- Verify password was set correctly
- Check for case sensitivity
- Ensure no extra whitespace in input

**Timer not updating**
- Verify app is in foreground (timer pauses in background)
- Check notification observers are set up correctly
- Ensure proper memory management (no retain cycles)

**UserDefaults not persisting**
- Verify custom suite name is correct
- Check app permissions
- Ensure UserDefaults are being synchronized

### Debug Information

```swift
// Print current state information
let manager = TestFlightTrialManager.shared
print("Current state: \(manager.currentState)")
print("Is TestFlight: \(manager.isInTestFlight())")
print("Remaining time: \(manager.remainingTrialTime)")
print("Is unlocked: \(manager.isTrialUnlocked)")
```

## Requirements

- iOS 12.0+ / macOS 10.15+
- Swift 5.7+
- Xcode 14.0+

## License

[Your License Here]

## Contributing

[Your contribution guidelines here]
