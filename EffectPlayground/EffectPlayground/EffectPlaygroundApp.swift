//
//  EffectPlaygroundApp.swift
//  EffectPlayground
//
//  Created by Alex Ozun on 15/12/2025.
//

import SwiftUI
import Effect
@main
struct EffectPlaygroundApp: App {
    var body: some Scene {
        WindowGroup {
          VStack {
            Button {
              with {
                Console.WriteLine { print($0.uppercased()) }
              } perform: {
                _ = Task.effect {
                  Console.writeLine("hello")
                }
              }
            } label: {
              Text("Fetch random number (observe console logs)")
            }
          }
          .padding()
        }
    }
}

@EffectScope
struct Model {
  func doSomething() -> String {
    let line = Console.readLine()
    print(line)
    unrelated()
    return line
  }
}

func unrelated() {
  let line = Console.readLine()
  print(line)
}
