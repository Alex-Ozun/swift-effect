@testable import Effect
import EffectMacros
import SwiftCompilerPlugin
import MacroTesting
import Testing

@Suite(.macros([EffectScopeFunctionMacro.self]))
struct EffectScopeFunctionMacroTests {
  @Test
  func plain() {
    assertMacro(record: .failed) {
      #"""
      struct Parent {
        @EffectScopeFunction
        func doSomething() {
          print("Hello")
        }
      }
      """#
    } expansion: {
      """
      struct Parent {
        func doSomething() {
          Effect.withScope(self._capturedHandlers) {
              print("Hello")
          }
        }
      }
      """
    }
  }
  
  @Test
  func throwing() {
    assertMacro(record: .failed) {
      #"""
      struct Parent {
        @EffectScopeFunction
        func doSomething() throws {
          print("Hello")
        }
      }
      """#
    } expansion: {
      """
      struct Parent {
        func doSomething() throws {
          try  Effect.withScope(self._capturedHandlers) {
              print("Hello")
          }
        }
      }
      """
    }
  }
  
  @Test
  func async() {
    assertMacro(record: .failed) {
      #"""
      struct Parent {
        @EffectScopeFunction
        func doSomething() async {
          print("Hello")
        }
      }
      """#
    } expansion: {
      """
      struct Parent {
        func doSomething() async {
          await  Effect.withScope(self._capturedHandlers) {
              print("Hello")
          }
        }
      }
      """
    }
  }
  
  @Test
  func asyncThrowing() {
    assertMacro(record: .failed) {
      #"""
      struct Parent {
        @EffectScopeFunction
        func doSomething() async throws {
          print("Hello")
        }
      }
      """#
    } expansion: {
      """
      struct Parent {
        func doSomething() async throws {
          try await  Effect.withScope(self._capturedHandlers) {
              print("Hello")
          }
        }
      }
      """
    }
  }
  
  @Test
  func staticFunction() {
    assertMacro(record: .failed) {
      #"""
      struct Parent {
        @EffectScopeFunction
        static func doSomething() async throws {
          print("Hello")
        }
      }
      """#
    } diagnostics: {
      """
      struct Parent {
        @EffectScopeFunction
        ┬───────────────────
        ╰─ 🛑 @EffectScopeFunction can only be added to instance methods and deinit. It cannot be added to global or static functions.
        static func doSomething() async throws {
          print("Hello")
        }
      }
      """
    } 
  }
  
  @Test
  func global() {
    assertMacro(record: .failed) {
      #"""
      @EffectScopeFunction
      func doSomething() {
        print("Hello")
      }
      """#
    } diagnostics: {
      """
      @EffectScopeFunction
      ┬───────────────────
      ╰─ 🛑 @EffectScopeFunction can only be added to instance methods and deinit. It cannot be added to global or static functions.
      func doSomething() {
        print("Hello")
      }
      """
    } 
  }
  
  @Test
  func ignored() {
    assertMacro(record: .failed) {
      #"""
      @EffectScopeIgnored
      func doSomething() {
        print("Hello")
      }
      """#
    } diagnostics: {
      """

      """
    } expansion: {
      """
      @EffectScopeIgnored
      func doSomething() {
        print("Hello")
      }
      """
    }
  }
}
