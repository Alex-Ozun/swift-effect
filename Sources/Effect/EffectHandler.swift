import Foundation

public protocol SyncEffectHandler: EffectHandler {
  func handle<T>(operation: () throws -> T) rethrows -> T
}

public protocol EffectHandler: Sendable {
  associatedtype _Effect: EffectProtocol
  func handle<T>(
    isolation: isolated (any Actor)?,
    operation: () async throws -> T
  ) async rethrows -> T
}

public func with<T, Handler: EffectHandler>(
  isolation: isolated (any Actor)? = #isolation,
  _ handler: Handler,
  operation: () async throws -> T
) async rethrows -> T {
  try await handler.handle(isolation: isolation, operation: operation)
}

public func with<T, Handler: SyncEffectHandler>(
  _ handler: Handler,
  perform: () throws -> T
) rethrows -> T {
  try handler.handle(operation: perform)
}

@_disfavoredOverload
func with<T>(
  isolation: isolated (any Actor)? = #isolation,
  _ handlers: [any EffectHandler],
  perform: () async throws -> T
) async rethrows -> T {
  try await withoutActuallyEscaping(perform) { operation in
    try await handlers
      .reversed()
      .reduce(operation) { composedOperation, handler in
        {
          try await handler.handle(isolation: isolation) {
            try await composedOperation()
          }
        }
      }()
  }
}

public func with<T>(
  @EffectHandlersBuilder _ handlers: () -> [any EffectHandler],
  isolation: isolated (any Actor)? = #isolation,
  perform: () async throws -> T
) async rethrows -> T {
  try await with(handlers(), perform: perform)
}

@_disfavoredOverload
func with<T>(
  _ handlers: [any SyncEffectHandler],
  isolation: isolated (any Actor)? = #isolation,
  perform: () throws -> T,
) rethrows -> T {
  try withoutActuallyEscaping(perform) { operation in
    try handlers
      .reversed()
      .reduce(operation) { composedOperation, handler in
        {
          try handler.handle { try composedOperation() }
        }
      }()
  }
}

public func with<T>(
  @SyncEffectHandlersBuilder _ handlers: () -> [any SyncEffectHandler],
  perform: () throws -> T
) rethrows -> T {
  try with(handlers(), perform: perform)
}

@resultBuilder
public enum EffectHandlersBuilder {
  public static func buildBlock(_ components: [any EffectHandler]...) -> [any EffectHandler] {
    components.flatMap { $0 }
  }

  public static func buildExpression(_ expression: (any EffectHandler)) -> [any EffectHandler] {
    [expression]
  }

  public static func buildExpression(_ expression: [any EffectHandler]) -> [any EffectHandler] {
    expression
  }

  public static func buildOptional(_ component: [any EffectHandler]?) -> [any EffectHandler] {
    component ?? []
  }

  public static func buildEither(first component: [any EffectHandler]) -> [any EffectHandler] {
    component
  }

  public static func buildEither(second component: [any EffectHandler]) -> [any EffectHandler] {
    component
  }

  public static func buildArray(_ components: [[any EffectHandler]]) -> [any EffectHandler] {
    components.flatMap { $0 }
  }

  public static func buildFinalResult(_ component: [any EffectHandler]) -> [any EffectHandler] {
    component
  }
}

@resultBuilder
public enum SyncEffectHandlersBuilder {
  public static func buildBlock(_ components: [any SyncEffectHandler]...) -> [any SyncEffectHandler] {
    components.flatMap { $0 }
  }

  public static func buildExpression(_ expression: (any SyncEffectHandler)) -> [any SyncEffectHandler] {
    [expression]
  }

  public static func buildExpression(_ expression: [any SyncEffectHandler]) -> [any SyncEffectHandler] {
    expression
  }

  public static func buildOptional(_ component: [any SyncEffectHandler]?) -> [any SyncEffectHandler] {
    component ?? []
  }

  public static func buildEither(first component: [any SyncEffectHandler]) -> [any SyncEffectHandler] {
    component
  }

  public static func buildEither(second component: [any SyncEffectHandler]) -> [any SyncEffectHandler] {
    component
  }

  public static func buildArray(_ components: [[any SyncEffectHandler]]) -> [any SyncEffectHandler] {
    components.flatMap { $0 }
  }

  public static func buildFinalResult(_ component: [any SyncEffectHandler]) -> [any SyncEffectHandler] {
    component
  }
}
