//
//  EffectHandlerCompositionTests.swift
//  EffectPlaygroundTests
//
//  Created by Alex Ozun on 19/12/2025.
//

import Testing
import Effect
@testable import EffectPlayground
typealias WriteLine = Console.WriteLine
typealias ReadLine = Console.ReadLine

@Suite
struct EffectHandlerCompositionTests {
  @Test
  func innerFilter() async throws {
    try await withTestHandler {
      // Inner writeLine handler may choose to send some effects up to Test Handler
      // this way we can build a "high-pass" filter for effects that meet some criteria of interest
      with(WriteLine {
          if $0 == "Hello" || $0 == "Hi" { // We're only interested in testing greetings
            Console.writeLine($0)
          }
        }) {
        echo()
      }
    } test: { effect in
      try await effect.expect(\.Console.readLine, return: "Hello")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello")}
      
      try await effect.expect(\.Console.readLine, return: "Hi")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hi") }
      
      try await effect.expect(\.Console.readLine, return: "Good bye")
//      try await effect.expect(\.Console.writeLine) { // filtered out
//        #expect($0 == "Good bye")
//      }
      
      try await effect.expect(\.Console.readLine, return: "Bye")
//      try await effect.expect(\.Console.writeLine) { // filtered out
//        #expect($0 == "Bye")
//      }
      
      try await effect.expect(\.Console.readLine, return: "Stop")
      
    }
  }
  
  @Test
  func innerStub() async throws {
    try await withTestHandler {
      // Inner no-op writeLine handler discharges
      // all writeLine effects before they can reach Test Handler
      // this way we can "stub out" or filter out all effects of this type.
      with(WriteLine { _ in }) {
        echo()
      }
    } test: { effect in
      try await effect.expect(\.Console.readLine, return: "Hello")
      try await effect.expect(\.Console.readLine, return: "Good bye")
      try await effect.expect(\.Console.readLine, return: "Stop")
      
    }
  }
  
  @Test
  func outerDevNull() async throws {
    try await with(WriteLine { _ in }) { //outer "dev/null" handler
      try await withTestHandler {
        echo()
      } test: { effect in
        try await effect.expect(\.Console.readLine, return: "Hello")
        try await effect.yield() // ignores this effect and sends it up to the outer handler
        
        try await effect.expect(\.Console.readLine, return: "Good bye")
        try await effect.expect(\.Console.writeLine) { #expect($0 == "Good bye")}
        
        try await effect.expect(\.Console.readLine, return: "Stop")
      }
    }
  }
  
  @Test
  func outerMock() async throws {
    try await with(ReadLine { "Hello" }) { //outer mock
      try await withTestHandler {
        echo()
      } test: { effect in
        try await effect.yield() // ignores this effect and sends it up to the outer handler
        try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
        
        try await effect.expect(\.Console.readLine, return: "Good bye")
        try await effect.expect(\.Console.writeLine) { #expect($0 == "Good bye") }
        
        try await effect.yield() // ignores this effect and sends it up to the outer handler
        try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
        
        try await effect.expect(\.Console.readLine, return: "Stop")
        
      }
    }
  }
  
  @Test
  func handlerComposition() async throws {
    try await withTestHandler { // root
      // Compose bottom to top
      with {
        WriteLine { line in
          Console.writeLine(line.uppercased()) // outer
        }
        WriteLine { line in
          Console.writeLine(String(line.reversed())) // inner
        }
      } perform: {
        echo()
      }
    } test: { effect in
      try await effect.expect(\.Console.readLine, return: "Hello")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "OLLEH") }
      try await effect.expect(\.Console.readLine, return: "Good bye")
      try await effect.expect(\.Console.writeLine) { #expect($0 == "EYB DOOG") }
      try await effect.expect(\.Console.readLine, return: "Stop")
    }
  }
}
