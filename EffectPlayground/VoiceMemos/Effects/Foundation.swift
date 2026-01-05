import AsyncAlgorithms
import Foundation
import UIKit
import Effect

extension Effect {
  @Effect
  static func date() -> Foundation.Date {
    Foundation.Date()
  }
  @Effect(name: "UUID")
  static func uuid() -> Foundation.UUID {
    Foundation.UUID()
  }
  @Effect
  static func temporaryDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
  }
  @Effect
  static func openSettings() async {
    await MainActor.run {
      UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
  }
  @Effect
  static func timer(interval: Duration) -> any AsyncSequence<Void, Never> {
    AsyncTimerSequence(interval: interval, clock: ContinuousClock()).map { _ in }
  }
}
