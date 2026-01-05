import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EffectScopeFunctionMacro: BodyMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    providingBodyFor declaration: some SwiftSyntax.DeclSyntaxProtocol & SwiftSyntax.WithOptionalCodeBlockSyntax,
    in context: some SwiftSyntaxMacros.MacroExpansionContext
  ) throws -> [SwiftSyntax.CodeBlockItemSyntax] {
    let errorMessage = "@EffectScopeFunction can only be added to instance methods and deinit. It cannot be added to global or static functions."
    guard context.parentTypeName() != nil else {
      throw CustomError.message(errorMessage)
    }
    
    if let funcDecl = declaration.as(FunctionDeclSyntax.self), !funcDecl.isStatic {
      return [
        """
        \(raw: funcDecl.effectSpecifiers) Effect.withScope(self._capturedHandlers) {\(funcDecl.body?.statements)
        }
        """
      ]
    } else if declaration.is(DeinitializerDeclSyntax.self) {
      return [
        """
        Effect.withScope(self._capturedHandlers) {\(declaration.body?.statements)
        }
        """
      ]
    } else {
      throw CustomError.message(errorMessage)
    }
  }
}

public struct EffectScopeIgnoredMacro: PeerMacro {
  public static func expansion(of node: SwiftSyntax.AttributeSyntax, providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {
    []
  }
}
