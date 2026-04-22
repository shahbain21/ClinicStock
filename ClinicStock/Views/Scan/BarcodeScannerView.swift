//
//  BarcodeScanner.swift
//  ClinicStock
//
//  Native AVFoundation barcode scanner wrapped as a SwiftUI view.
//
//  DEBUG LOGGING:
//  - Metadata callback now prints the raw scanned string plus the
//    detected type (EAN-13, Code 128, etc.) so we can diagnose when
//    a GS1-128 barcode gets read as its EAN-13 fallback vs. with
//    the full AI sequence. Only logged in DEBUG builds.
//

import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addOverlay()
        requestCameraAccessAndSetup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Camera authorization + setup
    // ══════════════════════════════════════════════════════

    private func requestCameraAccessAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.showPermissionError()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionError()
        @unknown default:
            showPermissionError()
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
              ),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession?.canAddInput(input) == true
        else {
            showCameraError()
            return
        }

        captureSession?.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession?.canAddOutput(output) == true else {
            showCameraError()
            return
        }
        captureSession?.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [
            .code128,
            .ean13,
            .ean8,
            .upce,
            .qr,
            .dataMatrix,
            .pdf417
        ]

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill

        if let preview = previewLayer {
            view.layer.insertSublayer(preview, at: 0)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Overlay (cutout + label + cancel)
    // ══════════════════════════════════════════════════════

    private func addOverlay() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)

        let scanWidth: CGFloat = 280
        let scanHeight: CGFloat = 160
        let scanX = (view.bounds.width - scanWidth) / 2
        let scanY = (view.bounds.height - scanHeight) / 2
        let scanRect = CGRect(x: scanX, y: scanY, width: scanWidth, height: scanHeight)

        let path = UIBezierPath(rect: view.bounds)
        let cutout = UIBezierPath(roundedRect: scanRect, cornerRadius: 12)
        path.append(cutout)
        path.usesEvenOddFillRule = true

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        overlay.layer.mask = maskLayer

        let borderView = UIView(frame: scanRect)
        borderView.layer.borderColor = UIColor.white.cgColor
        borderView.layer.borderWidth = 2
        borderView.layer.cornerRadius = 12
        borderView.backgroundColor = .clear
        borderView.isUserInteractionEnabled = false
        view.addSubview(borderView)

        let label = UILabel()
        label.text = "Align barcode within frame"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 16)
        ])

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            )
        ])
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Metadata delegate
    // ══════════════════════════════════════════════════════

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }

        hasScanned = true

        #if DEBUG
        // Log the raw captured value + type so we can diagnose when
        // a GS1-128 barcode gets read as its EAN-13 fallback.
        print("╔══════════════════════════════════════════════════════")
        print("║ [BarcodeScanner] scan captured")
        print("║   type:  \(object.type.rawValue)")
        print("║   value: \(value)")
        print("║   length: \(value.count) chars")
        // Show the raw bytes in case FNC1 or other non-printable
        // characters are present (they'd otherwise be invisible).
        let hexBytes = value.unicodeScalars.map {
            String(format: "%02X", $0.value)
        }.joined(separator: " ")
        print("║   bytes: \(hexBytes)")
        print("╚══════════════════════════════════════════════════════")
        #endif

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onScan?(value)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Error states
    // ══════════════════════════════════════════════════════

    private func showPermissionError() {
        showMessage(
            title: "Camera Access Denied",
            message: "Enable camera access in Settings to scan barcodes."
        )
    }

    private func showCameraError() {
        showMessage(
            title: "Camera Not Available",
            message: "The camera could not be started. Please try again."
        )
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func cancel() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
        dismiss(animated: true)
    }
}
