import Foundation
import IOKit

// TONY: Cache memory and GPU usage in RAMBarViewModel.
// TONY: Make refreshAllAsync vs refreshKeyStats

class RAMBarViewModel: ObservableObject {
    @Published var state = RAMBarState()
    @Published var isLoading = true
    @Published var isRefreshing = false

    init() {
        // Load full data in background on first open
        refreshAsync()
    }

    func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Get system memory (fast, no shell)
            let memory = MemoryMonitor.shared.getSystemMemory()

            // Get process data — single ps aux call, reused across all queries
            let processes = ProcessMonitor.shared.getProcessList()
            let apps = ProcessMonitor.shared.getAppMemory(from: processes)
            let claude = ProcessMonitor.shared.getClaudeSessions(from: processes)
            let python = ProcessMonitor.shared.getPythonProcesses(from: processes)
            let vscode = ProcessMonitor.shared.getVSCodeWorkspaces(from: processes)
            let chrome = ProcessMonitor.shared.getChromeTabs(from: processes)

            var newState = RAMBarState()
            newState.systemMemory = memory
            newState.apps = apps
            newState.claudeSessions = claude
            newState.pythonProcesses = python
            newState.vscodeWorkspaces = vscode
            newState.chromeTabs = chrome
            newState.lastUpdate = Date()
            newState.diagnostics = ProcessMonitor.shared.generateDiagnostics(state: newState)

            // Track memory history (last 30 readings)
            var history = self?.state.memoryHistory ?? []
            history.append(memory.usagePercent)
            if history.count > 30 { history.removeFirst(history.count - 30) }
            newState.memoryHistory = history

            DispatchQueue.main.async {
                self?.state = newState
                self?.isLoading = false
                self?.isRefreshing = false
            }
        }
    }
}

class GPUUsageProvider: ObservableObject {
    @Published var currentUsage: Double = 0.0
    @Published var usageHistory: [Double] = []
    
    private var usageHistorySize = 1
    //private var timer: Timer?
    init() {}
    
    public func setHistorySize(historySize: Int) {
        if (historySize >= 1) {
            usageHistorySize = historySize
        }
//        startMonitoring()
    }

//    func startMonitoring() {
//        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
//            self.currentUsage = self.getGPUUtilization()
//        }
//    }
    
    func getGPUUtilization() -> [Double] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                IOServiceMatching(kIOAcceleratorClassName),
                                                &iterator)
        
        if result != KERN_SUCCESS {
            return [0.0]
        }
        
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            
            var properties: Unmanaged<CFMutableDictionary>?
            let propertiesResult = IORegistryEntryCreateCFProperties(service, &properties,
                                                                   kCFAllocatorDefault, 0)
            
            if propertiesResult == KERN_SUCCESS,
               let props = properties?.takeRetainedValue() as? [String: Any],
               let stats = props["PerformanceStatistics"] as? [String: Any] {
                
                // Extract device utilization
                let utilization: Int? = stats["Device Utilization %"] as? Int ??
                                       stats["GPU Activity(%)"] as? Int ?? nil
                
                // Extract renderer utilization
//                    let renderer: Int? = stats["Renderer Utilization %"] as? Int ?? nil
//                    
//                    // Extract tiler utilization
//                    let tiler: Int? = stats["Tiler Utilization %"] as? Int ?? nil
                
                let deviceUtil = utilization.map { Double(min(max($0, 0), 100)) }
//                    let rendererUtil = renderer.map { Double(min(max($0, 0), 100)) }
//                    let tilerUtil = tiler.map { Double(min(max($0, 0), 100)) }
                
                usageHistory.append(deviceUtil! / 100.0)
                if usageHistory.count > usageHistorySize { usageHistory.removeFirst(usageHistory.count - usageHistorySize) }

                return usageHistory
            }
            
            service = IOIteratorNext(iterator)
        }
        
        return [0.0]
    }
}

