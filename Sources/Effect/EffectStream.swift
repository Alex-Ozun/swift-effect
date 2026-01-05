import Foundation

public struct EffectStream<Element, Failure: Error>: AsyncSequence, AsyncIteratorProtocol {
  public func makeAsyncIterator() -> EffectStream<Element, Failure> {
    self
  }
  
  public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        TestHandler.current.runtimeContinuation.yield(
          effect(EffectStreamContinuation(continuation))
        )
      }
    } catch {
      // Guaranteed to be Failure because it's thrown by EffectStreamContinuation
      throw (error as! Failure)
    }
  }
  
  private var effect: (EffectStreamContinuation<Element?, Failure>) -> any EffectBridge
  
  public init<Effect: EffectBridge>(
    effect: @escaping (EffectStreamContinuation<Element?, Failure>) -> Effect
  ) where Effect.Continuation.Value == Element?, Effect.Continuation.Failure == Failure {
    self.effect = effect
  }
}
