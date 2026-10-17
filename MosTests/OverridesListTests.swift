//
//  OverridesListTests.swift
//  MosTests
//
//  覆盖设置列表: 代码创建的启用开关列
//

import XCTest
@testable import Mos_Debug

final class OverridesListTests: XCTestCase {

    private let testPath = "/Applications/OverridesListTest.app"

    override func tearDown() {
        Options.shared.application.applications.remove(from: testPath)
        super.tearDown()
    }

    func testEnabledColumnShowsCheckboxForEachRow() {
        Options.shared.application.applications.append(Application(path: testPath))
        let controller = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.application) as PreferencesApplicationViewController
        _ = controller.view
        let tableView: NSTableView = controller.tableView
        tableView.reloadData()

        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("enabledCell"))
        XCTAssertEqual(column, 0, "the enable checkbox is the first column")
        let row = Options.shared.application.applications.count - 1
        let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: true)
        let checkBox = cell?.subviews.first as? NSButton
        XCTAssertNotNil(checkBox, "every row must show its enable checkbox")
        XCTAssertEqual(checkBox?.state, .on)
    }
}
