import Foundation

struct StartEffect: EffectProtocol {
  let continuation: EffectContinuation<Void, Never>
  func yield() async {
    await continuation.resume()
  }
  
  func resume(with result: sending Result<(), Never>) async {
    await continuation.resume()
  }
}

struct StartEffectBridge: EffectBridge {
  let continuation: CheckedContinuation<Void, Never>
  
  func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> StartEffect {
    StartEffect(
      continuation: EffectContinuation { val in
        continuation.resume(with: val)
        await execute()
      }
    )
  }
}

