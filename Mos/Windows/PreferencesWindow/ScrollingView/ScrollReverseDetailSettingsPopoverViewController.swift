import Cocoa

class ScrollReverseDetailSettingsPopoverViewController: AdaptivePopover, ScrollOptionsContextProviding {

    @IBOutlet weak var verticalReverseCheckBox: NSButton?
    @IBOutlet weak var horizontalReverseCheckBox: NSButton?

    var currentTargetApplication: Application?
    var currentTargetDevice: ScrollDevice?
    var onOptionsChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        syncViewWithOptions()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncViewWithOptions()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    @IBAction func verticalReverseToggle(_ sender: NSButton) {
        updateScrollOptions([.reverse]) { $0.reverseVertical = sender.state == .on }
        syncViewWithOptions()
        onOptionsChanged?()
    }

    @IBAction func horizontalReverseToggle(_ sender: NSButton) {
        updateScrollOptions([.reverse]) { $0.reverseHorizontal = sender.state == .on }
        syncViewWithOptions()
        onOptionsChanged?()
    }

    private func syncViewWithOptions() {
        let scroll = getTargetApplicationScrollOptions()
        updateReverseDependentControl(verticalReverseCheckBox, isOn: scroll.reverseVertical)
        updateReverseDependentControl(horizontalReverseCheckBox, isOn: scroll.reverseHorizontal)
    }
}
