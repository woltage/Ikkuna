import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import IkkunaCore

final class GeometryTests: XCTestCase {
    func testCenterCyclesNarrowWideNarrowWithStageInsets() {
        let usable = CGRect(x: -1080, y: 40, width: 1000, height: 800)
        let initial = CGRect(x: -1000, y: 100, width: 400, height: 300)
        let narrow = Geometry.centerCycle(from: initial, in: usable, centeredOn: -600, gap: 4)
        let wide = Geometry.centerCycle(from: narrow, in: usable, centeredOn: -600, gap: 4)
        XCTAssertEqual(narrow.width, 496)
        XCTAssertEqual(wide.width, 744)
        XCTAssertEqual(narrow.midX, -600)
        XCTAssertEqual(wide.midX, -600)
        XCTAssertEqual(narrow.height, 792)
        XCTAssertEqual(wide.minY, 44)
        XCTAssertEqual(Geometry.centerCycle(from: wide, in: usable, centeredOn: -600, gap: 4), narrow)
    }

    func testVerticalResizeMovesSharedEdgeAndPreservesWidths() {
        let top = WindowRect(1, CGRect(x: 0, y: 0, width: 600, height: 398))
        let bottom = WindowRect(2, CGRect(x: 0, y: 402, width: 600, height: 398))
        let plan = ResizePlan(focused: top, windows: [top, bottom], screen: CGRect(x: 0, y: 0, width: 600, height: 800), vertical: true)
        let frames = plan.frames(delta: 50)
        XCTAssertEqual(plan.originals[1], top.frame)
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 0, width: 600, height: 448))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 452, width: 600, height: 348))
        XCTAssertEqual(plan.frames(delta: 1000)[2]?.height, 200)
    }
    func testVerticalResizeFromBottomKeepsOuterEdge() {
        let top = WindowRect(1, CGRect(x: -600, y: -100, width: 600, height: 398))
        let bottom = WindowRect(2, CGRect(x: -600, y: 302, width: 600, height: 398))
        let plan = ResizePlan(focused: bottom, windows: [top, bottom], screen: CGRect(x: -600, y: -100, width: 600, height: 800), vertical: true)
        XCTAssertEqual(plan.frames(delta: -50)[2], CGRect(x: -600, y: 352, width: 600, height: 348))
        XCTAssertEqual(plan.frames(delta: -50)[1], CGRect(x: -600, y: -100, width: 600, height: 448))
    }
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    func testTilesPreserveOuterAndInnerGaps() {
        let left = Geometry.tile(in: screen, columns: 2, rows: 1, column: 0, row: 0, gap: 4)
        let right = Geometry.tile(in: screen, columns: 2, rows: 1, column: 1, row: 0, gap: 4)
        XCTAssertEqual(left.minX, 4); XCTAssertEqual(right.minX-left.maxX, 4)
        XCTAssertEqual(screen.maxX-right.maxX, 4); XCTAssertEqual(left.height, 792)
    }
    func testQuartersOnDisplayWithNegativeOrigin() {
        let display = CGRect(x: -1800, y: -100, width: 1800, height: 1000)
        let bottomRight = Geometry.tile(in: display, columns: 2, rows: 2, column: 1, row: 1, gap: 8)
        XCTAssertEqual(bottomRight.maxX, -8); XCTAssertEqual(bottomRight.maxY, 892)
    }
    func testExcessiveGapNeverCreatesNegativeDimensions() {
        let tile = Geometry.tile(in: screen, columns: 2, rows: 2, column: 1, row: 1, gap: 100_000)
        XCTAssertGreaterThan(tile.width, 0); XCTAssertGreaterThan(tile.height, 0)
        XCTAssertTrue(screen.contains(tile))
    }
    func testScreenUsesLargestIntersection() {
        let screens = [screen, CGRect(x: 1200, y: 0, width: 1600, height: 900)]
        XCTAssertEqual(Geometry.screenIndex(for: CGRect(x: 1150, y: 0, width: 500, height: 500), screens: screens), 1)
    }
    func testNoDisplaysHasNoIndex() {
        XCTAssertNil(Geometry.screenIndex(for: screen, screens: []))
    }
    func testDirectionalFocusPrefersAlignedWindow() {
        let current = WindowRect(1, CGRect(x: 400, y: 300, width: 100, height: 100))
        let aligned = WindowRect(2, CGRect(x: 600, y: 300, width: 100, height: 100))
        let diagonal = WindowRect(3, CGRect(x: 510, y: 480, width: 100, height: 100))
        XCTAssertEqual(Geometry.directionalTarget(from: current, candidates: [current, diagonal, aligned], direction: .right), 2)
    }
    func testFocusWrapsToFurthestOppositeWindow() {
        let current = WindowRect(1, CGRect(x: 1000, y: 0, width: 100, height: 100))
        let near = WindowRect(2, CGRect(x: 600, y: 0, width: 100, height: 100))
        let far = WindowRect(3, CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(Geometry.directionalTarget(from: current, candidates: [near, current, far], direction: .right), 3)
    }
    func testReturnMemoryWinsWhenAngleIsValid() {
        let current = WindowRect(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let near = WindowRect(2, CGRect(x: 150, y: 0, width: 100, height: 100))
        let remembered = WindowRect(3, CGRect(x: 300, y: 100, width: 100, height: 100))
        XCTAssertEqual(Geometry.directionalTarget(from: current, candidates: [near, remembered], direction: .right, remembered: 3), 3)
    }
    func testDiagonalOrStaleMemoryDoesNotOverrideForwardScan() {
        let current = WindowRect(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let near = WindowRect(2, CGRect(x: 150, y: 0, width: 100, height: 100))
        let diagonal = WindowRect(3, CGRect(x: 100, y: 400, width: 100, height: 100))
        XCTAssertEqual(Geometry.directionalTarget(from: current, candidates: [near, diagonal], direction: .right, remembered: 3), 2)
        XCTAssertEqual(Geometry.directionalTarget(from: current, candidates: [near], direction: .right, remembered: 9), 2)
    }
    func testNoOtherWindowProducesNoFocusTarget() {
        let current = WindowRect(1, screen)
        XCTAssertNil(Geometry.directionalTarget(from: current, candidates: [current], direction: .up))
    }
    func testOcclusionCombinesAdjacentWindows() {
        XCTAssertEqual(Geometry.coveredFraction(of: screen, by: [
            CGRect(x: 0, y: 0, width: 600, height: 800), CGRect(x: 600, y: 0, width: 600, height: 800)
        ]), 1, accuracy: 0.001)
    }
    func testOverlappingOccludersAreNotCountedTwice() {
        let cover = CGRect(x: 0, y: 0, width: 480, height: 800)
        XCTAssertEqual(Geometry.coveredFraction(of: screen, by: [cover, cover]), 0.4, accuracy: 0.001)
    }
    func testOffscreenOccludersAreClipped() {
        XCTAssertEqual(Geometry.coveredFraction(of: screen, by: [CGRect(x: -600, y: 0, width: 1200, height: 800)]), 0.5)
    }
    func testMoveBetweenDifferentDisplaySizesPreservesFractions() {
        let source = CGRect(x: -1200, y: 0, width: 1200, height: 800)
        let target = CGRect(x: 0, y: -100, width: 2400, height: 1600)
        let moved = Geometry.moved(CGRect(x: -900, y: 200, width: 600, height: 400), from: source, to: target)
        XCTAssertEqual(moved, CGRect(x: 600, y: 300, width: 1200, height: 800))
    }
    func testFillStopsAtNeighborAndUsesFullHeight() {
        let neighbor = CGRect(x: 600, y: 0, width: 596, height: 800)
        let fill = Geometry.fill(CGRect(x: 30, y: 30, width: 300, height: 200), in: screen, neighbors: [neighbor], left: true, gap: 4)
        XCTAssertEqual(fill, CGRect(x: 4, y: 4, width: 592, height: 792))
    }
    func testFillAnchorsPastExistingLeftColumn() {
        let neighbor = CGRect(x: 4, y: 4, width: 396, height: 792)
        let fill = Geometry.fill(screen, in: screen, neighbors: [neighbor], left: true, gap: 4)
        XCTAssertEqual(fill.minX, 404); XCTAssertEqual(fill.maxX, 1196)
    }
    func testRowFillIgnoresNeighborInOtherRow() {
        let neighbor = CGRect(x: 600, y: 404, width: 596, height: 392)
        let fill = Geometry.fill(screen, in: screen, neighbors: [neighbor], left: true, row: 0, gap: 4)
        XCTAssertEqual(fill.minY, 4); XCTAssertEqual(fill.height, 394)
        XCTAssertEqual(fill.width, 1192)
    }
    func testCoordinatedResizePreservesGapAndMinimumWidths() {
        let left = WindowRect(1, CGRect(x: 4, y: 4, width: 594, height: 792))
        let right = WindowRect(2, CGRect(x: 602, y: 4, width: 594, height: 792))
        let plan = ResizePlan(focused: left, windows: [left, right], screen: screen)
        let frames = plan.frames(delta: 10000)
        XCTAssertEqual(frames[2]?.width, 200)
        XCTAssertEqual(frames[2]!.minX-frames[1]!.maxX, 4)
        XCTAssertEqual(frames[2]?.maxX, 1196)
        XCTAssertEqual(plan.frames(delta: -10000)[1]?.width, 200)
    }
    func testResizeIncludesBothStackedRows() {
        let windows = [WindowRect(1, CGRect(x: 4, y: 4, width: 594, height: 394)),
                       WindowRect(2, CGRect(x: 4, y: 402, width: 594, height: 394)),
                       WindowRect(3, CGRect(x: 602, y: 4, width: 594, height: 394)),
                       WindowRect(4, CGRect(x: 602, y: 402, width: 594, height: 394))]
        let frames = ResizePlan(focused: windows[0], windows: windows, screen: screen).frames(delta: 50)
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[1]?.width, 644); XCTAssertEqual(frames[2]?.width, 644)
        XCTAssertEqual(frames[3]?.width, 544); XCTAssertEqual(frames[4]?.width, 544)
    }
    func testRightColumnGrowsLeftward() {
        let left = WindowRect(1, CGRect(x: 4, y: 4, width: 594, height: 792))
        let right = WindowRect(2, CGRect(x: 602, y: 4, width: 594, height: 792))
        let frames = ResizePlan(focused: right, windows: [left, right], screen: screen).frames(delta: 50)
        XCTAssertEqual(frames[2]?.minX, 552); XCTAssertEqual(frames[2]?.maxX, 1196)
        XCTAssertEqual(frames[1]?.width, 544)
    }
    func testIsolatedResizeStopsAtScreenEdge() {
        let window = WindowRect(1, CGRect(x: 0, y: 0, width: 400, height: 800))
        let frames = ResizePlan(focused: window, windows: [window], screen: screen).frames(delta: 10000)
        XCTAssertEqual(frames[1]?.maxX, 1200)
    }
}
