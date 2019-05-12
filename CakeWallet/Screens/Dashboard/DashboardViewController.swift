import UIKit
import CakeWalletLib
import CakeWalletCore
import CWMonero
import FlexLayout


final class DashboardController: BaseViewController<DashboardView>, StoreSubscriber, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate {
    let walletNameView = WalletNameView()
    weak var dashboardFlow: DashboardFlow?
    private var showAbleBalance: Bool
    private(set) var presentWalletsListButtonTitle: UIBarButtonItem?
    private(set) var presentWalletsListButtonImage: UIBarButtonItem?
    private var sortedTransactions:  [DateComponents : [TransactionDescription]] = [:] {
        didSet {
            transactionsKeys = sort(dateComponents: Array(sortedTransactions.keys))
        }
    }
    private var transactionsKeys: [DateComponents] = []
    private var initialHeight: UInt64
    private var refreshControl: UIRefreshControl
    private let calendar: Calendar
    private var scrollViewOffset: CGFloat = 0
    let store: Store<ApplicationState>
    
    init(store: Store<ApplicationState>, dashboardFlow: DashboardFlow?, calendar: Calendar = Calendar.current) {
        self.store = store
        self.dashboardFlow = dashboardFlow
        self.calendar = calendar
        showAbleBalance = true
        initialHeight = 0
        refreshControl = UIRefreshControl()
        super.init()
        tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(named: "wallet_icon")?.resized(to: CGSize(width: 28, height: 28)).withRenderingMode(.alwaysOriginal),
            selectedImage: UIImage(named: "wallet_selected_icon")?.resized(to: CGSize(width: 28, height: 28)).withRenderingMode(.alwaysOriginal)
        )
    }
    
    override func configureBinds() {
        navigationController?.navigationBar.backgroundColor = .clear
        
        let backButton = UIBarButtonItem(title: "", style: .plain, target: self, action: nil)
        navigationItem.backBarButtonItem = backButton  
        
        contentView.transactionsTableView.register(items: [TransactionDescription.self])
        contentView.transactionsTableView.delegate = self
        contentView.transactionsTableView.dataSource = self
        contentView.transactionsTableView.addSubview(refreshControl)
    
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: UIControlEvents.valueChanged)
        
        let onCryptoAmountTap = UITapGestureRecognizer(target: self, action: #selector(changeShownBalance))
        contentView.cryptoAmountLabel.isUserInteractionEnabled = true
        contentView.cryptoAmountLabel.addGestureRecognizer(onCryptoAmountTap)
        
        let sendButtonTap = UITapGestureRecognizer(target: self, action: #selector(presentSend))
        contentView.sendButton.isUserInteractionEnabled = true
        contentView.sendButton.addGestureRecognizer(sendButtonTap)
        
        let receiveButtonTap = UITapGestureRecognizer(target: self, action: #selector(presentReceive))
        contentView.receiveButton.isUserInteractionEnabled = true
        contentView.receiveButton.addGestureRecognizer(receiveButtonTap)
        
        insertNavigationItems()
    }
    
    private func insertNavigationItems() {
        presentWalletsListButtonTitle = UIBarButtonItem(
            title: "Change",
            style: .plain,
            target: self,
            action: #selector(presentWalletsList)
        )
        
        presentWalletsListButtonImage = UIBarButtonItem(
            image: UIImage(named: "arrow_bottom_purple_icon")?
                .resized(to: CGSize(width: 11, height: 9)).withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(presentWalletsList)
        )
        
        presentWalletsListButtonImage?.tintColor = .vividBlue

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "more")?.resized(to: CGSize(width: 28, height: 28)), style: .plain, target: self, action: #selector(presentWalletActions))
        navigationItem.titleView = walletNameView
        
        if let presentWalletsListButtonTitle = presentWalletsListButtonTitle,
           let presentWalletsListButtonImage = presentWalletsListButtonImage {
            
            presentWalletsListButtonTitle.setTitleTextAttributes([
                NSAttributedStringKey.font: applyFont(ofSize: 13),
                NSAttributedStringKey.foregroundColor: UIColor.wildDarkBlue
            ], for: .normal)
            
            presentWalletsListButtonTitle.setTitleTextAttributes([
                NSAttributedStringKey.font: applyFont(ofSize: 13),
                NSAttributedStringKey.foregroundColor: UIColor.wildDarkBlue
            ], for: .highlighted)
            
            navigationItem.rightBarButtonItems = [presentWalletsListButtonImage, presentWalletsListButtonTitle]
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.subscribe(self)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        store.unsubscribe(self)
    }
    
    override func setTitle() {
        title = NSLocalizedString("wallet", comment: "")
    }
    
    func onStateChange(_ state: ApplicationState) {
        updateStatus(state.blockchainState.connectionStatus)
        updateCryptoBalance(showAbleBalance ? state.balanceState.unlockedBalance : state.balanceState.balance)
        updateFiatBalance(showAbleBalance ? state.balanceState.unlockedFiatBalance : state.balanceState.fullFiatBalance)
        onWalletChange(state.walletState, state.blockchainState)
        updateTransactions(state.transactionsState.transactions)
        updateInitialHeight(state.blockchainState)
        
        walletNameView.title = state.walletState.name
        walletNameView.subtitle = state.walletState.account.label
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sortedTransactions.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let key = transactionsKeys[section]
        return sortedTransactions[key]?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 45
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let key = transactionsKeys[section]
        let dateFormatter = DateFormatter()
        let label = UILabel(frame: CGRect(origin: .zero, size: CGSize(width: tableView.frame.size.width, height: 45)))
        let date = NSCalendar.current.date(from: key)!
        label.textColor = UIColor(hex: 0x9BACC5)
        label.font = applyFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        
        if Calendar.current.isDateInToday(date) {
            label.text = "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            label.text = "Yesterday"
        } else {
            let now = Date()
            let currentYear = Calendar.current.component(.year, from: now)
            dateFormatter.dateFormat = key.year == currentYear ? "dd MMMM" : "dd MMMM yyyy"
            label.text = dateFormatter.string(from: date)
        }
        
        return label
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let transaction = getTransaction(by: indexPath) else {
            return UITableViewCell()
        }
        
        let cell = tableView.dequeueReusableCell(withItem: transaction, for: indexPath)
        
        if let transactionUITableViewCell = cell as? TransactionUITableViewCell {
            transactionUITableViewCell.addSeparator()
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        if let transaction = getTransaction(by: indexPath) {
            presentTransactionDetails(for: transaction)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        animateFixedHeader(for: scrollView)
        
        updateCryptoBalance(store.state.balanceState.balance)
        updateFiatBalance(store.state.balanceState.unlockedFiatBalance)
    }
    
    private func animateFixedHeader(for scrollView: UIScrollView) {
        let currentOffset = scrollView.contentOffset.y
        let headerHeight = contentView.fixedHeader.bounds.height
        let headerMinHeight: CGFloat = 185
        
        let hideContentAnimation = { (toValue: CGFloat) -> Void in
            UIViewPropertyAnimator(duration: 0.15, curve: .easeOut, animations: { [weak self] in
                self?.contentView.progressBar.alpha = toValue
                self?.contentView.cryptoTitleLabel.alpha = toValue
            }).startAnimation()
        }
        
        if currentOffset > 0 {
            if (currentOffset > 25 && headerHeight > headerMinHeight) || (currentOffset < scrollViewOffset && headerHeight < DashboardView.fixedHeaderHeight) {
                scrollViewOffset = currentOffset
                let dashboardHeightToSet = DashboardView.fixedHeaderHeight - currentOffset + 25
                
                if currentOffset > 130 {
                    contentView.buttonsRow.flex.height(80 - currentOffset * 0.15)
                }
                
                if dashboardHeightToSet > 160 {
                    contentView.fixedHeader.flex.height(dashboardHeightToSet)
                }
                
                if currentOffset > 60 {
                    hideContentAnimation(0.0)
                    
                } else {
                    hideContentAnimation(1.0)
                }
                
                if 100 - currentOffset > 10 {
                    contentView.cardViewCoreDataWrapper.flex.top(70 - currentOffset)
                }
                
                contentView.buttonsRow.flex.markDirty()
                contentView.fixedHeader.flex.markDirty()
                contentView.fixedHeader.flex.layout(mode: .adjustHeight)
                return
            }
        }
        
        guard scrollView.contentOffset.y > contentView.fixedHeader.frame.height else {
            updateCryptoBalance(store.state.balanceState.balance)
            updateFiatBalance(store.state.balanceState.unlockedFiatBalance)
            
            return
        }
    }
    
    @objc
    private func presentWalletActions() {
        let alertViewController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel)
        
        let presentReconnectAction = UIAlertAction(title: NSLocalizedString("reconnect", comment: ""), style: .default) { [weak self] _ in
            self?.reconnectAction()
        }
        
        let showSeedAction = UIAlertAction(title: NSLocalizedString("show_seed", comment: ""), style: .default) { [weak self] _ in
            guard
                let walletName = self?.store.state.walletState.name,
                let walletType = self?.store.state.walletState.walletType else {
                    return
            }
            
            let index = WalletIndex(name: walletName, type: walletType)
            self?.showSeedAction(for: index)
        }
        
        let showKeysAction = UIAlertAction(title: NSLocalizedString("show_keys", comment: ""), style: .default) { [weak self] _ in
            self?.showKeysAction()
        }
        
        let presentAddressBookAction = UIAlertAction(title: NSLocalizedString("address_book", comment: ""), style: .default) { [weak self] _ in
            self?.dashboardFlow?.change(route: .addressBook)
        }
        
        let presentAccountsAction = UIAlertAction(title: NSLocalizedString("accounts", comment: ""), style: .default) { [weak self] _ in
            self?.dashboardFlow?.change(route: .accounts)
        }
        
        alertViewController.addAction(presentReconnectAction)
        alertViewController.addAction(showSeedAction)
        alertViewController.addAction(showKeysAction)
        alertViewController.addAction(presentAccountsAction)
        alertViewController.addAction(presentAddressBookAction)
        alertViewController.addAction(cancelAction)
        DispatchQueue.main.async {
            self.present(alertViewController, animated: true)
        }
    }
    
    @objc
    private func changeShownBalance() {
        showAbleBalance = !showAbleBalance
        onStateChange(store.state)
    }
    
    private func getTransaction(by indexPath: IndexPath) -> TransactionDescription? {
        let key = transactionsKeys[indexPath.section]
        return sortedTransactions[key]?[indexPath.row]
    }

    private func onWalletChange(_ walletState: WalletState, _ blockchainState: BlockchainState) {
        initialHeight = 0
        updateTitle(walletState.name)
    }
    
    private func showSeedAction(for wallet: WalletIndex) {
        let authController = AuthenticationViewController(store: store, authentication: AuthenticationImpl())
        let navController = UINavigationController(rootViewController: authController)
        
        authController.onDismissHandler = onDismissHandler
        authController.handler = { [weak authController, weak self] in
            do {
                let gateway = MoneroWalletGateway()
                let walletURL = gateway.makeConfigURL(for: wallet.name)
                let walletConfig = try WalletConfig.load(from: walletURL)
                let seed = try gateway.fetchSeed(for: wallet)
                
                authController?.dismiss(animated: true) {
                    self?.dashboardFlow?.change(route: .showSeed(wallet: wallet.name, date: walletConfig.date, seed: seed))
                }
                
            } catch {
                print(error)
                self?.showErrorAlert(error: error)
            }
        }
        
        present(navController, animated: true)
    }
    
    
    private func showKeysAction() {
        let authController = AuthenticationViewController(store: store, authentication: AuthenticationImpl())
        let navController = UINavigationController(rootViewController: authController)
        authController.onDismissHandler = onDismissHandler
        authController.handler = { [weak authController, weak self] in
            authController?.dismiss(animated: true) {
                self?.dashboardFlow?.change(route: .showKeys)
            }
        }
        
        present(navController, animated: true)
    }
    
    private func reconnectAction() {
        let alertController = UIAlertController(
            title: NSLocalizedString("reconnection", comment: ""),
            message: NSLocalizedString("reconnect_alert_text", comment: ""),
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("reconnect", comment: ""),
            style: .default,
            handler: { [weak self, weak alertController] _ in
                self?.store.dispatch(WalletActions.reconnect)
                alertController?.dismiss(animated: true)
            }
        ))
        
        alertController.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: nil
        ))
        
        present(alertController, animated: true, completion: nil)
    }
    
    private func observePullAction(for offset: CGFloat) {
        guard offset < -40 else {
            return
        }
        
        store.dispatch(TransactionsActions.askToUpdate)
    }
    
    private func updateInitialHeight(_ blockchainState: BlockchainState) {
        guard initialHeight == 0 else {
            return
        }
        
        if case let .syncing(height) = blockchainState.connectionStatus {
            initialHeight = height
        }
    }
    
    @objc
    private func presentWalletsList() {
        dashboardFlow?.change(route: .wallets)
    }
    
    @objc
    private func presentReceive() {
        dashboardFlow?.change(route: .receive)
    }
    
    @objc
    private func presentSend() {
        dashboardFlow?.change(route: .send)
    }
    
    private func presentTransactionDetails(for tx: TransactionDescription) {
        let transactionDetailsViewController = TransactionDetailsViewController(transactionDescription: tx)
        let nav = UINavigationController(rootViewController: transactionDetailsViewController)
        tabBarController?.present(nav, animated: true)
    }
    
    private func updateSyncing(_ currentHeight: UInt64, blockchainHeight: UInt64) {
        if blockchainHeight < currentHeight || blockchainHeight == 0 {
            store.dispatch(BlockchainActions.fetchBlockchainHeight)
        } else {
            let track = blockchainHeight - initialHeight
            let _currentHeight = currentHeight > initialHeight ? currentHeight - initialHeight : 0
            let remaining = track > _currentHeight ? track - _currentHeight : 0
            guard currentHeight != 0 && track != 0 else { return }
            let val = Float(_currentHeight) / Float(track)
            let prg = Int(val * 100)
            contentView.progressBar.updateProgress(prg)
            contentView.updateStatus(text: NSLocalizedString("blocks_remaining", comment: "")
                + ": "
                + String(remaining)
                + "(\(prg)%)")
        }
    }
    
    private func updateStatus(_ connectionStatus: ConnectionStatus) {
        switch connectionStatus {
        case let .syncing(currentHeight):
            updateSyncing(currentHeight, blockchainHeight: store.state.blockchainState.blockchainHeight)
        case .connection:
            updateStatusConnection()
        case .notConnected:
            updateStatusNotConnected()
        case .startingSync:
            updateStatusstartingSync()
        case .synced:
            updateStatusSynced()
        case .failed:
            updateStatusFailed()
        }
    }
    
    private func updateStatusConnection() {
        contentView.progressBar.updateProgress(0)
        contentView.updateStatus(text: NSLocalizedString("connecting", comment: ""))
    }
    
    private func updateStatusNotConnected() {
        contentView.progressBar.updateProgress(0)
        contentView.updateStatus(text: NSLocalizedString("not_connected", comment: ""))
    }
    
    private func updateStatusstartingSync() {
        contentView.progressBar.updateProgress(0)
        contentView.updateStatus(text: NSLocalizedString("starting_sync", comment: ""))
        contentView.rootFlexContainer.flex.layout()
    }
    
    private func updateStatusSynced() {
        contentView.progressBar.updateProgress(100)
        contentView.updateStatus(text: NSLocalizedString("synchronized", comment: ""), done: true)
    }
    
    private func updateStatusFailed() {
        contentView.progressBar.updateProgress(0)
        contentView.updateStatus(text: NSLocalizedString("failed_connection_to_node", comment: ""))
    }
    
    private func updateFiatBalance(_ amount: Amount) {
        contentView.fiatAmountLabel.text = amount.formatted()
        contentView.fiatAmountLabel.flex.markDirty()
    }
    
    private func updateCryptoBalance(_ amount: Amount) {
        contentView.cryptoTitleLabel.text = "XMR"
            + " "
            + (showAbleBalance ? NSLocalizedString("available_balance", comment: "") : NSLocalizedString("full_balance", comment: ""))
        contentView.cryptoAmountLabel.text = amount.formatted()
        contentView.cryptoTitleLabel.flex.markDirty()
        contentView.cryptoAmountLabel.flex.markDirty()
    }
    
    private func updateTransactions(_ transactions: [TransactionDescription]) {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }

        contentView.transactionTitleLabel.isHidden = transactions.count <= 0
        
        let sortedTransactions = Dictionary(grouping: transactions) {
            return calendar.dateComponents([.day, .year, .month], from: ($0.date))
        }

        self.sortedTransactions = sortedTransactions
        
        if self.sortedTransactions.count > 0 {
            if contentView.transactionTitleLabel.isHidden {
                contentView.transactionTitleLabel.isHidden = false
            }
        } else if !contentView.transactionTitleLabel.isHidden {
            contentView.transactionTitleLabel.isHidden = true
        }
        
        contentView.transactionsTableView.reloadData()
    }
    
    private func updateTitle(_ title: String) {
        if navigationItem.leftBarButtonItem?.title != title {
            navigationItem.leftBarButtonItem?.title = title
        }
    }

    @objc
    private func toAddressBookAction() {
        dashboardFlow?.change(route: .addressBook)
    }
    
    @objc
    private func refresh(_ refreshControl: UIRefreshControl) {
        store.dispatch(TransactionsActions.askToUpdate)
        refreshControl.endRefreshing()
    }
}
