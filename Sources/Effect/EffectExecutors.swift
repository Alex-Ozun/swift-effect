import Dispatch
import Semaphore

@globalActor
public actor EffectSchedulingActor {
  private let runtimeExecutor = SerialQueueExecutor(queue: DispatchQueue(label: "swift-effect.scheduling"))
  
  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    runtimeExecutor.asUnownedSerialExecutor()
  }
  
  public static let shared = EffectSchedulingActor()
  private let semaphore = AsyncSemaphore(value: 1)
  
  func withCriticalRegion<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: @escaping () async throws -> T
  ) async throws -> T {
    await semaphore.wait()
    defer { semaphore.signal() }
    return try await body()
  }
}

@globalActor
public actor EffectExecutionActor {
  private let runtimeExecutor = SerialQueueExecutor(queue: DispatchQueue(label: "swift-effect.execution"))
  
  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    runtimeExecutor.asUnownedSerialExecutor()
  }
  
  public static let shared = EffectExecutionActor()
  private let semaphore = AsyncSemaphore(value: 1)
  
  func withCriticalRegion<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: @escaping () async throws -> T
  ) async throws -> T {
    await semaphore.wait()
    defer { semaphore.signal() }
    return try await body()
  }
}

@globalActor
public actor EffectTaskExecutionActor {
  private let runtimeExecutor = SerialQueueExecutor(queue: DispatchQueue(label: "swift-effect-task.execution"))
  
  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    runtimeExecutor.asUnownedSerialExecutor()
  }
  
  public static let shared = EffectTaskExecutionActor()
  private let semaphore = AsyncSemaphore(value: 1)
  
  func withCriticalRegion<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: @escaping () async throws -> T
  ) async throws -> T {
    await semaphore.wait()
    defer {
      semaphore.signal()
    }
    return try await body()
  }
}

private final class SerialQueueExecutor: SerialExecutor {
  let queue: DispatchQueue
  init(queue: DispatchQueue) {
    self.queue = queue
  }
  
  func enqueue(_ job: consuming ExecutorJob) {
    let unownedJob = UnownedJob(job)
    queue.async {
      unownedJob.runSynchronously(on: self.asUnownedSerialExecutor())
    }
  }

  func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    UnownedSerialExecutor(ordinary: self)
  }
}
