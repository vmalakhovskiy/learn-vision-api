

import UIKit
import AVFoundation
import Vision

enum AppError: Error {
    case captureSessionSetup(reason: String)
    case visionError(error: Error)
    case otherError(error: Error)
    
    static func display(_ error: Error, inViewController viewController: UIViewController) {
        if let appError = error as? AppError {
            appError.displayInViewController(viewController)
        } else {
            AppError.otherError(error: error).displayInViewController(viewController)
        }
    }
    
    func displayInViewController(_ viewController: UIViewController) {
        let title: String?
        let message: String?
        switch self {
        case .captureSessionSetup(let reason):
            title = "AVSession Setup Error"
            message = reason
        case .visionError(let error):
            title = "Vision Error"
            message = error.localizedDescription
        case .otherError(let error):
            title = "Error"
            message = error.localizedDescription
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        viewController.present(alert, animated: true, completion: nil)
    }
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var cameraView: CameraPreview = CameraPreview()

    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var firstFrame = true
    
    @IBOutlet weak var timePassedLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    
    ///Time elapsed in seconds
    var timeElapsed: Double = 0 {
        didSet {
            ///Needs support for human readable minute, etc...?
            timePassedLabel.text = String(Int(timeElapsed.rounded()))
            if(timeElapsed.rounded() == 0) {
                timePassedLabel.isHidden = true
            }else {
                timePassedLabel.isHidden = false
            }
        }
    }
    
    var timer = Timer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(cameraView)
        view.sendSubviewToBack(cameraView)
        cameraView.frame = view.bounds
        cameraView.autoresizingMask = [.flexibleRightMargin, .flexibleLeftMargin, .flexibleBottomMargin, .flexibleTopMargin]
        cameraView.delegate = self
    }
    
    func startTimer() {
        if(timer.isValid == false) {
            startButton.isHidden = true
            timeElapsed = 0
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.incrementTimer), userInfo: nil, repeats: true)
        }
    }
    
    func stopTimer() {
        if(timer.isValid == true) {
            timePassedLabel.text = "Score: \(String(Int(timeElapsed.rounded())))"
            startButton.isHidden = false
            timer.invalidate()
        }
    }
    
    func resetTimer() {
        if(timer.isValid == true) {
            timeElapsed = 0
        }
    }
    
    @objc func incrementTimer() {
        timeElapsed += 1
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            if cameraFeedSession == nil {
                cameraView.previewLayer.videoGravity = .resizeAspectFill
                try setupAVSession()
                cameraView.previewLayer.session = cameraFeedSession
            }
            cameraFeedSession?.startRunning()
            
        } catch {
            AppError.display(error, inViewController: self)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        cameraFeedSession?.stopRunning()
        super.viewWillDisappear(animated)
    }
    
    func setupAVSession() throws {
        // Select a front facing camera, make an input.
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw AppError.captureSessionSetup(reason: "Could not find a front facing camera.")
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            throw AppError.captureSessionSetup(reason: "Could not create video device input.")
        }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.high
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            throw AppError.captureSessionSetup(reason: "Could not add video device input to the session")
        }
        session.addInput(deviceInput)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            // Add a video data output.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            throw AppError.captureSessionSetup(reason: "Could not add video data output to the session")
        }
        session.commitConfiguration()
        cameraFeedSession = session
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer)
        let detectFaceRequest = VNDetectFaceLandmarksRequest(completionHandler: detectedFace)
        
        do {
            try handler.perform([detectFaceRequest])
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func detectedFace(request: VNRequest, error: Error?) {
        
        guard
            let results = request.results as? [VNFaceObservation],
            let result = results.first
        else {
            
            cameraView.clear()
            return
        }
        
        DispatchQueue.main.async {
            self.updateFaceView(for: result)
        }
    }
    
    func updateFaceView(for result: VNFaceObservation) {
        defer {
            DispatchQueue.main.async {
                self.cameraView.setNeedsDisplay()
            }
        }
        guard let landmarks = result.landmarks else {
            return
        }
        if let leftEye = landmark(
            points: landmarks.leftEye?.normalizedPoints,
            to: result.boundingBox) {
            cameraView.leftEye = leftEye
            //visualizePoints(points: leftEye)
            ///Open is around 13
            print("Left Eye diff: \(leftEye[5].y - leftEye[1].y)")
            if(timer.isValid == true && (leftEye[5].y - leftEye[1].y) <= 5) {
                stopTimer()
            }
        }
        if let rightEye = landmark(
            points: landmarks.rightEye?.normalizedPoints,
            to: result.boundingBox) {
            cameraView.rightEye = rightEye
            //visualizePoints(points: rightEye)
            print("Right Eye diff: \(rightEye[5].y - rightEye[1].y)")
            if(timer.isValid == true && (rightEye[5].y - rightEye[1].y) <= 5) {
                stopTimer()
            }
        }
    }
    
    func visualizePoints(points: [CGPoint]) {
        if let subLayers = view.layer.sublayers {
            for x in subLayers {
                if(x is CAShapeLayer) {
                    x.removeFromSuperlayer()
                }
            }
        }
        for x in points {
            let path = UIBezierPath(arcCenter: x, radius: 5, startAngle: 0, endAngle: 1, clockwise: false)
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            shapeLayer.fillColor = UIColor.systemOrange.cgColor
            view.layer.addSublayer(shapeLayer)
        }
    }
    
    func landmark(point: CGPoint, to rect: CGRect) -> CGPoint {
        let absolute = point.absolutePoint(in: rect)
        
        let converted = cameraView.previewLayer.layerPointConverted(fromCaptureDevicePoint: absolute)
        
        return converted
    }
    
    func landmark(points: [CGPoint]?, to rect: CGRect) -> [CGPoint]? {
        guard let points = points else {
            return nil
        }
        
        return points.compactMap { landmark(point: $0, to: rect) }
    }
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .downMirrored
            
        case .landscapeRight:
            return .upMirrored
            
        default:
            return .leftMirrored
        }
    }
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    
    // MARK: - Actions
    
    @IBAction func startTapped(_ sender: Any) {
        startTimer()
    }
    
}

extension CGPoint {
    func absolutePoint(in rect: CGRect) -> CGPoint {
        return CGPoint(x: x * rect.size.width, y: y * rect.size.height) + rect.origin
    }
}

func + (left: CGPoint, right: CGPoint) -> CGPoint {
  return CGPoint(x: left.x + right.x, y: left.y + right.y)
}

extension CameraViewController: CameraPreviewDelegate {
    
    func eyesClosed() {
        self.resetTimer()
    }
}
