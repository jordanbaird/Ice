import CoreGraphics
import Foundation

@main
struct MenuBarOverlayGeometryTests {
    static func main() {
        var failed = 0
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failed += 1 }
        }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: 24, inset: 5) ==
              CGRect(x: 0, y: 871, width: 1440, height: 29), "panel fits immediately below the screen top")
        let secondary = CGRect(x: -1920, y: 240, width: 1920, height: 1080)
        check(MenuBarOverlayGeometry.frame(screen: secondary, menuBarHeight: 32, inset: 3.5) ==
              CGRect(x: -1920, y: 1284.5, width: 1920, height: 35.5), "nonzero and negative display origins are preserved")
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: 0, inset: 5) == nil, "missing native menu-bar height is rejected")
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: -1, inset: 5) == nil, "negative height is rejected")
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: 900, inset: 5) == nil, "oversized panel is rejected")
        check(MenuBarOverlayGeometry.frame(screen: .zero, menuBarHeight: 24, inset: 5) == nil, "missing screen is rejected")
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: .nan, inset: 5) == nil, "NaN geometry is rejected")
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: .infinity, inset: 5) == nil, "infinite geometry is rejected")
        check(MenuBarOverlayGeometry.frame(screen: screen, menuBarHeight: 24, inset: -1) == nil, "negative inset is rejected")
        exit(failed == 0 ? 0 : 1)
    }
}
