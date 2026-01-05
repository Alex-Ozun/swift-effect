//
//  File.swift
//  swift-effect
//
//  Created by Alex Ozun on 22/12/2025.
//

import Foundation

struct Exit: EffectProtocol {  
  let continuation: NoContinuation
  func yield() async {}
  func resume(with result: sending Result<Never, Never>) async {}
}

struct ExitEffectBridge: EffectBridge {
  let continuation: NoContinuation
  
  func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> Exit {
    Exit(continuation: NoContinuation())
  }
}
