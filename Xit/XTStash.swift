import Cocoa

/// Wraps a stash to preset a unified list of file changes.
public class XTStash: NSObject
{
  unowned var repo: XTRepository
  var message: String?
  var mainCommit: XTCommit?
  var indexCommit, untrackedCommit: XTCommit?
  private var cachedChanges: [FileChange]?

  init(repo: XTRepository, index: UInt, message: String?)
  {
    self.repo = repo
    self.message = message
    
    if let mainCommit = repo.commitForStash(at: index) {
      self.mainCommit = mainCommit
      if mainCommit.parentOIDs.count > 1 {
        self.indexCommit = XTCommit(oid: mainCommit.parentOIDs[1],
                                    repository: repo)
        if mainCommit.parentOIDs.count > 2 {
          self.untrackedCommit = XTCommit(oid: mainCommit.parentOIDs[2],
                                          repository: repo)
        }
      }
    }
  }

  func changes() -> [FileChange]
  {
    if let changes = cachedChanges {
      return changes
    }
    
    guard var unstagedChanges = mainCommit?.sha.map({
        repo.changes(for: $0, parent: indexCommit?.oid) })
    else { return [] }
    let stagedChanges = indexCommit.map { repo.changes(for: $0.sha!,
                                                       parent: nil) }
                        ?? []
    
    if let untrackedCommit = self.untrackedCommit {
      let untrackedChanges = repo.changes(for: untrackedCommit.sha!, parent: nil)
      
      unstagedChanges.append(contentsOf: untrackedChanges)
    }
    // Unstaged statuses aren't set because these are coming out of commits,
    // so they all have to be switched.
    for unstaged in unstagedChanges {
      unstaged.unstagedChange = unstaged.change
      unstaged.change = .unmodified
    }
    
    let unstagedPaths = unstagedChanges.map({ $0.path })
    var unstagedDict = [String: FileChange]()
    
    // Apparently the closest thing to dictionaryWithObjects:forKeys:
    for (path, fileChange) in zip(unstagedPaths, unstagedChanges) {
      unstagedDict[path] = fileChange
    }
    
    for staged in stagedChanges {
      if let change = unstagedDict[staged.path] {
        change.change = staged.change
      }
      else {
        unstagedDict[staged.path] = staged
      }
    }
    
    var changes = [FileChange](unstagedDict.values)
    
    changes.sort { $0.path.compare($1.path) == .orderedAscending }
    self.cachedChanges = changes
    return changes
  }

  func headBlobForPath(_ path: String) -> Blob?
  {
    guard let headEntry = try? mainCommit?.gtCommit.parents[0].tree?
                               .entry(withPath: path),
          let objectWrapped = try? headEntry?.gtObject(),
          let object = objectWrapped
    else { return nil }
    
    return object as? GTBlob
  }

  func stagedDiffForFile(_ path: String) -> XTDiffMaker?
  {
    guard let indexCommit = self.indexCommit,
          let indexEntry = try? indexCommit.tree?.entry(withPath: path),
          let indexBlob = try? indexEntry!.gtObject() as? GTBlob
    else { return nil }
    let headBlob = self.headBlobForPath(path)
    
    return XTDiffMaker(from: XTDiffMaker.SourceType(headBlob),
                       to: XTDiffMaker.SourceType(indexBlob),
                       path: path)
  }

  func unstagedDiffForFile(_ path: String) -> XTDiffMaker?
  {
    guard let indexCommit = self.indexCommit
    else { return nil }

    var indexBlob: GTBlob? = nil
    
    if let indexEntry = try? indexCommit.tree!.entry(withPath: path) {
      let object = try? indexEntry.gtObject()
      
      indexBlob = object as? GTBlob
    }
    
    if let untrackedCommit = self.untrackedCommit,
       let untrackedEntry = try? untrackedCommit.tree?.entry(withPath: path) {
      guard let untrackedBlob = try? untrackedEntry!.gtObject() as? GTBlob
      else { return nil }
      
      return XTDiffMaker(from: XTDiffMaker.SourceType(indexBlob),
                         to: XTDiffMaker.SourceType(untrackedBlob),
                         path: path)
    }
    if let unstagedEntry = try? self.mainCommit?.tree?.entry(withPath: path) {
      guard let unstagedBlob = try? unstagedEntry?.gtObject() as? GTBlob
      else { return nil }
      
      return XTDiffMaker(from: XTDiffMaker.SourceType(indexBlob),
                         to: XTDiffMaker.SourceType(unstagedBlob),
                         path: path)
    }
    return nil
  }
}
