import SpriteKit

/// One keyboard-driven menu: a title, an optional subtitle, and a list of
/// items. ↑/↓ (or W/S) move, Enter/Space choose, ←/→ adjust an item that
/// supports it, Esc goes back. Used for every menu in the game.
@MainActor
final class MenuNode: SKNode {
    struct Item {
        var title: () -> String
        var detail: String? = nil
        var adjust: ((Int) -> Void)? = nil     // ←/→ handler, e.g. player count
        var action: () -> Void

        init(_ title: String, detail: String? = nil, action: @escaping () -> Void) {
            self.title = { title }; self.detail = detail; self.action = action
        }
        init(dynamic title: @escaping () -> String, adjust: @escaping (Int) -> Void, action: @escaping () -> Void) {
            self.title = title; self.adjust = adjust; self.action = action
        }
    }

    private let items: [Item]
    private let onBack: (() -> Void)?
    private var selected: Int
    private let visibleRows = 8
    private var rows: [SKNode] = []
    private let highlight = SKShapeNode(rectOf: CGSize(width: 420, height: 34), cornerRadius: 10)
    private let rowHeight: CGFloat = 38
    private let listTop: CGFloat

    init(title: String, subtitle: String? = nil, items: [Item], selected: Int = 0,
         footer: String? = nil, onBack: (() -> Void)? = nil) {
        self.items = items
        self.onBack = onBack
        self.selected = min(selected, max(items.count - 1, 0))
        let shown = min(items.count, visibleRows)
        let height = 120 + CGFloat(shown) * rowHeight + (subtitle == nil ? 0 : 26) + (footer == nil ? 0 : 30)
        let midY = CGFloat(Units.screenH) / 2
        listTop = midY + height / 2 - 96 - (subtitle == nil ? 0 : 26)
        super.init()

        let panel = SKShapeNode(rectOf: CGSize(width: 500, height: height), cornerRadius: 18)
        panel.fillColor = NSColor(white: 0.03, alpha: 0.82)
        panel.strokeColor = NSColor(white: 1, alpha: 0.18)
        panel.lineWidth = 1.5
        panel.position = CGPoint(x: CGFloat(Units.screenW) / 2, y: midY)
        addChild(panel)

        let titleLabel = Self.label(title, size: 38, weight: "Heavy")
        titleLabel.fontColor = Art.color(0xFFD23F)
        titleLabel.position = CGPoint(x: CGFloat(Units.screenW) / 2, y: midY + height / 2 - 54)
        addChild(titleLabel)
        if let subtitle {
            let s = Self.label(subtitle, size: 14, weight: "DemiBold")
            s.fontColor = NSColor(white: 0.85, alpha: 1)
            s.position = CGPoint(x: CGFloat(Units.screenW) / 2, y: titleLabel.position.y - 30)
            addChild(s)
        }
        if let footer {
            let f = Self.label(footer, size: 12, weight: "DemiBold")
            f.fontColor = NSColor(white: 0.7, alpha: 1)
            f.position = CGPoint(x: CGFloat(Units.screenW) / 2, y: midY - height / 2 + 18)
            addChild(f)
        }
        highlight.fillColor = Art.color(0xFFD23F, 0.22)
        highlight.strokeColor = Art.color(0xFFD23F, 0.8)
        addChild(highlight)
        layoutRows()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func label(_ text: String, size: CGFloat, weight: String = "Bold") -> SKLabelNode {
        let l = SKLabelNode(text: text)
        l.fontName = "AvenirNext-\(weight)"
        l.fontSize = size
        l.fontColor = .white
        l.verticalAlignmentMode = .center
        return l
    }

    /// Scrolls so the selection stays visible, then redraws the rows.
    private func layoutRows() {
        rows.forEach { $0.removeFromParent() }
        rows.removeAll()
        let first = max(0, min(selected - visibleRows / 2, items.count - visibleRows))
        for (slot, i) in (first..<min(items.count, first + visibleRows)).enumerated() {
            let row = SKNode()
            row.position = CGPoint(x: CGFloat(Units.screenW) / 2, y: listTop - CGFloat(slot) * rowHeight)
            let title = Self.label(items[i].title(), size: 19, weight: i == selected ? "Heavy" : "DemiBold")
            if let detail = items[i].detail {
                title.horizontalAlignmentMode = .left
                title.position.x = -190
                let d = Self.label(detail, size: 13, weight: "Medium")
                d.horizontalAlignmentMode = .right
                d.position.x = 190
                d.fontColor = NSColor(white: 0.75, alpha: 1)
                row.addChild(d)
            }
            row.addChild(title)
            addChild(row)
            rows.append(row)
            if i == selected { highlight.position = row.position }
        }
        if items.count > visibleRows {
            let more = Self.label("\(selected + 1) / \(items.count)", size: 11)
            more.fontColor = NSColor(white: 0.6, alpha: 1)
            more.position = CGPoint(x: CGFloat(Units.screenW) / 2 + 220, y: listTop + 22)
            addChild(more)
            rows.append(more)
        }
    }

    /// ←/→ change the selected item, or else the menu's one adjustable item
    /// (so the player count can be changed from anywhere in level select).
    private var adjuster: ((Int) -> Void)? { items[selected].adjust ?? items.first { $0.adjust != nil }?.adjust }

    /// Returns true if the key was used.
    func handle(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 126, 13: selected = (selected - 1 + items.count) % items.count          // ↑ / W
        case 125, 1: selected = (selected + 1) % items.count                          // ↓ / S
        case 123, 0: adjuster?(-1)                                                     // ← / A
        case 124, 2: adjuster?(1)                                                      // → / D
        case 36, 49: items[selected].action(); return true                            // Enter / Space
        case 53: onBack?(); return true                                               // Esc
        default: return false
        }
        layoutRows()
        return true
    }
}
