// Test helper (compiled by scripts/e2e-insert.sh): posts a debug command to a running Voxara.
//   vxpost dictate-file <wav> <dictation|prompt> <expectBundleID>
//   vxpost open-test-bench
//   vxpost test-mode <on|off>
import Foundation
let a = CommandLine.arguments
var info: [String: Any] = ["command": a.count > 1 ? a[1] : ""]
if a.count > 4, a[1] == "dictate-file" {
    info["path"] = a[2]; info["mode"] = a[3]; info["expectBundleID"] = a[4]
}
if a.count > 2, a[1] == "test-mode" { info["value"] = (a[2] == "on") }
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.daniel.voicetext.debug"), object: nil, userInfo: info, deliverImmediately: true)
