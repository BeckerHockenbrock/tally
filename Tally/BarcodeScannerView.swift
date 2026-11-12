import SwiftUI
import VisionKit
import Vision
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var ready = false
    @State private var message: String?
    let onBarcode: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if ready && scenePhase == .active {
                    LiveBarcodeScanner(onBarcode: { code in
                        ready = false
                        onBarcode(code)
                        dismiss()
                    }, onError: { error in
                        ready = false
                        message = error
                    })
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "barcode.viewfinder").font(.largeTitle)
                        Text(message ?? "Preparing camera…").multilineTextAlignment(.center)
                        if AVCaptureDevice.authorizationStatus(for: .video) == .denied,
                           let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: settings)
                        }
                        Button("Enter Barcode Manually") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { ready = false; dismiss() }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { ready = false; return }
                await prepareCamera()
            }
        }
    }

    @MainActor
    private func prepareCamera() async {
        guard DataScannerViewController.isSupported else {
            message = "Camera scanning is not supported here. Enter the barcode manually, including in Simulator."
            return
        }
        var permission = AVCaptureDevice.authorizationStatus(for: .video)
        if permission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            permission = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard !Task.isCancelled else { return }
        guard permission == .authorized else {
            message = "Camera access is denied or restricted. Enable it in Settings or enter the barcode manually."
            return
        }
        guard DataScannerViewController.isAvailable else {
            message = "The scanner is currently unavailable. Try again or enter the barcode manually."
            return
        }
        message = nil
        ready = true
    }
}

private struct LiveBarcodeScanner: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode, onError: onError) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // Vision reports UPC-A as EAN-13 with a leading zero.
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        context.coordinator.startTask = Task { @MainActor [weak scanner, weak coordinator = context.coordinator] in
            await Task.yield()
            guard !Task.isCancelled, let scanner, let coordinator else { return }
            do { try scanner.startScanning() }
            catch { coordinator.onError("Could not start the scanner. " + error.localizedDescription) }
        }
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        coordinator.startTask?.cancel()
        controller.stopScanning()
        controller.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var startTask: Task<Void, Never>?
        var gate = BarcodeScanGate()
        let onBarcode: (String) -> Void
        let onError: (String) -> Void

        init(onBarcode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
            self.onError = onError
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            receive(items, scanner: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate items: [RecognizedItem], allItems: [RecognizedItem]) {
            receive(items, scanner: scanner)
        }

        private func receive(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            for item in items {
                guard case .barcode(let barcode) = item, var code = barcode.payloadStringValue else { continue }
                if barcode.observation.symbology == .upce {
                    guard let expanded = FoodBarcode.expandUPCE(code) else { continue }
                    code = expanded
                }
                guard gate.accept(code) else { continue }
                scanner.stopScanning()
                onBarcode(code)
                break
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            scanner.stopScanning()
            onError("Scanning became unavailable. " + error.localizedDescription)
        }
    }
}
