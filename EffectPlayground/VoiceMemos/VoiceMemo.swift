import Effect
import SwiftUI

struct VoiceMemo: Identifiable, Equatable {
  let id: URL
  var date: Date
  var duration: TimeInterval
  var title: String
  var url: URL

  init(date: Date, duration: TimeInterval, title: String, url: URL) {
    self.id = url
    self.date = date
    self.duration = duration
    self.title = title
    self.url = url
  }
}

@MainActor
@Observable
final class VoiceMemoViewModel: Identifiable {
  enum Mode: Equatable {
    case notPlaying
    case playing(progress: Double)
  }

  let id: URL
  var memo: VoiceMemo
  var mode: Mode = .notPlaying

  private var playbackTask: (any TaskProtocol<Void>)?
  private var timerTask: (any TaskProtocol<Void>)?

  let onPlaybackStarted: (URL) -> Void
  let onPlaybackFailed: () -> Void
  
  init(
    memo: VoiceMemo,
    onPlaybackStarted: @escaping (URL) -> Void,
    onPlaybackFailed: @escaping () -> Void
  ) {
    self.id = memo.id
    self.memo = memo
    self.onPlaybackStarted = onPlaybackStarted
    self.onPlaybackFailed = onPlaybackFailed
  }
  
  func togglePlay() {
    switch mode {
    case .notPlaying:
      startPlayback()
    case .playing:
      stopPlayback()
    }
  }

  func stopPlayback() {
    playbackTask?.cancel()
    timerTask?.cancel()
    playbackTask = nil
    timerTask = nil
    mode = .notPlaying
  }

  private func startPlayback() {
    mode = .playing(progress: 0)
    onPlaybackStarted(id)

    timerTask?.cancel()
    timerTask = Task.effect(name: "timer") { [weak self] in
      guard let self else { return }
      var elapsed: TimeInterval = 0
      for await _ in Effect.timer(interval: .seconds(0.5)) {
        elapsed += 0.5
        let progress = self.memo.duration > 0 ? min(1, elapsed / self.memo.duration) : 1
        self.mode = .playing(progress: progress)
      }
    }

    playbackTask?.cancel()
    playbackTask = Task.effect(name: "play") { [weak self] in
      guard let self else { return }
      do {
        _ = try await AudioPlayback.play(url: self.memo.url)
        self.finishPlayback(success: true)
      } catch {
        self.finishPlayback(success: false)
      }
    }
  }

  private func finishPlayback(success: Bool) {
    timerTask?.cancel()
    playbackTask?.cancel()
    playbackTask = nil
    timerTask = nil
    mode = .notPlaying
    if !success {
      onPlaybackFailed()
    }
  }
}

struct VoiceMemoView: View {
  let viewModel: VoiceMemoViewModel

  var body: some View {
    let currentTime =
      viewModel.mode.playing.map { $0 * viewModel.memo.duration } ?? viewModel.memo.duration
    HStack {
      TextField(
        "Untitled, \(viewModel.memo.date.formatted(date: .numeric, time: .shortened))",
        text: Binding(
          get: { viewModel.memo.title },
          set: { viewModel.memo.title = $0 }
        )
      )

      Spacer()

      dateComponentsFormatter.string(from: currentTime).map {
        Text($0)
          .font(.footnote.monospacedDigit())
          .foregroundColor(Color(.systemGray))
      }

      Button {
        viewModel.togglePlay()
      } label: {
        Image(systemName: viewModel.mode.isPlaying ? "stop.circle" : "play.circle")
          .font(.system(size: 22))
      }
    }
    .buttonStyle(.borderless)
    .frame(maxHeight: .infinity, alignment: .center)
    .padding(.horizontal)
    .listRowBackground(viewModel.mode.isPlaying ? Color(.systemGray6) : .clear)
    .listRowInsets(EdgeInsets())
    .background(
      Color(.systemGray5)
        .frame(maxWidth: viewModel.mode.isPlaying ? .infinity : 0)
        .animation(
          viewModel.mode.isPlaying ? .linear(duration: viewModel.memo.duration) : nil,
          value: viewModel.mode.isPlaying
        ),
      alignment: .leading
    )
  }
}

private extension VoiceMemoViewModel.Mode {
  var isPlaying: Bool {
    if case .playing = self { return true }
    return false
  }

  var playing: Double? {
    if case let .playing(progress) = self { return progress }
    return nil
  }
}
