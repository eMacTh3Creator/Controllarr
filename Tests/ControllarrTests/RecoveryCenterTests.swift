//
//  RecoveryCenterTests.swift
//  ControllarrTests
//

import Testing
import Foundation
import Persistence
@testable import Services

@Test func testRecoveryPlanMatchesEligibleEnabledRule() {
    let now = Date()
    let issues = [
        RecoveryCenter.Issue(
            infoHash: "hash-1",
            name: "Example Torrent",
            trigger: .noPeers,
            firstSeen: now.addingTimeInterval(-3_600)
        )
    ]
    let rules = [
        RecoveryRule(
            enabled: true,
            trigger: .noPeers,
            action: .pause,
            delayMinutes: 30
        )
    ]

    let plan = RecoveryCenter.plan(
        issues: issues,
        rules: rules,
        at: now,
        appliedAutomaticRules: [:]
    )

    #expect(plan.count == 1)
    #expect(plan.first?.infoHash == "hash-1")
    #expect(plan.first?.action == .pause)
    #expect(plan.first?.reason == .noPeers)
}

@Test func testRecoveryPlanSkipsAlreadyAppliedOrDisabledRules() {
    let now = Date()
    let issues = [
        RecoveryCenter.Issue(
            infoHash: "hash-1",
            name: "Example Torrent",
            trigger: .metadataTimeout,
            firstSeen: now.addingTimeInterval(-3_600)
        )
    ]
    let rules = [
        RecoveryRule(
            enabled: false,
            trigger: .metadataTimeout,
            action: .reannounce,
            delayMinutes: 5
        ),
        RecoveryRule(
            enabled: true,
            trigger: .metadataTimeout,
            action: .pause,
            delayMinutes: 5
        )
    ]

    let firstPlan = RecoveryCenter.plan(
        issues: issues,
        rules: rules,
        at: now,
        appliedAutomaticRules: ["hash-1": ["metadata_timeout|pause|5"]]
    )

    #expect(firstPlan.isEmpty)
}

@Test func testRecoveryPlanRuleChaining() {
    let now = Date()
    let issues = [
        RecoveryCenter.Issue(
            infoHash: "hash-1",
            name: "Stalled Torrent",
            trigger: .stalledWithPeers,
            firstSeen: now.addingTimeInterval(-7200) // 2 hours ago
        )
    ]

    // Two rules for same trigger at different delays — both should fire
    let rules = [
        RecoveryRule(
            enabled: true,
            trigger: .stalledWithPeers,
            action: .reannounce,
            delayMinutes: 30
        ),
        RecoveryRule(
            enabled: true,
            trigger: .stalledWithPeers,
            action: .pause,
            delayMinutes: 60
        )
    ]

    let plan = RecoveryCenter.plan(
        issues: issues,
        rules: rules,
        at: now,
        appliedAutomaticRules: [:]
    )

    #expect(plan.count == 2)
    #expect(plan[0].action == .reannounce)
    #expect(plan[1].action == .pause)
}

@Test func testRecoveryPlanRuleChainingRespectDelay() {
    let now = Date()
    let issues = [
        RecoveryCenter.Issue(
            infoHash: "hash-1",
            name: "Stalled Torrent",
            trigger: .stalledWithPeers,
            firstSeen: now.addingTimeInterval(-2400) // 40 minutes ago
        )
    ]

    let rules = [
        RecoveryRule(
            enabled: true,
            trigger: .stalledWithPeers,
            action: .reannounce,
            delayMinutes: 30  // 40 > 30, fires
        ),
        RecoveryRule(
            enabled: true,
            trigger: .stalledWithPeers,
            action: .pause,
            delayMinutes: 60  // 40 < 60, does NOT fire yet
        )
    ]

    let plan = RecoveryCenter.plan(
        issues: issues,
        rules: rules,
        at: now,
        appliedAutomaticRules: [:]
    )

    #expect(plan.count == 1)
    #expect(plan.first?.action == .reannounce)
}

@Test func testRecoveryPlanPostProcessTrigger() {
    let now = Date()
    let issues = [
        RecoveryCenter.Issue(
            infoHash: "hash-pp",
            name: "Failed Extraction",
            trigger: .postProcessExtractionFailed,
            firstSeen: now.addingTimeInterval(-600) // 10 min ago
        )
    ]
    let rules = [
        RecoveryRule(
            enabled: true,
            trigger: .postProcessExtractionFailed,
            action: .retryPostProcess,
            delayMinutes: 5
        )
    ]

    let plan = RecoveryCenter.plan(
        issues: issues,
        rules: rules,
        at: now,
        appliedAutomaticRules: [:]
    )

    #expect(plan.count == 1)
    #expect(plan.first?.action == .retryPostProcess)
    #expect(plan.first?.reason == .postProcessExtractionFailed)
}

@Test func testRecoveryPlanDiskPressureTrigger() {
    let now = Date()
    let issues = [
        RecoveryCenter.Issue(
            infoHash: "hash-dp",
            name: "Big Download",
            trigger: .diskPressure,
            firstSeen: now.addingTimeInterval(-1800)
        )
    ]
    let rules = [
        RecoveryRule(
            enabled: true,
            trigger: .diskPressure,
            action: .removeKeepFiles,
            delayMinutes: 15
        )
    ]

    let plan = RecoveryCenter.plan(
        issues: issues,
        rules: rules,
        at: now,
        appliedAutomaticRules: [:]
    )

    #expect(plan.count == 1)
    #expect(plan.first?.action == .removeKeepFiles)
    #expect(plan.first?.reason == .diskPressure)
}

@Test func testNewTriggerAndActionRawValues() {
    #expect(RecoveryTrigger.postProcessMoveFailed.rawValue == "post_process_move_failed")
    #expect(RecoveryTrigger.postProcessExtractionFailed.rawValue == "post_process_extraction_failed")
    #expect(RecoveryTrigger.diskPressure.rawValue == "disk_pressure")
    #expect(RecoveryAction.retryPostProcess.rawValue == "retry_post_process")
}
