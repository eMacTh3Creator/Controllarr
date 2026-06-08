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
    #expect(enter == 650)
    #expect(exit == 580)
}

// MARK: - Engage (not currently conservative)

@Test func testEngagesAtOrAboveEnterThreshold() {
    // Below the enter threshold: stay relaxed.
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 0, alreadyConservative: false))
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 649, alreadyConservative: false))
    // At and above the enter threshold: engage.
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 650, alreadyConservative: false))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 700, alreadyConservative: false))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 5000, alreadyConservative: false))
}

// MARK: - Relax (currently conservative)

@Test func testRelaxesOnlyBelowExitThreshold() {
    // Still at/above exit threshold while engaged: remain conservative.
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 700, alreadyConservative: true))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 650, alreadyConservative: true))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 600, alreadyConservative: true))
    #expect(CTRLSession.shouldConserveResolver(forTorrentCount: 580, alreadyConservative: true))
    // Below exit threshold: relax.
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 579, alreadyConservative: true))
    #expect(!CTRLSession.shouldConserveResolver(forTorrentCount: 0, alreadyConservative: true))
}

// MARK: - No flapping inside the band

@Test func testNoFlappingWhileHoveringInsideBand() {
    // A library oscillating between 600 and 660 must NOT toggle the mode:
    // once engaged it stays engaged across the whole band.
    var conservative = false
    // Cross up into conservative.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 660, alreadyConservative: conservative)
    #expect(conservative)
    // Dip to 600 (inside the band) — still conservative.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 600, alreadyConservative: conservative)
    #expect(conservative)
    // Back up to 651 — still conservative, no re-toggle.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 651, alreadyConservative: conservative)
    #expect(conservative)
    // Drop to 610 — still conservative.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 610, alreadyConservative: conservative)
    #expect(conservative)
    // Only a real drop below 580 relaxes it.
    conservative = CTRLSession.shouldConserveResolver(forTorrentCount: 500, alreadyConservative: conservative)
    #expect(!conservative)
}
