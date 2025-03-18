import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var menuBarViewModel = MenuBarViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Set initial icon
            button.image = createStatusIcon(isProcessing: false)
            // Enable layer-backing for animations
            button.wantsLayer = true
            // Setup click handling
            button.action = #selector(togglePopover)
            button.target = self
            
            // Add tooltip
            button.toolTip = "Transcription Status"
        }
        
        setupPopover()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 250, height: 120)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView(viewModel: menuBarViewModel)
        )
    }
    
    @objc private func togglePopover() {
        if let button = statusItem?.button {
            if let popover = popover {
                if popover.isShown {
                    popover.performClose(nil)
                } else {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        }
    }

    private func createStatusIcon(isProcessing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        
        let bounds = NSRect(x: 0, y: 0, width: 18, height: 18)
        
        // Draw background circle
        let circlePath = NSBezierPath(ovalIn: bounds)
        if isProcessing {
            NSColor.systemBlue.setFill()
        } else {
            NSColor.systemGray.setFill()
        }
        circlePath.fill()
        
        // Draw "T" letter in white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.white
        ]
        
        let text = "T"
        let textSize = text.size(withAttributes: attributes)
        let textPoint = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2
        )
        
        text.draw(at: textPoint, withAttributes: attributes)
        
        image.unlockFocus()
        return image
    }

    func updateMenuBarIcon(isProcessing: Bool, currentFileNames: [String]) {
        if let button = statusItem?.button {
            button.image = createStatusIcon(isProcessing: isProcessing)
            
            // Add a subtle animation if processing
            if isProcessing {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 1.0
                animation.toValue = 0.6
                animation.duration = 1.0
                animation.autoreverses = true
                animation.repeatCount = .infinity
                button.layer?.add(animation, forKey: "pulse")
            } else {
                button.layer?.removeAllAnimations()
            }
            
            // Update tooltip
            let fileList = currentFileNames.joined(separator: ", ")
            button.toolTip = isProcessing ? "Processing: \(fileList)" : "Idle"
            
            // Update ViewModel
            menuBarViewModel.isProcessing = isProcessing
            menuBarViewModel.currentFileNames = currentFileNames
            
            // Force UI Refresh by reopening popover if shown
            if popover?.isShown == true {
                popover?.performClose(nil)
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// SwiftUI ObservableObject for real-time updates
class MenuBarViewModel: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var currentFileNames: [String] = []
}

// SwiftUI MenuBarView
struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Status:")
                    .bold()
                Text(viewModel.isProcessing ? "Processing" : "Idle")
                    .foregroundColor(viewModel.isProcessing ? .blue : .gray)
            }

            if viewModel.isProcessing && !viewModel.currentFileNames.isEmpty {
                HStack {
                    Text("Files:")
                        .bold()
                    Text(viewModel.currentFileNames.joined(separator: ", "))
                        .lineLimit(1)
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
    }
}
