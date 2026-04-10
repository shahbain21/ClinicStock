//
//  CatalogSearchView.swift
//  ClinicStock
//
//

import SwiftUI
import AVFoundation

struct CatalogSearchView: View {

    @StateObject private var searchService = HCPCSSearchService()
    @State private var searchText = ""
    @State private var showScanner = false
    @State private var selectedItem: HCPCSCatalogItem? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    // GTIN confirmation flow
    @State private var pendingGTIN: String? = nil
    @State private var showGTINConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Search bar + scan button ──
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search by name or HCPCS code...", text: $searchText)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .onChange(of: searchText) { _, newValue in
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    guard !Task.isCancelled else { return }
                                    await searchService.search(query: newValue)
                                }
                            }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchService.results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                }
                .padding()

                // ── Loading indicator ──
                if !searchService.isLoaded {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading catalog...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // ── Results ──
                if searchService.isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if searchText.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Search by name or scan a barcode")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Text("\(searchService.isLoaded ? "96" : "...") items in catalog")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if searchService.results.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No results for \"\(searchText)\"")
                            .foregroundColor(.secondary)
                        Text("Try a different name or scan the barcode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(searchService.results, id: \.hcpcsCode) { item in
                        Button {
                            // If we have a pending GTIN, save it to this item
                            if let gtin = pendingGTIN {
                                Task {
                                    await searchService.confirmAndSaveGTIN(
                                        gtin: gtin,
                                        forItem: item
                                    )
                                    pendingGTIN = nil
                                }
                            }
                            selectedItem = item
                        } label: {
                            CatalogResultRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("DME Catalog")
            .navigationBarTitleDisplayMode(.large)

            // ── Barcode scanner ──
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { scannedValue in
                    showScanner = false
                    Task {
                        let result = await searchService.lookupBarcode(scannedValue)
                        switch result {
                        case .found(let item, _):
                            // Direct match — show item immediately
                            selectedItem = item

                        case .gtinNotFound(let gtin, _):
                            // GTIN not in catalog — save it pending confirmation
                            // Show search so staff can find and confirm the item
                            pendingGTIN = gtin
                            showGTINConfirmation = true

                        case .unrecognized:
                            // Barcode format not recognized
                            searchText = ""
                            searchService.results = []
                        }
                    }
                }
            }

            // ── GTIN confirmation banner ──
            .alert("Item Not Recognized", isPresented: $showGTINConfirmation) {
                Button("Search for it") {
                    // Clear search so staff can type the item name
                    searchText = ""
                    searchService.results = []
                }
                Button("Cancel", role: .cancel) {
                    pendingGTIN = nil
                }
            } message: {
                Text("This barcode isn't in the catalog yet. Search for the item by name and tap it to link this barcode automatically.")
            }

            // ── Item detail ──
            .sheet(item: $selectedItem) { item in
                CatalogItemDetailView(item: item)
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Result Row
// ══════════════════════════════════════════════════════

struct CatalogResultRow: View {
    let item: HCPCSCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.displayName)
                    .font(.headline)
                Spacer()
                Text(item.hcpcsCode)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
            }
            Text(item.shortClinicalName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(item.category)
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Item Detail
// ══════════════════════════════════════════════════════

struct CatalogItemDetailView: View {
    let item: HCPCSCatalogItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Code") {
                    HStack {
                        Text("HCPCS")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.hcpcsCode)
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Category")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.category)
                    }
                }

                Section("Clinical name") {
                    Text(item.clinicalName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Known as") {
                    ForEach(item.commonNames, id: \.self) { name in
                        Text(name.capitalized)
                            .font(.subheadline)
                    }
                }

                if let gtins = item.gtins, !gtins.isEmpty {
                    Section("Linked barcodes") {
                        ForEach(gtins, id: \.self) { gtin in
                            Text(gtin)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Barcode Scanner
// ══════════════════════════════════════════════════════

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
        setupCamera()
        addOverlay()
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
        captureSession?.stopRunning()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession?.canAddInput(input) == true
        else {
            showCameraError()
            return
        }

        captureSession?.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession?.canAddOutput(output) == true else { return }
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
        view.layer.addSublayer(previewLayer!)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    private func addOverlay() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
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
        captureSession?.stopRunning()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onScan?(value)
    }

    private func showCameraError() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func cancel() {
        captureSession?.stopRunning()
        dismiss(animated: true)
    }
}
