//
//  ViewController.swift
//  FaceDetectionExample
//
//  Created by Hyobin Kim on 25/07/2019.
//  Copyright © 2019 Imgbase. All rights reserved.
//

import UIKit
import AVKit
import Vision

class ViewController: UIViewController {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var previewViewAspect: NSLayoutConstraint!
    @IBOutlet weak var previewImageView: UIImageView!

    private var type: ExampleType = .faceDetectingInImage {
        didSet {
            switch type {
            case .faceDetectingInImage:
                initializedFaceDetectionInImage()
            case .objectTrackingInAVCaptureSession:
                initializedObjectTrackingInAVCaptureSesseion()
            case .faceDetectingInAVCaptureSession:
                initializedFaceDetectionInAVCaptureSession()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        type = .faceDetectingInAVCaptureSession
    }

    private func initializedFaceDetectionInImage() {
        guard let image = UIImage(named: "IMG_4794") else {
            return
        }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        let scaledHeight = view.frame.width / image.size.width * image.size.height
        imageView.frame = CGRect(origin: .zero, size: CGSize(width: view.frame.width, height: scaledHeight))
        view.addSubview(imageView)

        let request = VNDetectFaceRectanglesRequest { (req, error) in
            if let error = error {
                print("Failed to detect faces:", error)
                return
            }

            req.results?.forEach({ (res) in
                guard let faceObservation = res as? VNFaceObservation else {
                    return
                }
                print("faceObservation [\(faceObservation)]")
                let width = self.view.frame.width * faceObservation.boundingBox.width
                let height = scaledHeight * faceObservation.boundingBox.height
                let x = self.view.frame.width * faceObservation.boundingBox.origin.x
                let y = scaledHeight * (1.0 - faceObservation.boundingBox.minY) - height

                let redView = UIView()
                redView.backgroundColor = UIColor.red.withAlphaComponent(0.3)
                redView.frame = CGRect(x: x, y: y, width: width, height: height)
                self.view.addSubview(redView)
            })
        }
        guard let cgImage = image.cgImage else {
            return
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch let reqError {
            print("Failed to perform request:", reqError)
        }
    }

    private func initializedObjectTrackingInAVCaptureSesseion() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device) else {
                return
        }

        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        captureSession.addInput(input)
        captureSession.startRunning()

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = CGRect(origin: .zero, size: previewView.frame.size)
        previewView.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)

        previewView.isHidden = false
        previewImageView.isHidden = true
    }

    private func initializedFaceDetectionInAVCaptureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device) else {
                return
        }

        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        captureSession.addInput(input)
        captureSession.startRunning()

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = CGRect(origin: .zero, size: previewView.frame.size)
        self.previewLayer = previewLayer

        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)

        previewView.isHidden = true
        previewImageView.isHidden = false
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {


        switch type {
        case .objectTrackingInAVCaptureSession:
            captureOutputForObjectTracking(sampleBuffer: sampleBuffer)
        case .faceDetectingInAVCaptureSession:
            captureOutputForFaceDetecting(sampleBuffer: sampleBuffer)
        default:
            break
        }
    }

    private func captureOutputForObjectTracking(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        // https://developer.apple.com/machine-learning/
        guard let model = try? VNCoreMLModel(for: SqueezeNet().model) else {
            return
        }
        let request = VNCoreMLRequest(model: model) { (finishedReq, error) in
            guard let results = finishedReq.results as? [VNClassificationObservation],
                let first = results.first else {
                    return
            }
            print(first.identifier, first.confidence)
        }
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }

    private func captureOutputForFaceDetecting(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(CGImagePropertyOrientation.right)
        guard let cgImage = convertCIImageToCGImage(input: ciImage) else {
            return
        }

        DispatchQueue.main.async {
            self.previewImageView.image = UIImage(cgImage: cgImage)
            self.previewImageView.subviews.forEach({ (view) in
                view.removeFromSuperview()
            })
        }

        let request = VNDetectFaceRectanglesRequest { (req, error) in
            if let error = error {
                print("Failed to detect faces:", error)
                return
            }

            req.results?.forEach({ (res) in
                if let faceObservation = res as? VNFaceObservation {
                    DispatchQueue.main.async {
                        print("faceObservation [\(faceObservation)]")
                        let width = self.previewImageView.frame.width * faceObservation.boundingBox.width
                        let height = self.previewImageView.frame.height * faceObservation.boundingBox.height
                        let x = self.previewImageView.frame.width * faceObservation.boundingBox.origin.x
                        let y = self.previewImageView.frame.height * (1.0 - faceObservation.boundingBox.minY) - height

                        let redView = UIView()
                        redView.frame = CGRect(x: x, y: y, width: width, height: height)
                        redView.backgroundColor = UIColor.red.withAlphaComponent(0.3)
                        self.previewImageView.addSubview(redView)
                    }
                }
            })
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch let reqError {
            print("Failed to perform request:", reqError)
        }
    }
}

extension ViewController {
    func convertCIImageToCGImage(input: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        return context.createCGImage(input, from: input.extent)
    }
}

enum ExampleType {
    case faceDetectingInImage
    case objectTrackingInAVCaptureSession
    case faceDetectingInAVCaptureSession
}

