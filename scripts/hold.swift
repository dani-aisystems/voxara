// Test helper: simulates holding a modifier key (flagsChanged events) for N seconds.
//   hold <keyCode> <deviceFlagHex> <flagMaskDecimal> <seconds>      e.g. Right Option: 61 40 524288 6
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let key = CGKeyCode(UInt16(a[1])!)
let device = UInt64(a[2], radix: 16)!
let mask = UInt64(a[3])!
let seconds = Double(a[4])!
func post(down: Bool) {
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: key, keyDown: down)!
    e.type = .flagsChanged
    e.flags = CGEventFlags(rawValue: down ? (mask | device) : 0)
    e.post(tap: .cghidEventTap)
}
post(down: true)
Thread.sleep(forTimeInterval: seconds)
post(down: false)
