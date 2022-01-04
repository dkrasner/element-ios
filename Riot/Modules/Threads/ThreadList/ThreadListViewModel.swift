// File created from ScreenTemplate
// $ createScreen.sh Threads/ThreadList ThreadList
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

import Foundation

final class ThreadListViewModel: ThreadListViewModelProtocol {
    
    // MARK: - Properties
    
    // MARK: Private

    private let session: MXSession
    private let roomId: String
    private var threads: [MXThread] = []
    private var eventFormatter: MXKEventFormatter?
    private var roomState: MXRoomState?
    
    private var currentOperation: MXHTTPOperation?
    
    // MARK: Public

    weak var viewDelegate: ThreadListViewModelViewDelegate?
    weak var coordinatorDelegate: ThreadListViewModelCoordinatorDelegate?
    var selectedFilterType: ThreadListFilterType = .all
    
    private(set) var viewState: ThreadListViewState = .idle {
        didSet {
            self.viewDelegate?.threadListViewModel(self, didUpdateViewState: viewState)
        }
    }
    
    // MARK: - Setup
    
    init(session: MXSession,
         roomId: String) {
        self.session = session
        self.roomId = roomId
        session.threadingService.addDelegate(self)
    }
    
    deinit {
        session.threadingService.removeDelegate(self)
        self.cancelOperations()
    }
    
    // MARK: - Public
    
    func process(viewAction: ThreadListViewAction) {
        switch viewAction {
        case .loadData:
            loadData()
        case .complete:
            coordinatorDelegate?.threadListViewModelDidLoadThreads(self)
        case .showFilterTypes:
            viewState = .showingFilterTypes
        case .selectFilterType(let type):
            selectedFilterType = type
            loadData()
        case .selectThread(let index):
            selectThread(index)
        case .cancel:
            cancelOperations()
            coordinatorDelegate?.threadListViewModelDidCancel(self)
        }
    }
    
    var numberOfThreads: Int {
        return threads.count
    }
    
    func threadViewModel(at index: Int) -> ThreadViewModel? {
        guard index < threads.count else {
            return nil
        }
        return viewModel(forThread: threads[index])
    }
    
    var titleViewModel: ThreadRoomTitleViewModel {
        guard let room = session.room(withRoomId: roomId) else {
            return .empty
        }
        
        let avatarViewData = AvatarViewData(matrixItemId: room.matrixItemId,
                                            displayName: room.displayName,
                                            avatarUrl: room.mxContentUri,
                                            mediaManager: room.mxSession.mediaManager,
                                            fallbackImage: AvatarFallbackImage.matrixItem(room.matrixItemId,
                                                                                          room.displayName))
        
        let encrpytionBadge: UIImage?
        if let summary = room.summary, session.crypto != nil {
            encrpytionBadge = EncryptionTrustLevelBadgeImageHelper.roomBadgeImage(for: summary.roomEncryptionTrustLevel())
        } else {
            encrpytionBadge = nil
        }
        
        return ThreadRoomTitleViewModel(roomAvatar: avatarViewData,
                                        roomEncryptionBadge: encrpytionBadge,
                                        roomDisplayName: room.displayName)
    }
    
    private var emptyViewModel: ThreadListEmptyViewModel {
        switch selectedFilterType {
        case .all:
            return ThreadListEmptyViewModel(icon: Asset.Images.threadsIcon.image,
                                            title: VectorL10n.threadsEmptyTitle,
                                            info: VectorL10n.threadsEmptyInfoAll,
                                            tip: VectorL10n.threadsEmptyTip,
                                            showAllThreadsButtonTitle: VectorL10n.threadsEmptyShowAllThreads,
                                            showAllThreadsButtonHidden: true)
        case .myThreads:
            return ThreadListEmptyViewModel(icon: Asset.Images.threadsIcon.image,
                                            title: VectorL10n.threadsEmptyTitle,
                                            info: VectorL10n.threadsEmptyInfoMy,
                                            tip: VectorL10n.threadsEmptyTip,
                                            showAllThreadsButtonTitle: VectorL10n.threadsEmptyShowAllThreads,
                                            showAllThreadsButtonHidden: false)
        }
    }
    
    // MARK: - Private
    
    private func viewModel(forThread thread: MXThread) -> ThreadViewModel {
        let rootAvatarViewData: AvatarViewData?
        let rootMessageSender: MXUser?
        let lastAvatarViewData: AvatarViewData?
        let lastMessageSender: MXUser?
        let rootMessageText = rootMessageText(forThread: thread)
        let (lastMessageText, lastMessageTime) = lastMessageTextAndTime(forThread: thread)
        
        //  root message
        if let rootMessage = thread.rootMessage, let senderId = rootMessage.sender {
            rootMessageSender = session.user(withUserId: rootMessage.sender)
            
            let fallbackImage = AvatarFallbackImage.matrixItem(senderId,
                                                               rootMessageSender?.displayname)
            rootAvatarViewData = AvatarViewData(matrixItemId: senderId,
                                                displayName: rootMessageSender?.displayname,
                                                avatarUrl: rootMessageSender?.avatarUrl,
                                                mediaManager: session.mediaManager,
                                                fallbackImage: fallbackImage)
        } else {
            rootAvatarViewData = nil
            rootMessageSender = nil
        }
        
        //  last message
        if let lastMessage = thread.lastMessage, let senderId = lastMessage.sender {
            lastMessageSender = session.user(withUserId: lastMessage.sender)
            
            let fallbackImage = AvatarFallbackImage.matrixItem(senderId,
                                                               lastMessageSender?.displayname)
            lastAvatarViewData = AvatarViewData(matrixItemId: senderId,
                                                displayName: lastMessageSender?.displayname,
                                                avatarUrl: lastMessageSender?.avatarUrl,
                                                mediaManager: session.mediaManager,
                                                fallbackImage: fallbackImage)
        } else {
            lastAvatarViewData = nil
            lastMessageSender = nil
        }
        
        let summaryViewModel = ThreadSummaryViewModel(numberOfReplies: thread.numberOfReplies,
                                                      lastMessageSenderAvatar: lastAvatarViewData,
                                                      lastMessageText: lastMessageText)
        
        return ThreadViewModel(rootMessageSenderUserId: rootMessageSender?.userId,
                               rootMessageSenderAvatar: rootAvatarViewData,
                               rootMessageSenderDisplayName: rootMessageSender?.displayname,
                               rootMessageText: rootMessageText,
                               lastMessageTime: lastMessageTime,
                               summaryViewModel: summaryViewModel)
    }
    
    private func rootMessageText(forThread thread: MXThread) -> String? {
        guard let eventFormatter = eventFormatter else {
            return nil
        }
        guard let message = thread.rootMessage else {
            return nil
        }
        let formatterError = UnsafeMutablePointer<MXKEventFormatterError>.allocate(capacity: 1)
        return eventFormatter.string(from: message,
                                     with: roomState,
                                     error: formatterError)
    }
    
    private func lastMessageTextAndTime(forThread thread: MXThread) -> (String?, String?) {
        guard let eventFormatter = eventFormatter else {
            return (nil, nil)
        }
        guard let message = thread.lastMessage else {
            return (nil, nil)
        }
        let formatterError = UnsafeMutablePointer<MXKEventFormatterError>.allocate(capacity: 1)
        return (
            eventFormatter.string(from: message,
                                  with: roomState,
                                  error: formatterError),
            eventFormatter.dateString(from: message, withTime: true)
        )
    }
    
    private func loadData(showLoading: Bool = true) {

        if showLoading {
            viewState = .loading
        }
        
        switch selectedFilterType {
        case .all:
            threads = session.threadingService.threads(inRoom: roomId)
        case .myThreads:
            threads = session.threadingService.participatedThreads(inRoom: roomId)
        }
        
        if threads.isEmpty {
            viewState = .empty(emptyViewModel)
            return
        }
        
        threadsLoaded()
    }
    
    private func threadsLoaded() {
        guard let eventFormatter = session.roomSummaryUpdateDelegate as? MXKEventFormatter,
              let room = session.room(withRoomId: roomId) else {
            //  go into loaded state
            self.viewState = .loaded
            
            return
        }
        
        room.state { [weak self] roomState in
            guard let self = self else { return }
            self.eventFormatter = eventFormatter
            self.roomState = roomState
            
            //  go into loaded state
            self.viewState = .loaded
        }
    }
    
    private func selectThread(_ index: Int) {
        guard index < threads.count else {
            return
        }
        let thread = threads[index]
        coordinatorDelegate?.threadListViewModelDidSelectThread(self, thread: thread)
    }
    
    private func cancelOperations() {
        self.currentOperation?.cancel()
    }
}

extension ThreadListViewModel: MXThreadingServiceDelegate {
    
    func threadingServiceDidUpdateThreads(_ service: MXThreadingService) {
        loadData(showLoading: false)
    }
    
}