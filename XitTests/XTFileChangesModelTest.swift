import XCTest
@testable import Xit

class XTFileChangesModelTest: XTTest
{  
  func data(for string: String) -> Data
  {
    return (string as NSString).data(using: String.Encoding.utf8.rawValue)!
  }
  
  func string(from data: Data) -> String
  {
    return NSString(data: data, encoding: String.Encoding.utf8.rawValue)! as String
  }
  
  func testCommit()
  {
    guard let headSHA = repository.headSHA,
          let headCommit = GitCommit(sha: headSHA,
                                     repository: repository.gitRepo)
    else {
      XCTFail("no head")
      return
    }
    let model = CommitSelection(repository: repository, commit: headCommit)
    let changes = model.fileList.changes
    
    XCTAssertEqual(changes.count, 1)
    
    let change = changes[0]
    
    XCTAssertEqual(change.path, TestFileName.file1.rawValue)
    XCTAssertEqual(change.status, DeltaStatus.added)
    
    let data = model.fileList.dataForFile(TestFileName.file1.rawValue)
    
    XCTAssertEqual(data, self.data(for:"some text"))
    
    guard let diffResult = model.fileList.diffForFile(TestFileName.file1.rawValue),
          let patch = diffResult.extractPatch()
    else {
      XCTFail()
      return
    }
    
    XCTAssertEqual(patch.addedLinesCount, 1)
  }
  
  func checkPatchLines(
      _ model: RepositorySelection, path: TestFileName, staged: Bool,
      added: Int, deleted: Int)
  {
    guard let diffResult = model.list(staged: staged).diffForFile(path.rawValue),
          let patch = diffResult.extractPatch()
    else {
      XCTFail()
      return
    }
    
    XCTAssertEqual(patch.addedLinesCount, added,
                   String(format: "%@%@", staged ? ">" : "<", path.rawValue))
    XCTAssertEqual(patch.deletedLinesCount, deleted,
                   String(format: "%@%@", staged ? ">" : "<", path.rawValue))
  }
  
  func testStash() throws
  {
    try makeStash()
    
    let model = StashSelection(repository: repository, index: 0)
    
    XCTAssertEqual(model.oidToSelect?.sha, repository.headSHA)
    
    let changes = model.fileList.changes
    let unstagedChanges = model.unstagedFileList.changes
    
    XCTAssertEqual(changes.count, 1)
    XCTAssertEqual(unstagedChanges.count, 2)
    
    let addedContent =
      self.string(from: model.fileList.dataForFile(TestFileName.added.rawValue)!)
    let untrackedContent =
      self.string(from: model.unstagedFileList.dataForFile(TestFileName.untracked.rawValue)!)
    let file1Unstaged =
      self.string(from: model.unstagedFileList.dataForFile(TestFileName.file1.rawValue)!)
    let file1Staged =
      self.string(from: model.fileList.dataForFile(TestFileName.file1.rawValue)!)
    
    XCTAssertEqual(addedContent, "add")
    XCTAssertEqual(untrackedContent, "new")
    XCTAssertEqual(file1Unstaged, "stashy")
    XCTAssertEqual(file1Staged, "some text")
    XCTAssertNil(model.fileList.dataForFile(TestFileName.untracked.rawValue))
    
    checkPatchLines(model, path: .added, staged: true, added: 1, deleted: 0)
    checkPatchLines(model, path: .added, staged: false, added: 0, deleted: 0)
    checkPatchLines(model, path: .untracked, staged: false, added: 1, deleted: 0)
    checkPatchLines(model, path: .file1, staged: false, added: 1, deleted: 1)
    checkPatchLines(model, path: .file1, staged: true, added: 0, deleted: 0)
    XCTAssertNil(model.fileList.diffForFile(TestFileName.untracked.rawValue))
  }
  
  func testStaging() throws
  {
    let model = StagingSelection(repository: repository)
    var changes = model.unstagedFileList.changes
    
    XCTAssertEqual(changes.count, 0)

    try execute(in: repository) {
      Write("change", to: .file1)
    }
    repository.invalidateIndex()
    changes = model.unstagedFileList.changes
    XCTAssertEqual(changes.count, 1)
    
    guard !changes.isEmpty
    else {
      XCTFail("empty changes")
      return
    }
    var change = changes[0]
    
    XCTAssertEqual(change.path, TestFileName.file1.rawValue)
    XCTAssertEqual(change.status, DeltaStatus.modified)

    try execute(in: repository) {
      Write("new", to: .added)
    }
    repository.invalidateIndex()
    changes = model.unstagedFileList.changes
    XCTAssertEqual(changes.count, 2)
    guard !changes.isEmpty
    else {
      XCTFail("empty changes")
      return
    }
    change = changes[0] // "added" will be sorted to the top
    XCTAssertEqual(change.path, TestFileName.added.rawValue)
    XCTAssertEqual(change.status, DeltaStatus.untracked)

    try execute(in: repository) {
      Stage(.added)
    }
    XCTAssertEqual(model.unstagedFileList.changes.count, 1)
    changes = model.fileList.changes
    XCTAssertEqual(changes.count, 1)
    guard !changes.isEmpty
    else {
      XCTFail("empty changes")
      return
    }
    change = changes[0]
    XCTAssertEqual(change.path, TestFileName.added.rawValue)
    XCTAssertEqual(change.status, DeltaStatus.added)
  }
  
  func testStagingTreeSimple()
  {
    let model = StagingSelection(repository: repository)
    let tree = model.fileList.treeRoot(oldTree: nil)
    guard let children = tree.children
    else {
      XCTFail("no children")
      return
    }
    
    XCTAssertEqual(children.count, 1)
    
    let change = children[0].representedObject as! FileChange
    
    XCTAssertEqual(change.status, DeltaStatus.unmodified)
  }
  
  func testCommitTree() throws
  {
    try execute(in: repository) {
      CommitFiles {
        Write("new", to: .added)
      }
    }

    guard let headSHA = repository.headSHA,
          let headCommit = GitCommit(sha: headSHA, repository: repository.gitRepo)
    else {
      XCTFail("no head")
      return
    }
    let model = CommitSelection(repository: repository,
                              commit: headCommit)
    let tree = model.fileList.treeRoot(oldTree: nil)
    let children = try XCTUnwrap(tree.children)
    
    XCTAssertEqual(children.count, 2)
    
    var change = children[0].representedObject as! FileChange
    
    XCTAssertEqual(change.path, TestFileName.added.rawValue)
    XCTAssertEqual(change.status, DeltaStatus.added)
    
    change = children[1].representedObject as! FileChange
    XCTAssertEqual(change.path, TestFileName.file1.rawValue)
    XCTAssertEqual(change.status, DeltaStatus.unmodified)
  }
  
  func testStashTree() throws
  {
    try execute(in: repository, actions: { () -> [any RepoAction] in
      CommitFiles {
        Write("bye!", to: .deleted)
      }
      Delete(.deleted)
      Stage(.deleted)
    })

    try makeStash()
    
    let model = StashSelection(repository: repository, index: 0)
    let tree = model.fileList.treeRoot(oldTree: nil)
    let children = try XCTUnwrap(tree.children)
    
    XCTAssertEqual(children.count, 3)
    
    typealias ExpectedItem = (name: TestFileName, change: DeltaStatus)
    let expectedItems: [ExpectedItem] = [(name: .added, change: .added),
                                         (name: .deleted, change: .deleted),
                                         (name: .file1, change: .unmodified)]
    
    for pair in zip(children, expectedItems) {
      guard let item = pair.0.representedObject as? FileChange
      else {
        XCTFail("wrong object type")
        continue
      }
      
      XCTAssertEqual(item.path, pair.1.name.rawValue)
      XCTAssertEqual(item.status, pair.1.change)
    }
    
    let unstagedTree = model.unstagedFileList.treeRoot(oldTree: nil)
    guard let unstagedChildren = unstagedTree.children,
          unstagedChildren.count == 4,
          let item = unstagedChildren[3].representedObject as? FileChange
    else {
      XCTFail("no children or wrong count")
      return
    }

    XCTAssertEqual(item.path, TestFileName.untracked.rawValue)
    XCTAssertEqual(item.status, .untracked)
  }
}
