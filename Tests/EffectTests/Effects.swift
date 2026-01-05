import Effect

struct Console {
  @Effect
  static func readLine() -> String {
    Swift.readLine()!
  }
  
  @Effect
  static func readLines() -> any AsyncSequence<String, any Error> {
    AsyncThrowingStream {
      try await Task.sleep(for: .seconds(1))
      return Swift.readLine()!
    }
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

// To generate ergonomic accessors in test. Not necessary, can just use types.
extension Effect {
  var Console: EffectTests.Console { EffectTests.Console() }
  var Random: EffectTests.Random { EffectTests.Random() }
}
