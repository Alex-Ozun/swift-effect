@preconcurrency import AVFoundation
import Foundation
import Effect

struct AudioPlayback {
  @Effect
  static func play(url: URL) async throws -> Bool {
    let stream = AsyncThrowingStream<Bool, any Error> { continuation in
      do {
        let delegate = try Delegate(
          url: url,
          didFinishPlaying: { successful in
            continuation.yield(successful)
            continuation.finish()
          },
          decodeErrorDidOccur: { error in
            continuation.finish(throwing: error)
          }
        )
        delegate.player.play()
        continuation.onTermination = { _ in
          delegate.player.stop()
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
    return try await stream.first(where: { _ in true }) ?? false
  }
}

extension Effect {
  var AudioPlayback: VoiceMemos.AudioPlayback { VoiceMemos.AudioPlayback() }
}


private final class Delegate: NSObject, AVAudioPlayerDelegate, Sendable {
  let didFinishPlaying: @Sendable (Bool) -> Void
  let decodeErrorDidOccur: @Sendable (Error?) -> Void
  let player: AVAudioPlayer

  init(
    url: URL,
    didFinishPlaying: @escaping @Sendable (Bool) -> Void,
    decodeErrorDidOccur: @escaping @Sendable (Error?) -> Void
  ) throws {
    self.didFinishPlaying = didFinishPlaying
    self.decodeErrorDidOccur = decodeErrorDidOccur
    self.player = try AVAudioPlayer(contentsOf: url)
    super.init()
    self.player.delegate = self
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    self.didFinishPlaying(flag)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    self.decodeErrorDidOccur(error)
  }
}
