import Effect
import Testing

@Suite
struct UnstructuredEffectTaskTests {
  @Test
  func enqueueTasksInOrder() async throws {
    func program() {
      Console.writeLine("before")
      Task.effect(name: "task 1") {
        Console.writeLine("task 1")
      }
      Task.effect(name: "task 2") {
        Console.writeLine("task 2")
      }
      Console.writeLine("after")    }
    try await withTestHandler(taskHandling: .suspend) {
      program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expectTask(action: .enqueue)
      try await effect.expectTask(action: .enqueue)
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
    }
  }
  
  @Test
  func enqueueTasksOutOfOrder() async throws {
    func program() {
      Console.writeLine("before")
      Task.effect(name: "task 1") {
        Console.writeLine("task 1")
      }
      Task.effect(name: "task 2") {
        Console.writeLine("task 2")
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .suspend) {
      program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      let task = try await effect.expectTask(action: .suspend)
      let task2 = try await effect.expectTask(action: .suspend)
      task2.enqueue() // enqueue task 2 before 1
      task.enqueue()
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
    }
  }
  
  @Test
  func nestedTasks() async throws {
    func program() {
      Console.writeLine("before")
        Task.effect {
          Task.effect {
            Task.effect {
              Task.effect {
                Task.effect {
                  Task.effect {
                    Task.effect {
                      Task.effect {
                        Console.writeLine("task 5")
                      }
                    }
                    Console.writeLine("task 4")
                  }
                }
                Console.writeLine("task 3")
              }
            }
            Console.writeLine("task 2")
          }
          Console.writeLine("task 1")
        }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .automaticallyEnqueue) {
      program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 3") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 4") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 5") }
    }
  }
  
  @Test
  func flattenedTasks() async throws {
    func program() {
      Console.writeLine("before")
      Task.effect {
        Console.writeLine("task 1")
      }
      Task.effect {
        Console.writeLine("task 2")
      }
      Task.effect {
        Console.writeLine("task 3")
      }
      Task.effect {
        Console.writeLine("task 4")
      }
      Task.effect {
        Console.writeLine("task 5")
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .automaticallyEnqueue) {
      program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 3") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 4") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 5") }
    }
  }
  
  @Test
  func mixedTasks() async throws {
    func program() {
      Console.writeLine("before")
      Task.effect {
        Task.effect {
          Console.writeLine("inner task 1")
        }
        Console.writeLine("task 1")
      }
      Task.effect {
        Task.effect {
          Console.writeLine("inner task 2")
        }
        Console.writeLine("task 2")
      }
      Task.effect {
        Task.effect {
          Console.writeLine("inner task 3")
        }
        Console.writeLine("task 3")
      }
      Task.effect {
        Task.effect {
          Console.writeLine("inner task 4")
        }
        Console.writeLine("task 4")
      }
      Task.effect {
        Task.effect {
          Console.writeLine("inner task 5")
        }
        Console.writeLine("task 5")
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .automaticallyEnqueue) {
      program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 3") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 4") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 5") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "inner task 1") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "inner task 2") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "inner task 3") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "inner task 4") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "inner task 5") }
    }
  }
  
  @Test
  func mixOfRandomlySlowTasks() async throws {
    let count = 10
    func program() {
      Console.writeLine("before")
      for i in (1...count) {
        Task.effect {
          try? await Task.sleep(for: .milliseconds(Double.random(in: (1...10))))
          for j in (1...count) {
            Task.effect {
              try? await Task.sleep(for: .milliseconds(Double.random(in: (1...10))))
              Console.writeLine("task \(j)")
            }
          }
          Console.writeLine("task \(i)")
        }
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .automaticallyEnqueue) {
      program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      for i in (1...count) {
        try await effect.expect(\.Console.writeLine) { #expect($0 == "task \(i)") }
      }
      for _ in (1...count) {
        for j in (1...count) {
          try await effect.expect(\.Console.writeLine) { #expect($0 == "task \(j)") }
        }
      }
    }
  }
  
  @Test
  func awaitTasks() async throws {
    func program() async {
      Console.writeLine("before")
      let task = Task.effect {
        Console.writeLine("task 1")
        return Console.readLine()
      }
      async let line = task.value
      Console.writeLine(await task.value)
      Console.writeLine(await line)
      Console.writeLine(await task.value)
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .automaticallyEnqueue) {
      await program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
      try await effect.expect(\.Console.readLine) { "Hello" }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "Hello") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
    }
  }
  
  @Test
  func skipTasks() async throws {
    func program() async {
      Console.writeLine("before")
      Task.effect(name: "task 1") {
        Console.writeLine("task 1")
      }
      Task.effect(name: "task 2") {
        Console.writeLine("task 2")
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .ignore) {
      await program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
    }
  }
  
  @Test
  func skipTasksButCaptureAwaiting() async throws {
    func program() async {
      Console.writeLine("before")
      Task.effect(name: "task 1") {
        Console.writeLine("task 1")
      }
      await Task.effect(name: "task 2") {
        Console.writeLine("task 2")
      }.value
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .ignore) {
      await program()
    } test: { effect in
      try await effect.expect(\.Console.writeLine) { #expect($0 == "before") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
    }
  }
  
  @Test
  func enqueueTasks() async throws {
    func program() {
      Task.effect(name: "task 1") {
        Console.writeLine("task 1")
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .suspend) {
      program()
    } test: { effect in
      try await effect.expectTask(action: .enqueue)
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
    }
  }
  
  @Test
  func suspendTasks() async throws {
    func program() {
      Task.effect(name: "task 1") {
        _ = Task.effect(name: "task 2") {
          _ = Task.effect(name: "task 3") {
            Console.writeLine("task 3")
          }
        }
      }
      Console.writeLine("after")
    }
    try await withTestHandler(taskHandling: .suspend) {
      program()
    } test: { effect in
      let task = try await effect.expectTask(action: .suspend)
      try await effect.expect(\.Console.writeLine) { #expect($0 == "after") }
      task.enqueue()
      let task2 = try await effect.expectTask(action: .suspend)
      task2.enqueue()
      let task3 = try await effect.expectTask(action: .suspend)
      task3.enqueue()
      try await effect.expect(\.Console.writeLine) { #expect($0 == "task 3") }
    }
  }
}
