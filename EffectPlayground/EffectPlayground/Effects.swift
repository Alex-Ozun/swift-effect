//
//  Effects.swift
//  EffectPlayground
//
//  Created by Alex Ozun on 15/12/2025.
//

import Foundation
import Effect
import Semaphore

struct Console {
  @Effect()
  static func readLine() -> String {
    Swift.readLine()!
  }
  
  @Effect()
  static func readLine2() -> String? {
    Swift.readLine()
  }
  
  @Effect
  static func readLines() -> any AsyncSequence<String, any Error> {
    AsyncThrowingStream {
      try await Task.sleep(for: .seconds(1))
      return Swift.readLine()!
    }
  }
  
  @Effect
  static func readLineAsync() async -> String {
    Swift.readLine()!
  }
  
  @Effect
  static func writeLine(_ line: String) {
    print(line)
  }
}

struct Random {
  @Effect
  static func generateRandomNumber() async throws -> Int {
    return Int.random(in: 0 ... 5)
  }
}

struct HTTP {
  @Effect(name: "DataFromURL")
  static func data(from url: URL) async throws -> Data {
    let (data, _) = try await URLSession.shared.data(from: url)
    Console.writeLine("DataFromURL (URL Session) fetching data from the internet...")
    try await Task.sleep(for: .seconds(2))
    return data
  }
}

// To generate ergonomic accessors in test. Not necessary, can just use types.
extension Effect {
  var Console: EffectPlayground.Console { EffectPlayground.Console() }
  var HTTP: EffectPlayground.HTTP { EffectPlayground.HTTP() }
  var Random: EffectPlayground.Random { EffectPlayground.Random() }
//  var readLine: Console.ReadLine.Type { Console.ReadLine.self }
//  var readLines: Console.ReadLines.Type { Console.ReadLines.self }
//  var readLineAsync: Console.ReadLineAsync.Type { Console.ReadLineAsync.self }
//  var writeLine: Console.WriteLine.Type { Console.WriteLine.self }
//  var generateRandomNumber: Random.GenerateRandomNumber.Type { Random.GenerateRandomNumber.self }
//  var dataFromURL: HTTP.DataFromURL.Type { HTTP.DataFromURL.self }
}

extension Effect {
  @Effect
  static func generic<Value: AdditiveArithmetic & Sendable>(l: Value, r: Value) -> Value {
    l + r
  }
  
  @Effect
  static func nonSendableEffect(_ line: NonSendable) -> NonSendable {
    NonSendable()
  }
}

class NonSendable {}

struct MyError: Error, Equatable {}
