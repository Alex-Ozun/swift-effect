import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EffectMacro: PeerMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
    in context: some SwiftSyntaxMacros.MacroExpansionContext
  ) throws -> [SwiftSyntax.DeclSyntax] {
    guard var funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw CustomError.message("@Effect only works on functions")
    }
    guard let parentTypeName = context.parentTypeName() else {
      throw CustomError.message("Must be declared in a type")
    }
    let newAttributeList = funcDecl.attributes.filter {
      guard case let .attribute(attribute) = $0,
            let attributeType = attribute.attributeName.as(IdentifierTypeSyntax.self),
            let nodeType = node.attributeName.as(IdentifierTypeSyntax.self)
      else {
        return true
      }
      
      return attributeType.name.text != nodeType.name.text
    }
    let effectNameBase: String
    if case let .argumentList(arguments) = node.arguments,
      let firstElement = arguments.first,
      let stringLiteral = firstElement.expression
        .as(StringLiteralExprSyntax.self),
      stringLiteral.segments.count == 1,
      case let .stringSegment(wrapperName)? = stringLiteral.segments.first {
      effectNameBase = wrapperName.content.text
    } else {
      effectNameBase = funcDecl.capitalizedName
    }
    funcDecl.attributes = newAttributeList
    var expansion: [DeclSyntax] = [
      funcDecl.taskLocalImplementation(effectNameBase, parentTypeName: parentTypeName),
      """
      struct \(raw: effectNameBase)\(funcDecl.genericParameterClause): \(funcDecl.effectHandlerConformance) {
        \(funcDecl.closureVariableDefinition())
        typealias _Effect = \(raw: effectNameBase)Effect\(raw: funcDecl.genericArguments)
        init(
            \(funcDecl.name): @Sendable @escaping \(raw: funcDecl.closureParameterClause)\(funcDecl.signature.effectSpecifiers)\(raw: funcDecl.closureReturnClause) = \(raw: parentTypeName).\(raw: funcDecl.underscoredName)\(raw: funcDecl.implementationFunctionAccessor)
        ) {
          self.\(funcDecl.name) = \(funcDecl.name)
        }
      
         func handle<EffectReturnType>(
          isolation: isolated (any Actor)? = #isolation,
          operation: () async throws -> EffectReturnType
         ) async rethrows -> EffectReturnType {
          let parent_\(funcDecl.name): \(funcDecl.implementationFunctionType) = \(raw: funcDecl.underscoredName)\(raw: funcDecl.implementationFunctionAccessor)
          let parent_nestingLevel = Effect.nestingLevel
          let \(funcDecl.name): @Sendable \(raw: funcDecl.closureParameterClause)\(funcDecl.signature.effectSpecifiers)\(raw: funcDecl.closureReturnClause) = { \(raw: funcDecl.closureArgumentsClause)
            \(raw: funcDecl.effectSpecifiers) Effect.$nestingLevel.withValue(parent_nestingLevel) {
              \(funcDecl.withNestingLevelStatement(
                  effectNameBase,
                  effectSpecifiers: funcDecl.effectSpecifiers,
                  parentTypeName: parentTypeName
                  )
                )
                \(funcDecl.withParentImplementationStatement(effectNameBase, root: "self.", parentTypeName: parentTypeName))
              }
            }
          }
          \(funcDecl.withLocalImplementationStatement(effectNameBase, parentTypeName: parentTypeName, isAsync: true))
            try await Effect.$nestingLevel.withValue(parent_nestingLevel + 1) {
              \(funcDecl.withNestingLevelStatement(effectNameBase, effectSpecifiers: "try await", parentTypeName: parentTypeName))
                let result = try await operation()
                if let effectScope = result as? EffectScope {
                  let key = ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: funcDecl.genericArguments).self)
                  effectScope._capturedHandlers.handlers[key] = self
                  return effectScope as! EffectReturnType
                } else {
                  return result
                }
              }
            }
          }
          return result
         }\(funcDecl.syncEffectHandlerImplementation(effectNameBase, parentTypeName: parentTypeName))
      }
      """,
      """
        \(funcDecl.nestingLevelStorageDeclaration)
        struct \(raw: effectNameBase)Effect\(funcDecl.genericParameterClause): EffectProtocol {
          \(funcDecl.taskLocalNestingLevel(effectNameBase: effectNameBase, parentTypeName: parentTypeName))
          \(raw: funcDecl.effectProperties)
          var _arguments: \(raw: funcDecl.closureParameterClause) { 
            (\(raw: funcDecl.closureCallArguments())) 
          }
          let continuation: EffectContinuation<\(raw: funcDecl.returnType), \(raw: funcDecl.errorType)>
          
          init(\(raw: funcDecl.effectInitParameters)
            continuation: EffectContinuation<\(raw: funcDecl.returnType), \(raw: funcDecl.errorType)>
          ) {\(raw: funcDecl.initPropertyAssignments)
            self.continuation = continuation
          }
          func yield() async throws {
            \(funcDecl.yieldBlock)
          }
        }   
      """,
      """
        private struct \(raw: effectNameBase)EffectBridge\(funcDecl.genericParameterClause): EffectBridge {
          \(raw: funcDecl.effectBridgeProperties)
          let continuation: \(raw: funcDecl.bridgeContinuationType)
          
          nonisolated init(\(raw: funcDecl.effectBridgeInitParameters)
            continuation: \(raw: funcDecl.bridgeContinuationType)
          ) {\(raw: funcDecl.initPropertyAssignments)
            self.continuation = continuation
          }
      
          func effect(_ execute: @Sendable @escaping @EffectExecutionActor () async -> Void) -> \(raw: effectNameBase)Effect\(raw: funcDecl.genericArguments) {
            .init(\(raw: funcDecl.effectContinuationInitArguments)
              continuation: EffectContinuation { val in
                continuation.resume(with: val)
                await execute()
              }
            )
          }
        }
      """,
      """
      static func with\(raw: effectNameBase)\(funcDecl.genericParametersClauseWithEffectReturnType)(
          isolation: isolated (any Actor)? = #isolation,
        _ handler: \(raw: parentTypeName).\(raw: effectNameBase)\(raw: funcDecl.genericArguments),
        perform: () async throws -> EffectReturnType
      ) async rethrows -> EffectReturnType {
        let parent_\(funcDecl.name): \(funcDecl.implementationFunctionType) = \(raw: funcDecl.underscoredName)\(raw: funcDecl.implementationFunctionAccessor)
        let \(funcDecl.name): @Sendable \(raw: funcDecl.closureParameterClause)\(funcDecl.signature.effectSpecifiers)\(raw: funcDecl.closureReturnClause) = { \(raw: funcDecl.closureArgumentsClause)
            \(funcDecl.withParentImplementationStatement(effectNameBase, root: "handler.", parentTypeName: parentTypeName))
        }
        \(funcDecl.withLocalImplementationStatement(effectNameBase, parentTypeName: parentTypeName, isAsync: true))
          try await Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
            \(funcDecl.withNestingLevelStatement(effectNameBase, effectSpecifiers: "try await", parentTypeName: parentTypeName))
              try await perform()
            }
          }
        }
        return result
      }
      """,
    ]
    if funcDecl.isGeneric && parentTypeName == "Effect" {
      expansion.append(
        """
        @EffectExecutionActor
        func expect\(raw: effectNameBase)\(funcDecl.genericParameterClause)(
          of: \(raw: funcDecl.genericArgumentsTuple),
          _ handle: \(raw: funcDecl.closureParameterClause) \(funcDecl.signature.effectSpecifiers) -> \(raw: effectNameBase)Effect\(raw: funcDecl.genericArguments).Value,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
          line: UInt = #line,
          column: UInt = #column
        ) async throws {
          await TestHandler.current.advanceToNextEffect()
          guard let effect = self.value as? \(raw: effectNameBase)Effect\(raw: funcDecl.genericArguments) else {
            Self.reportIssue(
              "Expected \\(\(raw: effectNameBase)Effect\(raw: funcDecl.genericArguments).self), received \\(self.value!.description)",
              fileID: fileID,
              filePath: filePath,
              line: line,
              column: column
            )
            throw UnexpectedEffect()
          }
          let result = Result {
            \(raw: funcDecl.effectSpecifiers) handle(\(raw: funcDecl.closureCallArguments(callee: "effect.")))
          }
          await effect.resume(with: result)
        }
        """
      )
    } else {
      expansion.append(
        """
        var \(raw: effectNameBase.lowercasedFirstLetter): \(raw: effectNameBase).Type {  \(raw: effectNameBase).self }
        """
      )
    }
    return expansion
  }
}

extension EffectMacro: BodyMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    providingBodyFor declaration: some SwiftSyntax.DeclSyntaxProtocol & SwiftSyntax.WithOptionalCodeBlockSyntax,
    in context: some SwiftSyntaxMacros.MacroExpansionContext
  ) throws -> [SwiftSyntax.CodeBlockItemSyntax] {
    guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw CustomError.message("@Effect only works on functions")
    }
    let isGlobal = context.lexicalContext.isEmpty
    if !isGlobal && !funcDecl.isStatic {
      throw CustomError.message("@Effect only works on static functions")
    }
    let effectNameBase: String
    if case let .argumentList(arguments) = node.arguments,
      let firstElement = arguments.first,
      let stringLiteral = firstElement.expression
        .as(StringLiteralExprSyntax.self),
      stringLiteral.segments.count == 1,
      case let .stringSegment(wrapperName)? = stringLiteral.segments.first {
      effectNameBase = wrapperName.content.text
    } else {
      effectNameBase = funcDecl.capitalizedName
    }
    return [
      """
      if TestHandler.current.isTesting && TestHandler.current.nestingLevel >= \(raw: effectNameBase)Effect\(raw: funcDecl.genericArguments).nestingLevel\(raw: funcDecl.nestingLevelAccessor) {
        \(raw: funcDecl.unsafeTransfers)
        \(bridgeExpansion(effectNameBase: effectNameBase, funcDecl: funcDecl))
      } else {
          return \(raw: funcDecl.closureCallsight(namePrefix: "__", accessor: funcDecl.implementationFunctionAccessor))
      }
      """
    ]
  }
  
  private static func bridgeExpansion(
    effectNameBase: String,
    funcDecl: FunctionDeclSyntax
  ) -> SwiftSyntax.CodeBlockItemSyntax {
    if funcDecl.isAsyncSequence {
      effectStreamBridgeExpansion(effectNameBase: effectNameBase, funcDecl: funcDecl)
    } else {
      standaloneEffectBridgeExpansion(effectNameBase: effectNameBase, funcDecl: funcDecl)
    }
  }
  
  private static func standaloneEffectBridgeExpansion(
    effectNameBase: String,
    funcDecl: FunctionDeclSyntax
  ) -> SwiftSyntax.CodeBlockItemSyntax {
    return """
      \(raw: funcDecl.semaphoreInit) \(funcDecl.tryKeyword) await \(raw: funcDecl.continuationType) { continuation in
          TestHandler.current.runtimeContinuation.yield(
            \(raw: effectNameBase)EffectBridge(\(raw: funcDecl.effectBridgeContinuationInitArguments)
              continuation: continuation
            )
          )
        }
        \(raw: funcDecl.semaphoreWait(effectNameBase))
    """
  }
  
  private static func effectStreamBridgeExpansion(
    effectNameBase: String,
    funcDecl: FunctionDeclSyntax
  ) -> SwiftSyntax.CodeBlockItemSyntax {
    return """
      return EffectStream { continuation in
        \(raw: effectNameBase)EffectBridge(\(raw: funcDecl.effectBridgeContinuationInitArguments)
          continuation: continuation
        )
      }
    """
  }
}

extension String {
  var capitalizedFirstLetter: String {
    prefix(1).capitalized + dropFirst()
  }
  var lowercasedFirstLetter: String {
    prefix(1).lowercased() + dropFirst()
  }
}

enum CustomError: Error, CustomStringConvertible {
  case message(String)

  var description: String {
    switch self {
    case .message(let text):
      return text
    }
  }
}

extension FunctionDeclSyntax {
  var hasParams: Bool {
    signature.parameterClause.parameters.count > 0
  }
  var isAsync: Bool {
    asyncKeyword != nil
  }
  var isThrowing: Bool {
    throwsClause != nil
  }
  var isStatic: Bool {
    modifiers.contains (where: { modifier in
      modifier.name.tokenKind == .keyword(.static)
    })
  }
  var isGeneric: Bool {
    genericParameterClause != nil
  }
  
  var genericArguments: String {
    if let names = self.genericParameterClause?.parameters.map(\.name).map(\.text) {
      return "<\(names.joined(separator: ","))>"
    } else {
      return ""
    }
  }
  
  var genericArgumentsTuple: String {
    if let names = self.genericParameterClause?.parameters.map({ $0.name.text + ".Type" }), !names.isEmpty {
      if names.count > 1 {
        return "\(names.joined(separator: ", _: "))"
      } else {
        return "\(names[0])"
      }
    } else {
      return ""
    }
  }
  
  var genericParametersClauseWithEffectReturnType: GenericParameterClauseSyntax? {
    if var genericParameterClause = self.genericParameterClause {
      let parameters = Array(genericParameterClause.parameters)
      genericParameterClause.parameters = [
        GenericParameterSyntax(
          name: "EffectReturnType",
          trailingComma: .commaToken()
        )
      ] + parameters
      return genericParameterClause
    } else {
      return GenericParameterClauseSyntax(parameters: [
        GenericParameterSyntax(
          name: "EffectReturnType"
        )
      ])
    }
  }
  
  var semaphoreInit: String {
    guard !isAsync else { return "return" }
    
    return """
    let result = _EffectResult<\(returnType), \(errorType)>()
    let semaphore = DispatchSemaphore(value: 0)
    Task(priority: .userInitiated) {  @EffectExecutionActor in
      \(isThrowing ? "do {" : "")
        let value: \(returnType) =
    """
  }
  func semaphoreWait(_ effectNameBase: String) -> String {
    guard !isAsync else { return "" }
    
    return """
         result.setValue(.success(value))
      \(isThrowing
        ? """
          } catch {
             result.setValue(.failure(error))
          }
          """
        : ""
        )
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 1)
    switch result.value {
    case let .success(value):
      return value
    \(isThrowing
      ? """
        case let .failure(error):
          throw error
        """
      : ""
      )
    case .none:
      \(isThrowing ? "throw TimeOut()" : "fatalError()")
    }
    """
  }
  
  var effectSpecifiers: String {
    var effectSpecifiers = ""
    if signature.effectSpecifiers?.throwsClause != nil {
      effectSpecifiers.append("try ")
    }
    if signature.effectSpecifiers?.asyncSpecifier != nil {
      effectSpecifiers.append("await ")
    }
    return effectSpecifiers
  }
  
  var callArguments: String {
    let arguments = signature.parameterClause.parameters.map { param in
      let argName = param.secondName ?? param.firstName
      let paramName = param.firstName
      if paramName.text != "_" {
        return "\(paramName.text): \(argName.text)"
      }
      return "\(argName.text)"
    }.joined(separator: ", ")
    return "(\(arguments))"
  }
  
  func closureCallArguments(callee: String = "") -> String {
    signature.parameterClause.parameters.map { param in
      let argName = param.secondName ?? param.firstName
      return "\(callee)\(argName.text)"
    }.joined(separator: ", ")
  }
  
  var closureReturnClause: String {
    let returnType = if let type = signature.returnClause?.type {
      "\(type.trimmed)"
    } else {
      "Void"
    }
    return "-> \(returnType)"
  }
  
  var returnType: String {
    if let (type, _) = asyncSequenceTypeArguments {
      "\(type.trimmed)?"
    } else if let type = signature.returnClause?.type {
      "\(type.trimmed)"
    } else {
      "Void"
    }
  }

  var bridgeContinuationType: DeclSyntax {
    if isAsyncSequence {
      "EffectStreamContinuation<\(raw: returnType), \(raw: errorType)>"
    } else {
      "CheckedContinuation<\(raw: returnType), \(raw: errorType)>"
    }
  }
  
  var asyncSequenceTypeArguments: (value: TypeSyntax, error: TypeSyntax)? {
    guard let type = signature.returnClause?.type else { return nil }
    var base: TypeSyntax = type

    if let opt = base.as(OptionalTypeSyntax.self) {
      base = opt.wrappedType
    } else if let iuo = base.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      base = iuo.wrappedType
    }
    
    func unwrapParens(_ base: TypeSyntax) -> TypeSyntax {
      if let tuple = base.as(TupleTypeSyntax.self),
         tuple.elements.count == 1,
         let only = tuple.elements.first {
        return unwrapParens(only.type)
      }
      return base
    }
    
    base = unwrapParens(base)

    if let someOrAny = base.as(SomeOrAnyTypeSyntax.self) {
      base = someOrAny.constraint
    }
    
    var genericArgumentClause: GenericArgumentClauseSyntax?
    
    if let ident = base.as(IdentifierTypeSyntax.self),
       ident.name.text == "AsyncSequence" {
      genericArgumentClause = ident.genericArgumentClause
    } else if let member = base.as(MemberTypeSyntax.self),
       member.name.text == "AsyncSequence" {
      genericArgumentClause = member.genericArgumentClause
    }
    
    if let genericArgumentClause {
      let typeArguments = Array(genericArgumentClause.arguments)
      guard typeArguments.count == 2 else { return nil }

      switch (typeArguments[0].argument, typeArguments[1].argument) {
      case let (.type(valueType), .type(errorType)):
        return (valueType, errorType)
      default:
        return nil
      }
    } else {
      return nil
    }
  }
  
  var isAsyncSequence: Bool {
    asyncSequenceTypeArguments != nil
  }
  
  var closureParameterClause: String {
    let types = signature.parameterClause.parameters.map(\.type)
    return "(\(types.map(\.description).joined(separator: ", ")))"
  }
  
  var underscoredName: String {
    "__" + name.text
  }
  
  var capitalizedName: String {
    name.text.capitalizedFirstLetter
  }
  
  var awaitKeyword: TokenSyntax? {
    signature.effectSpecifiers?.asyncSpecifier == nil ? nil : .keyword(.await)
  }
  var tryKeyword: TokenSyntax? {
    signature.effectSpecifiers?.throwsClause == nil ? nil : .keyword(.try)
  }
  var asyncKeyword: TokenSyntax? {
    signature.effectSpecifiers?.asyncSpecifier
  }
  var throwsClause: ThrowsClauseSyntax? {
    signature.effectSpecifiers?.throwsClause
  }
  var rethrowsClause: TokenSyntax? {
    signature.effectSpecifiers?.throwsClause == nil ? nil : .keyword(.rethrows)
  }
  
  
  func callsight(namePrefix: String = "", parentType: String = "") -> DeclSyntax {
    "\(raw: effectSpecifiers)\(raw: parentType)\(raw: namePrefix)\(name)\(raw: callArguments)"
  }
  
  func closureCallsight(namePrefix: String = "", parentType: String = "", accessor: DeclSyntax = "") -> DeclSyntax {
    "\(raw: effectSpecifiers)\(raw: parentType)\(raw: namePrefix)\(name)\(raw: accessor)(\(raw: closureCallArguments()))"
  }

  func closureVariableDefinition(namePrefix: String = "") -> DeclSyntax {
    "var \(raw: namePrefix)\(name): @Sendable \(raw: closureParameterClause)\(signature.effectSpecifiers)\(raw: closureReturnClause)"
  }
  
  var yieldBlock: DeclSyntax {
    let implementationCallsight = closureCallsight(namePrefix: "__", accessor: implementationFunctionAccessor)
    if isAsyncSequence {
      return """
      var iterator = \(raw: implementationCallsight).makeAsyncIterator()
       await continuation.resume(
        returning: try await iterator.next(isolation: EffectExecutionActor.shared)
      )
      """
    } else {
      return """
      await continuation.resume(
        returning: \(raw: implementationCallsight)
      )
      """
    }
  }
  
  var effectProperties: String {
    signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName: TokenSyntax
      if let secondName = param.secondName {
        if secondName.tokenKind == .wildcard {
          propertyName = "arg\(raw: index + 1)"
        } else {
          propertyName = secondName
        }
      } else if param.firstName.tokenKind == .wildcard {
        propertyName = "arg\(raw: index + 1)"
      } else {
        propertyName = param.firstName
      }
      return "let \(propertyName): \(param.type)"
    }.joined(separator: "\n")
  }
  
  var effectBridgeProperties: String {
    signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName: TokenSyntax
      if let secondName = param.secondName {
        if secondName.tokenKind == .wildcard {
          propertyName = "arg\(raw: index + 1)"
        } else {
          propertyName = secondName
        }
      } else if param.firstName.tokenKind == .wildcard {
        propertyName = "arg\(raw: index + 1)"
      } else {
        propertyName = param.firstName
      }
      return "let \(propertyName): UnsafeTransfer<\(param.type)>"
    }.joined(separator: "\n")
  }
  
  var effectBridgeContinuationInitArguments: DeclSyntax {
    var args = signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName = param.firstName.tokenKind == .wildcard ? "" : "\(param.firstName): "
      let argName = param.secondName ?? param.firstName
      return "\(propertyName)\(argName)"
    }.joined(separator: ",\n")
    if !args.isEmpty {
      args.insert(Character("\n"), at: args.startIndex)
      args.append(",")
    }
    return "\(raw: args)"
  }
  
  var effectContinuationInitArguments: DeclSyntax {
    var args = signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName = param.firstName.tokenKind == .wildcard ? "" : "\(param.firstName): "
      let argName = param.secondName ?? param.firstName
      return "\(propertyName)\(argName).value"
    }.joined(separator: ",\n")
    if !args.isEmpty {
      args.insert(Character("\n"), at: args.startIndex)
      args.append(",")
    }
    return "\(raw: args)"
  }
  
  var unsafeTransfers: DeclSyntax {
    let lines = signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName: TokenSyntax
      if let secondName = param.secondName {
        if secondName.tokenKind == .wildcard {
          propertyName = "arg\(raw: index + 1)"
        } else {
          propertyName = secondName
        }
      } else if param.firstName.tokenKind == .wildcard {
        propertyName = "arg\(raw: index + 1)"
      } else {
        propertyName = param.firstName
      }
      return "let \(propertyName) = UnsafeTransfer(\(propertyName))"
    }.joined(separator: "\n")
    return "\(raw: lines)"
  }
  
  var runtimeContinuationCallArguments: DeclSyntax {
    var args = signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName = param.firstName.tokenKind == .wildcard ? "" : "\(param.firstName): "
      let argName = param.secondName ?? param.firstName
      return "\(propertyName)\(argName)_transfer.value"
    }.joined(separator: ",\n")
    if !args.isEmpty {
      args.insert(Character("\n"), at: args.startIndex)
      args.append(",")
    }
    return "\(raw: args)"
  }
  
  var effectInitParameters: String {
    guard hasParams else { return "" }
    let params = signature.parameterClause.parameters.map {
      "\($0)"
    }.joined(separator: "\n")
    return "\n\(params),"
  }
  
  var effectBridgeInitParameters: String {
    guard hasParams else { return "" }
    let params = signature.parameterClause.parameters.map { parameter in
      var copy = parameter
      copy.type = "UnsafeTransfer<\(parameter.type)>"
      return "\(copy)"
    }.joined(separator: "\n")
    return "\n\(params),"
  }
  
  var initPropertyAssignments: String {
    guard hasParams else { return "" }
    return "\n" + signature.parameterClause.parameters.enumerated().map { (index, param) in
      let propertyName: TokenSyntax
      if let secondName = param.secondName {
        if secondName.tokenKind == .wildcard {
          propertyName = "arg\(raw: index + 1)"
        } else {
          propertyName = secondName
        }
      } else if param.firstName.tokenKind == .wildcard {
        propertyName = "arg\(raw: index + 1)"
      } else {
        propertyName = param.firstName
      }
      return "self.\(propertyName) = \(propertyName)"
    }.joined(separator: "\n")
  }
  
  func syncEffectHandlerImplementation(_ effectNameBase: String, parentTypeName: String) -> DeclSyntax {
    guard !isAsync else { return "" }
    
    return """
     \n
      func handle<EffectReturnType>(operation: () throws -> EffectReturnType) rethrows -> EffectReturnType {
        let parent_\(name): \(implementationFunctionType) = \(raw: underscoredName)\(raw: implementationFunctionAccessor)
        let parent_nestingLevel = Effect.nestingLevel
        let \(name): @Sendable \(raw: closureParameterClause)\(signature.effectSpecifiers)\(raw: closureReturnClause) = { \(raw: closureArgumentsClause)
          \(raw: effectSpecifiers) Effect.$nestingLevel.withValue(parent_nestingLevel) {
            \(withNestingLevelStatement(effectNameBase, effectSpecifiers: effectSpecifiers, parentTypeName: parentTypeName))
              \(withParentImplementationStatement(effectNameBase, root: "self.", parentTypeName: parentTypeName))
            }
          }
        }
        \(withLocalImplementationStatement(effectNameBase, parentTypeName: parentTypeName, isAsync: false))
          try Effect.$nestingLevel.withValue(Effect.nestingLevel + 1) {
            \(withNestingLevelStatement(effectNameBase, effectSpecifiers: "try", parentTypeName: parentTypeName))
              let result = try operation()
              if let effectScope = result as? EffectScope {
                let key = ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: genericArguments).self)
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
    """
  }
  
  func taskLocalImplementation(_ effectNameBase: String, parentTypeName: String) -> DeclSyntax {
    if isGeneric {
      """
      private nonisolated static let \(implementationStorageName): TaskLocal<[ObjectIdentifier: any Sendable]> = TaskLocal(wrappedValue: [:])
      
      private nonisolated static func \(raw: underscoredName)\(genericParameterClause)() -> \(implementationFunctionType) { 
          if let impl = \(implementationStorageName).get()[ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: genericArguments).self)] {
            return impl as! @Sendable \(raw: closureParameterClause)\(signature.effectSpecifiers)\(raw: closureReturnClause)
          } else {
            return {\(raw: closureArgumentsClause) \(body?.statements) 
            }
          }      
          }
      """
    } else {
      """
      private nonisolated static let \(raw: underscoredName): TaskLocal<@Sendable \(raw: closureParameterClause)\(signature.effectSpecifiers)\(raw: closureReturnClause)> = TaskLocal(wrappedValue: { \(raw: closureArgumentsClause) \(body?.statements) 
          })
      """
    }
  }
  
  var implementationStorageName: DeclSyntax {
    "\(raw: underscoredName)_storage"
  }
  
  var nestingLevelStorageDeclaration: DeclSyntax? {
    if isGeneric {
      "nonisolated static let \(nestingLevelStorageName): TaskLocal<[ObjectIdentifier: UInt8]> = TaskLocal(wrappedValue: [:])"
    } else {
      nil
    }
  }
  
  func withNestingLevelStatement(_ effectNameBase: String, effectSpecifiers: String, parentTypeName: String) -> DeclSyntax {
    if isGeneric {
      """
      \(raw: effectSpecifiers) \(nestingLevelStorageName).withValue(
        \(nestingLevelStorageName).get().merging([ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: genericArguments).self) : Effect.nestingLevel]) { _, new in new }
      ) {
      """
    } else {
      """
      \(raw: effectSpecifiers) \(raw: effectNameBase)Effect\(raw: genericArguments).nestingLevel.withValue(Effect.nestingLevel) {
      """
    }
  }
  
  var nestingLevelStorageName: DeclSyntax {
    "\(raw: underscoredName)_nestingLevel_storage"
  }

  
  func taskLocalNestingLevel(effectNameBase: String, parentTypeName: String) -> DeclSyntax {
    if isGeneric {
      """
      nonisolated static func nestingLevel() -> UInt8 { 
          if let nestingLevel = \(nestingLevelStorageName).get()[ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: genericArguments).self)] {
            return nestingLevel
          } else {
            return 0
          }      
      }
      """
    } else {
      """
      nonisolated static let nestingLevel: TaskLocal<UInt8> = TaskLocal(wrappedValue: 0)
      """
    }
  }
  
  var implementationFunctionType: DeclSyntax {
    "@Sendable \(raw: closureParameterClause)\(signature.effectSpecifiers)\(raw: closureReturnClause)"
  }
  
  var implementationFunctionAccessor: DeclSyntax {
    if isGeneric {
      "()"
    } else {
      ".get()"
    }
  }
  
  var nestingLevelAccessor: DeclSyntax {
    if isGeneric {
      "()"
    } else {
      ".get()"
    }
  }

  func withParentImplementationStatement(_ effectNameBase: String, root: String, parentTypeName: String) -> DeclSyntax {
    if isGeneric {
      """
      \(raw: effectSpecifiers) \(implementationStorageName).withValue(
        \(implementationStorageName).get().merging(
        [ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: genericArguments).self) : parent_\(name)]
        ) {_, new in new }
      ) {
        \(closureCallsight(parentType: root))
      }
      """
    } else {
      """
      \(raw: effectSpecifiers) \(raw: underscoredName).withValue(parent_\(name)) {
          \(closureCallsight(parentType: root))
      }
      """
    }
  }
  
  func withLocalImplementationStatement(_ effectNameBase: String, parentTypeName: String, isAsync: Bool) -> DeclSyntax {
    let awaitKeyword: DeclSyntax = "\(raw: (isAsync ? "await" : ""))"
    return if isGeneric {
      """
      let result = try \(awaitKeyword) \(implementationStorageName).withValue(
        \(implementationStorageName).get().merging(
          [ObjectIdentifier(\(raw: parentTypeName).\(raw: effectNameBase)\(raw: genericArguments).self) : \(name)]
        ) {_, new in new }
      ) {
      """
    } else {
      """
      let result = try \(awaitKeyword) \(raw: underscoredName).withValue(\(name)) {
      """
    }
  }
  
  var effectHandlerConformance: DeclSyntax {
    return if isAsync {
       "EffectHandler"
    } else {
      "SyncEffectHandler"
    }
  }
  
  var closureArgumentsClause: String {
    "\(closureArguments) \((closureArguments ==  "" ? "" : "in"))"
  }
  
  var closureArguments: String {
    signature.parameterClause.parameters.map { param in
      let argName = param.secondName ?? param.firstName
      return "\(argName.text)"
    }.joined(separator: ", ")
  }
  
  var continuationType: String {
    if isThrowing {
      "withCheckedThrowingContinuation"
    } else {
      "withCheckedContinuation"
    }
  }
  
  var errorType: DeclSyntax {
    if let (_, type) = asyncSequenceTypeArguments {
      "\(type.trimmed)"
    } else if isThrowing {
      if let type = throwsClause?.type {
        "\(type)"
      } else {
        "any Error"
      }
    } else {
      "Never"
    }
  }
}
extension MacroExpansionContext {
  var isEffectExtension: Bool {
    for node in lexicalContext.reversed() {
      switch node.as(SyntaxEnum.self) {
      case let .extensionDecl(extensionDecls) where "\(extensionDecls.extendedType.trimmed)" == "Effect":
        return true
      default:
        continue
      }
    }
    return false
  }
  func parentTypeName() -> String? {
    for node in lexicalContext.reversed() {
      switch node.as(SyntaxEnum.self) {
      case let .enumDecl(enumDecl):
        return enumDecl.name.text
      case let .structDecl(structDecl):
        return structDecl.name.text
      case let .classDecl(classDecl):
        return classDecl.name.text
      case let .actorDecl(actorDecl):
        return actorDecl.name.text
      case let .extensionDecl(extensionDecls):
        return "\(extensionDecls.extendedType.trimmed)"
      default:
        continue
      }
    }
    return nil
  }
}
