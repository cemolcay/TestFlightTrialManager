//
//  ViewController.swift
//  TestFlightTrialManager
//
//  Created by Cem Olcay on 6/2/25.
//

import UIKit
import TestFlightTrialManager

extension UIView {
    var parentViewController: UIViewController? {
        sequence(first: self) { $0.next }
            .compactMap{ $0 as? UIViewController }
            .first
    }
}

class AppView: UIView {
    let stateLabel = UILabel()
    let unlockButton = UIButton(type: .system)
    
    init() {
        super.init(frame: .zero)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    func commonInit() {
        let layout = UIStackView()
        
        addSubview(layout)
        layout.translatesAutoresizingMaskIntoConstraints = false
        layout.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        layout.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        layout.axis = .vertical
        layout.alignment = .center
        layout.distribution = .fill
        layout.spacing = 8

        let label = UILabel()
        label.text = "Awesome app and its full features here"
        
        unlockButton.setTitle("Unlock Trial", for: .normal)
        unlockButton.addTarget(self, action: #selector(unlockButtonPressed(sender:)), for: .primaryActionTriggered)

        layout.addArrangedSubview(label)
        layout.addArrangedSubview(stateLabel)
        layout.addArrangedSubview(unlockButton)
        
        updateTrialMode()
        
        // Time updates (every second during trial)
        NotificationCenter.default.addObserver(forName: .trialTimeDidUpdate, object: nil, queue: .main) { notification in
            let remaining = TestFlightTrialManager.shared.formattedRemainingTime
            self.stateLabel.text = "Trial Mode (\(remaining))"
        }
    }
    
    @IBAction func unlockButtonPressed(sender: UIButton) {
        guard let parentViewController else { return }
        TestFlightTrialManager.shared.presentPasswordPrompt(from: parentViewController)
    }
    
    func updateTrialMode() {
        switch TestFlightTrialManager.shared.currentState {
        case .production:
            unlockButton.isHidden = true
            stateLabel.text = "Full features - release mode"
        case .trial:
            unlockButton.isHidden = false
            stateLabel.text = "Trial Mode"
        case .expiredTrial:
            unlockButton.isHidden = false
            stateLabel.text = "Trial expired (you shouldn't see that!)"
        case .beta:
            stateLabel.text = "Beta Mode"
            unlockButton.isHidden = true
        }
    }
}

class TrialOverView: UIView {
    let unlockButton = UIButton(type: .system)
    
    init() {
        super.init(frame: .zero)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    func commonInit() {
        let layout = UIStackView()
        
        addSubview(layout)
        layout.translatesAutoresizingMaskIntoConstraints = false
        layout.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        layout.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        layout.axis = .vertical
        layout.alignment = .center
        layout.distribution = .fill
        layout.spacing = 8

        let label = UILabel()
        label.text = "Trial mode has expired"

        unlockButton.setTitle("Unlock Trial", for: .normal)
        unlockButton.addTarget(self, action: #selector(unlockButtonPressed(sender:)), for: .primaryActionTriggered)

        layout.addArrangedSubview(label)
        layout.addArrangedSubview(unlockButton)
    }
    
    @IBAction func unlockButtonPressed(sender: UIButton) {
        guard let parentViewController else { return }
        TestFlightTrialManager.shared.presentPasswordPrompt(from: parentViewController)
    }
}

class ViewController: UIViewController {
    let appView = AppView()
    let trialOverView = TrialOverView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(appView)
        appView.translatesAutoresizingMaskIntoConstraints = false
        appView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor).isActive = true
        appView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor).isActive = true
        appView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        appView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        
        view.addSubview(trialOverView)
        trialOverView.translatesAutoresizingMaskIntoConstraints = false
        trialOverView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor).isActive = true
        trialOverView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor).isActive = true
        trialOverView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        trialOverView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        
    
        setupTrialMode()
        updateTrialMode()
    }
    
    func setupTrialMode() {
        // Configure trial manager
        TestFlightTrialManager.configure(with: .init(
            trialDuration: 1 * 60,      // 1 minute
            password: "pass",           // Password for invited beta users
            userDefaultsSuiteName: nil, // Optional custom UserDefaults suite
            simulationMode: true        // simulate testflight for developemnt
        ))
        
        // For development reset trial on start
        TestFlightTrialManager.shared.lockTrial()
        TestFlightTrialManager.shared.resetTrialTime()
        TestFlightTrialManager.shared.startTrialIfNeeded()
        
        // Trial expiration
        NotificationCenter.default.addObserver(forName: .trialDidExpire, object: nil, queue: .main) { _ in
            // Handle trial expiration - show upgrade screen, disable features, etc.
            self.updateTrialMode()
        }

        // State changes
        NotificationCenter.default.addObserver(forName: .trialStateDidChange, object: nil, queue: .main) { notification in
            if notification.userInfo?[TrialNotificationKeys.newState] is AppState {
                // Update UI based on new state
                self.updateTrialMode()
            }
        }
    }
    
    func updateTrialMode() {
        appView.updateTrialMode()

        switch TestFlightTrialManager.shared.currentState {
        case .production, .trial, .beta:
            trialOverView.isHidden = true
            appView.isHidden = false
        case .expiredTrial:
            trialOverView.isHidden = false
            appView.isHidden = true
        }
    }
}

