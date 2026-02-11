import UIKit
import ZoomVideoSDK

enum ControlOption: Int {
    case toggleVideo, toggleAudio, leaveSession
}

class SessionViewController: UIViewController {
    
    /*
     You should sign your JWT with a backend service in a production use-case
     For faster JWT generation, you can navigate checkout the JWTGenerator.swift under Script folder and its README for more details on how to consume it. Once you got the token, you can simple copy and paste it below.
     Ensure that the sessionName matches the session name used to generate the JWT Token.
     */
    let jwtToken = <#Your JWT Token#>
    let sessionName = <#Session Name#>
    let userName = <#Username#> // Display name

    // MARK: - Properties
    let videoViewAspectRatio: CGFloat = 1.0
    var loadingLabel: UILabel = .init()
    var scrollView: UIScrollView = .init()
    var videoStackView: UIStackView = .init()
    var remoteUserViews: [Int: (view: UIView, placeholder: UIView)] = [:]
    var localView: UIView = .init()
    var localPlaceholder: UIView?
    var tabBar: UITabBar = .init()
    var toggleVideoBarItem: UITabBarItem = .init(title: "Stop Video", image: UIImage(systemName: "video.slash"), tag: ControlOption.toggleVideo.rawValue)
    var toggleAudioBarItem: UITabBarItem = .init(title: "Mute", image: UIImage(systemName: "mic.slash"), tag: ControlOption.toggleAudio.rawValue)

    // MARK: - Lifecycle Methods

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        ZoomVideoSDK.shareInstance()?.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await joinSession()
        }
    }

    // MARK: - Private Methods

    private func joinSession() async {
        let sessionContext = ZoomVideoSDKSessionContext()
        sessionContext.token = jwtToken
        sessionContext.sessionName = sessionName
        sessionContext.userName = userName
        if ZoomVideoSDK.shareInstance()?.joinSession(sessionContext) == nil {
            print("Join session failed")
            showError(message: "Failed to join session")
            return
        }
    }

    private func showError(message: String) {
        Task { @MainActor in
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.dismiss(animated: true)
            })
            present(alert, animated: true)
        }
    }
}

// MARK: - ZoomVideoSDKDelegate

extension SessionViewController: ZoomVideoSDKDelegate {
    func onSessionJoin() {
        guard let myUser = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf(),
              let myUserVideoCanvas = myUser.getVideoCanvas() else { return }

        Task(priority: .background) {
            addLocalViewToGrid()
            self.loadingLabel.isHidden = true
            self.tabBar.isHidden = false

            // Ensure video is started
            if let videoHelper = ZoomVideoSDK.shareInstance()?.getVideoHelper(),
               !(myUserVideoCanvas.videoStatus()?.on ?? false)
            {
                _ = videoHelper.startVideo()
            }

            myUserVideoCanvas.subscribe(with: self.localView, aspectMode: .panAndScan, andResolution: ._Auto)

            // Update UI to reflect video state
            self.localPlaceholder?.isHidden = true
            self.toggleVideoBarItem.title = "Stop Video"
            self.toggleVideoBarItem.image = UIImage(systemName: "video.slash")
        }
    }

    func onUserJoin(_: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
        guard let users = users,
              let myself = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf() else { return }

        for user in users where user.getID() != myself.getID() {
            let views = addRemoteUserView(for: user)
            remoteUserViews[user.getID()] = views

            if let remoteUserVideoCanvas = user.getVideoCanvas() {
                Task(priority: .background) {
                    views.placeholder.isHidden = true
                    remoteUserVideoCanvas.subscribe(with: views.view, aspectMode: .panAndScan, andResolution: ._Auto)
                }
            }
        }
    }

    func onUserVideoStatusChanged(_: ZoomVideoSDKVideoHelper?, user: [ZoomVideoSDKUser]?) {
        guard let users = user,
              let myself = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf() else { return }

        for user in users where user.getID() != myself.getID() {
            if let canvas = user.getVideoCanvas(),
               let isVideoOn = canvas.videoStatus()?.on,
               let views = remoteUserViews[user.getID()]
            {
                Task(priority: .background) {
                    views.placeholder.isHidden = isVideoOn
                }
            }
        }
    }

    func onUserLeave(_: ZoomVideoSDKUserHelper?, users: [ZoomVideoSDKUser]?) {
        guard let users = users,
              let myself = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf() else { return }

        for user in users where user.getID() != myself.getID() {
            if let canvas = user.getVideoCanvas(),
               let views = remoteUserViews[user.getID()]
            {
                Task(priority: .background) {
                    canvas.unSubscribe(with: views.view)
                    if let container = views.view.superview {
                        container.removeFromSuperview()
                    }
                }
                remoteUserViews.removeValue(forKey: user.getID())
            }
        }
    }

    func onSessionLeave() {
        if let myCanvas = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()?.getVideoCanvas() {
            Task(priority: .background) {
                myCanvas.unSubscribe(with: self.localView)
            }
        }

        ZoomVideoSDK.shareInstance()?.getSession()?.getRemoteUsers()?.forEach { user in
            if let canvas = user.getVideoCanvas() {
                Task(priority: .background) {
                    canvas.unSubscribe(with: self.videoStackView)
                }
            }
        }

        presentingViewController?.dismiss(animated: true)
    }
}

// MARK: - UITabBarDelegate

extension SessionViewController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        tabBar.selectedItem = nil

        switch item.tag {
        case ControlOption.toggleVideo.rawValue:
            handleVideoToggle(tabBar)
        case ControlOption.toggleAudio.rawValue:
            handleAudioToggle(tabBar)
        case ControlOption.leaveSession.rawValue:
            tabBar.isUserInteractionEnabled = false
            ZoomVideoSDK.shareInstance()?.leaveSession(false)
        default:
            break
        }
    }

    private func handleVideoToggle(_ tabBar: UITabBar) {
        tabBar.items![ControlOption.toggleVideo.rawValue].isEnabled = false

        guard let canvas = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf()?.getVideoCanvas(),
              let videoHelper = ZoomVideoSDK.shareInstance()?.getVideoHelper(),
              let isVideoOn = canvas.videoStatus()?.on else { return }

        Task(priority: .background) {
            let _ = isVideoOn ? videoHelper.stopVideo() : videoHelper.startVideo()
            // Update UI to reflect new video state
            let newVideoState = !isVideoOn
            self.toggleVideoBarItem.title = newVideoState ? "Stop Video" : "Start Video"
            self.toggleVideoBarItem.image = UIImage(systemName: newVideoState ? "video.slash" : "video")
            self.localPlaceholder?.isHidden = newVideoState
        }

        tabBar.items![ControlOption.toggleVideo.rawValue].isEnabled = true
    }

    private func handleAudioToggle(_ tabBar: UITabBar) {
        tabBar.items![ControlOption.toggleAudio.rawValue].isEnabled = false

        guard let myUser = ZoomVideoSDK.shareInstance()?.getSession()?.getMySelf(),
              let audioStatus = myUser.audioStatus(),
              let audioHelper = ZoomVideoSDK.shareInstance()?.getAudioHelper() else { return }

        if audioStatus.audioType == .none {
            audioHelper.startAudio()
        } else {
            let _ = audioStatus.isMuted ? audioHelper.unmuteAudio(myUser) : audioHelper.muteAudio(myUser)
            toggleAudioBarItem.title = audioStatus.isMuted ? "Mute" : "Start Audio"
            toggleAudioBarItem.image = UIImage(systemName: audioStatus.isMuted ? "mic.slash" : "mic")
        }

        tabBar.items![ControlOption.toggleAudio.rawValue].isEnabled = true
    }
}
