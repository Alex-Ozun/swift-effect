import Foundation

public protocol ThrowingTaskProtocol<Success>: Sendable, Hashable {
  associatedtype Success: Sendable
  
  var value: Success { get async throws }
  var result: Result<Success, any Error> { get async }
  func cancel()
  var isCancelled: Bool { get }
  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  func escalatePriority(to newPriority: TaskPriority)
}

public protocol TaskProtocol<Success>: Sendable, Hashable {
  associatedtype Success: Sendable
  
  var value: Success { get async }
  var result: Result<Success, Never> { get async }
  func cancel()
  var isCancelled: Bool { get }
  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  func escalatePriority(to newPriority: TaskPriority)
}

extension Task: TaskProtocol where Failure == Never {}
extension Task: ThrowingTaskProtocol where Failure == Error {}

extension TaskProtocol {
  /// Waits for the result of the task, propagating cancellation to the task.
  ///
  /// Equivalent to wrapping a call to `Task.value` in `withTaskCancellationHandler`.
  public var cancellableValue: Success {
    get async {
      await withTaskCancellationHandler {
        await self.value
      } onCancel: {
        self.cancel()
      }
    }
  }
}

extension ThrowingTaskProtocol {
  /// Waits for the result of the task, propagating cancellation to the task.
  ///
  /// Equivalent to wrapping a call to `Task.value` in `withTaskCancellationHandler`.
  public var cancellableValue: Success {
    get async throws {
      try await withTaskCancellationHandler {
        try await self.value
      } onCancel: {
        self.cancel()
      }
    }
  }
}

public extension Task {
  @discardableResult
  static func effect(
    name: String? = nil,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping @isolated(any) () async -> Success
  ) -> any TaskProtocol<Success> where Failure == Never {
    Effect.task(name: name, priority: priority, operation: operation)
  }
  
  @discardableResult
  static func effect(
    name: String? = nil,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping @isolated(any) () async throws -> Success
  ) -> any ThrowingTaskProtocol<Success> where Failure == (any Error) {
    Effect.task(name: name, priority: priority, operation: operation)
  }
  
  @discardableResult
  static func effect(
    name: String? = nil,
    executorPreference taskExecutor: (any TaskExecutor)?,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping () async -> Success
  ) -> any TaskProtocol<Success> where Failure == Never {
    Effect.task(
      name: name,
      priority: priority,
      operation: { @EffectTaskExecutionActor in
        await operation()
      }
    )
  }
  
  @discardableResult
  static func effect(
    name: String? = nil,
    executorPreference taskExecutor: (any TaskExecutor)?,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping () async throws -> Success
  ) -> any ThrowingTaskProtocol<Success> where Failure == (any Error) {
    Effect.task(
      name: name,
      priority: priority,
      operation: { @EffectTaskExecutionActor in
        try await operation()
      }
    )
  }
}

public extension Effect {
  @discardableResult
  static func task<Success: Sendable>(
    name: String? = nil,
    executorPreference taskExecutor: (any TaskExecutor)?,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping () async throws -> Success
  ) -> any ThrowingTaskProtocol<Success> {
    Effect.task(
      name: name,
      priority: priority,
      operation: { @EffectTaskExecutionActor in
        try await operation()
      }
    )
  }
  
  @discardableResult
  static func task<Success: Sendable>(
    name: String? = nil,
    executorPreference taskExecutor: (any TaskExecutor)?,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping () async -> Success
  ) -> any TaskProtocol<Success> {
    Effect.task(
      name: name,
      priority: priority,
      operation: { @EffectTaskExecutionActor in
        await operation()
      }
    )
  }
  
  @discardableResult
  static func task<Success: Sendable>(
    name: String? = nil,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping @isolated(any) () async throws -> Success
  ) -> any ThrowingTaskProtocol<Success> {
    if TestHandler.current.taskScheduling != .live
        && TestHandler.current.isTesting
        && TestHandler.current.nestingLevel >= TaskEffect<Success, any Error>.nestingLevel() {
      let task = EffectTask(name: name, isolatedOperation: operation)
      switch TestHandler.current.taskScheduling {
      case .suspend:
        let semaphore = DispatchSemaphore(value: 0)
        Task(priority: .userInitiated) {  @EffectExecutionActor in
          try await withCheckedThrowingContinuation { continuation in
            TestHandler.current.runtimeContinuation.yield(
              TaskEffectBridge<Success, any Error>(
                task: task,
                continuation: continuation
              )
            )
          }
          semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
        return task
      case .automaticallyEnqueue, .ignore:
        return task
      case .live:
        fatalError("We shouldn't be here")
      }
    } else {
      return Task(
        name: name,
        priority: priority,
        operation: operation
      )
    }
  }
  
  @discardableResult
  static func task<Success: Sendable>(
    name: String? = nil,
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: sending @escaping @isolated(any) () async -> Success
  ) -> any TaskProtocol<Success> {
    if TestHandler.current.taskScheduling != .live
        && TestHandler.current.isTesting
        && TestHandler.current.nestingLevel >= TaskEffect<Success, Never>.nestingLevel() {
      let task = EffectTask(name: name, isolatedOperation: operation)
      switch TestHandler.current.taskScheduling {
      case .suspend:
        let semaphore = DispatchSemaphore(value: 0)
        Task(priority: .userInitiated) {  @EffectExecutionActor in
          await withCheckedContinuation { continuation in
            TestHandler.current.runtimeContinuation.yield(
              TaskEffectBridge(
                task: task,
                continuation: continuation
              )
            )
          }
          semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
        return task
      case .automaticallyEnqueue, .ignore:
        return task
      case .live:
        fatalError("We shouldn't be here")
      }
    } else {
      return Task(
        name: name,
        priority: priority,
        operation: operation
      )
    }
  }
  
  private nonisolated static let __task_storage: TaskLocal<[ObjectIdentifier: any Sendable]> = TaskLocal(wrappedValue: [:])
  
  private nonisolated static func __task<Success: Sendable, Failure: Error>() -> @Sendable (EffectTask<Success, Failure>) -> Void {
    if let impl = __task_storage.get()[ObjectIdentifier(TaskEffectHandler<Success, Failure>.self)] {
      return impl as! @Sendable (EffectTask<Success, Failure>) -> Void
    } else {
      return { task in
        Task(
          name: task.name,
          priority: task.priority,
          operation: task.operation
        )
      }
    }
  }
  
  struct TaskEffectHandler<Success: Sendable, Failure: Error>: SyncEffectHandler {
    public typealias _Effect = TaskEffect<Success, Failure>
    var task: @Sendable (EffectTask<Success, Failure>) -> Void
    
    init(
      task: @Sendable @escaping (EffectTask<Success, Failure>) -> Void  = Effect.__task()
    ) {
      self.task = task
    }
    
    public func handle<EffectReturnType>(
      isolation: isolated (any Actor)? = #isolation,
      operation: () async throws -> EffectReturnType
    ) async rethrows -> EffectReturnType {
      let parent_task: @Sendable (EffectTask<Success, Failure>) -> Void  = __task()
      let parent_nestingLevel = Effect.nestingLevel
      let task: @Sendable (EffectTask<Success, Failure>) -> Void  = { task in
        Effect.$nestingLevel.withValue(parent_nestingLevel) {
          __task_nestingLevel_storage.withValue(
            __task_nestingLevel_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : Effect.nestingLevel]) { _, new in
              new
            }
          ) {
            __task_storage.withValue(
              __task_storage.get().merging(
                [ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : parent_task]
              ) { _, new in
                new
              }
            ) {
              self.task(task)
            }
          }
        }
      }
      let result = try await __task_storage.withValue(
        __task_storage.get().merging(
          [ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : task]
        ) { _, new in
          new
        }
      ) {
        try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
          try await __task_nestingLevel_storage.withValue(
            __task_nestingLevel_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : Effect.nestingLevel]) { _, new in
              new
            }
          ) {
            let result = try await operation()
            if let effectScope = result as? EffectScope {
              let key = ObjectIdentifier(TaskEffectHandler.self)
              effectScope._capturedHandlers.handlers[key] = self
              return effectScope as! EffectReturnType
            } else {
              return result
            }
          }
        }
      }
      return result
    }
    
    public func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
      let parent_task: @Sendable (EffectTask<Success, Failure>) -> Void = __task()
      let parent_nestingLevel = Effect.nestingLevel
      let task: @Sendable (EffectTask<Success, Failure>) -> Void = { task in
        Effect.$nestingLevel.withValue(parent_nestingLevel) {
          __task_nestingLevel_storage.withValue(
            __task_nestingLevel_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : Effect.nestingLevel]) { _, new in
              new
            }
          ) {
            __task_storage.withValue(
              __task_storage.get().merging(
                [ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : parent_task]
              ) { _, new in
                new
              }
            ) {
              self.task(task)
            }
          }
        }
      }
      let result = try  __task_storage.withValue(
        __task_storage.get().merging(
          [ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : task]
        ) { _, new in
          new
        }
      ) {
        try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
          try __task_nestingLevel_storage.withValue(
            __task_nestingLevel_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : Effect.nestingLevel]) { _, new in
              new
            }
          ) {
            let result = try operation()
            if let effectScope = result as? EffectScope {
              let key = ObjectIdentifier(TaskEffectHandler.self)
              effectScope._capturedHandlers.handlers[key] = self
              return effectScope as! EffectReturnType
            } else {
              return result
            }
          }
        }
      }
      return result
    }
  }
  
  nonisolated static let __task_nestingLevel_storage: TaskLocal<[ObjectIdentifier: UInt8]> = TaskLocal(wrappedValue: [:])
 
  struct TaskEffect<Success: Sendable, Failure: Error>: EffectProtocol {
    public typealias _Handler = TaskEffectHandler<Success, Failure>
    public func enqueue() {
      TestHandler.current.unstructuredTaskScheduler.enqueue(task.underlying)
    }
    
    func resume() async {
      await continuation.resume()
    }
    
    public func yield() async throws {
      await continuation.resume()
    }
    
    nonisolated static func nestingLevel() -> UInt8 {
      if let nestingLevel = __task_nestingLevel_storage.get()[ObjectIdentifier(TaskEffect.self)] {
        return nestingLevel
      } else {
        return 0
      }
    }
    
    private let task: EffectTask<Success, Failure>
    public let continuation: EffectContinuation<Void, Failure>
    public var name: String? { task.name }
    public var isCancelled: Bool { task.isCancelled }
    
    init(
      task: EffectTask<Success, Failure>,
      continuation: EffectContinuation<Void, Failure>
    ) {
      self.task = task
      self.continuation = continuation
    }
    
    public nonisolated var description: String {
      """
      \(TaskEffect<Success, Failure>.self)
      \(task.name.map { "Name: \($0)" } ?? "")
      "ID: \(task.id)"
      """
    }
  }
  
  private struct TaskEffectBridge<Success: Sendable, Failure: Error>: EffectBridge {
    let task: EffectTask<Success, Failure>
    let continuation: CheckedContinuation<Void, Failure>
    
    nonisolated init(
      task: EffectTask<Success, Failure>,
      continuation: CheckedContinuation<Void, Failure>
    ) {
      self.task = task
      self.continuation = continuation
    }
    
    func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> TaskEffect<Success, Failure> {
      .init(
        task: task,
        continuation: EffectContinuation { _ in
          continuation.resume()
          await execute()
        }
      )
    }
  }
  
  static func withTaskEffect<EffectReturnType, Success: Sendable, Failure: Error>(
    _ handler: TaskEffectHandler<Success, Failure>,
    operation: sending () async throws -> EffectReturnType
  ) async rethrows -> EffectReturnType {
    let parent_task: @Sendable (EffectTask<Success, Failure>) -> Void = __task()
    let task: @Sendable (EffectTask<Success, Failure>) -> Void  = { task in
      __task_storage.withValue(
        __task_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : parent_task]) { _, new in new }
      ) {
        handler.task(task)
      }
    }
    let result = try await __task_storage.withValue(
      __task_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : task]) { _, new in new }
    ) {
      try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
        try await __task_nestingLevel_storage.withValue(
          __task_nestingLevel_storage.get().merging([ObjectIdentifier(TaskEffectHandler<Success, Failure>.self) : Effect.nestingLevel]) { _, new in
            new
          }
        ) {
          try await operation()
        }
      }
    }
    return result
  }
}

public enum TaskSchedulingAction: Sendable {
  case enqueue
  case suspend
}

struct MyError: Error {}

struct EffectTask<Success: Sendable, Failure: Error>: @unchecked Sendable, Hashable {
  static func == (lhs: EffectTask<Success, Failure>, rhs: EffectTask<Success, Failure>) -> Bool {
    lhs.name == rhs.name
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(name)
  }
  let underlying: AnyTaskEffect
  let operation: @isolated(any) () async throws -> Success
  let id = UUID()
  let name: String?
  let priority: TaskPriority?
  var isCancelled: Bool {
    switch underlying.state {
    case .cancelled: true
    default: false
    }
  }
  func cancel() {
    underlying.state = .cancelled
  }
  
  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  func escalatePriority(to newPriority: TaskPriority) {}
  var result: Result<Success, Failure> {
    get async {
      fatalError("unimplemented")
    }
  }
}

extension EffectTask: ThrowingTaskProtocol where Failure == (any Error) {
  init(
    name: String? = nil,
    priority: TaskPriority? = nil,
    isolatedOperation: sending @escaping @isolated(any) () async throws -> Success
  ) {
    self.name = name
    self.priority = priority
    self.operation = { @EffectTaskExecutionActor in
      try await isolatedOperation()
    }
    underlying = AnyTaskEffect(id: id, name: name, operation: operation)
  }
  
  init(
    name: String? = nil,
    priority: TaskPriority? = nil,
    operation: sending @escaping () async throws -> Success
  ) {
    self.name = name
    self.priority = priority
    self.operation = { @EffectTaskExecutionActor in
      try await operation()
    }
    underlying = AnyTaskEffect(id: id, name: name, operation: self.operation)
  }
  var value: Success {
    get async throws {
      try await TestHandler.current.unstructuredTaskScheduler.value(forTaskID: id) as! Success
    }
  }
}

extension EffectTask: TaskProtocol where Failure == Never {
  var value: Success {
    get async {
      try! await TestHandler.current.unstructuredTaskScheduler.value(forTaskID: id) as! Success
    }
  }
  
  init(
    name: String? = nil,
    priority: TaskPriority? = nil,
    isolatedOperation: sending @escaping @isolated(any) () async -> Success
  ) {
    self.name = name
    self.priority = priority
    self.operation = { @EffectTaskExecutionActor in
      await isolatedOperation()
    }
    underlying = AnyTaskEffect(id: id, name: name, operation: operation)
  }
  
  init(
    name: String? = nil,
    priority: TaskPriority? = nil,
    operation: sending @escaping () async -> Success
  ) {
    self.name = name
    self.priority = priority
    self.operation = { @EffectTaskExecutionActor in
      await operation()
    }
    underlying = AnyTaskEffect(id: id, name: name, operation: self.operation)
  }
}

final class AnyTaskEffect: @unchecked Sendable {
  enum State: Sendable {
    case created
    case enqueued
    case executing
    case completed(any Sendable)
    case cancelled
  }
  var state: State = .created
  let id: UUID
  let name: String?
  let operation: @isolated(any) () async throws -> any Sendable
  
  init<Success: Sendable, Failure: Error>(_ effectTask: EffectTask<Success, Failure>) {
    id = effectTask.id
    name = effectTask.name
    operation = effectTask.operation
  }
  
  init(
    id: UUID,
    name: String?,
    operation: @escaping @isolated(any) () async throws -> any Sendable,
  ) {
    self.id = id
    self.name = name
    self.operation = operation
    TestHandler.current.unstructuredTaskScheduler.add(self)
  }
  
  func getValue<Success: Sendable>(of: Success.Type) async throws -> Success {
    let result = try await operation()
    if let result = result as? Success {
      return result
    } else {
      throw TypeMismatch(message: "Task returned a value of type \(result.self), expected \(Success.self)")
    }
  }
}

struct TypeMismatch: Error {
  let message: String
}
