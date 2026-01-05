<h1 align="center">Swift Effect</h1>
<h4 align="center">Algebraics Effect and Effect Handlers for Swift</h4>

[![](https://img.shields.io/badge/preview-not_ready_for_production-F94444)](https://github.com/Alex-Ozun/swift-effect/releases)

**Swift Effect** is an architecture-agnostic effect system that makes side effects—such as I/O, networking, randomness, concurrency—controllable, composable, and testable without forcing structural changes to your application code. With just two lightweight abstractions—**Effects** and **Effect Handlers**—it enables natural composition of behaviours while keeping application code linear, procedural, and easy to reason about. In tests, the same mechanism powers mock-less testing of behaviours: observable effects can be intercepted, suspended, and resumed with just-in-time test data, without invasive scaffolding or test-only abstractions in application code, commonly required by traditional DI libraries and architectural frameworks.

🔗 Jump to:
- ✨ [Features](#-features)
- 📖 [Examples](#-examples)
	- [Definings Effects](#defining-effects)
	- [Effect composition](#effect-composition)
	- [Testing](#testing)
	- [Effect composition in Tests](#effect-composition-in-tests)
	- [AsyncStreams and Effects](#async-streams-and-effects)
	- [Deterministic testing of Unstructured Concurrency](#deterministic-testing-of-unstructured-concurrency)
	- [Effect Scopes](#effect-scopes)
- ❓[FAQ](#faq)
	- [1. How is programming with Effects different from Dependency Injection?](#1-how-is-programming-with-effects-different-from-dependency-injection)
  	- [2. Aren’t effects just global functions? Aren’t globals bad?]([#2-arent-effects-just-global-functions-arent-globals-bad)
# ✨ Features

- **Minimal but General**: Effects and Effect Handler form a minimal, operation-level abstraction—often representing an atomic operation such as `print`—that can be freely composed with other effectful operations to build arbitrarily complex behaviours. This contrasts with traditional DI libraries that build on object- and type-level abstractions (for example, a `ConsoleService`), which are more prone to [leaking](https://www.joelonsoftware.com/2002/11/11/the-law-of-leaky-abstractions/) to application code, and are generally harder to compose due to their bespoke nature.
- **Composable**: Effect Handlers can be nested in the same way as `do–try–catch` exception handlers, placed anywhere in the stack hierarchy, enabling natural and intuitive composition of behaviours. This allows to separate application logic from specific behaviours, making programs modular, extensible, and portable.
- **Modular**: Effects and Effect Handlers are just normal functions. This allows application code that performs Effects to remain completely decoupled from Effect Handlers that provide their behavior. Effects can be defined in one module and handled in another, and multiple Effect Handlers for the same Effect can be supplied by different modules as needed.
- **Testable**: The library provides a `TestHandler`, a special Effect Handler that can intercept, suspend, inspect, and resume any Effects performed by the system under test. This enables a powerful testing style in which application code can be executed step by step, allowing tests to assert and interpret **observable behaviour and state** without ahead-of-time mocking, much like a human tester would by running the program and manually inputting data as it is needed.
- **Deterministic Concurrency**: The library enables deterministic testing of Swift Concurrency primitives—such as Tasks, Task Groups (WIP), and Async Streams—by modelling them as controllable effects in their own right.
- **Research-based**: The library is informed by extensive [theory and practice](https://github.com/yallop/effects-bibliography) around computational effects. **Swift Effect**'s design is primarily inspired by the established effect systems in [OCaml](https://ocaml.org/manual/5.4/effects.html) and [Koka](https://koka-lang.github.io/koka/doc/book.html#why-effects).

# 📖 Examples

## Defining Effects

Let’s start with a simple echo CLI program that prints back each input line and exits when `nil` is entered:

```swift
func echo() {
  while let line = readLine() { // ⚠️ I/O side effect
    print(line) // ⚠️ I/O side effect
  }
}
```
```
echo()
> Hello
Hello
> Good Bye
Good Bye
>
exit
```

This deceptively simple program performs two unmanaged I/O side effects—`readLine` and `print`—making it practically impossible to test or extend with custom behaviours.

Let's turn `readLine` and `print` operations into controllable Effects:

```swift
enum Console { // Namespace
  @Effect
  static func readLine() -> String? {
    Swift.readLine()
  }
  
  @Effect
  static func print(_ line: String) {
    Swift.print(line)
  }
}
```

The `@Effect` macro exposes each operation to the effect system, and generates their corresponding Effect Handlers, which we'll see in action shortly.

First, let's update `echo` to use our new effects:

```swift
func echo() {
  while let line = Console.readLine() {
    Console.print(line)
  }
}
```

Notice that we didn't have to change the structure, control flow, or the interface of `echo`. It remains linear and procedural.

If we run `echo` again, it will work the exact same way as before. `Console.readLine` and `Console.print` operations will be handled by the global Effect Handlers, which simply call the implementations of the two static functions we defined above. This on itself is unremarkable.

But we can now extend `echo` with custom behaviours by running it with custom effect handlers. 

We do this by using the `with-handle-perform` effect handling block, which mirrors the semantics of `do-try-catch` exception handling block, so you can apply the same intuition here:

```swift
func main() {
  with {
    Print { line in
      let uppercased = line.uppercased()
      Swift.print(uppercased)
    }
  } perform: {
    echo()
  }
}
```
Now, each response is uppercased, without changing the original implementation of `echo`:

```
main()
> "Hello"
"HELLO"
> "Good Bye"
"GOOD BYE"
>
exit
```

`Print` effect handler was generated by the `@Effect` macro. Effect handlers take the capitalized names of corresponding effects.

When we run `echo()` and it performs `Console.print` effect, the first `Print` effect handler in the call stack will catch and handle this effect.

Crucially, `echo` doesn't know or care about how `Console.readLine` and `Console.print` effects are handled. It focuses on the application logic built on top of these two abstract operations.

*(Note: a set of abstract operations and the rules by which they work is known as Algebra, hence the term Algebraic Effects).* 

## Effect composition

Effect handlers are just normal functions, and they can perform effects too, including the ones they handle.
Let's look at the uppercased `Print` effect handler again:

```swift
Print { line in
  let uppercased = line.uppercased()
  Swift.print(uppercased)
}
```

It's problematic because it's over-specified to use `Swift.print` implementation, while its only purpose is to just uppercase outputs.

We can make this handler more reusable and composable like this:

```swift
Print { line in
  let uppercased = line.uppercased()
  Console.print(uppercased) // yield print effect to the next handler
}
```

Instead of hard-coding `Swift.print` implementation, `Print` just uppercases outputs and then performs the abstract `Console.print` effect itself!
Effect handlers follow the same rules as any other function, and all effects performed by effect handlers are caught and handled by the next corresponding handler in the call stack. Yielding effects from one handler to the next one works the same way as rethrowing errors from one `do-try-catch` exception handler to the next one.

This design gives rise to natural and intuitive composition of behaviour.

Let's add logging to our `echo` program:

```swift
// main.app
import Module

func main() {
  var log: [String] = []
  with {
    Print { line in
      log.append(line)
      Console.print(line) // yields to the next handler (global)
    }
  } perform: {
    module()
  }
}
// Module.framework
func module() {
   with {
    Print { line in
      let uppedcased = line.uppedcased()
      Console.print(uppedcased) // yields to the next handler (main)
    }
  } perform: {
    echo()
  }
}
```

```
main()
> Hello
HELLO    // log: ["HELLO"]
> Good Bye
GOOD BYE // log: ["HELLO", "GOOD BYE"]
>
exit
```

`with-handler-perform` blocks are result builders, and can install multiple effect handlers at a time, and include control flow statements:

```swift
func main() {
var log: [String] = []
  with {
    if enableLogging {
      Print { line in
        log.append(line)
        Console.print(line)
      }
    }
    ReadLine {
      Console.readLine().uppercased()
    }
  } perform: {
    echo()
  }
}
```

## Testing

Finally, let's put our `echo` program to test. 

**Swift Effect** provides a special `withTestHandler` effect handler that can catch all effects produces by the program under test.

```swift
func echo() {
  while let line = Console.readLine() {
    Console.print(line)
  }
}
@Test
func test() async throws {
  try await withTestHandler {
    echo()                                                    // 1
  } test: { effect in                                         
    try await effect.expect(Console.ReadLine.self) {          // 2
  	  return "Hello"                                          // 3
    }
    try await effect.expect(Console.Print.self) { line in     // 4
	  #expect(line == "Hello")                                // 5
    }
    try await effect.expect(Console.ReadLine.self) {
	  return "Good Bye"
    }
    try await effect.expect(Console.Print.self) { line in
  	  #expect(line == "Good Bye")
    }
    try await effect.expect(Console.ReadLine.self) {
	  return nil // exit                                       // 6
    }
  }
}
```

Let's break down the sequence of events:
1. `echo()` is launched inside `withTestHandler` context.
2. The `test` block is immediately suspended on the first line, awaiting the first effect produced by `echo`, which is expected to be `Console.readLine`. When `echo` performs `Console.readLine()`, execution of `echo` is suspended until a value is supplied by an effect handler. This effect is intercepted by the `test` handler, which attempts to match it against the `effect.expect(Console.ReadLine.self)` expectation. If an unexpected effect is produces, the test fails.
3. Since the produced effect matches the expectation, the test resumes into the trailing closure, which acts as a just-in-time `ReadLine` effect handler. In this case, the handler simply returns the `"Hello"` line, allowing `echo` to resume execution and to echo `"Hello"` back.
4. The test then proceeds to `await effect.expect(Console.Print.self)` and is suspended again, waiting for the next effect to be produced by `echo`.
5. When `echo` performs `Console.print("Hello")`, execution of `echo` is again suspended while awaiting the `print` effect to be handled. The test intercepts the effect and attempts to match it against the `await effect.expect(Console.Print.self)` expectation. Upon a successful match, the test resumes into the just-in-time trailing closure effect handler. In this case, the handler asserts `#expect(line == "Hello")` and returns, allowing `echo` to resume execution and proceed to the next `readLine` loop iteration.
6. This ping-pong exchange between the program and the test continues until a `ReadLine` handler returns `nil`, causing the program to exit and the test to conclude.

The library also provides syntactic sugar for ergonomic effect matching using key paths, as well as return-only handling for effects that have no input arguments:
```swift
try await effect.expect(\.Console.readLine, return: "Hello")
try await effect.expect(\.Console.print) { #expect($0 == "Hello") }
```

## Effect composition in Tests

What happens if we compose `withTestHandler` with another effect handler inside? 

```swift
@Test
func test() async throws {
  try await withTestHandler { // outer handler
    with {                    // inner handler
      Print { _ in }          // no-op print
    } perform: {
      echo()
    }                                                  
  } test: { effect in                                         
    try await effect.expect(\.Console.readLine, return: "Hello")
    try await effect.expect(\.Console.readLine, return: "Good Bye")
    try await effect.expect(\.Console.readLine, return: nil)
  }
}
```

The same rule applies here: the first available effect handler in the call stack intercepts the effect. In this case, when `echo` performs `Console.readLine()`, the first available handler for `readLine` is the `TestHandler`, which catches the effect, matches it against the expectation, and returns `"Hello"`.

But when `echo` performs `Console.print`, the first handler for this effect is the inner one providing the no-op `Print` behaviour. This handler does not yield the `print` effect to the next handler, so it effectively discharges the effect and it never reaches the `TestHandler`. As a result, the effect is completely invisible to `TestHandler`. In this sense, the inner handler acts as a filter for `print` effects.

### Opt-in testing pattern with inner handlers

Consider this inner `Print` handler that discharges all print effects but yields to the next handler when "Hello" is printed:

```swift
@Test
func test() async throws {
  try await withTestHandler { // outer handler
    with {                    // inner handler
      Print {
        if $0 == "Hello" {
          Console.print(line) // opt-in to testing "Hello" by yielding to the test handler 
        }
      }
    } perform: {
      echo()
    }                                                  
  } test: { effect in                                         
    try await effect.expect(\.Console.readLine, return: "Hello")
    try await effect.expect(\.Console.print) { #expect($0 == "Hello") }  // opt-in
    try await effect.expect(\.Console.readLine, return: "Hi")
    try await effect.expect(\.Console.readLine, return: "Good Bye")
    try await effect.expect(\.Console.readLine, return: nil)
  }
}
```

In this test, we only care about testing `"Hello"` prints and ignore everything else. This pattern is useful when a program produces many irrelevant effects—for example, a large number of `Logging.log(.debug, ...)` effects. In such cases, we can filter out all log effects except those with `LogLevel.error`.


### Opt-out testing pattern with outer handlers

Let's reverse this composition by making `Print` wrap `withTestHandler` instead:

```swift
@Test
func test() async throws {
  with {                        // outer handler
    Print { _ in } // no-op stub
  } perform: {
    try await withTestHandler { // outer handler
      echo()                                                  
    } test: { effect in                                         
		try await effect.expect(\.Console.readLine, return: "Hello")
		try await effect.expect(\.Console.print) { #expect($0 == "Hello") }
		try await effect.expect(\.Console.readLine, return: "Hi")
		try await effect.yield() // opt-out by yielding to the next handler (no-op Print)
		try await effect.expect(\.Console.readLine, return: "Good Bye")
		try await effect.yield() // opt-out by yielding to the next handler (no-op Print)
		try await effect.expect(\.Console.readLine, return: nil)
    }
  }
}
```

In this arrangement, all effects are first caught by the `TestHandler`, but it can choose yield some effects to the next handler by calling `try await effect.yield()`. The outer handler can be a traditional mock that provides some "default" and reusable test behaviour. As you can see, the **Minimal but General** design principle of **Swift Effect** allows us to reproduce traditional workflows like DI+Test Doubles when we need them.


## Async Streams and Effects

**Swift Effect** naturally fits asynchronous programming and provides a strong model for treating `AsyncStream` and `AsyncSequence` as controllable effects in test environment.

Let's define an Effect that returns an async stream of random numbers, one number per second:

```swift
enum Random {
  @Effect
  static func numbers(in range: ClosedRange<Int>) -> any AsyncSequence<Int, any Error> {
    AsyncThrowingStream {
      try await Task.sleep(for: .seconds(1))
	  return Int.random(in: range)
    }
  }
}
```

Let's create a View and View Model that consume this stream and update observable state in response to new numbers:

```swift
struct RandomNumberView: View {
  let viewModel: RandomNumberViewModel
  var body: some View {
    Text(viewModel.message)
      .task {
        await viewModel.getRandomNumbers()
      }
  }
}

@MainActor
@Observable
class RandomNumberViewModel {
  private var previousNumber: Int?
  var message: String = ""
  
  func getRandomNumbers() async {
    do {
      for try await number in Random.numbers(in: 0...100) {
        if previousNumber == number {
          message = "It's the same number again, boooring!!"
        } else if number.isMultiple(of: 2) {
          message = "\(number) is a good number"
        } else {
          message = "\(number) is a bad number"
        }
        previousNumber = number
      }
      message = "Good bye!"
    } catch {
      message = "Bad error"
    }
  }
}
```

Again, this deceptively simple ViewModel can be awkward to test with traditional DI approaches, often requiring carefully crafted mocks to exercise different asynchronous sequences. With **Swift Effect**, testing `AsyncStream`s and `AsyncSequence`s is straightforward.

Semantically, an Effect that produces an `AsyncSequence` of elements is equivalent to an `AsyncSequence` of effects that each produce a single element. This is exactly how such effects are handled and tested:

```swift
@MainActor
@Test
func test() async throws {
	let viewModel = RandomNumberViewModel()
	
	try await withTestHandler {
	  await viewModel.getRandomNumbers()
	} test: { effect in
	  try await effect.expect(\.Random.numbers) { range in
		#expect(range == (0...100))
		return 1
	  }
	  await #expect(viewModel.message == "1 is a bad number")
	  try await effect.expect(\.Random.numbers) { _ in 2 }
	  await #expect(viewModel.message == "2 is a good number")
	  try await effect.expect(\.Random.numbers) { _ in 3 }
	  await #expect(viewModel.message == "3 is a bad number")
	  try await effect.expect(\.Random.numbers) { _ in 3 }
	  await #expect(viewModel.message == "It's the same number again, boooring!!")
	  try await effect.expect(\.Random.numbers) { _ in nil } //end of stream
	  await #expect(viewModel.message == "Good Bye!")
	}
}
```

As easily, we can throw an error from the stream to exercise the corresponding view state:

```swift
@MainActor
@Test
func testError() async throws {
	try await withTestHandler {
	  await viewModel.getRandomNumbers()
	} test: { effect in
      ...
	  try await effect.expect(\.Random.numbers) { throw SomeError() }
	  await #expect(viewModel.message == "Bad error")
	}
}
```

## Deterministic testing of Unstructured Concurrency

**Swift Effect** provides a built-in `Task.effect` that acts as a drop-in replacement for `Task`. In production, this effect simply returns a normal `Task`, leaving runtime behaviour unchanged. In tests, however, it allows the `TestHandler` to take control of task scheduling in a fully deterministic way.

Consider this program:

```swift
func program() {
  Console.print("Start")
  Task(name: "Task 1") {
    Console.print("Task 1")
  }
  Task(name: "Task 2") {
    Console.print("Task 2")
  }
  Console.print("Exit")
}
```

If we run `program()` multiple times, the order of the print statements will be non-deterministic because Task 1 and Task 2 run concurrently and may be scheduled in any order, even if they are isolated to the same actor.

```swift
> program()
Start
Task 2
Task 1
Exit
> program()
Start
Task 1
Task 2
Exit
```

Let's now update the program to use `Task.effect`:

```swift
func program() {
  Console.print("Start")
  Task.effect(name: "Task 1") {
    Console.print("Task 1")
  }
  Task.effect(name: "Task 2") {
    Console.print("Task 2")
  }
  Console.print("Exit")
}
```

This won't change the runtime behaviour of production code, but in the test we can gain control over task scheduling:

```swift
@Test
func enqueueInOrder() async throws {
  try await withTestHandler {
    program()                                                            // 1 | Queue: [program]
  } test: { effect in
	try await effect.expect(\.Console.print) { #expect($0 == "Start") }  // 2
	try await effect.expectTask("Task 1", action: .enqueue)              // 3 | Queue: [program, Task 1]
	try await effect.expectTask("Task 2", action: .enqueue)              // 4 | Queue: [program, Task 1, Task 2]
	try await effect.expect(\.Console.print) { #expect($0 == "Exit") }   // 5 | Queue: [program, Task 1, Task 2]
	try await effect.expect(\.Console.print) { #expect($0 == "Task 1") } // 6 | Queue: [Task 1, Task 2]
	try await effect.expect(\.Console.print) { #expect($0 == "Task 2") } // 7 | Queue: [Task 2]
  }
}
```

1. `program()` is added to the serial test execution queue.
2. The first `print("Start")` is handled normally.
3. The test is suspended, awaiting the `Task` effect produced by the program via the `expectTask` expectation. When the program creates Task 1, the effect is intercepted and handled by the test with the `.enqueue` action, which appends the task to the end of the serial execution queue, after `program()`.
4. The same happens with Task 2, which is appended after Task 1.
5. The second `print("End")` is handled normally, `program()` exits its scope, and is popped from the execution queue.
6. Task 1 is executed, performing `print("Task 1")`, which is expected by the test. Task 1 exits its scope and is popped from the execution queue.
7. Task 2 is executed, performing `print("Task 2")`, which is expected by the test. Task 2 exits its scope and is popped from the execution queue.

Let's write another test where the order of these tasks is swapped:

```swift
@Test
func enqueueInOrder() async throws {
  try await withTestHandler {
    program()                                                            //   | Queue: [program]
  } test: { effect in
	try await effect.expect(\.Console.print) { #expect($0 == "Start") }  
	let task1 = try await effect.expectTask("Task 1", action: .suspend)  // 1 | Queue: [program]
	let task2 = try await effect.expectTask("Task 2", action: .suspend)  //   | Queue: [program]                
	task2.enqueue                                                        // 2 | Queue: [program, Task 2]
	task1.enqueue                                                        //   | Queue: [program, Task 2, Task 1]     
	try await effect.expect(\.Console.print) { #expect($0 == "Exit") }   //   | Queue: [program, Task 2, Task 1]     
	try await effect.expect(\.Console.print) { #expect($0 == "Task 2") } // 3 | Queue: [Task 2, Task 1]
	try await effect.expect(\.Console.print) { #expect($0 == "Task 1") } //   | Queue: [Task 1]     
  }
}
```

1. In this test, when we intercept `Task` effects, we handle them with the `.suspend` action and store them in variables.
2. We then explicitly enqueue `task2` first and `task1` second, swapping their order in the execution queue:
   `Execution Queue: [program, Task 2, Task 1]`
3. When the tasks are executed, we expect the corresponding `print` effects to arrive in the order `"Task 2"` and then `"Task 1"`.

`withTestHandler` provides a `taskHandling` argument that can be set to `.automaticallyEnqueue`, which enqueues tasks onto the serial queue in order of creation without requiring the `test` block to intercept them. Effectively, this flattens arbitrarily nested task hierarchies into a single serial queue:

```swift
@Test
func nestedTasks() async throws {
  try await withTestHandler(taskHandling: .automaticallyEnqueue) {
    Task.effect(name: "Task 1") {
      Console.writeLine("Task 1")
      Task.effect(name: "Task 3") {
        Console.writeLine("Task 3")
      }
    }
    Task.effect(name: "Task 2") {
      Console.writeLine("Task 2")
      Task.effect(name: "Task 4") {
        Console.writeLine("Task 4")
      }
    }
  } test: { effect in
    try await effect.expect(\.Console.writeLine) { #expect($0 == "task 1") }
    try await effect.expect(\.Console.writeLine) { #expect($0 == "task 2") }
    try await effect.expect(\.Console.writeLine) { #expect($0 == "task 3") }
    try await effect.expect(\.Console.writeLine) { #expect($0 == "task 4") }
  }
}
```

You can use `taskHandling: .suspend` to intercept every produced task and schedule them explicitly in whatever order you need. This does not violate the Swift Concurrency runtime rules because tasks can only be scheduled after they have been created and intercepted by the test handler. For example, you cannot schedule Task 4 before Task 2 because Task 2 is Task 4’s parent. However, you *can* exercise different orderings of unrelated tasks, which is both possible and expected in a production environment.

## Effect Scopes

**Swift Effect** uses `TaskLocal`s to install Effect Handlers for the scope they wrap. This means that if we create an instance of a program like this:

```swift
struct Program {
  func run() {
    Console.print("Hello")
  }
}
```

...and then pass the `program` instance into different scopes, the behaviour of each `program.run()` call will depend on the effect handlers installed in the calling scopes.


```swift
func main() {
  let program = Program()
	
  with {
    Print { Console.print($0.uppercased()) }
  } perform: {
    program.run() // in scope with custom Print
  }

  program.run()  // in global scope
}
main()
> HELLO
> Hello
```

But sometimes we may want to pass around program instances with certain handlers “baked in”. We can do this in two ways:

1. Using simple function composition, by capturing the program and the handler in a reusable closure:

```swift
func main() {
  let program = Program()
  let run = {
    with {
      Print { Console.print($0.uppercased()) }
    } perform: {
      program.run()
    }
  }

  run() // uppercased Print is baked-in, global handler won't see print effects
  with {
    Print { Console.print($0.lowercased()) }
  } perform: {
    run() // still handled by the uppercased Print because it's inner-most, the outer lowercased Print has no effect here.
  }
}
main()
> HELLO
> HELLO
```

2. By using the `@EffectScope` macro to make all methods defined within the `Program` type capture the currently installed effect handlers at initialisation time:

```swift
@EffectScope
struct Program {
  func run() {
    Console.print("Hello")
  }
}

func main() {
  let program = with {
    Print { Console.print($0.uppercased()) }
  } perform: {
    Program()
  }
  program.run()
  program.run()
}
main()
> HELLO
> HELLO
```

With this mechanims, we can reproduce traditional Dependency Injection patterns. This is another example of how the **Minimal but General** design of effects and effect handlers enables complex abstractions and workflows to be built from simple, composable primitives.

## More Examples

You can find additional examples inside [EffectPlaygound](https://github.com/Alex-Ozun/swift-effect/tree/main/EffectPlayground)

## FAQ
### 1. How is programming with Effects different from Dependency Injection?

While there are many similarities between Effects/Effect Handlers and traditional Dependency Injection,
the differences between them have a profound effect (pun intended) on the way we model, structure, and reason about our programs.

**Where the abstraction lives**

**DI**: Abstractions live at the object and type level. You pass around concrete objects (e.g. `APIService`) within your code. Your programs directly call methods on these objects and interact with their state. While injected objects usually sit behind an interface (e.g. a protocol or a struct with closures), these object-/type-level abstractions often leak implementation details by strongly implying specific expected behavior. Such interfaces often serve merely as test-only scaffolding to allow injection of mocks, which themselves tend to become over-specified in order to satisfy the implied behaviour. This, of course, is not an inherent issue with DI, and with sufficient engineering discipline, traditional DI can avoid all these problems.

**Effects**: Abstractions live at the operation level. Programs are built around abstract operations such as `Console.print`, `Logging.log`, `HTTP.data(for: url)`, `UI.fontSize`, etc. While these operations are namespaced by the domains they belong to, there is no implied behaviour or stateful relationship between individual operations unless such relationships are expressed explicitly via shared input/output data, for example `AudioRecording.start(fileURL: fileURL); AudioRecording.stop(fileURL: fileURL)`.
At this more granular level of abstraction, programmers are incentivised to model behaviour more generically, with operations and their relationships expressed explicitly through data flow. This leads to more procedural, portable, and composable code that can be recombined under different Effect Handler interpretations.

**Composability**:

**DI:** Mixing and customising the behaviour of multiple objects, types, or services often requires creating bespoke object hierarchies. For example, extending `APIService` with custom caching behaviour typically involves introducing a higher-level coordinator such as `CachedAPIService`, which combines the behaviour of wrapped services in an ad hoc manner.

**Effects**: Multiple effect handlers for the same effect can be installed on the same call stack and can extend each other in a generic way, without the need for direct coordination. For example, extending the `HTTP.data(for: URL)` effect with custom caching behaviour can be achieved by installing multiple independent HTTP effect handlers, each intercepting and augmenting the operation as needed.

```swift
func main() {
  with {
    HTTP.Data { url in
      ... URL session
    }
  } perform: {
    module()
  }
}
func module() {
  let localCache = ...
  with {
    HTTP.Data { url in
      if let data = localCache(url) {
        return data // return cached data immediately
      } else {
        let data = await HTTP.data(for: url) // yield to next handler
        localCache.set(data, url) // update cache
        return data
      }
    }
  } perform: {
    program()
  }
}
func program() {
  let data = await HTTP.data(for: url)
}
```
In this example, neither the program nor any of the effect handlers are aware of each other’s existence, and any handler can be added or removed at will, thereby changing the caching policy without modifying any other part of the program.

**Testing**:

**DI**: You define and configure test doubles, such as mocks and stubs, ahead of time and inject them into the system under test in order to exercise logic in isolation from concrete dependency implementations.

**Effects**: You directly intercept, inspect, and resume individual observable **effectful** operations as they are performed by the system under test, exercising logic by interpreting that behaviour in the context of a given step within the test.

### 2. Aren’t effects just global functions? Aren’t globals bad?
Yes and no. Effects are indeed modelled as global functions, but they are **namespaced**, **scoped**, **thread-safe**, and **dynamically bound** global functions.

**Namespaced**

All effects are namespaced by the domain they belong to. This minimises name collisions with other global systems, particularly system-provided ones.

**Scoped**

Each effect’s behaviour is scoped to the effect handlers installed in the call-stack hierarchy at the point where the effect is performed.

**Thread-safe**

Effect handler scopes are thread-safe and cannot escape into unrelated execution contexts. This invariant is guaranteed by the underlying TaskLocal mechanism to which effect handlers are bound.

**Dynamically bound**

When an effect is performed, its behaviour is resolved dynamically at runtime by matching it to the nearest applicable effect handler in the thread-safe scope stack.
Together, these mechanisms eliminate most of the problems traditionally associated with globals, such as implicit shared mutable state, lack of composability, and inability to customise or extend behaviour safely.

It is still possible to violate these invariants by using unsafe global state behind effect implementations. However, this is a universal risk in impure programming and applies equally to dependency injection, effects, or any other architectural pattern in an inherently impure language such as Swift.

## Similar projects
- [Probing](https://github.com/NSFatalError/Probing) is a cool library with similar goals that provides "programmable breakpoints" that enable powerful testing of complex Swift Concurrency workflows and stateful programs.
- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) While more focused on traditional dependency injection approaches, this library makes heavy use of `TaskLocal`s for installing dependencies into scopes, which makes it closely related to this project—and indeed a significant source of inspiration.
- [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) The most widely adopted architectural framework that ships with a first-class effect system out of the box. While incredibly powerful for effect control and testing, it unfortunately requires a fundamental restructuring of otherwise “normal” procedural programs into a unidirectional data-flow model. Which is one of the key problems this project aims to solve.

### Author

This project was created and is maintained by Alex Ozun

- About & Contacts: https://swiftology.io/about/
- Blog: https://swiftology.io
- Talks: https://swiftology.io/videos/
