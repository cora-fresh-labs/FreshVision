import Foundation

struct ImageStore: Sendable {
  private let directory: URL
  init() throws {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    directory = base.appending(path: "FreshVisionScans", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  func save(_ data: Data, id: UUID) throws -> String {
    let name = "\(id.uuidString.lowercased()).jpg"
    try data.write(to: directory.appending(path: name), options: .atomic)
    return name
  }
  func data(for name: String) throws -> Data {
    try Data(contentsOf: directory.appending(path: name))
  }
  func url(for name: String) -> URL { directory.appending(path: name) }
}
