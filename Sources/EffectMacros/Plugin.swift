import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct EffectPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
      EffectMacro.self,
      EffectScopeMacro.self,
      EffectScopeFunctionMacro.self,
      EffectScopeIgnoredMacro.self,
    ]
}
