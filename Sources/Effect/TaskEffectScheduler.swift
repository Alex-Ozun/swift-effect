import Foundation

final class TaskEffectScheduler: @unchecked Sendable, IteratorProtocol, Sequence {
  private let lock = NSRecursiveLock()
  private var executionQueue: [AnyTaskEffect] = []
  private var values: [UUID: any Sendable] = [:]
  private var tasks: [UUID: AnyTaskEffect] = [:]
  
  var hasEnqueuedTasks: Bool {
    lock.sync {
      !executionQueue.isEmpty
    }
  }
  func next() -> AnyTaskEffect? {
    lock.sync {
      if !executionQueue.isEmpty {
        let task = executionQueue.removeFirst()
        task.state = .executing
        return task
      } else {
        return nil
      }
    }
  }
  
  func add(_ task: AnyTaskEffect) {
    lock.sync {
      tasks[task.id] = task
      if case .automaticallyEnqueue = TestHandler.current.taskScheduling {
        enqueue(task)
      }
    }
  }
  
  func enqueue(_ task: AnyTaskEffect) {
    lock.sync {
      switch task.state {
      case .created:
        task.state = .enqueued
        executionQueue.append(task)
      case .cancelled, .executing, .enqueued, .completed:
        return
      }
    }
  }
  
  func dequeueTask(with id: UUID) -> AnyTaskEffect? {
    lock.sync {
      if let index = executionQueue.firstIndex(where: { $0.id == id }) {
        let task = executionQueue.remove(at: index)
        task.state = .executing
        return task
      } else if let task = tasks[id] {
        task.state = .executing
        return task
      } else {
        return nil
      }
    }
  }
  
  func complete(task: AnyTaskEffect, with value: any Sendable) {
    lock.sync {
      task.state = .completed(value)
    }
  }
  
  private func value(for id: UUID) -> (any Sendable)? {
    lock.sync {
      switch tasks[id]?.state {
      case let .completed(value): return value
      default: return nil
      }
    }
  }
  
  func value(forTaskID id: UUID) async throws -> any Sendable {
    try await EffectTaskExecutionActor.shared.withCriticalRegion {
      if let value = self.value(for: id) {
        return value
      } else if let task = self.dequeueTask(with: id) {
        let value = try await task.operation()
        self.complete(task: task, with: value)
        return value
      } else if let task = self.tasks[id] {
        preconditionFailure("Unexpected task state. Name: \(task.name ?? "")\n id: \(task.id)\n \(task.state)")
      } else {
        preconditionFailure("Task not found. id: \(id)")
      }
    }
  }
}

public enum TaskHandlingMode: Sendable {
  /// Suspend every unstructured Task upon its creation.
  /// TestHandler must explicitly handle all incoming tasks in order of creation, and decide on whether to enqueue or skip them.
  case suspend
  /// Automatically add every unstructured Task, in order of creation, to the end of the serial execution queue.
  /// TestHandler will not observe any incoming Tasks, only the effects produced by these tasks when they execute.
  case automaticallyEnqueue
  /// Don't enqueue, intercept, or execute any unstructured Tasks. Execution finishes when the program-under-test goes out of scope.
  case ignore
  /// Allow Swift Concurrency runtime to enqueue tasks normally.
  case live
}

extension NSRecursiveLock {
  @inlinable @discardableResult
  @_spi(Internals) public func sync<R>(work: () throws -> R) rethrows -> R {
    self.lock()
    defer { self.unlock() }
    return try work()
  }
}
