import Foundation
import SwiftUI

final class CheckOutRemoteOpController: OperationController
{
  let remoteName: String
  let remoteBranch: String
  
  init(windowController: XTWindowController, remote: String, branch: String)
  {
    self.remoteName = remote
    self.remoteBranch = branch
    
    super.init(windowController: windowController)
  }
  
  override func start() throws
  {
    guard let window = windowController?.window
    else { throw RepoError.unexpected }
    let model = CheckOutRemotePanel.Model()
    let panel = CheckOutRemotePanel(
      model: model,
      originBranch: remoteBranch,
      validateBranch: validateBranch(_:),
      cancelAction: {
        window.endSheet(window, returnCode: .OK)
      },
      createAction: {
        
        window.endSheet(window, returnCode: .cancel)
      })
    let controller = NSHostingController(rootView: panel)
    let sheet = NSWindow(contentViewController: controller)
    
    window.beginSheet(sheet) {
      [self] in
      if $0 == .OK {
        ended()
        performOperation(model: model)
      }
      else {
        ended(result: .canceled)
      }
    }
  }
  
  func performOperation(model: CheckOutRemotePanel.Model)
  {
    guard let repository = windowController?.repository
    else { return }
    
    do {
      let operation = CheckOutRemoteOperation(repository: repository,
                                              remoteName: remoteName,
                                              remoteBranch: remoteBranch)
      
      try operation.perform(using: model)
    }
    catch let error as RepoError {
      windowController?.showErrorMessage(error: error)
    }
    catch {
      windowController?.showErrorMessage(error: .unexpected)
    }
  }

  func validateBranch(_ branchName: String) -> CheckOutRemotePanel.BranchNameStatus
  {
    let refName = "refs/heads/" + branchName
    
    if !GitReference.isValidName(refName) {
      return .invalid
    }
    if repository?.localBranch(named: branchName) != nil {
      return .conflict
    }
    return .valid
  }
}
