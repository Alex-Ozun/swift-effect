import Effect
import Testing

@Suite
struct AsyncSequenceTests {
  @Test
  func finishing() async throws {
    func echoStream() async throws {
      for try await line in Console.readLines() {
        Console.writeLine(line)
      }
      Console.writeLine("finished")
    }
    try await withTestHandler {
      try await echoStream()
    } test: { effect in
      try await effect.expect(\.Console.readLines, return: "Hello")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
      
      try await effect.expect(\.Console.readLines, return: "Good Bye")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Good Bye") }
      
      try await effect.expect(\.Console.readLines, return: nil) /*end of stream*/
      try await effect.expect(\.Console.writeLine) { #expect($0 == "finished") }
    }
  }
  
  @Test
  func throwing() async throws {
    struct MyError: Error {}
    func echoStream() async throws {
      for try await line in Console.readLines() {
        Console.writeLine(line)
      }
      Issue.record("should be unreachable")
    }
    await #expect(throws: MyError.self) {
      try await withTestHandler {
        try await echoStream()
      } test: { effect in
        try await effect.expect(\.Console.readLines, return: "Hello")
        try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
        
        try await effect.expect(\.Console.readLines, return: "Good Bye")
        try await effect.expect(\.Console.writeLine) { #expect($0 == "Good Bye") }
        try await effect.expect(\.Console.readLines) { throw MyError() }
        Issue.record("should be unreachable")
      }
    }
  }
}
