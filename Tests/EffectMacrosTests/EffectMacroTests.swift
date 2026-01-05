@testable import Effect
import EffectMacros
import SwiftCompilerPlugin
import MacroTesting
import Testing

@Suite(.macros([EffectMacro.self]))
struct EffectMacroTests {
  @Test
  func asyncThrowingEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) async throws -> C {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) async throws -> C {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              return try await withCheckedThrowingContinuation { continuation in
                  TestHandler.current.runtimeContinuation.yield(
                    DoSomethingEffectBridge(
            a: a,
            b,
                      continuation: continuation
                    )
                  )
                }

          } else {
              return try await __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) async throws -> C> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: EffectHandler {
          var doSomething: @Sendable (A, B) async throws -> C
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) async throws -> C = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) async throws -> C = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) async throws -> C = { a, b in
              try await  Effect.$nestingLevel.withValue(parent_nestingLevel) {
                try await  DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  try await  __doSomething.withValue(parent_doSomething) {
                      try await self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C, any Error>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C, any Error>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              await continuation.resume(
                returning: try await __doSomething.get()(a, b)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: CheckedContinuation<C, any Error>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: CheckedContinuation<C, any Error>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) async throws -> C = __doSomething.get()
          let doSomething: @Sendable (A, B) async throws -> C = { a, b in
              try await  __doSomething.withValue(parent_doSomething) {
                  try await handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func syncThrowingEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) throws -> C {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) throws -> C {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              let result = _EffectResult<C, any Error>()
            let semaphore = DispatchSemaphore(value: 0)
            Task(priority: .userInitiated) {  @EffectExecutionActor in
              do {
                let value: C = try await withCheckedThrowingContinuation { continuation in
                  TestHandler.current.runtimeContinuation.yield(
                    DoSomethingEffectBridge(
            a: a,
            b,
                      continuation: continuation
                    )
                  )
                }
                     result.setValue(.success(value))
              } catch {
               result.setValue(.failure(error))
            }
              semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1)
            switch result.value {
            case let .success(value):
              return value
            case let .failure(error):
              throw error
            case .none:
              throw TimeOut()
            }
          } else {
              return try __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) throws -> C> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: SyncEffectHandler {
          var doSomething: @Sendable (A, B) throws -> C
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) throws -> C = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) throws -> C = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) throws -> C = { a, b in
              try  Effect.$nestingLevel.withValue(parent_nestingLevel) {
                try  DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  try  __doSomething.withValue(parent_doSomething) {
                      try self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) throws -> C = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) throws -> C = { a, b in
              try  Effect.$nestingLevel.withValue(parent_nestingLevel) {
                try  DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  try  __doSomething.withValue(parent_doSomething) {
                      try self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try  __doSomething.withValue(doSomething) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C, any Error>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C, any Error>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              await continuation.resume(
                returning: try __doSomething.get()(a, b)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: CheckedContinuation<C, any Error>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: CheckedContinuation<C, any Error>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) throws -> C = __doSomething.get()
          let doSomething: @Sendable (A, B) throws -> C = { a, b in
              try  __doSomething.withValue(parent_doSomething) {
                  try handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func syncNonThrowingEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) -> C {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) -> C {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              let result = _EffectResult<C, Never>()
            let semaphore = DispatchSemaphore(value: 0)
            Task(priority: .userInitiated) {  @EffectExecutionActor in

                let value: C =  await withCheckedContinuation { continuation in
                  TestHandler.current.runtimeContinuation.yield(
                    DoSomethingEffectBridge(
            a: a,
            b,
                      continuation: continuation
                    )
                  )
                }
                     result.setValue(.success(value))

              semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1)
            switch result.value {
            case let .success(value):
              return value

            case .none:
              fatalError()
            }
          } else {
              return __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) -> C> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: SyncEffectHandler {
          var doSomething: @Sendable (A, B) -> C
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) -> C = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> C = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> C = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> C = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> C = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try  __doSomething.withValue(doSomething) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C, Never>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              await continuation.resume(
                returning: __doSomething.get()(a, b)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: CheckedContinuation<C, Never>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: CheckedContinuation<C, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) -> C = __doSomething.get()
          let doSomething: @Sendable (A, B) -> C = { a, b in
               __doSomething.withValue(parent_doSomething) {
                  handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func asyncNonThrowingEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) async -> C {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) async -> C {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              return  await withCheckedContinuation { continuation in
                  TestHandler.current.runtimeContinuation.yield(
                    DoSomethingEffectBridge(
            a: a,
            b,
                      continuation: continuation
                    )
                  )
                }

          } else {
              return await __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) async -> C> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: EffectHandler {
          var doSomething: @Sendable (A, B) async -> C
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) async -> C = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) async -> C = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) async -> C = { a, b in
              await  Effect.$nestingLevel.withValue(parent_nestingLevel) {
                await  DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  await  __doSomething.withValue(parent_doSomething) {
                      await self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C, Never>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              await continuation.resume(
                returning: await __doSomething.get()(a, b)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: CheckedContinuation<C, Never>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: CheckedContinuation<C, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) async -> C = __doSomething.get()
          let doSomething: @Sendable (A, B) async -> C = { a, b in
              await  __doSomething.withValue(parent_doSomething) {
                  await handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func voidReturningEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething() {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething() {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {

              let result = _EffectResult<Void, Never>()
            let semaphore = DispatchSemaphore(value: 0)
            Task(priority: .userInitiated) {  @EffectExecutionActor in

                let value: Void =  await withCheckedContinuation { continuation in
                  TestHandler.current.runtimeContinuation.yield(
                    DoSomethingEffectBridge(
                      continuation: continuation
                    )
                  )
                }
                     result.setValue(.success(value))

              semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1)
            switch result.value {
            case let .success(value):
              return value

            case .none:
              fatalError()
            }
          } else {
              return __doSomething.get()()
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable () -> Void> = TaskLocal(wrappedValue: {
             print("hello")
            })

        struct DoSomething: SyncEffectHandler {
          var doSomething: @Sendable () -> Void
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping () -> Void = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable () -> Void = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable () -> Void = {
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething()
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable () -> Void = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable () -> Void = {
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething()
                  }
                }
              }
            }
            let result = try  __doSomething.withValue(doSomething) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)

            var _arguments: () {
              ()
            }
            let continuation: EffectContinuation<Void, Never>

            init(
              continuation: EffectContinuation<Void, Never>
            ) {
              self.continuation = continuation
            }
            func yield() async throws {
              await continuation.resume(
                returning: __doSomething.get()()
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {

            let continuation: CheckedContinuation<Void, Never>

            nonisolated init(
              continuation: CheckedContinuation<Void, Never>
            ) {
              self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                continuation: EffectContinuation { val in
                  continuation.resume(with: val)
                  await execute()
                }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable () -> Void = __doSomething.get()
          let doSomething: @Sendable () -> Void = {
               __doSomething.withValue(parent_doSomething) {
                  handler.doSomething()
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func asyncThrowingSequenceEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) -> any AsyncSequence<C, MyError> {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) -> any AsyncSequence<C, MyError> {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              return EffectStream { continuation in
                DoSomethingEffectBridge(
            a: a,
            b,
                  continuation: continuation
                )
              }
          } else {
              return __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) -> any AsyncSequence<C, MyError>> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: SyncEffectHandler {
          var doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError>
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) -> any AsyncSequence<C, MyError> = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError> = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError> = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError> = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError> = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try  __doSomething.withValue(doSomething) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C?, MyError>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C?, MyError>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              var iterator = __doSomething.get()(a, b).makeAsyncIterator()
               await continuation.resume(
                returning: try await iterator.next(isolation: EffectExecutionActor.shared)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: EffectStreamContinuation<C?, MyError>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: EffectStreamContinuation<C?, MyError>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError> = __doSomething.get()
          let doSomething: @Sendable (A, B) -> any AsyncSequence<C, MyError> = { a, b in
               __doSomething.withValue(parent_doSomething) {
                  handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func asyncSequenceEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) -> any AsyncSequence<C, Never> {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) -> any AsyncSequence<C, Never> {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              return EffectStream { continuation in
                DoSomethingEffectBridge(
            a: a,
            b,
                  continuation: continuation
                )
              }
          } else {
              return __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) -> any AsyncSequence<C, Never>> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: SyncEffectHandler {
          var doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never>
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) -> any AsyncSequence<C, Never> = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never> = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never> = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never> = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never> = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try  __doSomething.withValue(doSomething) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C?, Never>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C?, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              var iterator = __doSomething.get()(a, b).makeAsyncIterator()
               await continuation.resume(
                returning: try await iterator.next(isolation: EffectExecutionActor.shared)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: EffectStreamContinuation<C?, Never>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: EffectStreamContinuation<C?, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never> = __doSomething.get()
          let doSomething: @Sendable (A, B) -> any AsyncSequence<C, Never> = { a, b in
               __doSomething.withValue(parent_doSomething) {
                  handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func asyncSequenceWithoutAnyKeywordEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func doSomething(a: A, _ b: B) -> AsyncSequence<C, MyError> {
          print("hello")
        }
      }
      """
    } expansion: {
      """
      extension Effect {
        static func doSomething(a: A, _ b: B) -> AsyncSequence<C, MyError> {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= DoSomethingEffect.nestingLevel.get() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              return EffectStream { continuation in
                DoSomethingEffectBridge(
            a: a,
            b,
                  continuation: continuation
                )
              }
          } else {
              return __doSomething.get()(a, b)
          }
        }

        private nonisolated static let __doSomething: TaskLocal<@Sendable (A, B) -> AsyncSequence<C, MyError>> = TaskLocal(wrappedValue: { a, b in
             print("hello")
            })

        struct DoSomething: SyncEffectHandler {
          var doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError>
          typealias _Effect = DoSomethingEffect
          init(
              doSomething: @Sendable @escaping (A, B) -> AsyncSequence<C, MyError> = Effect.__doSomething.get()
          ) {
            self.doSomething = doSomething
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError> = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError> = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try await __doSomething.withValue(doSomething) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError> = __doSomething.get()
            let parent_nestingLevel = Effect.nestingLevel
            let doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError> = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                   __doSomething.withValue(parent_doSomething) {
                      self.doSomething(a, b)
                  }
                }
              }
            }
            let result = try  __doSomething.withValue(doSomething) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.DoSomething.self)
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

        struct DoSomethingEffect: EffectProtocol {
            nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
            let a: A
            let b: B
            var _arguments: (A, B) {
              (a, b)
            }
            let continuation: EffectContinuation<C?, MyError>

            init(
              a: A,
              _ b: B,
                    continuation: EffectContinuation<C?, MyError>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }
            func yield() async throws {
              var iterator = __doSomething.get()(a, b).makeAsyncIterator()
               await continuation.resume(
                returning: try await iterator.next(isolation: EffectExecutionActor.shared)
              )
            }
          }

        private struct DoSomethingEffectBridge: EffectBridge {
            let a: UnsafeTransfer<A>
            let b: UnsafeTransfer<B>
            let continuation: EffectStreamContinuation<C?, MyError>

            nonisolated init(
              a: UnsafeTransfer<A>,
              _ b: UnsafeTransfer<B>,
                    continuation: EffectStreamContinuation<C?, MyError>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> DoSomethingEffect {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withDoSomething<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.DoSomething,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError> = __doSomething.get()
          let doSomething: @Sendable (A, B) -> AsyncSequence<C, MyError> = { a, b in
               __doSomething.withValue(parent_doSomething) {
                  handler.doSomething(a, b)
              }
          }
          let result = try await __doSomething.withValue(doSomething) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await DoSomethingEffect.nestingLevel.withValue(Effect.nestingLevel) {
                try await perform()
              }
            }
          }
          return result
        }

        var doSomething: DoSomething.Type {
          DoSomething.self
        }
      }
      """
    }
  }
  
  @Test
  func genericEffect() {
    assertMacro(record: .failed) {
      """
      extension Effect {
        @Effect
        static func generic<Value: Equatable>(a: Value, _ b: Value) -> Bool {
          a == b
        }
      }
      """
    } expansion: {
      #"""
      extension Effect {
        static func generic<Value: Equatable>(a: Value, _ b: Value) -> Bool {
          if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= GenericEffect<Value>.nestingLevel() {
            let a = UnsafeTransfer(a)
            let b = UnsafeTransfer(b)
              let result = _EffectResult<Bool, Never>()
            let semaphore = DispatchSemaphore(value: 0)
            Task(priority: .userInitiated) {  @EffectExecutionActor in

                let value: Bool =  await withCheckedContinuation { continuation in
                  TestHandler.current.runtimeContinuation.yield(
                    GenericEffectBridge(
            a: a,
            b,
                      continuation: continuation
                    )
                  )
                }
                     result.setValue(.success(value))

              semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1)
            switch result.value {
            case let .success(value):
              return value

            case .none:
              fatalError()
            }
          } else {
              return __generic()(a, b)
          }
        }

        private nonisolated static let __generic_storage: TaskLocal<[ObjectIdentifier: any Sendable]> = TaskLocal(wrappedValue: [:])

        private nonisolated static func __generic<Value: Equatable>() -> @Sendable (Value, Value)-> Bool { 
            if let impl = __generic_storage.get()[ObjectIdentifier(Effect.Generic<Value>.self)] {
              return impl as! @Sendable (Value, Value)-> Bool
            } else {
              return {a, b in 
             a == b 
              }
            }      
            }

        struct Generic<Value: Equatable>: SyncEffectHandler {
          var generic: @Sendable (Value, Value) -> Bool
          typealias _Effect = GenericEffect<Value>
          init(
              generic: @Sendable @escaping (Value, Value) -> Bool = Effect.__generic()
          ) {
            self.generic = generic
          }

           func handle<EffectReturnType>(
            isolation: isolated (any Actor)? = #isolation,
            operation: () async throws -> EffectReturnType
           ) async rethrows -> EffectReturnType {
            let parent_generic: @Sendable (Value, Value) -> Bool = __generic()
            let parent_nestingLevel = Effect.nestingLevel
            let generic: @Sendable (Value, Value) -> Bool = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 __generic_nestingLevel_storage.withValue(
                  __generic_nestingLevel_storage.get().merging([ObjectIdentifier(Effect.Generic<Value>.self) : Effect.nestingLevel]) { _, new in
                    new
                  }
                ) {
                   __generic_storage.withValue(
                    __generic_storage.get().merging(
                    [ObjectIdentifier(Effect.Generic<Value>.self) : parent_generic]
                    ) { _, new in
                      new
                    }
                  ) {
                    self.generic(a, b)
                  }
                }
              }
            }
            let result = try await __generic_storage.withValue(
              __generic_storage.get().merging(
                [ObjectIdentifier(Effect.Generic<Value>.self) : generic]
              ) { _, new in
                new
              }
            ) {
              try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
                try await __generic_nestingLevel_storage.withValue(
                  __generic_nestingLevel_storage.get().merging([ObjectIdentifier(Effect.Generic<Value>.self) : Effect.nestingLevel]) { _, new in
                    new
                  }
                ) {
                  let result = try await operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.Generic<Value>.self)
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

          func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
            let parent_generic: @Sendable (Value, Value) -> Bool = __generic()
            let parent_nestingLevel = Effect.nestingLevel
            let generic: @Sendable (Value, Value) -> Bool = { a, b in
               Effect.$nestingLevel.withValue(parent_nestingLevel) {
                 __generic_nestingLevel_storage.withValue(
                  __generic_nestingLevel_storage.get().merging([ObjectIdentifier(Effect.Generic<Value>.self) : Effect.nestingLevel]) { _, new in
                    new
                  }
                ) {
                   __generic_storage.withValue(
                    __generic_storage.get().merging(
                    [ObjectIdentifier(Effect.Generic<Value>.self) : parent_generic]
                    ) { _, new in
                      new
                    }
                  ) {
                    self.generic(a, b)
                  }
                }
              }
            }
            let result = try  __generic_storage.withValue(
              __generic_storage.get().merging(
                [ObjectIdentifier(Effect.Generic<Value>.self) : generic]
              ) { _, new in
                new
              }
            ) {
              try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
                try __generic_nestingLevel_storage.withValue(
                  __generic_nestingLevel_storage.get().merging([ObjectIdentifier(Effect.Generic<Value>.self) : Effect.nestingLevel]) { _, new in
                    new
                  }
                ) {
                  let result = try operation()
                  if let effectScope = result as? EffectScope {
                    let key = ObjectIdentifier(Effect.Generic<Value>.self)
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

        nonisolated static let __generic_nestingLevel_storage: TaskLocal<[ObjectIdentifier: UInt8]> = TaskLocal(wrappedValue: [:])
          struct GenericEffect<Value: Equatable>: EffectProtocol {
            nonisolated static func nestingLevel() -> UInt8 { 
                if let nestingLevel = __generic_nestingLevel_storage.get()[ObjectIdentifier(Effect.Generic<Value>.self)] {
                  return nestingLevel
                } else {
                  return 0
                }      
            }
            let a: Value
        let b: Value
            var _arguments: (Value, Value) { 
              (a, b) 
            }
            let continuation: EffectContinuation<Bool, Never>
            
            init(
        a: Value, 
        _ b: Value,
              continuation: EffectContinuation<Bool, Never>
            ) {
        self.a = a
        self.b = b
              self.continuation = continuation
            }
            func yield() async throws {
              await continuation.resume(
                returning: __generic()(a, b)
              )
            }
          }

        private struct GenericEffectBridge<Value: Equatable>: EffectBridge {
            let a: UnsafeTransfer<Value>
            let b: UnsafeTransfer<Value>
            let continuation: CheckedContinuation<Bool, Never>

            nonisolated init(
              a: UnsafeTransfer<Value>,
              _ b: UnsafeTransfer<Value>,
                    continuation: CheckedContinuation<Bool, Never>
            ) {
              self.a = a
              self.b = b
                    self.continuation = continuation
            }

            func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> GenericEffect<Value> {
              .init(
                a: a.value,
                b.value,
                        continuation: EffectContinuation { val in
                          continuation.resume(with: val)
                          await execute()
                        }
              )
            }
          }

        static func withGeneric<EffectReturnType, Value: Equatable>(
            isolation: isolated (any Actor)? = #isolation,
          _ handler: Effect.Generic<Value>,
          perform: () async throws -> EffectReturnType
        ) async rethrows -> EffectReturnType {
          let parent_generic: @Sendable (Value, Value) -> Bool = __generic()
          let generic: @Sendable (Value, Value) -> Bool = { a, b in
               __generic_storage.withValue(
                __generic_storage.get().merging(
                [ObjectIdentifier(Effect.Generic<Value>.self) : parent_generic]
                ) { _, new in
                  new
                }
              ) {
                handler.generic(a, b)
              }
          }
          let result = try await __generic_storage.withValue(
            __generic_storage.get().merging(
              [ObjectIdentifier(Effect.Generic<Value>.self) : generic]
            ) { _, new in
              new
            }
          ) {
            try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
              try await __generic_nestingLevel_storage.withValue(
                __generic_nestingLevel_storage.get().merging([ObjectIdentifier(Effect.Generic<Value>.self) : Effect.nestingLevel]) { _, new in
                  new
                }
              ) {
                try await perform()
              }
            }
          }
          return result
        }

        @EffectExecutionActor
        func expectGeneric<Value: Equatable>(
          of: Value.Type,
          _ handle: (Value, Value)  -> GenericEffect<Value>.Value,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
          line: UInt = #line,
          column: UInt = #column
        ) async throws {
          await TestHandler.current.advanceToNextEffect()
          guard let effect = self.value as? GenericEffect<Value> else {
            Self.reportIssue(
              "Expected \(GenericEffect<Value>.self), received \(self.value!.description)",
              fileID: fileID,
              filePath: filePath,
              line: line,
              column: column
            )
            throw UnexpectedEffect()
          }
          let result = Result {
             handle(effect.a, effect.b)
          }
          await effect.resume(with: result)
        }
      }
      """#
    }
  }
}
