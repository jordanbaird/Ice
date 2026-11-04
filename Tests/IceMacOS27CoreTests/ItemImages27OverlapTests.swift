import CoreGraphics
import Testing
@testable import IceMacOS27Core

/// See ``ItemImages27/overlappingTags(frames:)``.
@Suite("Overlapping frames are nobody's glyph")
struct ItemImages27OverlapTests {
    /// Mos's stale frame against the Stats module that moved under it, measured 2026-11-04.
    let mos = ("com.caldis.Mos:Item-0", CGRect(x: 1487, y: 2, width: 32, height: 24))
    let stats = ("eu.exelban.Stats:Item-2", CGRect(x: 1497, y: 2, width: 33, height: 24))
    let clock = ("com.apple.MenuBarAgent:com.apple.menuextra.clock", CGRect(x: 1790, y: 2, width: 110, height: 24))

    @Test("Both sides of an overlap are refused")
    func bothRefused() {
        let tags = ItemImages27.overlappingTags(frames: [mos.0: mos.1, stats.0: stats.1, clock.0: clock.1])
        #expect(tags == [mos.0, stats.0])
    }

    /// Measured 2026-11-04: Pritunl at 1271 w=34 ends at 1305 and Docker Desktop begins at
    /// 1303. Neighbours on a real bar touch, and rounding puts them a point or two into each
    /// other; that is not a stale frame, and refusing both left the hidden section with no
    /// glyphs at all.
    @Test("Neighbours that touch by a point or two are not in conflict")
    func touchingNeighbours() {
        let pritunl = ("com.electron.pritunl:Item-0", CGRect(x: 1271, y: 2, width: 34, height: 24))
        let docker = ("com.electron.dockerdesktop:Item-0", CGRect(x: 1303, y: 2, width: 45, height: 24))
        #expect(ItemImages27.overlappingTags(frames: [pritunl.0: pritunl.1, docker.0: docker.1]).isEmpty)
    }

    @Test("Items side by side are nobody's overlap")
    func neighboursAreFine() {
        let left = ("a", CGRect(x: 100, y: 2, width: 30, height: 24))
        let right = ("b", CGRect(x: 130, y: 2, width: 30, height: 24))
        #expect(ItemImages27.overlappingTags(frames: [left.0: left.1, right.0: right.1]).isEmpty)
    }

    @Test("A frame on another display does not overlap one here")
    func otherDisplay() {
        let here = ("a", CGRect(x: 100, y: 2, width: 30, height: 24))
        let there = ("b", CGRect(x: -900, y: 102, width: 30, height: 24))
        #expect(ItemImages27.overlappingTags(frames: [here.0: here.1, there.0: there.1]).isEmpty)
    }
}
