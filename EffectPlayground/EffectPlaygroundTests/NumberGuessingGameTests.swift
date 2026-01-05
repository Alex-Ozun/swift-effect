//
//  NumberGuessingGameTests.swift
//  EffectPlaygroundTests
//
//  Created by Alex Ozun on 19/12/2025.
//

import Effect
import Testing
@testable import EffectPlayground

@MainActor
@Suite
struct NumberGuessingGameTests {
  @Test func correctGuess() async throws {
    let game = NumberGuessingGame()
    let hasGuessedCorrect = try await withTestHandler {
      try await game.run()
    }
    test: { effect in
      try await effect.expect(\.Random.generateRandomNumber, return: 1)
      await #expect(game.message == "Please guess a number from 1 to 5:")
      try await effect.expect(\.Console.readLineAsync, return: "1")
      await #expect(game.message == "You guessed 1, Correct!")
    }
    #expect(hasGuessedCorrect)
  }
  
  @Test func incorrectGuess() async throws {
    let game = NumberGuessingGame()
    let hasGuessedCorrect = try await withTestHandler {
      try await game.run()
    }
    test: { effect in
      try await effect.expect(\.Random.generateRandomNumber, return: 1)
      await #expect(game.message == "Please guess a number from 1 to 5:")
      try await effect.expect(\.Console.readLineAsync, return: "2")
      await #expect(game.message == "You guessed 2, Incorrect! The number was 1.")
    }
    #expect(!hasGuessedCorrect)
  }
  
  @Test func notANumberGuess() async throws {
    let game = NumberGuessingGame()
    let hasGuessedCorrect = try await withTestHandler {
      try await game.run()
    }
    test: { effect in
      try await effect.expect(\.Random.generateRandomNumber, return: 1)
      await #expect(game.message == "Please guess a number from 1 to 5:")
      try await effect.expect(\.Console.readLineAsync, return: "rubbish")
      await #expect(game.message == "Not a number")
    }
    #expect(!hasGuessedCorrect)
  }
}
