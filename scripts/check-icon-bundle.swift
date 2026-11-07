// Confere no app COMPILADO que os glifos da barra de menus existem e são templates reais
// (NSImage.isTemplate). Uso: swiftc scripts/check-icon-bundle.swift -o /tmp/cib && /tmp/cib <Trincano.app>
import AppKit

_ = NSApplication.shared
guard CommandLine.arguments.count > 1, let bundle = Bundle(path: CommandLine.arguments[1]) else {
    print("uso: check-icon-bundle <Trincano.app>")
    exit(2)
}
var failed = false
for name in ["FrostBarFill", "FrostBarStroke"] {
    let image = bundle.image(forResource: NSImage.Name(name))
    let ok = image?.isTemplate == true && image?.size == NSSize(width: 18, height: 18)
    print("\(name): found=\(image != nil) isTemplate=\(image?.isTemplate ?? false) size=\(image?.size ?? .zero) -> \(ok ? "OK" : "FALHOU")")
    failed = failed || !ok
}
exit(failed ? 1 : 0)
