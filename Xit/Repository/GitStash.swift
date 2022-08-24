import Cocoa

public protocol Stash: AnyObject
{
  var message: String? { get }
  var mainCommit: (any Commit)? { get }
  var indexCommit: (any Commit)? { get }
  var untrackedCommit: (any Commit)? { get }
  
  func indexChanges() -> [FileChange]
  func workspaceChanges() -> [FileChange]
  func stagedDiffForFile(_ path: String) -> PatchMaker.PatchResult?
  func unstagedDiffForFile(_ path: String) -> PatchMaker.PatchResult?
}

/// Wraps a stash to preset a unified list of file changes.
public final class GitStash: Stash
{
  typealias Repo = CommitStorage & FileContents & FileStatusDetection & Stashing
  
  unowned var repo: any Repo
  public var message: String?
  public var mainCommit: (any Commit)?
  public var indexCommit, untrackedCommit: (any Commit)?
  private var cachedIndexChanges, cachedWorkspaceChanges: [FileChange]?

  init(repo: any Repo, index: UInt, message: String?)
  {
    self.repo = repo
    self.message = message
    
    if let mainCommit = repo.commitForStash(at: index) {
      self.mainCommit = mainCommit
      if mainCommit.parentOIDs.count > 1 {
        self.indexCommit = repo.commit(forOID: mainCommit.parentOIDs[1])
        if mainCommit.parentOIDs.count > 2 {
          self.untrackedCommit = repo.commit(forOID: mainCommit.parentOIDs[2])
        }
      }
    }
  }

  public func indexChanges() -> [FileChange]
  {
    if let changes = cachedIndexChanges {
      return changes
    }
    
    let changes = indexCommit.map { repo.changes(for: $0.id, parent: nil) } ?? []
    
    cachedIndexChanges = changes
    return changes
  }
  
  public func workspaceChanges() -> [FileChange]
  {
    if let changes = cachedWorkspaceChanges {
      return changes
    }
    
    guard let mainCommit = self.mainCommit
    else { return [] }
    var changes = repo.changes(for: mainCommit.id, parent: indexCommit?.id)
    
    if let untrackedCommit = self.untrackedCommit {
      let untrackedChanges = repo.changes(for: untrackedCommit.id, parent: nil)
      
      changes.append(contentsOf: untrackedChanges)
    }
    
    changes.sort { $0.path.compare($1.path) == .orderedAscending }
    self.cachedWorkspaceChanges = changes
    return changes
  }

  func headBlobForPath(_ path: String) -> (any Blob)?
  {
    guard let mainCommit = self.mainCommit as? GitCommit,
          let parentOID = mainCommit.parentOIDs.first,
          let parent = GitCommit(oid: parentOID,
                                 repository: mainCommit.repository),
          let headEntry = parent.tree?.entry(path: path)
    else { return nil }
    
    return headEntry.object as? Blob
  }

  public func stagedDiffForFile(_ path: String) -> PatchMaker.PatchResult?
  {
    guard let indexCommit = self.indexCommit as? GitCommit
    else { return nil }
    guard repo.isTextFile(path, context: .commit(indexCommit))
    else { return .binary }
    guard let indexEntry = indexCommit.tree?.entry(path: path),
          let indexBlob = indexEntry.object as? Blob
    else { return nil }
    let headBlob = self.headBlobForPath(path)
    
    return .diff(PatchMaker(from: PatchMaker.SourceType(headBlob),
                             to: PatchMaker.SourceType(indexBlob),
                             path: path))
  }

  public func unstagedDiffForFile(_ path: String) -> PatchMaker.PatchResult?
  {
    guard let indexCommit = self.indexCommit as? GitCommit
    else { return nil }

    var indexBlob: (any Blob)?
    
    if let indexEntry = indexCommit.tree!.entry(path: path) {
      if !repo.isTextFile(path, context: .commit(indexCommit)) {
        return .binary
      }
      indexBlob = indexEntry.object as? Blob
    }
    
    if let untrackedCommit = self.untrackedCommit as? GitCommit,
       let untrackedEntry = untrackedCommit.tree?.entry(path: path) {
      if !repo.isTextFile(path, context: .commit(untrackedCommit)) {
        return .binary
      }
      guard let untrackedBlob = untrackedEntry.object as? Blob
      else { return nil }
      
      return .diff(PatchMaker(from: PatchMaker.SourceType(indexBlob),
                               to: PatchMaker.SourceType(untrackedBlob),
                               path: path))
    }
    if let mainCommit = self.mainCommit,
       let unstagedEntry = mainCommit.tree?.entry(path: path) {
      guard let unstagedBlob = unstagedEntry.object as? Blob
      else { return nil }
      
      return .diff(PatchMaker(from: PatchMaker.SourceType(indexBlob),
                               to: PatchMaker.SourceType(unstagedBlob),
                               path: path))
    }
    return nil
  }
}
