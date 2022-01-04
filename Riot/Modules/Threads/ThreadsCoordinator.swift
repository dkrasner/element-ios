// File created from FlowTemplate
// $ createRootCoordinator.sh Threads Threads ThreadList
/*
 Copyright 2021 New Vector Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import UIKit

@objcMembers
final class ThreadsCoordinator: NSObject, ThreadsCoordinatorProtocol {
    
    // MARK: - Properties
    
    // MARK: Private
        
    private let parameters: ThreadsCoordinatorParameters
    private var selectedThreadCoordinator: RoomCoordinator?
    
    private var navigationRouter: NavigationRouterType {
        return self.parameters.navigationRouter
    }
    
    // MARK: Public

    // Must be used only internally
    var childCoordinators: [Coordinator] = []
    
    weak var delegate: ThreadsCoordinatorDelegate?
    
    // MARK: - Setup
    
    init(parameters: ThreadsCoordinatorParameters) {
        self.parameters = parameters
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didPopModule(_:)),
                                               name: NavigationRouter.didPopModule,
                                               object: nil)
    }    
    
    // MARK: - Public
    
    func start() {

        let rootCoordinator = self.createThreadListCoordinator()
        
        rootCoordinator.start()

        self.add(childCoordinator: rootCoordinator)
        
        // Detect when view controller has been dismissed by gesture when presented modally (not in full screen).
        self.navigationRouter.toPresentable().presentationController?.delegate = self
        
        if self.navigationRouter.modules.isEmpty == false {
            self.navigationRouter.push(rootCoordinator, animated: true, popCompletion: { [weak self] in
                self?.remove(childCoordinator: rootCoordinator)
            })
        } else {
            self.navigationRouter.setRootModule(rootCoordinator) { [weak self] in
                self?.remove(childCoordinator: rootCoordinator)
            }
        }
    }
    
    func stop() {
        if selectedThreadCoordinator != nil {
            let modules = self.navigationRouter.modules
            guard modules.count >= 3 else {
                return
            }
            let moduleToGoBack = modules[modules.count - 3]
            self.navigationRouter.popToModule(moduleToGoBack, animated: true)
        } else {
            self.navigationRouter.popModule(animated: true)
        }
    }
    
    func toPresentable() -> UIViewController {
        return self.navigationRouter.toPresentable()
    }
    
    // MARK: - Private
    
    @objc
    private func didPopModule(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let module = userInfo[NavigationRouter.NotificationUserInfoKey.module] as? Presentable,
              let selectedThreadCoordinator = selectedThreadCoordinator else {
            return
        }
        
        if module.toPresentable() == selectedThreadCoordinator.toPresentable() {
            selectedThreadCoordinator.delegate = nil
            remove(childCoordinator: selectedThreadCoordinator)
            self.selectedThreadCoordinator = nil
        }
    }

    private func createThreadListCoordinator() -> ThreadListCoordinator {
        let coordinatorParameters = ThreadListCoordinatorParameters(session: self.parameters.session,
                                                                    roomId: self.parameters.roomId)
        let coordinator = ThreadListCoordinator(parameters: coordinatorParameters)
        coordinator.delegate = self
        return coordinator
    }
    
    private func createThreadCoordinator(forThread thread: MXThread) -> RoomCoordinator {
        let parameters = RoomCoordinatorParameters(navigationRouter: navigationRouter,
                                                   navigationRouterStore: nil,
                                                   session: parameters.session,
                                                   roomId: parameters.roomId,
                                                   eventId: nil,
                                                   threadId: thread.id,
                                                   displayConfiguration: .forThreads)
        let coordinator = RoomCoordinator(parameters: parameters)
        coordinator.delegate = self
        return coordinator
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate
extension ThreadsCoordinator: UIAdaptivePresentationControllerDelegate {
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.delegate?.threadsCoordinatorDidDismissInteractively(self)
    }
}

// MARK: - ThreadListCoordinatorDelegate
extension ThreadsCoordinator: ThreadListCoordinatorDelegate {
    func threadListCoordinatorDidLoadThreads(_ coordinator: ThreadListCoordinatorProtocol) {
        
    }
    
    func threadListCoordinatorDidSelectThread(_ coordinator: ThreadListCoordinatorProtocol, thread: MXThread) {
        let roomCoordinator = createThreadCoordinator(forThread: thread)
        selectedThreadCoordinator = roomCoordinator
        roomCoordinator.start()
        self.add(childCoordinator: roomCoordinator)
    }
    
    func threadListCoordinatorDidCancel(_ coordinator: ThreadListCoordinatorProtocol) {
        self.delegate?.threadsCoordinatorDidComplete(self)
    }
}

//  MARK: - RoomCoordinatorDelegate

extension ThreadsCoordinator: RoomCoordinatorDelegate {
    
    func roomCoordinatorDidLeaveRoom(_ coordinator: RoomCoordinatorProtocol) {
        
    }
    
    func roomCoordinatorDidCancelRoomPreview(_ coordinator: RoomCoordinatorProtocol) {
        
    }
    
    func roomCoordinator(_ coordinator: RoomCoordinatorProtocol, didSelectRoomWithId roomId: String, eventId: String?) {
        self.delegate?.threadsCoordinatorDidSelect(self, roomId: roomId, eventId: eventId)
    }
    
    func roomCoordinatorDidDismissInteractively(_ coordinator: RoomCoordinatorProtocol) {
        
    }
    
}