// Test helper (compiled by scripts/e2e-insert.sh): posts a debug command to a running Voxara.
//   vxpost dictate-file <wav> <dictation|prompt> <expectBundleID>
//   vxpost open-test-bench
import Foundation
let a = CommandLine.arguments
var info: [String: Any] = ["command": a.count > 1 ? a[1] : ""]
if a.count > 4, a[1] == "dictate-file" {
    info["path"] = a[2]; info["mode"] = a[3]; info["expectBundleID"] = a[4]
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.daniel.voicetext.debug"), object: nil, userInfo: info, deliverImmediately: true)
