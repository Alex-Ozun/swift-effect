import Foundation

public protocol ContinuationProtocol<Value, Failure>: Sendable, ~Copyable {
  associatedtype Value
  associatedtype Failure: Error
}

struct NoContinuation: ContinuationProtocol {
  public typealias Value = Never
  public typealias Failure = Never
}

@EffectExecutionActor
public struct EffectContinuation<Value, Failure: Error>: ContinuationProtocol {
  private let continuation: (sending Result<Value, Failure>) async -> Void
  
  public init(_ continuation: @escaping (sending Result<Value, Failure>) async -> Void) {
    self.continuation = continuation
  }
  
  public func resume(returning value: sending Value) async {
    await continuation(.success(value))
  }
  
  public func resume(throwing error: Failure) async {
    await continuation(.failure(error))
  }
  
  public func resume(with result: sending Result<Value, Failure>) async {
    await continuation(result)
  }
  
  public func resume() async where Value == Void {
    await continuation(.success(()))
  }
}

public struct EffectStreamContinuation<Value, Failure: Error>: ContinuationProtocol {
  private let base: CheckedContinuation<Value, any Error>
  
  public init(_ base: CheckedContinuation<Value, any Error>) {
    self.base = base
  }
  
  public func resume(returning value: sending Value) {
    base.resume(returning: value)
  }
  
  public func resume(throwing error: Failure) {
    base.resume(throwing: error)
  }
  
  public func resume(with result: sending Result<Value, Failure>) {
    base.resume(with: result)
  }
}

extension CheckedContinuation: ContinuationProtocol {
  public typealias Value = T
  public typealias Failure = E
}
