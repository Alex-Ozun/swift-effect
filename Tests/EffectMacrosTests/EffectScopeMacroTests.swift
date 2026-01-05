@testable import Effect
import EffectMacros
import SwiftCompilerPlugin
import MacroTesting
import Testing

@Suite(.macros([EffectScopeMacro.self]))
struct EffectMacroScopeTests {
  @Test
  func classEffectScope() {
    assertMacro(record: .failed) {
      #"""
      @Observable
      @EffectScope
      @MainActor
      class ViewModel {
        @Environment(\.something) var something
        var name: String {
          get { "Alex" }
          set {}
        }
        let age = 10
        init() {}
        static func doSomething() {}
        deinit {}
        func doSomething() {}
        func doSomethingAsync() async {}
        func doSomethingAsync() async throws {}
      }
      """#
    } expansion: {
      #"""
      @Observable
      @MainActor
      class ViewModel {
        @Environment(\.something) var something
        var name: String {
          get { "Alex" }
          set {}
        }
        let age = 10
        init() {}
        static func doSomething() {}
        @EffectScopeFunction
        deinit {}
        @EffectScopeFunction
        func doSomething() {}
        @EffectScopeFunction
        func doSomethingAsync() async {}
        @EffectScopeFunction
        func doSomethingAsync() async throws {}

        var _capturedHandlers = Effect.CapturedHandlers()
      }

      extension ViewModel: EffectScope {
      }
      """#
    }
  }
  
  @Test
  func structEffectScope() {
    assertMacro(record: .failed) {
      #"""
      @Observable
      @EffectScope
      @MainActor
      struct ViewModel {
        @Environment(\.something) var something
        var name: String {
          get { "Alex" }
          set {}
        }
        let age = 10
        init() {}
        static func doSomething() {}
        deinit {}
        func doSomething() {}
        func doSomethingAsync() async {}
        func doSomethingAsync() async throws {}
      }
      """#
    } expansion: {
      #"""
      @Observable
      @MainActor
      struct ViewModel {
        @Environment(\.something) var something
        var name: String {
          get { "Alex" }
          set {}
        }
        let age = 10
        init() {}
        static func doSomething() {}
        @EffectScopeFunction
        deinit {}
        @EffectScopeFunction
        func doSomething() {}
        @EffectScopeFunction
        func doSomethingAsync() async {}
        @EffectScopeFunction
        func doSomethingAsync() async throws {}

        var _capturedHandlers = Effect.CapturedHandlers()
      }

      extension ViewModel: EffectScope {
      }
      """#
    }
  }
  
  @Test
  func actorEffectScope() {
    assertMacro(record: .failed) {
      #"""
      @Observable
      @EffectScope
      @MainActor
      actor ViewModel {
        @Environment(\.something) var something
        var name: String {
          get { "Alex" }
          set {}
        }
        let age = 10
        init() {}
        static func doSomething() {}
        deinit {}
        func doSomething() {}
        func doSomethingAsync() async {}
        func doSomethingAsync() async throws {}
      }
      """#
    } expansion: {
      #"""
      @Observable
      @MainActor
      actor ViewModel {
        @Environment(\.something) var something
        var name: String {
          get { "Alex" }
          set {}
        }
        let age = 10
        init() {}
        static func doSomething() {}
        @EffectScopeFunction
        deinit {}
        @EffectScopeFunction
        func doSomething() {}
        @EffectScopeFunction
        func doSomethingAsync() async {}
        @EffectScopeFunction
        func doSomethingAsync() async throws {}

        var _capturedHandlers = Effect.CapturedHandlers()
      }

      extension ViewModel: EffectScope {
      }
      """#
    }
  }
  
  
  @Test
  func extensionEffectScope() {
    assertMacro(record: .failed) {
        #"""
        @EffectScope
        extension ViewModel {
          var name: String { "Alex" }
          static func doSomething() {}
          @MainActor
          func doSomething() {}
          func doSomethingAsync() async {}
          func doSomethingAsync() async throws {}
        }
        """#
    } expansion: {
      """
      extension ViewModel {
        var name: String { "Alex" }
        static func doSomething() {}
        @MainActor
        @EffectScopeFunction
        func doSomething() {}
        @EffectScopeFunction
        func doSomethingAsync() async {}
        @EffectScopeFunction
        func doSomethingAsync() async throws {}
      }
      """
    }
  }
  
  @Test
  func ignoredFunctions() {
    assertMacro(record: .failed) {
        #"""
        @EffectScope
        extension ViewModel {
          var name: String { "Alex" }
          static func doSomething() {}
        
          @EffectScopeIgnored
          func doSomething() {}
          @EffectScopeIgnored
          func doSomethingAsync() async {}
          @EffectScopeIgnored
          @MainActor
          func doSomethingAsync() async throws {}
        
          @MainActor
          func doSomething() {}
          func doSomethingAsync() async {}
          func doSomethingAsync() async throws {}
        }
        """#
    } expansion: {
      """
      extension ViewModel {
        var name: String { "Alex" }
        static func doSomething() {}

        @EffectScopeIgnored
        func doSomething() {}
        @EffectScopeIgnored
        func doSomethingAsync() async {}
        @EffectScopeIgnored
        @MainActor
        func doSomethingAsync() async throws {}

        @MainActor
        @EffectScopeFunction
        func doSomething() {}
        @EffectScopeFunction
        func doSomethingAsync() async {}
        @EffectScopeFunction
        func doSomethingAsync() async throws {}
      }
      """
    }
  }
}
