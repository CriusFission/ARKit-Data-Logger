import UIKit
import SceneKit
import ARKit
import AVFoundation
import os.log

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var recordingButton: UIButton!
    @IBOutlet weak var updateRateLabel: UILabel!
    @IBOutlet weak var trackingStatusLabel: UILabel!
    @IBOutlet weak var worldMappingStatusLabel: UILabel!
    @IBOutlet weak var numberOfFeatureLabel: UILabel!

    private var isRecording = false
    private var videoStarted = false
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioRecorder: AVAudioRecorder?
    private var previousTimestamp = TimeInterval(0)
    private var customQueue = DispatchQueue(label: "com.example.recordingQueue")
    private var accumulatedPointCloud = PointCloud()

    private let ARKIT_CAMERA_POSE = "arkit_camera_pose.txt"
    private let ARKIT_POINT_CLOUD = "arkit_point_cloud.txt"

    private let videoOutputSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: UIScreen.main.bounds.size.width,
        AVVideoHeightKey: UIScreen.main.bounds.size.height
    ]

    private let mulSecondToNanoSecond = TimeInterval(1e9)

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.autoenablesDefaultLighting = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGestureRecognizer)
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

    @IBAction func recordingButtonTapped(_ sender: UIButton) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        let location = gesture.location(in: sceneView)
        let hitTestResults = sceneView.hitTest(location, types: [.existingPlaneUsingExtent])

        if let result = hitTestResults.first {
            addBox(to: result)
        }
    }

    private func addBox(to result: ARHitTestResult) {
        let boxGeometry = SCNBox(width: 0.2, height: 0.2, length: 0.2, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red
        boxGeometry.materials = [material]

        let boxNode = SCNNode(geometry: boxGeometry)
        boxNode.simdTransform = result.worldTransform
        sceneView.scene.rootNode.addChildNode(boxNode)
    }

    private func startRecording() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let videoPath = URL(fileURLWithPath: documentsPath).appendingPathComponent("video.mov")
        let audioPath = URL(fileURLWithPath: documentsPath).appendingPathComponent("audio.m4a")

        startAudioRecording(outputURL: audioPath)
        startVideoRecording(outputURL: videoPath)

        recordingButton.setTitle("Stop Recording", for: .normal)
        isRecording = true
    }

    private func stopRecording() {
        stopAudioRecording()
        stopVideoRecording()

        recordingButton.setTitle("Start Recording", for: .normal)
        isRecording = false

        mergeVideoAndAudio()
    }

    private func startVideoRecording(outputURL: URL) {
        guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            os_log("Failed to create video writer", log: .default, type: .error)
            return
        }

        guard let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings) else {
            os_log("Failed to create video writer input", log: .default, type: .error)
            return
        }

        if videoWriter.canAdd(videoWriterInput) {
            videoWriter.add(videoWriterInput)
        } else {
            os_log("Cannot add video writer input to video writer", log: .default, type: .error)
            return
        }

        self.videoWriter = videoWriter
        self.videoWriterInput = videoWriterInput

        videoStarted = false
    }

    private func stopVideoRecording() {
        videoWriterInput?.markAsFinished()

        videoWriter?.finishWriting { [weak self] in
            guard let self = self else {
                return
            }

            if let error = self.videoWriter?.error {
                self.errorMsg(msg: "Failed to finish writing video: \(error.localizedDescription)")
            }

            self.videoWriterInput = nil
            self.videoWriter = nil
        }
    }

    private func startAudioRecording(outputURL: URL) {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: outputURL, settings: audioSettings)
            audioRecorder?.record()
        } catch {
            errorMsg(msg: "Failed to start audio recording: \(error.localizedDescription)")
        }
    }

    private func stopAudioRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
    }

    private func mergeVideoAndAudio() {
        guard let videoURL = videoWriter?.outputURL else {
            errorMsg(msg: "Invalid video URL")
            return
        }

        guard let audioPath = audioRecorder?.url else {
            errorMsg(msg: "Invalid audio URL")
            return
        }

        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoURL)
        let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first

        let audioAsset = AVURLAsset(url: audioPath)
        let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first

        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: videoAsset.duration), of: videoAssetTrack!, at: .zero)
            try audioCompositionTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: audioAsset.duration), of: audioAssetTrack!, at: .zero)
        } catch {
            errorMsg(msg: "Failed to insert time range: \(error.localizedDescription)")
            return
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            errorMsg(msg: "Failed to create AVAssetExportSession")
            return
        }

        let outputURL = videoURL.deletingLastPathComponent().appendingPathComponent("merged_video.mov")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                DispatchQueue.main.async { [weak self] in
                    self?.showAlert(title: "Success", message: "Video and audio merged successfully")
                }
            case .failed:
                self.errorMsg(msg: "Failed to merge video and audio: \(exportSession.error?.localizedDescription ?? "")")
            case .cancelled:
                self.errorMsg(msg: "Merge video and audio export cancelled")
            default:
                break
            }
        }
    }

    private func errorMsg(msg: String) {
        os_log("%@", log: .default, type: .error, msg)
        DispatchQueue.main.async { [weak self] in
            self?.showAlert(title: "Error", message: msg)
        }
    }

    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if videoStarted {
            let timestamp = CFAbsoluteTimeGetCurrent()
            let deltaTime = timestamp - previousTimestamp
            previousTimestamp = timestamp

            updateRateLabel.text = String(format: "%.2f", 1 / deltaTime)
        }

        if isRecording {
            recordARFrame()
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARPlaneAnchor else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.trackingStatusLabel.text = "Detected a plane!"
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARPlaneAnchor else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.trackingStatusLabel.text = "Tracking plane..."
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARPlaneAnchor else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.trackingStatusLabel.text = "Plane removed!"
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let pointCloud = frame.rawFeaturePoints else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.numberOfFeatureLabel.text = "Number of feature points: \(pointCloud.points.count)"
        }

        accumulatedPointCloud.append(pointCloud)

        let currentTime = CFAbsoluteTimeGetCurrent()
        let deltaTime = currentTime - previousTimestamp
        previousTimestamp = currentTime

        guard deltaTime > 1 else {
            return
        }

        previousTimestamp = currentTime

        customQueue.async { [weak self] in
            self?.savePointCloud()
        }
    }

    private func recordARFrame() {
        guard let frame = sceneView.session.currentFrame else {
            return
        }

        guard let videoWriter = self.videoWriter, let videoWriterInput = self.videoWriterInput else {
            return
        }

        if !videoStarted {
            videoWriter.startWriting()
            videoWriter.startSession(atSourceTime: frame.timestamp)
            videoStarted = true
        }

        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let pixelBuffer = UnsafeMutablePointer<CVPixelBuffer>.allocate(capacity: 1)

        CVPixelBufferCreate(kCFAllocatorDefault, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA, nil, pixelBuffer)

        let ciContext = CIContext()
        ciContext.render(image, to: pixelBuffer)

        let frameTime = frame.timestamp - frame.displayTime
        let presentationTime = CMTime(seconds: frameTime, preferredTimescale: Int32(NSEC_PER_SEC))

        guard videoWriterInput.isReadyForMoreMediaData else {
            os_log("Not ready for video writer input data", log: .default, type: .info)
            return
        }

        if !videoWriterInput.append(CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, frame.camera), withPresentationTime: presentationTime) {
            os_log("Failed to append video writer input data", log: .default, type: .error)
        }

        pixelBuffer.deallocate()
    }

    private func savePointCloud() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            os_log("Failed to get documents path", log: .default, type: .error)
            return
        }

        let pointCloudPath = documentsPath.appendingPathComponent(ARKIT_POINT_CLOUD)

        let data = NSKeyedArchiver.archivedData(withRootObject: accumulatedPointCloud)
        do {
            try data.write(to: pointCloudPath)
        } catch {
            os_log("Failed to write point cloud data to file: %@", log: .default, type: .error, error.localizedDescription)
        }

        accumulatedPointCloud.points.removeAll()

        let cameraTransform = sceneView.session.currentFrame?.camera.transform ?? matrix_identity_float4x4

        let cameraTransformString = string(fromMatrix: cameraTransform)

        let cameraTransformPath = documentsPath.appendingPathComponent(ARKIT_CAMERA_POSE)

        do {
            try cameraTransformString.write(to: cameraTransformPath, atomically: true, encoding: .utf8)
        } catch {
            os_log("Failed to write camera transform to file: %@", log: .default, type: .error, error.localizedDescription)
        }
    }

    private func string(fromMatrix matrix: matrix_float4x4) -> String {
        let row1 = string(fromVector: matrix.columns.0)
        let row2 = string(fromVector: matrix.columns.1)
        let row3 = string(fromVector: matrix.columns.2)
        let row4 = string(fromVector: matrix.columns.3)

        return "\(row1)\n\(row2)\n\(row3)\n\(row4)"
    }

    private func string(fromVector vector: simd_float4) -> String {
        return "\(vector.x),\(vector.y),\(vector.z),\(vector.w)"
    }
}
