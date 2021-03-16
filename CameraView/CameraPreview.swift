

import UIKit
import AVFoundation

public protocol CameraPreviewDelegate {
    func eyesClosed()
}

class CameraPreview: UIView {
    
    var delegate: CameraPreviewDelegate?
    
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    
    func clear() {
      leftEye = []
      rightEye = []
      
      DispatchQueue.main.async {
        self.setNeedsDisplay()
      }
    }
    

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    func viewRectConverted(fromNormalizedContentsRect normalizedRect: CGRect) -> CGRect {
        return previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect)
    }
    
    override func draw(_ rect: CGRect) {
      guard let context = UIGraphicsGetCurrentContext() else {
        return
      }

      context.saveGState()
      defer {
        context.restoreGState()
      }

      UIColor.red.setStroke()
      context.strokePath()
      UIColor.white.setStroke()

      if !leftEye.isEmpty {
        context.addLines(between: leftEye)
        context.closePath()
        context.strokePath()
      }

      if !rightEye.isEmpty {
        context.addLines(between: rightEye)
        context.closePath()
        context.strokePath()
      }
        
        if leftEye.isEmpty && rightEye.isEmpty {
            userBlinked()
        }
    }
    
    func userBlinked() {
        self.delegate?.eyesClosed()
    }
}
