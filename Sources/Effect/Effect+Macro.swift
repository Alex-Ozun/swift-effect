@attached(peer, names: prefixed(__isGlobal_), prefixed(__), arbitrary)
@attached(body)
public macro Effect(name: String = "") = #externalMacro(
    module: "EffectMacros",
    type: "EffectMacro"
)

@attached(memberAttribute)
@attached(member, names: arbitrary)
@attached(extension, conformances: EffectScope)
public macro EffectScope() = #externalMacro(
    module: "EffectMacros",
    type: "EffectScopeMacro"
)

@attached(body)
public macro EffectScopeFunction() = #externalMacro(
    module: "EffectMacros",
    type: "EffectScopeFunctionMacro"
)

@attached(peer, names: overloaded)
public macro EffectScopeIgnored() = #externalMacro(
    module: "EffectMacros",
    type: "EffectScopeIgnoredMacro"
)
