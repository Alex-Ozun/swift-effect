import AsyncAlgorithms
import SwiftUI
import Effect

struct RecordingMemoData: Equatable {
  var date: Date
  var duration: TimeInterval
  var url: URL
}

@MainActor
@Observable
final class RecordingMemoViewModel {
  enum Mode {
    case recording
    case encoding
  }
  struct State: Equatable {
    var duration: TimeInterval = 0
    var mode: Mode = .recording
    let date: Date
    let url: URL
  }
  var state: State
  let onFinish: (Result<RecordingMemoData, Error>) -> Void

  private var timerTask: (any TaskProtocol<Void>)?

  init(
    date: Date,
    url: URL,
    onFinish: @escaping (Result<RecordingMemoData, Error>) -> Void
  ) {
    state = State.init(
      date: date,
      url: url
    )
    self.onFinish = onFinish
  }

  func start() async {
    timerTask = Task.effect(name: "timer") { [weak self] in
      for await _ in Effect.timer(interval: .seconds(1)) {
        self?.state.duration += 1
      }
    }
    Task.effect(name: "start recording") {
      do {
        let success = try await AudioRecording.startRecording(url: state.url)
        timerTask?.cancel()
        if success {
          onFinish(.success(RecordingMemoData(date: state.date, duration: state.duration, url: state.url)))
        } else {
          onFinish(.failure(RecordingFailed()))
        }
      } catch {
        timerTask?.cancel()
        onFinish(.failure(error))
      }
    }
  }

  func stop() async {
    state.mode = .encoding
    if let currentTime = await AudioRecording.currentTime() {
      state.duration = currentTime
    }
    await AudioRecording.stopRecording()
  }
}

struct RecordingFailed: Error, Equatable {}

struct RecordingMemoView: View {
  let viewModel: RecordingMemoViewModel

  var body: some View {
    VStack(spacing: 12) {
      Text("Recording")
        .font(.title)
        .colorMultiply(Color(Int(viewModel.state.duration).isMultiple(of: 2) ? .systemRed : .label))
        .animation(.easeInOut(duration: 0.5), value: viewModel.state.duration)

      if let formattedDuration = dateComponentsFormatter.string(from: viewModel.state.duration) {
        Text(formattedDuration)
          .font(.body.monospacedDigit().bold())
          .foregroundColor(.black)
      }

      ZStack {
        Circle()
          .foregroundColor(Color(.label))
          .frame(width: 74, height: 74)

        Button {
          Task {
            await viewModel.stop()
          }
        } label: {
          RoundedRectangle(cornerRadius: 4)
            .foregroundColor(Color(.systemRed))
            .padding(17)
        }
        .frame(width: 70, height: 70)
      }
    }
    .task {
      await viewModel.start()
    }
  }
}
