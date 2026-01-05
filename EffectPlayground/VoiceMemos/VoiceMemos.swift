import SwiftUI
import Effect

@MainActor
@Observable
final class VoiceMemosViewModel {
  enum RecorderPermission {
    case allowed
    case denied
    case undetermined
  }

  var alertMessage: String?
  var audioRecorderPermission = RecorderPermission.undetermined
  var recordingMemo: RecordingMemoViewModel?
  var voiceMemos: [VoiceMemoViewModel] = []

  init(voiceMemos: [VoiceMemo] = []) {
    self.voiceMemos = voiceMemos.map {
      makeVoiceMemoViewModel(memo: $0)
    }
  }

  func delete(at offsets: IndexSet) {
    voiceMemos.remove(atOffsets: offsets)
  }

  func openSettingsButtonTapped() async {
    await Effect.openSettings()
  }

  func recordButtonTapped() async {
    switch audioRecorderPermission {
    case .undetermined:
      let allowed = await AudioRecording.requestRecordPermission()
      audioRecorderPermission = allowed ? .allowed : .denied
      if allowed {
        startRecording()
      } else {
        alertMessage = "Permission is required to record voice memos."
      }

    case .denied:
      alertMessage = "Permission is required to record voice memos."

    case .allowed:
      startRecording()
    }
  }

  private func startRecording() {
    let url = Effect.temporaryDirectory()
      .appendingPathComponent(Effect.uuid().uuidString)
      .appendingPathExtension("m4a")
    self.recordingMemo = RecordingMemoViewModel(
      date: Effect.date(),
      url: url,
      onFinish: { [weak self] result in
        guard let self else { return }
        self.recordingMemo = nil
        switch result {
        case let .success(data):
          let memo = VoiceMemo(
            date: data.date,
            duration: data.duration,
            title: "",
            url: data.url
          )
          self.voiceMemos.insert(self.makeVoiceMemoViewModel(memo: memo), at: 0)
          
        case .failure:
          self.alertMessage = "Voice memo recording failed."
        }
      }
    )
  }

  private func makeVoiceMemoViewModel(memo: VoiceMemo) -> VoiceMemoViewModel {
    VoiceMemoViewModel(
      memo: memo,
      onPlaybackStarted: { [weak self] id in
        guard let self else { return }
        for memo in self.voiceMemos where memo.id != id {
          memo.stopPlayback()
        }
      },
      onPlaybackFailed: { [weak self] in
        self?.alertMessage = "Voice memo playback failed."
      }
    )
  }
}

struct VoiceMemosView: View {
  private var viewModel: VoiceMemosViewModel

  init(viewModel: VoiceMemosViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavigationStack {
      VStack {
        List {
          ForEach(viewModel.voiceMemos) { memoViewModel in
            VoiceMemoView(viewModel: memoViewModel)
          }
          .onDelete { viewModel.delete(at: $0) }
        }

        Group {
          if let recordingMemo = viewModel.recordingMemo {
            RecordingMemoView(viewModel: recordingMemo)
          } else {
            RecordButton(permission: viewModel.audioRecorderPermission) {
              Task {
                await viewModel.recordButtonTapped()
              }
            } settingsAction: {
              Task {
                await viewModel.openSettingsButtonTapped()
              }
            }
          }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.init(white: 0.95))
      }
      .alert(
        "Error",
        isPresented: Binding(
          get: { viewModel.alertMessage != nil },
          set: { if !$0 { viewModel.alertMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(viewModel.alertMessage ?? "")
      }
      .navigationTitle("Voice memos")
    }
  }
}

struct RecordButton: View {
  let permission: VoiceMemosViewModel.RecorderPermission
  let action: () -> Void
  let settingsAction: () -> Void

  var body: some View {
    ZStack {
      Group {
        Circle()
          .foregroundColor(Color(.label))
          .frame(width: 74, height: 74)

        Button(action: action) {
          RoundedRectangle(cornerRadius: 35)
            .foregroundColor(Color(.systemRed))
            .padding(2)
        }
        .frame(width: 70, height: 70)
      }
      .opacity(permission == .denied ? 0.1 : 1)

      if permission == .denied {
        VStack(spacing: 10) {
          Text("Recording requires microphone access.")
            .multilineTextAlignment(.center)
          Button("Open Settings", action: settingsAction)
        }
        .frame(maxWidth: .infinity, maxHeight: 74)
      }
    }
  }
}

#Preview {
  let previewMemos = [
    VoiceMemo(
      date: Date(),
      duration: 5,
      title: "Functions",
      url: URL(string: "https://www.swiftology.io")!
    ),
    VoiceMemo(
      date: Date(),
      duration: 5,
      title: "",
      url: URL(string: "https://www.swiftology.io")!
    ),
  ]
  return VoiceMemosView(
    viewModel: VoiceMemosViewModel(
      voiceMemos: previewMemos
    )
  )
}
