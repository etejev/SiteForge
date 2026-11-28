import Foundation

// SF-0206-002/006: CLI requests open a reviewable scope; only native Start
// buttons can begin a local run. The acknowledgement avoids a launch race.
let center = DistributedNotificationCenter.default()
let nonce = UUID().uuidString
let payload = try JSONSerialization.jsonObject(with: Data(CommandLine.arguments[1].utf8)) as! [String: Any]
var acknowledged = false
let observer = center.addObserver(forName: .init("app.siteforge.testingWindowOpened"), object: nonce, queue: .main) { _ in
    MainActor.assumeIsolated { acknowledged = true }
}
let deadline = Date().addingTimeInterval(10)
while !acknowledged && Date() < deadline {
    var request = payload
    request["nonce"] = nonce
    center.postNotificationName(.init("app.siteforge.openTesting"), object: nil, userInfo: request, deliverImmediately: true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}
center.removeObserver(observer)
if !acknowledged { print("The Testing window did not acknowledge this request. Open Settings → Advanced → Testing."); exit(2) }
print("Testing window opened. Review the prepared scope and press its Start button.")
