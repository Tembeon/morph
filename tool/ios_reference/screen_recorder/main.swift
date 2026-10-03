import AVFoundation
import CoreMediaIO
import Foundation

// Usage: MorphRecorder <log path> <movie path> <seconds>
// Records the connected iPhone's screen (CoreMediaIO screen capture device).
let args = CommandLine.arguments
let log = FileHandle(forWritingAtPath: args[1]) ?? FileHandle.standardOutput
func say(_ s: String) { log.write((s + "\n").data(using: .utf8)!) }
let movieURL = URL(fileURLWithPath: args.count > 2 ? args[2] : "/tmp/iphone.mov")
let seconds = args.count > 3 ? Double(args[3]) ?? 10 : 10

var prop = CMIOObjectPropertyAddress(
  mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var allow: UInt32 = 1
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

let access = DispatchSemaphore(value: 0)
AVCaptureDevice.requestAccess(for: .video) { ok in say("camera access: \(ok)"); access.signal() }
_ = access.wait(timeout: .now() + 60)

var device: AVCaptureDevice?
let deadline = Date().addingTimeInterval(15)
while device == nil && Date() < deadline {
  RunLoop.main.run(until: Date().addingTimeInterval(0.5))
  device = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
    .devices.first { $0.modelID == "iOS Device" }
}
guard let device else { say("error: no iPhone screen device"); exit(1) }
say("device: \(device.localizedName)")

final class Delegate: NSObject, AVCaptureFileOutputRecordingDelegate {
  var finished = false
  func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
    say(error.map { "finished with error: \($0)" } ?? "saved: \(url.path)")
    finished = true
  }
}
let session = AVCaptureSession()
do { session.addInput(try AVCaptureDeviceInput(device: device)) } catch { say("error: \(error)"); exit(1) }
let output = AVCaptureMovieFileOutput()
session.addOutput(output)
session.startRunning()
RunLoop.main.run(until: Date().addingTimeInterval(1))
try? FileManager.default.removeItem(at: movieURL)
let delegate = Delegate()
output.startRecording(to: movieURL, recordingDelegate: delegate)
say("recording \(seconds) s")
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
output.stopRecording()
while !delegate.finished { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
session.stopRunning()
