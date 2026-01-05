import SwiftUI

@main
struct VoiceMemosApp: App {
  var body: some Scene {
    WindowGroup {
      VoiceMemosView(viewModel: VoiceMemosViewModel())
    }
  }
}
