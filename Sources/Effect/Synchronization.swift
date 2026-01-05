import Foundation

func runInParallelUntilBothCompleteOrEitherThrows<T>(
  isolation: isolated (any Actor)? = #isolation,
  operation: sending @escaping () async throws -> T,
  test: @EffectExecutionActor @escaping () async throws -> Void
) async throws -> T {
  let (stream, continuation) = AsyncThrowingStream<T, any Error>.makeStream(of: T.self)
  var transfer = SendableConsumeOnceBox(operation)
  Task {
    try await withThrowingTaskGroup(of: Void.self) { group in
      var operation = transfer.send()
      group.addTask {
        await continuation.yield(with: Result(catching: operation.take()))
      }
      group.addTask {
        do {
          try await test()
        } catch {
          continuation.yield(with: .failure(error))
        }
      }
      try await group.waitForAll()
      continuation.finish()
    }
  }
  
  var result: T?
  for try await i in stream {
    result = i
  }
  if let result {
    return result
  } else {
    preconditionFailure("")
  }
}

func withSendable<T, R>(
  isolation: isolated (any Actor)? = #isolation,
  _ operation: @escaping () async throws -> T,
  _ sending: (@Sendable @escaping @isolated(any) () async throws -> sending T) async throws -> sending R
) async rethrows -> sending R {
  let sendable = UnsafeTransfer(operation)
  return try await sending {
    try await sendable.value()
  }
}

//https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/UnsafeTransfer.swift
/// A wrapper struct to unconditionally to transfer an non-Sendable value.
public struct UnsafeTransfer<Value>: @unchecked Sendable {
  public let value: Value

  public init(_ value: Value) {
    self.value = value
  }
}

//https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/MultiProducerSingleConsumerChannel/MultiProducerSingleConsumerAsyncChannel%2BInternal.swift#L1733
@usableFromInline
struct SendableConsumeOnceBox<Wrapped>: ~Copyable {
  @usableFromInline
  var wrapped: Optional<Wrapped>

  @inlinable
  init(_ wrapped: consuming sending Wrapped) {
    self.wrapped = .some(consume wrapped)
  }

  @usableFromInline
  mutating func send() -> sending Self {
    .init(take())
  }
  
  @inlinable
  mutating func take() -> sending Wrapped {
    return self.wrapped.take()!
  }
}

extension Optional where Wrapped: ~Copyable {
  @usableFromInline
  mutating func take() -> sending Self {
    let result = consume self
    self = nil
    return result
  }
}

extension Result {
  @_transparent
  public init(catching body: () async throws(Failure) -> Success) async {
    do {
      self = .success(try await body())
    } catch {
      self = .failure(error)
    }
  }
}
