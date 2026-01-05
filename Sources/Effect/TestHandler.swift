@_exported import Dispatch
import IssueReporting
import Foundation

extension Effect {
  public static func reportIssue(
    _ message: @autoclosure () -> String? = nil,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    IssueReporting.reportIssue(
      message(),
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
}

public func withTestHandler<T>(
  isolation: isolated (any Actor)? = #isolation,
  taskHandling: TaskHandlingMode = .suspend,
  operation: @escaping () async throws -> T,
  test: @escaping @EffectExecutionActor (EffectTest) async throws -> Void
) async throws -> T {
  try await EffectSchedulingActor.shared.withCriticalRegion {
    try await _withTestHandler(
      taskScheduling: taskHandling,
      operation: operation,
      test: test
    )
  }
}

private func _withTestHandler<T>(
  isolation: isolated (any Actor)? = #isolation,
  taskScheduling: TaskHandlingMode,
  operation: @escaping () async throws -> T,
  test: @escaping @EffectExecutionActor (EffectTest) async throws -> Void
) async throws -> T {
  let nestingLevel = Effect.nestingLevel + 1
  let testHandler = Effect.$nestingLevel.withValue(nestingLevel) {
    TestHandler(
      isTesting: true,
      nestingLevel: Effect.nestingLevel,
      taskScheduling: taskScheduling,
      test: test
    )
  }
  
  return try await runInParallelUntilBothCompleteOrEitherThrows(
    operation:  {
      try await TestHandler.$current.withValue(testHandler) {
        try await Effect.$nestingLevel.withValue(nestingLevel) {
          await testHandler.start()
          let result = try await operation()
          testHandler.endOfScope()
          for await _ in testHandler.blockStream {
            if let task = testHandler.unstructuredTaskScheduler.next() {
              _ = try await task.operation()
            }
            testHandler.endOfScope()
          }
          return result
        }
      }
    },
    test: {
      try await testHandler.begin()
      await testHandler.advanceToNextEffect()
      if let effect = testHandler.testEffect.value, !(effect is Exit) {
        throw UnhandledEffect(effect: effect)
      }
      testHandler.blockContinuation.finish()
    }
  )
}

public struct TestHandler: Sendable {
  @TaskLocal
  public static var current: TestHandler = .shared
  static let shared = TestHandler()
  public let isTesting: Bool
  public let nestingLevel: UInt8
  public let taskScheduling: TaskHandlingMode
  
  @EffectExecutionActor var testEffect = Effect()
  let unstructuredTaskScheduler = TaskEffectScheduler()

  init(
    isTesting: Bool = false,
    nestingLevel: UInt8 = 0,
    taskScheduling: TaskHandlingMode = .suspend,
    test: @escaping @EffectExecutionActor (EffectTest) async throws -> Void = { _ in },
  ) {
    self.isTesting = isTesting
    self.test = test
    self.nestingLevel = nestingLevel
    self.taskScheduling = taskScheduling
  }
  let test: @EffectExecutionActor (EffectTest) async throws -> Void
  public var runtimeContinuation: AsyncStream<any EffectBridge>.Continuation {
    _runtimeContinuation
  }
  var (effects, _runtimeContinuation) = AsyncStream<any EffectBridge>.makeStream()
  public var (blockStream, blockContinuation) = AsyncStream<Void>.makeStream()
  
  @EffectExecutionActor
  func begin() async throws {
    await execute()
    guard let start = testEffect.value as? StartEffect else {
      return
    }
    await start.continuation.resume()
    try await TestHandler.$current.withValue(self) {
      try await self.test(EffectTest(effect: testEffect))
    }
  }
  
  func start() async {
    await withCheckedContinuation { continuation in
      self.runtimeContinuation.yield(
        StartEffectBridge(continuation: continuation)
      )
    }
  }
  
  public func endOfScope() {
    runtimeContinuation.yield(ExitEffectBridge(continuation: NoContinuation()))
  }
  
  @EffectExecutionActor
  public func advanceToNextEffect() async {
    while (self.testEffect.value is Exit || self.testEffect.value is StartEffect) && (unstructuredTaskScheduler.hasEnqueuedTasks || taskScheduling == .live){
      blockContinuation.yield()
      await execute()
    }
  }
  
  @EffectExecutionActor
  public func drainTaskQueueAndReportUnhandledEffects() async -> Bool {
    while self.testEffect.value is Exit && unstructuredTaskScheduler.hasEnqueuedTasks {
      blockContinuation.yield()
      await execute()
    }
    return !(self.testEffect.value is Exit)
  }
  
  @EffectExecutionActor
  public func execute() async {
    var iterator = self.effects.makeAsyncIterator()
    
    guard let effectIR = await iterator.next() else {
      let exit = Exit(continuation: NoContinuation())
      testEffect.set(exit)
      return
    }
    let effect = effectIR.effect {
      await self.execute()
    }
    testEffect.set(effect)
  }
}
