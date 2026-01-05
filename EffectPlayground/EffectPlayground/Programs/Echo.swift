import Foundation

func echo() {
  var run = true
  while run {
    let line = Console.readLine()
    if line == "Stop" { run = false }
    else { Console.writeLine(line) }
  }
}
