import UIKit
import ZoomVideoSDK

class StartViewController: UIViewController {
    var enterSessionButton: UIButton!

    private func setupSDK() {
        let initParams = ZoomVideoSDKInitParams()
        initParams.domain = "zoom.us"
        let sdkInitReturnStatus = ZoomVideoSDK.shareInstance()?.initialize(initParams)
        switch sdkInitReturnStatus {
        case .Errors_Success:
            print("SDK initialization succeeded")
        default:
            if let error = sdkInitReturnStatus {
                print("SDK initialization failed: \(error)")
                return
            }
        }
    }

    override func loadView() {
        super.loadView()
        enterSessionButton = UIButton(type: .system)
        enterSessionButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enterSessionButton)
        NSLayoutConstraint.activate([
            enterSessionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            enterSessionButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidLoad() {
        enterSessionButton.configuration = .plain()
        enterSessionButton.configuration?.contentInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 16)
        enterSessionButton.configuration?.title = "Join Session"
        enterSessionButton.configuration?.background.backgroundColor = .white
        enterSessionButton.configuration?.background.cornerRadius = 8
        enterSessionButton.addTarget(self, action: #selector(enterButtonTapped(_:)), for: .touchUpInside)
        setupSDK()
    }

    @IBAction func enterButtonTapped(_: UIButton) {
        enterSessionButton.isEnabled = false
        let sessionViewController = SessionViewController()
        sessionViewController.modalPresentationStyle = .fullScreen
        present(sessionViewController, animated: false)
        enterSessionButton.isEnabled = true
    }
}
