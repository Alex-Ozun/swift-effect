import Foundation
@testable import Effect
import Testing

@Suite
struct EffectSchedulingActorTests {
  @Test
  func withCriticalRegion() async throws {
    class UncheckedSendable: @unchecked Sendable {
      var value = 0
    }
    let offset = UncheckedSendable()
    
    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
      for i in 0...1000 {
        taskGroup.addTask {
          try await EffectSchedulingActor.shared.withCriticalRegion {
            #expect(offset.value == 0)
            offset.value = i
            try await Task.sleep(for: .milliseconds(1))
            // i serves as a "random" offset to make sure we're not just luckily landing on another task's identical offset
            #expect(offset.value == i)
            offset.value = 0
        }
        }
      }
      try await taskGroup.waitForAll()
    }
    #expect(offset.value == 0)
  }
}
