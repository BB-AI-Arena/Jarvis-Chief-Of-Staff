import Foundation
var activity = VoiceActivity()
assert(!activity.update(rms: 0, at: 0))
assert(activity.update(rms: 0.1, at: 1))
assert(activity.update(rms: 0, at: 1.2))
assert(!activity.update(rms: 0, at: 1.5))
assert(!activity.update(rms: 0.0001, at: 2))
assert(activity.update(rms: 0.03, at: 3))
print("PASS: silent streaming audio stays listening; audible speech holds through short gaps")
