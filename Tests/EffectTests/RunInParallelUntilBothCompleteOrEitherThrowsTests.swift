import ConcurrencyExtras
@testable import Effect
import Testing

private struct OperationError: Error {}
private struct TestError: Error {}

private struct State {
  enum Event {
    case operationFinished
    case testFinished
  }
  var events: [Event] = []
}

@Suite
struct RunInParallelUntilBothCompleteOrEitherThrowsTests {
  @Test
  func waitsForBothToFinishWhenOperationFinishesFirst() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.1))
      return 42
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.2))
    }
    let result =  try await withSendable(operation) { operation in
      try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
    }
    #expect(result == 42)
    #expect(state.events == [.operationFinished, .testFinished])
  }
  
  @Test
  func waitsForBothToFinishWhenTestFinishesFirst() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.2))
      return 42
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.1))
    }
    let result =  try await withSendable(operation) { operation in
      try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
    }
    #expect(result == 42)
    #expect(state.events == [.testFinished, .operationFinished])
  }
  
  @Test
  func rethrowImmediatelyWhenOperationThrowsBeforeTestFinishes() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.1))
      throw OperationError()
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.2))
    }
    await #expect(throws: OperationError.self) {
      try await withSendable(operation) { operation in
        try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
      }
    }
    #expect(state.events == [.operationFinished])
  }
  
  @Test
  func rethrowWhenOperationThrowsAfterTestFinishes() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.2))
      throw OperationError()
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.1))
    }
    await #expect(throws: OperationError.self) {
      try await withSendable(operation) { operation in
        try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
      }
    }
    #expect(state.events == [.testFinished, .operationFinished])
  }
  
  @Test
  func rethrowImmediatelyWhenTestThrowsBeforeOperationFinishes() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.2))
      return 42
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.1))
      throw TestError()
    }
    await #expect(throws: TestError.self) {
      try await withSendable(operation) { operation in
        try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
      }
    }
    #expect(state.events == [.testFinished])
  }
  
  @Test
  func rethrowWhenTestThrowsAfterOperationFinishes() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.1))
      return 42
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.2))
      throw TestError()
    }
    await #expect(throws: TestError.self) {
      try await withSendable(operation) { operation in
        try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
      }
    }
    #expect(state.events == [.operationFinished, .testFinished])
  }
  
  @Test
  func rethrowImmediatelyWhenTestThrowsBeforeOperationThrows() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.2))
      throw OperationError()
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.1))
      throw TestError()
    }
    await #expect(throws: TestError.self) {
      try await withSendable(operation) { operation in
        try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
      }
    }
    #expect(state.events == [.testFinished])
  }
  
  @Test
  func rethrowImmediatelyWhenOperationThrowsBeforeTestThrows() async throws {
    let state = LockIsolated(State())
    func operation() async throws -> Int {
      defer { state.withValue { $0.events.append(.operationFinished) } }
      try await Task.sleep(for: .seconds(0.1))
      throw OperationError()
    }
    @EffectExecutionActor
    func test() async throws {
      defer { state.withValue { $0.events.append(.testFinished) } }
      try await Task.sleep(for: .seconds(0.2))
      throw TestError()
    }
    await #expect(throws: OperationError.self) {
      try await withSendable(operation) { operation in
        try await runInParallelUntilBothCompleteOrEitherThrows(operation: operation, test: test)
      }
    }
    #expect(state.events == [.operationFinished])
  }
}
