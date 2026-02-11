import UIKit
import ZoomVideoSDK

extension SessionViewController {
    func setupUI() {
        setupViews()
        setupConstraints()
        setupTabBar()
    }

    private func setupViews() {
        // Setup scroll view
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true

        // Setup video stack view
        videoStackView.axis = .vertical
        videoStackView.spacing = 8
        videoStackView.alignment = .fill
        videoStackView.distribution = .fillEqually

        for item in [loadingLabel, scrollView, tabBar] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }

        scrollView.addSubview(videoStackView)
        videoStackView.translatesAutoresizingMaskIntoConstraints = false

        loadingLabel.text = "Loading Session..."
        loadingLabel.textColor = .white
    }

    private func setupConstraints() {
        // Main container constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: tabBar.topAnchor),

            videoStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            videoStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            videoStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            videoStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),
            videoStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -16),

            tabBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        // Loading label
        loadingLabel.center(in: view, yOffset: -30)
    }

    private func setupTabBar() {
        tabBar.delegate = self
        tabBar.isHidden = true

        let leaveSessionBarItem = UITabBarItem(title: "Leave Session", image: UIImage(systemName: "phone.down"), tag: ControlOption.leaveSession.rawValue)
        tabBar.items = [toggleVideoBarItem, toggleAudioBarItem, leaveSessionBarItem]
    }

    func addLocalViewToGrid() {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .black

        localView.translatesAutoresizingMaskIntoConstraints = false
        let placeholder = createPlaceholderView(with: userName)
        localPlaceholder = placeholder

        containerView.addSubview(localView)
        containerView.addSubview(placeholder)

        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 1.0 / videoViewAspectRatio),

            localView.topAnchor.constraint(equalTo: containerView.topAnchor),
            localView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            localView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            localView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholder.topAnchor.constraint(equalTo: containerView.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            placeholder.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        videoStackView.addArrangedSubview(containerView)
    }

    func addRemoteUserView(for user: ZoomVideoSDKUser) -> (view: UIView, placeholder: UIView) {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .black

        let userView = UIView()
        let placeholderView = createPlaceholderView(with: user.getName() ?? "")

        userView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(userView)
        containerView.addSubview(placeholderView)

        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 1.0 / videoViewAspectRatio),

            userView.topAnchor.constraint(equalTo: containerView.topAnchor),
            userView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            userView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            userView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholderView.topAnchor.constraint(equalTo: containerView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        videoStackView.addArrangedSubview(containerView)

        return (userView, placeholderView)
    }
}

func createPlaceholderView(with name: String) -> UIView {
    let placeholderView = UIView()
    placeholderView.translatesAutoresizingMaskIntoConstraints = false
    placeholderView.backgroundColor = .darkGray

    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = 8
    stackView.alignment = .center
    stackView.translatesAutoresizingMaskIntoConstraints = false

    let imageView = UIImageView(image: UIImage(systemName: "person.fill"))
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .white
    imageView.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = name
    label.textColor = .white
    label.font = .systemFont(ofSize: 16, weight: .medium)
    label.translatesAutoresizingMaskIntoConstraints = false

    stackView.addArrangedSubview(imageView)
    stackView.addArrangedSubview(label)
    placeholderView.addSubview(stackView)

    NSLayoutConstraint.activate([
        imageView.heightAnchor.constraint(equalToConstant: 50),
        imageView.widthAnchor.constraint(equalToConstant: 50),

        stackView.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
        stackView.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),
    ])

    return placeholderView
}

// Helper extensions
extension UIView {
    func center(in view: UIView, yOffset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: yOffset).isActive = true
    }

    func pinToSafeArea(of view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    func anchor(top: NSLayoutYAxisAnchor? = nil,
                trailing: NSLayoutXAxisAnchor? = nil,
                padding: UIEdgeInsets = .zero,
                size: CGSize)
    {
        translatesAutoresizingMaskIntoConstraints = false

        if let top = top {
            topAnchor.constraint(equalTo: top, constant: padding.top).isActive = true
        }
        if let trailing = trailing {
            trailingAnchor.constraint(equalTo: trailing, constant: -padding.right).isActive = true
        }

        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
    }
}
