import Effect
import Foundation

func fetchRandomNumber() async throws {
  let data = try await HTTP.data(
    from: URL(string: "https://www.randomnumberapi.com/api/v1.0/random?min=1&max=7")!
  )
  let numbers = try JSONDecoder().decode([Int].self, from: data)
  guard let number = numbers.first else {
    Console.writeLine("received no numbers :(")
    return
  }
  if number == 7 {
    Console.writeLine("received a lucky number!")
  } else {
    Console.writeLine("received \(number)")
  }
}

enum FetchRandomNumber {
  static func main() async throws {
    try await with(DataFromURL.diskCache) {
      try await module()
    }
  }
}

func module() async throws {
  try await with(DataFromURL.inMemoryCache) {
    try await fetchRandomNumber() // program
  }
}

typealias DataFromURL = HTTP.DataFromURL

extension DataFromURL {
  static let inMemoryCache = DataFromURL { url in
    if let data = await InMemoryCache.shared.cache[url] {
      Console.writeLine("DataFromURL (In Memory Cache): cache hit")
      return data
    } else {
      Console.writeLine("DataFromURL (In Memory Cache): cache miss, passing up to the next handler")
      let data = try await HTTP.data(from: url)
      Console.writeLine("DataFromURL (In Memory Cache): warming cache")
      await InMemoryCache.shared.set(data, for: url)
      return data
    }
  }
  static let diskCache = DataFromURL { url in
    if let data = try await DiskCache.shared.read(url: url) {
      Console.writeLine("DataFromURL (Disk Cache): cache hit")
      return data
    } else {
      Console.writeLine("DataFromURL (Disk Cache): cache miss, passing up to the next handler")
      let data = try await HTTP.data(from: url)
      Console.writeLine("DataFromURL (Disk Cache): warming cache")
      await DiskCache.shared.write(data, for: url)
      return data
    }
  }
}

actor InMemoryCache {
  static let shared = InMemoryCache()
  var cache: [URL:Data] = [:]
  
  func set(_ data: Data, for url: URL) {
    cache[url] = data
  }
}

actor DiskCache {
  static let shared = DiskCache()
  var cache: [URL:Data] = [:] // pretend it's a db file
  
  func read(url: URL) async throws -> Data? {
    try await Task.sleep(for: .seconds(1))
    return cache[url]
  }
  func write(_ data: Data, for url: URL) {
    cache[url] = data
  }
}
