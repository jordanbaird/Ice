import Testing
@testable import IceMacOS27Core

@Suite("EnclosingApplication27")
struct EnclosingApplication27Tests {
    @Test("A helper inside an application gives that application")
    func helperInsideAnApp() {
        // Measured on this Mac: the owner of Docker's menu bar item.
        #expect(
            EnclosingApplication27.outermostApplicationPath(
                of: "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app"
            ) == "/Applications/Docker.app"
        )
    }

    @Test("An application that is its own outermost bundle gives nothing")
    func ownApp() {
        #expect(EnclosingApplication27.outermostApplicationPath(of: "/Applications/Cursor.app") == nil)
        #expect(EnclosingApplication27.outermostApplicationPath(of: "/Applications/Pritunl.app") == nil)
    }

    @Test("A path with no application bundle on it gives nothing")
    func noApp() {
        #expect(EnclosingApplication27.outermostApplicationPath(of: "/usr/libexec/something") == nil)
        #expect(EnclosingApplication27.outermostApplicationPath(of: "") == nil)
    }

    @Test("Only the outermost one counts, however deep the nesting")
    func deepNesting() {
        #expect(
            EnclosingApplication27.outermostApplicationPath(
                of: "/Applications/Outer.app/Contents/Frameworks/Middle.app/Contents/MacOS/Inner.app"
            ) == "/Applications/Outer.app"
        )
    }
}
