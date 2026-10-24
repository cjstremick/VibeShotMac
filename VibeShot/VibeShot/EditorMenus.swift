import AppKit

/// Shared by the menu bar and the custom markup toolbar's overflow item.
enum EditorMenus {
    static func populateTools(_ menu: NSMenu, target: AnyObject? = nil) {
        for tool in MarkupTool.allCases {
            let item = NSMenuItem(title: tool.displayNameWithShortcut,
                                  action: #selector(MarkupEditorController.chooseTool(_:)), keyEquivalent: "")
            item.tag = tool.rawValue
            item.target = target
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let thickness = NSMenu(title: "Line Thickness")
        for value in MarkupLineThicknessManager.shared.availableThicknesses {
            let item = NSMenuItem(title: "\(Int(value)) pt", action: #selector(MarkupEditorController.chooseThickness(_:)), keyEquivalent: "")
            item.tag = Int(value * 10)
            item.target = target
            thickness.addItem(item)
        }
        let style = NSMenuItem(title: "Line Thickness", action: nil, keyEquivalent: "")
        style.submenu = thickness
        menu.addItem(style)
        let color = NSMenuItem(title: "Choose Color…", action: #selector(MarkupEditorController.chooseColor(_:)), keyEquivalent: "")
        color.target = target
        menu.addItem(color)
    }
}
