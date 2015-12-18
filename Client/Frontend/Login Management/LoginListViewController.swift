/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Storage
import Shared

private struct LoginListUX {
    static let RowHeight: CGFloat = 58
    static let SearchHeight: CGFloat = 58
}

private let LoginCellIdentifier = "LoginCell"

class LoginListViewController: UIViewController {

    private var loginDataSource: LoginCursorDataSource = LoginCursorDataSource()
    private var loginSearchController: LoginSearchController? = nil

    private let profile: Profile

    private let searchView = SearchInputView()

    private let tableView = UITableView()

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        automaticallyAdjustsScrollViewInsets = false
        self.view.backgroundColor = UIColor.whiteColor()

        self.title = NSLocalizedString("Logins", tableName: "LoginManager", comment: "Title for Logins List View screen")
        loginSearchController = LoginSearchController(
            profile: self.profile,
            dataSource: loginDataSource,
            tableView: tableView)

        searchView.delegate = loginSearchController

        tableView.registerClass(LoginTableViewCell.self, forCellReuseIdentifier: LoginCellIdentifier)

        view.addSubview(searchView)
        view.addSubview(tableView)

        searchView.snp_makeConstraints { make in
            make.top.equalTo(snp_topLayoutGuideBottom).constraint
            make.left.right.equalTo(self.view)
            make.height.equalTo(LoginListUX.SearchHeight)
        }

        tableView.snp_makeConstraints { make in
            make.top.equalTo(searchView.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
        }
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        tableView.accessibilityIdentifier = "Login List"
        tableView.dataSource = loginDataSource
        tableView.delegate = self
        tableView.tableFooterView = UIView()

        KeyboardHelper.defaultHelper.addDelegate(self)

        profile.logins.getAllLogins().uponQueue(dispatch_get_main_queue()) { result in
            self.loginDataSource.cursor = result.successValue
            self.tableView.reloadData()
        }
    }
}

extension LoginListViewController: UITableViewDelegate {

    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Force the headers to be hidden
        return 0
    }

    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return LoginListUX.RowHeight
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let login = loginDataSource.loginAtIndexPath(indexPath)
        let detailViewController = LoginDetailViewController(profile: profile, login: login)
        navigationController?.pushViewController(detailViewController, animated: true)
    }
}

extension LoginListViewController: KeyboardHelperDelegate {
    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
    }

    func keyboardHelper(keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

/// Controller that handles interactions with the search widget and updating the data source for searching
private class LoginSearchController: NSObject, SearchInputViewDelegate {

    private let profile: Profile

    private var activeSearchDeferred: Success?

    private unowned let dataSource: LoginCursorDataSource

    private unowned let tableView: UITableView

    init(profile: Profile, dataSource: LoginCursorDataSource, tableView: UITableView) {
        self.profile = profile
        self.dataSource = dataSource
        self.tableView = tableView
        super.init()
    }

    @objc func searchInputView(searchView: SearchInputView, didChangeTextTo text: String) {
        searchLoginsWithText(text)
    }

    @objc func searchInputViewDidClose(searchView: SearchInputView) {
        activeSearchDeferred = profile.logins.getAllLogins()
            .bindQueue(dispatch_get_main_queue(), f: reloadTableWithResult)
    }

    private func searchLoginsWithText(text: String) -> Success {
        activeSearchDeferred = profile.logins.searchLoginsWithQuery(text)
            .bindQueue(dispatch_get_main_queue(), f: reloadTableWithResult)
        return activeSearchDeferred!
    }

    private func reloadTableWithResult(result: Maybe<Cursor<LoginData>>) -> Success {
        dataSource.cursor = result.successValue
        tableView.reloadData()
        activeSearchDeferred = nil
        return succeed()
    }
}

/// Data source for handling LoginData objects from a Cursor
private class LoginCursorDataSource: NSObject, UITableViewDataSource {

    var cursor: Cursor<LoginData>?

    func loginAtIndexPath(indexPath: NSIndexPath) -> LoginData {
        return loginsForSection(indexPath.section)[indexPath.row]
    }

    @objc func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sectionIndexTitles()?.count ?? 0
    }

    @objc func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return loginsForSection(section).count
    }

    @objc func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(LoginCellIdentifier, forIndexPath: indexPath) as! LoginTableViewCell

        let login = loginAtIndexPath(indexPath)
        cell.style = .IconAndBothLabels
        cell.updateCellWithLogin(login)
        return cell
    }

    @objc func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        return sectionIndexTitles()
    }

    @objc func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        guard let titles = sectionIndexTitles() where index < titles.count && index >= 0 else {
            return 0
        }
        return titles.indexOf(title) ?? 0
    }

    @objc func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionIndexTitles()?[section]
    }

    private func sectionIndexTitles() -> [String]? {
        guard cursor?.count > 0 else {
            return nil
        }

        var firstHostnameCharacters = [Character]()
        cursor?.forEach { login in
            guard let login = login, let baseDomain = login.hostname.asURL?.baseDomain() else {
                return
            }

            let firstChar = baseDomain.uppercaseString[baseDomain.startIndex]
            if !firstHostnameCharacters.contains(firstChar) {
                firstHostnameCharacters.append(firstChar)
            }
        }
        let sectionTitles = firstHostnameCharacters.map { String($0) }
        return sectionTitles.sort()
    }

    private func loginsForSection(section: Int) -> [LoginData] {
        guard let sectionTitles = sectionIndexTitles() else {
            return []
        }

        let titleForSectionAtIndex = sectionTitles[section]
        let logins = cursor?.filter { $0?.hostname.asURL?.baseDomain()?.uppercaseString.startsWith(titleForSectionAtIndex) ?? false }
        let flattenLogins = logins?.flatMap { $0 } ?? []
        return flattenLogins.sort { login1, login2 in
            let baseDomain1 = login1.hostname.asURL?.baseDomain()
            let baseDomain2 = login2.hostname.asURL?.baseDomain()
            let host1 = login1.hostname.asURL?.host
            let host2 = login2.hostname.asURL?.host

            if baseDomain1 == baseDomain2 {
                return host1 < host2
            } else {
                return baseDomain1 < baseDomain2
            }
        }
    }
}
