@testable import Effect
@testable import EffectPlayground
import Testing

public struct MyError: Error {
  public init() {}
}
@Suite
struct EchoTests {
  @Test
  func echoTest() async throws {
    func echo() {
      while let line = Console.readLine2() {
        Console.writeLine(line)
      }
    }
    try await withTestHandler {
      echo()
    } test: { effect in
      try await effect.expect(\.Console.readLine2, return: "Hello")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
      
      try await effect.expect(\.Console.readLine2, return: "Good Bye")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Good Bye") }
      
      try await effect.expect(\.Console.readLine2, return: nil)
    }
  }
}
