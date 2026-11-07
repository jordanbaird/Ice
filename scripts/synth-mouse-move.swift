// Move o cursor ao longo da barra de menus (so MOVIMENTOS, nenhum clique) para exercitar
// o caminho de hover do Trincano. Uso: swiftc -O scripts/synth-mouse-move.swift -o /tmp/mm && /tmp/mm [passes=4]
import CoreGraphics
import Foundation

let passes = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 4 : 4
let bounds = CGDisplayBounds(CGMainDisplayID())
let y: CGFloat = 12   // dentro da barra de menus
let original = CGEvent(source: nil)?.location ?? CGPoint(x: bounds.midX, y: 400)
for _ in 0..<passes {
    for step in stride(from: bounds.minX + 20, to: bounds.maxX - 20, by: 6) {
        CGWarpMouseCursorPosition(CGPoint(x: step, y: y))
        if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: step, y: y), mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        usleep(4000)
    }
}
CGWarpMouseCursorPosition(original)
print("moves done")
