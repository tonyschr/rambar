import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var updateTimer: Timer?
    private var lastMemoryWarningTime: Date?
    private var viewModel: RAMBarViewModel!
    private var gpuUsageProvider = GPUUsageProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Show elided "..." initially until memory data is available
            button.title = "…"
        }

        // Create view model and popover
        viewModel = RAMBarViewModel()
        let view = ContentView(viewModel: viewModel)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: view)

        // TONY: 5s --> 2s
        // Start update timer — 2s is responsive enough for a menu bar icon
        // Also updates popover content when visible
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusButton()
            self?.checkMemoryPressure()
            
            // Refresh popover content if it's visible
            if self?.popover.isShown == true {
                self?.viewModel.refreshAsync()
            }
        }
        RunLoop.main.add(updateTimer!, forMode: .common)

        // Delay first update so user sees "Loading..." briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateStatusButton()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Trigger an immediate refresh when opening
            viewModel.refreshAsync()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure popover window is key
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let memory = MemoryMonitor.shared.getSystemMemory()
        let percent = Int(memory.usagePercent)
        
        let gpuPercent = gpuUsageProvider.getGPUUtilization()
        //print("GPU: \(gpuPercent)")

        let symbolName: String
        let color: NSColor

        switch memory.status {
        case .nominal:
            symbolName = "memorychip"
            color = NSColor.systemGreen
        case .warning:
            symbolName = "memorychip.fill"
            color = NSColor.systemOrange
        case .critical:
            symbolName = "memorychip.fill"
            color = NSColor.systemRed
        }

        gpuUsageProvider.setHistorySize(historySize: 22)
        let chipSize = NSSize(width: 22, height: 22)
        let gpuSize = NSSize(width: 22, height: 22)
        let spacerWidth = 4.0
        let mysteryPadding = 8.0
        // print(chipSize.width + spacerWidth + gpuSize.width)
        let compositeImageSize = NSSize(
            width:  chipSize.width + spacerWidth + gpuSize.width + mysteryPadding,
            height: chipSize.height
        )

        let compositeImage = NSImage(size: compositeImageSize, flipped: false) { rect in
            // Draw the chip symbol scaled to fill the image
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            var symSize = NSSize()
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tinted = symbol.tinted(with: color)
                // Center the stimeymbol within our canvas
                symSize = tinted.size
                let symRect = NSRect(
                    x: 0,
                    y: (rect.height - symSize.height) / 2,
                    width: symSize.width,
                    height: symSize.height
                )
                tinted.draw(in: symRect)
            }

            // Overlay the percentage text, centered within the chip
            let text = "\(percent)%"
            let fontSize: CGFloat = percent >= 100 ? 5.5 : 6.5
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)

            // Use white for filled (warning/critical) states, color for nominal
            let textColor: NSColor = (symbolName == "memorychip.fill")
                ? NSColor.white
                : color

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let textSize = attrStr.size()
            let textRect = NSRect(
                x: (symSize.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attrStr.draw(in: textRect)
            
            NSColor.lightGray.set()
            
            let gpuBackground = NSRect(
                x: symSize.width + spacerWidth,
                y: 0,
                width: gpuSize.width,
                height: gpuSize.height
            )
            
            let gpuBackgroundPath = NSBezierPath(rect: gpuBackground)

            let transparentBlueBackground = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.4)
            transparentBlueBackground.set()
            gpuBackgroundPath.fill()   // Use .fill() for a solid block, or .stroke() for an outline

            // TONY: Rewrite to make more the +1 -2 offsets for the border
            NSColor.systemBlue.setStroke()
            let xOffset = Int(symSize.width + spacerWidth)
            let histogramCount = max(0, gpuPercent.count - 1)
            for  index in 0...histogramCount {
                let percent: Int = Int(gpuPercent[index] * gpuSize.height)
                NSBezierPath.strokeLine(from: NSPoint(x: xOffset + index, y: 0), to: NSPoint(x: xOffset + index, y: percent))
            }

            let transparentBlueBorder = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.7)
            transparentBlueBorder.set()
            gpuBackgroundPath.stroke()

            // TONY: For debugging of mysteryPadding.
            // NSColor.yellow.setStroke()
            // NSBezierPath.strokeLine(from: NSPoint(x: xOffset + 22, y: 0), to: NSPoint(x: xOffset + 22, y: percent))

            return true
        }

        compositeImage.isTemplate = false
        
        let attachment = NSTextAttachment()
        attachment.image = compositeImage
        attachment.bounds = NSRect(
            x: 0,
            y: (NSFont.systemFont(ofSize: NSFont.systemFontSize).capHeight - chipSize.height) / 2,
            width: compositeImageSize.width,
            height: compositeImageSize.height
        )

        let combined = NSMutableAttributedString()
        combined.append(NSAttributedString(attachment: attachment))
        button.attributedTitle = combined
    }

    
    private func checkMemoryPressure() {
        let memory = MemoryMonitor.shared.getSystemMemory()

        // Send warning if above 85% and not warned in last 5 minutes
        if memory.usagePercent >= 85 {
            let now = Date()
            if lastMemoryWarningTime == nil || now.timeIntervalSince(lastMemoryWarningTime!) > 300 {
                CrashDetector.shared.sendMemoryWarning(usagePercent: memory.usagePercent)
                lastMemoryWarningTime = now
            }
        }
    }
}

// Helper to tint NSImage
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
