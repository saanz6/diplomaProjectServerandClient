//
//  FaceCameraView.swift
//  DiplomProjectToBook
//
//  Created by Sanzhar  Zhabagin  on 12.03.2026.
//

import SwiftUI
import AVFoundation
import Vision

struct FaceCameraView: UIViewControllerRepresentable {
    
    @Binding var capturedImage: UIImage?

    func makeUIViewController(context: Context) -> CameraController {
        let controller = CameraController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CameraControllerDelegate {

        var parent: FaceCameraView

        init(_ parent: FaceCameraView) {
            self.parent = parent
        }

        func didCapture(image: UIImage) {
            parent.capturedImage = image
        }

    }
}

protocol CameraControllerDelegate: AnyObject {
    func didCapture(image: UIImage)
}

class CameraController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    weak var delegate: CameraControllerDelegate?
    let faceFrameLayer = CAShapeLayer()
    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()
    let instructionLabel = UILabel()
    let captureButton = UIButton(type: .system)

    var faceDetected = false

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCamera()
        setupFaceFrame()
        instructionLabel.text = "Поместите лицо в рамку"
        instructionLabel.textAlignment = .center
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.boldSystemFont(ofSize: 18)

        instructionLabel.frame = CGRect(
            x: 20,
            y: 80,
            width: view.frame.width - 40,
            height: 40
        )

        view.addSubview(instructionLabel)
        setupButton()
    }
    func setupFaceFrame() {

        let width: CGFloat = 250
        let height: CGFloat = 320

        let rect = CGRect(
            x: view.frame.midX - width/2,
            y: view.frame.midY - height/2,
            width: width,
            height: height
        )

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)

        faceFrameLayer.path = path.cgPath
        faceFrameLayer.strokeColor = UIColor.systemGreen.cgColor
        faceFrameLayer.fillColor = UIColor.clear.cgColor
        faceFrameLayer.lineWidth = 3

        view.layer.addSublayer(faceFrameLayer)
    }
    
    func setupCamera() {

        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: camera)
        else { return }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video"))

        session.addOutput(output)

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds

        view.layer.addSublayer(previewLayer)

        session.startRunning()
    }

    func setupButton() {

        captureButton.setTitle("Сделать фото", for: .normal)
        captureButton.backgroundColor = .systemBlue
        captureButton.setTitleColor(.white, for: .normal)
        captureButton.layer.cornerRadius = 10

        captureButton.frame = CGRect(x: 40,
                                     y: view.frame.height - 120,
                                     width: view.frame.width - 80,
                                     height: 50)

        captureButton.isEnabled = false

        captureButton.addTarget(self,
                                action: #selector(capturePhoto),
                                for: .touchUpInside)

        view.addSubview(captureButton)
    }

    // MARK: Vision Face Detection

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { request, _ in

            guard let results = request.results as? [VNFaceObservation] else { return }

            DispatchQueue.main.async {

                self.faceDetected = !results.isEmpty
                self.captureButton.isEnabled = self.faceDetected

                if self.faceDetected {
                    self.faceFrameLayer.strokeColor = UIColor.systemGreen.cgColor
                    self.instructionLabel.text = "Лицо обнаружено"
                } else {
                    self.faceFrameLayer.strokeColor = UIColor.systemRed.cgColor
                    self.instructionLabel.text = "Поместите лицо в рамку"
                }

            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)

        try? handler.perform([request])
    }

    // MARK: Capture Photo

    @objc func capturePhoto() {

        let settings = AVCapturePhotoSettings()
        let photoOutput = AVCapturePhotoOutput()

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

}

extension CameraController: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        delegate?.didCapture(image: image)

        dismiss(animated: true)
    }

}
