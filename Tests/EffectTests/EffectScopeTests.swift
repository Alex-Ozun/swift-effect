@testable import Effect
import Testing

@Suite
struct EffectScopeTests {
  @EffectScope
  struct Echo {
    func run() {
      var run = true
      while run {
        let line = Console.readLine()
        if line == "Stop" { run = false }
        else { Console.writeLine(line) }
      }
    }
    
    @EffectScopeIgnored
    func runIgnoringScope() {
      var run = true
      while run {
        let line = Console.readLine()
        if line == "Stop" { run = false }
        else { Console.writeLine(line) }
      }
    }
  }
  
  @Test
  func echoScopeTest() async throws {
    nonisolated(unsafe) var log: [String] = []
    let echo = with {
      Console.WriteLine { log.append($0) }
    } perform: {
      Echo()
    }
    
    try await withTestHandler {
      echo.run()
    } test: { effect in
      try await effect.expect(\.Console.readLine, return: "Hello")
      try await effect.expect(\.Console.readLine, return: "Good Bye")
      try await effect.expect(\.Console.readLine, return: "Stop")
    }
    #expect(log == ["Hello", "Good Bye"])
  }
  
  @Test
  func echoScopeIgnoredTest() async throws {
    nonisolated(unsafe) var log: [String] = []
    let echo = with {
      Console.WriteLine { log.append($0) }
    } perform: {
      Echo()
    }
    
    try await withTestHandler {
      echo.runIgnoringScope()
    } test: { effect in
      try await effect.expect(\.Console.readLine, return: "Hello")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
      try await effect.expect(\.Console.readLine, return: "Good Bye")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Good Bye") }
      try await effect.expect(\.Console.readLine, return: "Stop")
    }
    #expect(log == [])
  }
}
