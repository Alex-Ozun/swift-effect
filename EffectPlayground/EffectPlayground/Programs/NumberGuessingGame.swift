//
//  NumberGuessingGame.swift
//  EffectPlayground
//
//  Created by Alex Ozun on 19/12/2025.
//

import Foundation
import SwiftUI
import Effect

@MainActor
@Observable
@EffectScope
class NumberGuessingGame {
  var message: String = ""
  
  func run() async throws -> Bool {
    let number = try await Random.generateRandomNumber()
    message = "Please guess a number from 1 to 5:"
    let input = await Console.readLineAsync()
    
    var isCorrect: Bool
    if let num = Int(input) {
      if num == number {
        message = "You guessed \(input), Correct!"
        isCorrect = true
      } else {
        message = "You guessed \(input), Incorrect! The number was \(number)."
        isCorrect = false
      }
    } else {
      message = "Not a number"
      isCorrect = false
    }
    return isCorrect
  }
}
