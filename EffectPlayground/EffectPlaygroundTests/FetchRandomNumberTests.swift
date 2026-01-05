import Effect
internal import Foundation
@testable import EffectPlayground
import Testing

@Suite
struct FetchRandomNumberTests {
  @Test func luckyNumber() async throws {
    try await withTestHandler {
      try await fetchRandomNumber()
    } test: { effect in
      try await effect.expect(\.HTTP.dataFromURL) { url in
        #expect(url == URL(string: "https://www.randomnumberapi.com/api/v1.0/random?min=1&max=7")!)
        return "[7]".data(using: .utf8)!
      }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "received a lucky number!") }
    }
  }
  
  @Test func noNumbers() async throws {
    try await withTestHandler {
      try await fetchRandomNumber()
    } test: { effect in
      try await effect.expect(\.HTTP.dataFromURL) { url in
        #expect(url == URL(string: "https://www.randomnumberapi.com/api/v1.0/random?min=1&max=7")!)
        return "[]".data(using: .utf8)!
      }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "received no numbers :(") }
    }
  }
  
  @Test func someNumbers() async throws {
    try await withTestHandler {
      try await fetchRandomNumber()
    } test: { effect in
      try await effect.expect(\.HTTP.dataFromURL) { url in
        #expect(url == URL(string: "https://www.randomnumberapi.com/api/v1.0/random?min=1&max=7")!)
        return "[1]".data(using: .utf8)!
      }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "received 1") }
    }
  }
}
