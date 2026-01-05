import Foundation

@EffectExecutionActor
public protocol EffectProtocol<Value, Failure>: Sendable {
  associatedtype Value
  associatedtype Failure: Error
  associatedtype Continuation: ContinuationProtocol<Value, Failure>
  associatedtype Arguments = Never
  var _arguments: Arguments { get }
  var continuation: Continuation { get }
  nonisolated var description: String { get }
  func yield() async throws
  func resume(with result: sending Result<Value, Failure>) async
}

extension EffectProtocol {
  public var _arguments: Arguments {
    fatalError()
  }
}

public extension EffectProtocol {
  nonisolated var description: String {
    String(describing: type(of: self))
  }
}

@EffectExecutionActor
public extension EffectProtocol where Continuation == EffectContinuation<Value, Failure> {
  func resume(returning value: sending Value) async {
    await continuation.resume(returning: value)
  }
  
  func resume(throwing error: Failure) async {
    await continuation.resume(throwing: error)
  }
  
  func resume(with result: sending Result<Value, Failure>) async {
    await continuation.resume(with: result)
  }
}

@EffectExecutionActor
public extension EffectProtocol where Continuation == EffectContinuation<Void, Failure> {
  func resume() async {
    await continuation.resume(returning: ())
  }
}

@EffectExecutionActor
public protocol EffectBridge: Sendable {
  associatedtype Effect: EffectProtocol
  associatedtype Continuation: ContinuationProtocol where Continuation.Value == Effect.Value, Continuation.Failure == Effect.Failure
  var continuation: Continuation { get }
  func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> Effect
}

public protocol EffectScope {
  var _capturedHandlers: Effect.CapturedHandlers { get set }
}

public final class EffectTest: Sendable {
  let effect: Effect
  
  init(effect: Effect) {
    self.effect = effect
  }
  
  @EffectExecutionActor
  public func suspend<Handler: EffectHandler>(
    _ effect: KeyPath<Effect, Handler.Type>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws -> Handler._Effect {
    await TestHandler.current.advanceToNextEffect()
    guard let value = self.effect.value as? Handler._Effect else {
      Effect.reportIssue(
        "Expected \(Handler._Effect.self), received \(self.effect.value!.description)",
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      throw UnexpectedEffect()
    }
    return value
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _: Handler.Type,
    _ handle: (Handler._Effect.Arguments) async throws -> Handler._Effect.Value,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    await TestHandler.current.advanceToNextEffect()
    guard let effect = self.effect.value as? Handler._Effect else {
      Effect.reportIssue(
        "Expected \(Handler._Effect.self), received \(self.effect.value!.description)",
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      throw UnexpectedEffect()
    }
    do {
      let result = try await handle(effect._arguments)
      await effect.resume(with: .success(result))
    } catch {
      // temporary workaround since typed throws aren't correctly inferring types from the handle closure
      await effect.resume(with: .failure(error as! Handler._Effect.Failure))
    }
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _ effect: KeyPath<Effect, Handler.Type>,
    _ handle: (Handler._Effect.Arguments) async throws -> Handler._Effect.Value,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    try await expect(
      Handler.self,
      handle,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _: Handler.Type,
    return value: sending Handler._Effect.Value,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws where Handler._Effect.Arguments == Void {
    try await expect(
      Handler.self,
      { value },
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _ effect: KeyPath<Effect, Handler.Type>,
    return value: sending Handler._Effect.Value,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws where Handler._Effect.Arguments == Void {
    try await expect(
      effect,
      { value },
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _ effect: KeyPath<Effect, Handler.Type>,
    result: sending Result<Handler._Effect.Value, Handler._Effect.Failure>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws where Handler._Effect.Arguments == Void {
    try await expect(
      effect,
      { try result.get() },
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _ :Handler.Type,
    result: sending Result<Handler._Effect.Value, Handler._Effect.Failure>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws where Handler._Effect.Arguments == Void {
    try await expect(
      Handler.self,
      { try result.get() },
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _ effect: KeyPath<Effect, Handler.Type>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws where Handler._Effect.Value == Void, Handler._Effect.Arguments == Void {
    try await expect(
      effect,
      {},
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  public func expect<Handler: EffectHandler>(
    _ :Handler.Type,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws where Handler._Effect.Value == Void, Handler._Effect.Arguments == Void {
    try await expect(
      Handler.self,
      {},
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  @EffectExecutionActor
  @discardableResult
  public func expectTask<Success: Sendable, Failure: Error>(
    of: Success.Type = Void.self,
    failure: Failure.Type = Never.self,
    _ name: String? = nil,
    action: TaskSchedulingAction = .enqueue,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws -> Effect.TaskEffect<Success, Failure> {
    await TestHandler.current.advanceToNextEffect()
    let skipNameCheck = name == nil
    guard let task = self.effect.value as? Effect.TaskEffect<Success, Failure>, (skipNameCheck || task.name == name) else {
      Effect.reportIssue(
        "Expected \(Effect.TaskEffect<Success, Failure>.self), received \(self.effect.value!.description)",
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      throw UnexpectedEffect()
    }
    switch action {
    case .enqueue:
      await task.enqueue()
    case .suspend: break
    }
    await task.resume()
    return task
  }
  
  @EffectExecutionActor
  public func yield() async throws {
    await TestHandler.current.advanceToNextEffect()
    try await self.effect.value?.yield()
  }
}

public final class Effect: Sendable {
  public final class CapturedHandlers: @unchecked Sendable { // TODO: fix
    public var handlers: [ObjectIdentifier: any EffectHandler] = [:]
    public init() {}
  }
  
  @TaskLocal public static var nestingLevel: UInt8 = 0
  
  @EffectExecutionActor
  public private(set) var value: (any EffectProtocol)? = nil
  
  @EffectExecutionActor
  func set(_ value: some EffectProtocol) {
    self.value = value
  }
  
  public static func withScope<T>(
    _ effectScope: Effect.CapturedHandlers,
    @_implicitSelfCapture _ operation: () throws -> T
  ) rethrows -> T {
    let handlers = effectScope.handlers.values.compactMap { $0 as? (any SyncEffectHandler) }
    return try with(handlers) {
      try operation()
    }
  }
  
  public static func withScope<T>(
    isolation: isolated (any Actor)? = #isolation,
    _ effectScope: Effect.CapturedHandlers,
    @_implicitSelfCapture _ operation: () async throws -> T
  ) async rethrows -> T {
    let handlers = effectScope.handlers.values.compactMap { $0 as? (any SyncEffectHandler) }
    return try await with(isolation: isolation, handlers) {
      try await operation()
    }
  }
}

func rethrow<T>(operation: () throws -> T)  rethrows -> T {
  try operation()
}

func rethrow<T>(_ operation: () async throws -> T) async rethrows ->  T {
  try await operation()
}

public struct UnexpectedEffect: Error {
  public init(){}
}

public struct UnhandledEffect: Error {
  let effect: String
  public init(effect: any EffectProtocol) {
    self.effect = effect.description
  }
}

public class _EffectResult<T, E: Error>: @unchecked Sendable {
  public var value: Result<T, E>? = nil
  public func setValue(_ value: Result<T, E>) {
    self.value = value
  }
  public init() {
    self.value = nil
  }
}
