import AVFoundation
import CoreMediaIO
import Foundation
import QuartzCore

// Usage: MorphRecorder <log path> <movie path> <seconds>
// Records the connected iPhone's screen (CoreMediaIO screen capture device).
let args = CommandLine.arguments
let log = FileHandle(forWritingAtPath: args[1]) ?? FileHandle.standardOutput
func say(_ s: String) { log.write((s + "\n").data(using: .utf8)!) }
let movieURL = URL(fileURLWithPath: args.count > 2 ? args[2] : "/tmp/iphone.mov")
let seconds = args.count > 3 ? Double(args[3]) ?? 10 : 10
let metadataPath = args.count > 4 ? args[4] : nil
let stopPath = args.count > 5 ? args[5] : nil

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
if metadataPath == nil { session.addOutput(output) }
final class FrameMetadata: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  let handle: FileHandle
  private var buffer = Data()
  private var lastFlush = CACurrentMediaTime()
  private var movie: URL?
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var recording = false
  private var lastPTS: CMTime?
  init(path: String) {
    FileManager.default.createFile(atPath: path, contents: nil)
    handle = FileHandle(forWritingAtPath: path)!
  }
  private func write(_ row: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
    buffer.append(data)
    buffer.append(10)
    if buffer.count > 16384 || CACurrentMediaTime() - lastFlush > 0.5 { flush() }
  }
  func flush() {
    handle.write(buffer)
    buffer.removeAll(keepingCapacity: true)
    lastFlush = CACurrentMediaTime()
  }
  func begin(_ url: URL) {
    movie = url
    recording = true
  }
  func finish() -> Bool {
    recording = false
    guard let writer, let input else { say("error: no video buffers reached the writer"); return false }
    input.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    guard finished.wait(timeout: .now() + 30) == .success, writer.status == .completed else {
      say("error: buffer writer failed: \(String(describing: writer.error))")
      return false
    }
    say("saved: \(movie!.path)")
    return true
  }
  private func append(_ sample: CMSampleBuffer, image: CVPixelBuffer) -> Bool {
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    if let lastPTS, CMTimeCompare(pts, lastPTS) <= 0 {
      write(["k": "capture_encode_drop", "pts": CMTimeGetSeconds(pts), "e": "non-increasing source PTS"])
      return false
    }
    if writer == nil {
      do {
        let writer = try AVAssetWriter(outputURL: movie!, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                      AVVideoWidthKey: CVPixelBufferGetWidth(image), AVVideoHeightKey: CVPixelBufferGetHeight(image),
                                      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 32000000, AVVideoAllowFrameReorderingKey: false]]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings, sourceFormatHint: CMSampleBufferGetFormatDescription(sample))
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { say("error: buffer writer rejects video input"); return false }
        writer.add(input)
        guard writer.startWriting() else { say("error: buffer writer cannot start: \(String(describing: writer.error))"); return false }
        writer.startSession(atSourceTime: pts)
        self.writer = writer
        self.input = input
      } catch { say("error: buffer writer initialization: \(error)"); return false }
    }
    guard let input, input.isReadyForMoreMediaData, input.append(sample) else {
      write(["k": "capture_encode_drop", "pts": CMTimeGetSeconds(pts), "e": "encoder not ready or append failed"])
      return false
    }
    lastPTS = pts
    return true
  }
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    guard pts.isFinite else { return }
    var row: [String: Any] = ["k": "capture_buffer", "pts": pts, "host_t": CACurrentMediaTime(),
                             "width": CVPixelBufferGetWidth(image), "height": CVPixelBufferGetHeight(image),
                             "pixelFormat": CVPixelBufferGetPixelFormatType(image)]
    row["recording"] = recording
    if recording { row["movieAccepted"] = append(sampleBuffer, image: image) }
    if let attachments = CVBufferCopyAttachments(image, .shouldPropagate) as? [String: Any] {
      row["attachments"] = attachments.mapValues { String(describing: $0) }
    }
    write(row)
  }
  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    write(["k": "capture_drop", "pts": pts.isFinite ? pts : 0, "host_t": CACurrentMediaTime()])
  }
}
let metadataQueue = DispatchQueue(label: "morph.recorder.metadata")
var metadata: FrameMetadata?
if let metadataPath {
  let video = AVCaptureVideoDataOutput()
  video.alwaysDiscardsLateVideoFrames = true
  if session.canAddOutput(video) {
    let delegate = FrameMetadata(path: metadataPath)
    metadata = delegate
    video.setSampleBufferDelegate(delegate, queue: metadataQueue)
    session.addOutput(video)
    say("buffer metadata and single-source movie writer: enabled")
  } else {
    say("buffer metadata: unavailable for this source")
    exit(1)
  }
}
session.startRunning()
RunLoop.main.run(until: Date().addingTimeInterval(1))
try? FileManager.default.removeItem(at: movieURL)
let delegate = Delegate()
if let metadata { metadataQueue.sync { metadata.begin(movieURL) } }
else { output.startRecording(to: movieURL, recordingDelegate: delegate) }
say("recording \(seconds) s")
let recordingDeadline = Date().addingTimeInterval(seconds)
while Date() < recordingDeadline && !(stopPath.map { FileManager.default.fileExists(atPath: $0) } ?? false) {
  RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
var succeeded = true
if let metadata { metadataQueue.sync { succeeded = metadata.finish() } }
else {
  output.stopRecording()
  while !delegate.finished { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
}
session.stopRunning()
metadataQueue.sync { metadata?.flush() }
if !succeeded { exit(1) }
