import AVFoundation
import Foundation
import Effect

struct AudioRecording {
  private static let audioRecorder = AudioRecorder()
  
  @Effect
  static func currentTime() async -> TimeInterval? {
    await audioRecorder.currentTime
  }
  
  @Effect
  static func requestRecordPermission() async -> Bool {
    await AudioRecorder.requestPermission()
  }
  
  @Effect
  static func startRecording(url: URL) async throws -> Bool {
    try await audioRecorder.start(url: url)
  }
  
  @Effect
  static func stopRecording() async {
    await audioRecorder.stop()
  }
}

extension Effect {
  var AudioRecording: VoiceMemos.AudioRecording { VoiceMemos.AudioRecording() }
}

private actor AudioRecorder {
  var delegate: Delegate?
  var recorder: AVAudioRecorder?

  var currentTime: TimeInterval? {
    guard
      let recorder = self.recorder,
      recorder.isRecording
    else { return nil }
    return recorder.currentTime
  }

  static func requestPermission() async -> Bool {
    await AVAudioApplication.requestRecordPermission()
  }

  func stop() {
    self.recorder?.stop()
    try? AVAudioSession.sharedInstance().setActive(false)
  }

  func start(url: URL) async throws -> Bool {
    self.stop()

    let stream = AsyncThrowingStream<Bool, any Error> { continuation in
      do {
        self.delegate = Delegate(
          didFinishRecording: { flag in
            continuation.yield(flag)
            continuation.finish()
            try? AVAudioSession.sharedInstance().setActive(false)
          },
          encodeErrorDidOccur: { error in
            continuation.finish(throwing: error)
            try? AVAudioSession.sharedInstance().setActive(false)
          }
        )
        let recorder = try AVAudioRecorder(
          url: url,
          settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
          ])
        self.recorder = recorder
        recorder.delegate = self.delegate

        continuation.onTermination = { _ in
          recorder.stop()
        }

        try AVAudioSession.sharedInstance().setCategory(
          .playAndRecord, mode: .default, options: .defaultToSpeaker)
        try AVAudioSession.sharedInstance().setActive(true)
        self.recorder?.record()
      } catch {
        continuation.finish(throwing: error)
      }
    }

    for try await didFinish in stream {
      return didFinish
    }
    throw CancellationError()
  }
}

private final class Delegate: NSObject, AVAudioRecorderDelegate, Sendable {
  let didFinishRecording: @Sendable (Bool) -> Void
  let encodeErrorDidOccur: @Sendable ((any Error)?) -> Void

  init(
    didFinishRecording: @escaping @Sendable (Bool) -> Void,
    encodeErrorDidOccur: @escaping @Sendable ((any Error)?) -> Void
  ) {
    self.didFinishRecording = didFinishRecording
    self.encodeErrorDidOccur = encodeErrorDidOccur
  }

  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    self.didFinishRecording(flag)
  }

  func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
    self.encodeErrorDidOccur(error)
  }
}
