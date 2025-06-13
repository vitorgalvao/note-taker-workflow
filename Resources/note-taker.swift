import Foundation

// Helpers
struct ScriptFilter: Codable {
  let items: [Item]

  struct Item: Codable {
    let title: String
    let subtitle: String
    let type: String
    let icon: Icon
    let arg: String

    struct Icon: Codable {
      let path: String
      let type: String
    }

    init(_ fileString: String) {
      let fileURL: URL = URL(filePath: fileString)
      let fileName: String = fileURL.lastPathComponent

      self.title = fileName
      self.subtitle = (fileString as NSString).abbreviatingWithTildeInPath
      self.type = "file:skipcheck"
      self.arg = fileString
      self.icon = Icon(path: fileString, type: "fileicon")
    }
  }
}

// Main
let notesDir = ProcessInfo.processInfo.environment["notes_dir"] ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].absoluteString
let wordComparator = ProcessInfo.processInfo.environment["word_comparator"] ?? "==[cd]"
let fileOrder = "kMDItemContentModificationDate"
let fileTypePredicate = NSPredicate(format: "kMDItemContentTypeTree == 'public.plain-text'")

// Prepare query
let query = NSMetadataQuery()
query.searchScopes = [notesDir]
query.sortDescriptors = [NSSortDescriptor(key: fileOrder, ascending: false)]

// If there is an argument, search all words in the title or contents
// Otherwise list every file
if let searchString = CommandLine.arguments.dropFirst().first {
  let searchWords =
    searchString
    .components(separatedBy: .whitespacesAndNewlines)
    .filter { !$0.isEmpty }
    .map { NSPredicate(format: "kMDItemDisplayName \(wordComparator) %@ OR kMDItemTextContent \(wordComparator) %@", $0, $0) }

  query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fileTypePredicate] + searchWords)
} else {
  query.predicate = fileTypePredicate
}

// Run query
query.enableUpdates()
query.start()

// On query end
let notificationCenter = NotificationCenter.default
let observer = notificationCenter.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { _ in
  // Stop query
  query.stop()
  notificationCenter.removeObserver(observer)

  // Prepare results
  let results = query.results as? [NSMetadataItem] ?? []

  let sfItems: [ScriptFilter.Item] = results.compactMap {
    guard let resultPath = $0.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
    return ScriptFilter.Item(resultPath)
  }

  // No results
  guard !sfItems.isEmpty else {
    print("{\"items\":[{\"title\":\"No Results\",\"valid\":false}]}")
    exit(0)
  }

  // Output JSON
  let jsonData = try! JSONEncoder().encode(["items": sfItems])
  print(String(data: jsonData, encoding: .utf8)!)

  exit(0)
}

RunLoop.main.run()
