import UIKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var startButton: UIButton!
    @IBOutlet var stopButton: UIButton!
    
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var videoWriterAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var poseData: String?
    private var pointCloudData: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        let scene = SCNScene()
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    // Function to setup the video writer
    private func setupVideoWriter() {
        let outputSize = sceneView.bounds.size
        
        let videoFileName = "ARKit_video.mp4"
        let videoFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(videoFileName)
        
        do {
            videoWriter = try AVAssetWriter(url: videoFileURL, fileType: .mp4)
        } catch {
            print("Failed to create video writer: \(error)")
            return
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]
        
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]
        
        videoWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput!,
                                                                  sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        
        if let videoWriterInput = videoWriterInput, videoWriter!.canAdd(videoWriterInput) {
            videoWriter!.add(videoWriterInput)
        } else {
            print("Failed to add video writer input")
            return
        }
        
        if videoWriter!.startWriting() {
            videoWriter!.startSession(atSourceTime: .zero)
        } else {
            print("Failed to start video writer")
            return
        }
    }
    
    // Function to finish video export
    private func finishVideoExport() {
        guard let videoWriter = videoWriter,
              let videoWriterInput = videoWriterInput,
              let videoWriterAdaptor = videoWriterAdaptor else {
            return
        }
        
        videoWriterInput.markAsFinished()
        videoWriter.finishWriting {
            DispatchQueue.main.async {
                self.exportARData() // Export ARKit data after finishing video export
            }
        }
    }
    
    // Function to export ARKit data (pose and point cloud)
    private func exportARData() {
        // Export ARKit pose data
        if let poseData = self.poseData {
            let poseFileName = "ARKit_pose.txt"
            let poseFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(poseFileName)
            
            do {
                try poseData.write(to: poseFileURL, atomically: true, encoding: .utf8)
                print("ARKit pose data exported successfully")
            } catch {
                print("Failed to export ARKit pose data: \(error)")
            }
        }
        
        // Export ARKit point cloud data
        if let pointCloudData = self.pointCloudData {
            let pointCloudFileName = "ARKit_point_cloud.txt"
            let pointCloudFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(pointCloudFileName)
            
            do {
                try pointCloudData.write(to: pointCloudFileURL, atomically: true, encoding: .utf8)
                print("ARKit point cloud data exported successfully")
            } catch {
                print("Failed to export ARKit point cloud data: \(error)")
            }
        }
    }
    
    // ARSCNViewDelegate method for updating the scene
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if isRecording {
            recordFrame()
        }
    }
    
    // Function to record a video frame
    private func recordFrame() {
        guard let currentFrame = sceneView.session.currentFrame else {
            return
        }
        
        let pixelBuffer = currentFrame.capturedImage
        
        if let pixelBuffer = pixelBuffer {
            exportFrameAsVideoFrame(pixelBuffer)
        }
    }
    
    // Function to export a video frame as a pixel buffer
    private func exportFrameAsVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let videoWriter = videoWriter,
              let videoWriterInput = videoWriterInput,
              let videoWriterAdaptor = videoWriterAdaptor else {
            return
        }
        
        if videoWriterInput.isReadyForMoreMediaData {
            let frameTime = CMTimeMake(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000)
            videoWriterAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
        }
    }
    
    // Function to handle the button action
    @IBAction func startStopButtonPressed(_ sender: UIButton) {
        if isRecording {
            // Stop recording
            isRecording = false
            stopButton.setTitle("Start", for: .normal)
            stopButton.backgroundColor = UIColor.systemGreen
            
            finishVideoExport()
        } else {
            // Start recording
            isRecording = true
            startButton.setTitle("Stop", for: .normal)
            startButton.backgroundColor = UIColor.systemRed
            
            setupVideoWriter()
        }
    }
    
    // ARSessionDelegate method for tracking ARKit pose and point cloud
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Export ARKit pose and point cloud data
        let pose = frame.camera.transform
        let pointCloud = frame.rawFeaturePoints.points
        
        let poseString = "\(pose.columns.0.x),\(pose.columns.0.y),\(pose.columns.0.z),\(pose.columns.0.w),\(pose.columns.1.x),\(pose.columns.1.y),\(pose.columns.1.z),\(pose.columns.1.w),\(pose.columns.2.x),\(pose.columns.2.y),\(pose.columns.2.z),\(pose.columns.2.w),\(pose.columns.3.x),\(pose.columns.3.y),\(pose.columns.3.z),\(pose.columns.3.w)"
        let pointCloudString = pointCloud.map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: "|")
        
        self.poseData = poseString
        self.pointCloudData = pointCloudString
    }
}
