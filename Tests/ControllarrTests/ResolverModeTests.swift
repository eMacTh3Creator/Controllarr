//
//  ResolverModeTests.swift
//  ControllarrTests
//
//  Unit coverage for the large-library conservative-resolver decision
//  (the v2.1.9 crash guard) and its v2.1.10 hysteresis band. These exercise
//  the pure `+shouldConserveResolverForTorrentCount:alreadyConservative:`
//  seam, so no real libtorrent session is created.
//

import Testing
import LibtorrentShim

// MARK: - Thresholds

@Test func testResolverThresholdsFormHysteresisBand() {
    let enter = CTRLSession.conservativeResolverEnterThreshold()
    let exit = CTRLSession.conservativeResolverExitThreshold()
    // Enter threshold must sit strictly above the exit threshold, otherwise
    // there is no band and the mode can flap one torrent either side.
    #expect(enter > exit)
    #expect(enter == 250)
    #expect(exit == 200)
}

// MARK: - Engage (not currently conservative)

@Test func testEngagesAtOrAboveEnterThreshold() {
    // Below the enter threshold: stay relaxed.
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 0, alreadyConservative: false))
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 249, alreadyConservative: false))
    // At and above the enter threshold: engage.
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 250, alreadyConservative: false))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 300, alreadyConservative: false))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 5000, alreadyConservative: false))
}

// MARK: - Relax (currently conservative)

@Test func testRelaxesOnlyBelowExitThreshold() {
    // Still at/above exit threshold while engaged: remain conservative.
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 300, alreadyConservative: true))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 250, alreadyConservative: true))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 210, alreadyConservative: true))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 200, alreadyConservative: true))
    // Below exit threshold: relax.
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 199, alreadyConservative: true))
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 0, alreadyConservative: true))
}

// MARK: - No flapping inside the band

@Test func testNoFlappingWhileHoveringInsideBand() {
    // A library oscillating between 210 and 260 must NOT toggle the mode:
    // once engaged it stays engaged across the whole band.
    var conservative = false
    // Cross up into conservative.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 260, alreadyConservative: conservative)
    #expect(conservative)
    // Dip to 210 (inside the band) — still conservative.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 210, alreadyConservative: conservative)
    #expect(conservative)
    // Back up to 251 — still conservative, no re-toggle.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 251, alreadyConservative: conservative)
    #expect(conservative)
    // Drop to 220 — still conservative.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 220, alreadyConservative: conservative)
    #expect(conservative)
    // Only a real drop below 200 relaxes it.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 150, alreadyConservative: conservative)
    #expect(!conservative)
}
