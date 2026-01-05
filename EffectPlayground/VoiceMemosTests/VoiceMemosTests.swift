import AsyncAlgorithms
import Clocks
import Effect
import Foundation
import Testing
@testable import VoiceMemos

let deadbeefID = UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!
let deadbeefURL = URL(fileURLWithPath: "/tmp/DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF.m4a")

@MainActor
struct VoiceMemosTests {
  @Test
  func recordAndPlayback() async throws {
    let viewModel = VoiceMemosViewModel()
    try #require(viewModel.recordingMemo == nil)
    try await withTestHandler {
      await viewModel.recordButtonTapped()
    } test: { effect in
      try await effect.expect(\.AudioRecording.requestRecordPermission, return: true)
      try await effect.expect(\.temporaryDirectory, return: URL(fileURLWithPath: "/tmp"))
      try await effect.expect(\.uUID, return: deadbeefID)
      try await effect.expect(\.date, return: Date(timeIntervalSinceReferenceDate: 0))
      await #expect(viewModel.audioRecorderPermission == .allowed)
    }
    
    let recordingMemo = try #require(viewModel.recordingMemo)
    #expect(
      recordingMemo.state ==
      RecordingMemoViewModel.State(
        duration: 0,
        mode: .recording,
        date: Date(timeIntervalSinceReferenceDate: 0),
        url: deadbeefURL
      )
    )
    
    try await withTestHandler {
      await recordingMemo.start()
    } test: { effect in
      let timer = try await effect.expectTask("timer", action: .enqueue)
      try await effect.expectTask("start recording", action: .enqueue)
      await #expect(recordingMemo.state.duration == 0)
      try await effect.expect(\.timer) { _ in } // 1 second
      await #expect(recordingMemo.state.duration == 1)
      try await effect.expect(\.timer) { _ in } // 2 seconds
      await #expect(recordingMemo.state.duration == 2)
      try await effect.expect(\.timer) { _ in } // 3 seconds
      await #expect(recordingMemo.state.duration == 3)
      try await effect.expect(\.timer) { interval in
        #expect(interval == .seconds(1.0))
        return nil  // stop the timer at 3 seconds
      }
      try await effect.expect(\.AudioRecording.startRecording) { url in
        #expect(url == deadbeefURL)
        return true // finish recording with success
      }
      #expect(timer.isCancelled)
    }
    
    try await withTestHandler {
      await recordingMemo.stop()
    } test: { effect in
      try await effect.expect(\.AudioRecording.currentTime, return: 3)
      try await effect.expect(\.AudioRecording.stopRecording)
      
      await #expect(recordingMemo.state.mode == .encoding)
      await #expect(recordingMemo.state.duration == 3)
      await #expect(viewModel.recordingMemo == nil)
    }
    
    try #require(viewModel.voiceMemos.count == 1)
    let voiceMemoViewModel = try #require(viewModel.voiceMemos.first)
    #expect(
      voiceMemoViewModel.memo ==
      VoiceMemo(
        date: Date(timeIntervalSinceReferenceDate: 0),
        duration: 3,
        title: "",
        url: deadbeefURL
      )
    )
    #expect(voiceMemoViewModel.mode == .notPlaying)
    
    try await withTestHandler {
      voiceMemoViewModel.togglePlay()
    } test: { effect in
      let timerTask = try await effect.expectTask("timer", action: .enqueue)
      let playTask = try await effect.expectTask("play", action: .enqueue)
      
      await #expect(voiceMemoViewModel.mode == .playing(progress: 0))
      try await effect.expect(\.timer) { _ in }
      await #expect(voiceMemoViewModel.mode == .playing(progress: 1/6))
      try await effect.expect(\.timer) { _ in }
      await #expect(voiceMemoViewModel.mode == .playing(progress: 2/6))
      try await effect.expect(\.timer) { _ in }
      await #expect(voiceMemoViewModel.mode == .playing(progress: 3/6))
      try await effect.expect(\.timer) { _ in }
      await #expect(voiceMemoViewModel.mode == .playing(progress: 4/6))
      try await effect.expect(\.timer) { _ in }
      await #expect(voiceMemoViewModel.mode == .playing(progress: 5/6))
      try await effect.expect(\.timer) { _ in }
      await #expect(voiceMemoViewModel.mode == .playing(progress: 6/6))
      try await effect.expect(\.timer) { interval in
        #expect(interval == .seconds(0.5))
        return nil // stop the timer
      }
      try await effect.expect(\.AudioPlayback.play) { url in
        #expect(url == deadbeefURL)
        return true // finish playing with success
      }
      await #expect(voiceMemoViewModel.mode == .notPlaying)
      #expect(timerTask.isCancelled)
      #expect(playTask.isCancelled)
    }
  }
  
  @Test
  func permissionDenied() async throws {
    let viewModel = VoiceMemosViewModel()
    try await withTestHandler(taskHandling: .automaticallyEnqueue) {
      await viewModel.recordButtonTapped()
      await viewModel.openSettingsButtonTapped()
    } test: { effect in
      try await effect.expect(\.AudioRecording.requestRecordPermission, return: false)
      await #expect(viewModel.alertMessage == "Permission is required to record voice memos.")
      try await effect.expect(\.openSettings)
    }
  }
  
  @Test
  func recordFailure() async throws {
    struct SomeError: Error, Equatable {}
    let viewModel = VoiceMemosViewModel()
    try #require(viewModel.recordingMemo == nil)
    try await withTestHandler {
      await viewModel.recordButtonTapped()
    } test: { effect in
      try await effect.expect(\.AudioRecording.requestRecordPermission, return: true)
      try await effect.expect(\.temporaryDirectory, return: URL(fileURLWithPath: "/tmp"))
      try await effect.expect(\.uUID, return: deadbeefID)
      try await effect.expect(\.date, return: Date(timeIntervalSinceReferenceDate: 0))
      await #expect(viewModel.audioRecorderPermission == .allowed)
    }
    
    let recordingMemo = try #require(viewModel.recordingMemo)
    #expect(
      recordingMemo.state ==
      RecordingMemoViewModel.State(
        duration: 0,
        mode: .recording,
        date: Date(timeIntervalSinceReferenceDate: 0),
        url: deadbeefURL
      )
    )
    
    try await withTestHandler {
      await recordingMemo.start()
    } test: { effect in
      let timer = try await effect.expectTask("timer", action: .suspend)
      try await effect.expectTask("start recording", action: .enqueue)
      
      try await effect.expect(\.AudioRecording.startRecording) { url in
        #expect(url == deadbeefURL)
        throw SomeError()
      }
      #expect(timer.isCancelled)
      await #expect(viewModel.alertMessage == "Voice memo recording failed.")
      await #expect(viewModel.recordingMemo == nil)
    }
  }
  
  @Test
  func playHappyPath() async throws {
    let url = URL(fileURLWithPath: "pointfreeco/functions.m4a")
    let clock = TestClock()
    let voiceMemoViewModel = VoiceMemoViewModel(
      memo: VoiceMemo(
        date: Date(),
        duration: 1.25,
        title: "",
        url: url
      ),
      onPlaybackStarted: { _  in },
      onPlaybackFailed: {}
    )
    // Traditional mocking
    await with {
      Effect.Timer { interval in
        AsyncTimerSequence(interval: interval, clock: clock).map { _ in }
      }
      AudioPlayback.Play { url in
        try await clock.sleep(for: .milliseconds(1_250))
        return true
      }
    } perform: {
      voiceMemoViewModel.togglePlay()
    }
    // Temporary workaround while nested handlers don't work in tasks.
    try await Task.sleep(for: .seconds(0.1))
    #expect(voiceMemoViewModel.mode == .playing(progress: 0))
    await clock.advance(by: .milliseconds(500))
    try await Task.sleep(for: .seconds(0.1))
    #expect(voiceMemoViewModel.mode == .playing(progress: 0.4))
    await clock.advance(by: .milliseconds(500))
    try await Task.sleep(for: .seconds(0.1))
    #expect(voiceMemoViewModel.mode == .playing(progress: 0.8))
    await clock.advance(by: .milliseconds(250))
    try await Task.sleep(for: .seconds(0.1))
    #expect(voiceMemoViewModel.mode == .notPlaying)
  }
}

