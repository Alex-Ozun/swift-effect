@testable import Effect
import EffectMacros
import SwiftCompilerPlugin
import MacroTesting
import Testing

@Suite(.macros([EffectScopeIgnoredMacro.self]))
struct EffectScopeIgnoredMacroTests {
  @Test
  func ignored() {
    assertMacro(record: .failed) {
    #"""
    @EffectScopeIgnored
    func doSomething() {
      print("Hello")
    }
    """#
    } expansion: {
      """
      func doSomething() {
        print("Hello")
      }
      """
    }
  }
}
