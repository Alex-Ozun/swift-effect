import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EffectScopeMacro {}
extension EffectScopeMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard !declaration.is(ExtensionDeclSyntax.self) else {
      return []
    }
    return [try ExtensionDeclSyntax("extension \(type): EffectScope {}")]
  }
}

extension EffectScopeMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard !declaration.is(ExtensionDeclSyntax.self) else {
      return []
    }
    return [
      "var _capturedHandlers = Effect.CapturedHandlers()",
    ]
  }
}

extension EffectScopeMacro: MemberAttributeMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AttributeSyntax] {
    guard isLegalMember(member) && !isIgnored(member) else {
      return []
    }
    return [
      AttributeSyntax(
        attributeName: IdentifierTypeSyntax(
          name: .identifier("EffectScopeFunction")
        )
      )
    ]
  }

  private static func isLegalMember(_ member: some DeclSyntaxProtocol) -> Bool {
    if let funcDecl = member.as(FunctionDeclSyntax.self), !funcDecl.isStatic {
      return true
    } else if member.is(DeinitializerDeclSyntax.self) {
      return true
    } else {
      return false
    }
  }
  
  private static func isIgnored(_ member: some DeclSyntaxProtocol) -> Bool {
    var attributes: [SwiftSyntax.AttributeListSyntax.Element] = []
    
    if let funcDecl = member.as(FunctionDeclSyntax.self) {
      attributes = Array(funcDecl.attributes)
    } else if let deinitDecl = member.as(DeinitializerDeclSyntax.self) {
      attributes = Array(deinitDecl.attributes)
    }
    return attributes.contains {
      guard
        case .attribute(let attribute) = $0,
        let attributeName = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
        ["EffectScopeIgnored"].contains(attributeName)
      else { return false }
      return true
    }
  }
}
