import UIKit
import SceneKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var startStopButton: UIButton!

    private var isRecording = false
    private let customQueue = DispatchQueue(label: "com.example.ARKitRecording")

    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var videoOutputURL: URL?
    var fileURLs: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self

        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true

        // Create a new scene
        let scene = SCNScene()

        // Set the scene to the view
        sceneView.scene = scene
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's session
        sceneView.session.pause()
    }

    @IBAction func startStopButtonPressed(_ sender: UIButton) {
        if (self.isRecording == false) {
            // Start recording
            customQueue.async {
                if (self.createFiles()) {
                    DispatchQueue.main.async {
                        self.startStopButton.setTitle("Stop", for: .normal)
                    }
                    if let assetWriter = self.assetWriter, assetWriter.startWriting() {
                        assetWriter.startSession(atSourceTime: CMTime.zero)
                    }
                    self.isRecording = true
                } else {
                    self.errorMsg(msg: "Failed to create the file")
                    return
                }
            }
        } else {
            // Stop recording
            customQueue.async {
                self.isRecording = false

                if let assetWriter = self.assetWriter {
                    assetWriter.finishWriting {
                        if assetWriter.status == .completed {
                            // Video recording completed successfully
                            DispatchQueue.main.async {
                                let activityItems: [Any] = self.fileURLs + [self.videoOutputURL as Any]
                                let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                                self.present(activityVC, animated: true, completion: nil)
                            }
                        } else if assetWriter.status == .failed {
                            self.errorMsg(msg: "Failed to write video file: \(assetWriter.error?.localizedDescription ?? "")")
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.startStopButton.setTitle("Start", for: .normal)
            }
        }
    }

    private func createFiles() -> Bool {
        let timestamp = Date().timeIntervalSince1970
        let textFileName = "ARKit_text_\(timestamp).txt"
        let textFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(textFileName)

        // Generate sample text data
        let textData = "ARKit Recording Example\nTimestamp: \(timestamp)"

        // Write text data to file
        do {
            try textData.write(to: textFileURL, atomically: true, encoding: .utf8)
            self.fileURLs.append(textFileURL)
        } catch {
            errorMsg(msg: "Failed to create text file: \(error.localizedDescription)")
            return false
        }

        // Create video file
        let videoOutputFileName = "ARKit_video.mp4"
        let videoOutputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(videoOutputFileName)
        self.videoOutputURL = videoOutputURL

        do {
            assetWriter = try AVAssetWriter(outputURL: videoOutputURL, fileType: .mp4)
            let videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1080,
                AVVideoHeightKey: 1920,
            ]
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            if let videoInput = videoInput, assetWriter!.canAdd(videoInput) {
                assetWriter?.add(videoInput)
            } else {
                errorMsg(msg: "Failed to setup video input")
                return false
            }
        } catch {
            errorMsg(msg: "Failed to create asset writer: \(error.localizedDescription)")
            return false
        }

        return true
    }

    private func errorMsg(msg: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Error", message: msg, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }

    // ARSCNViewDelegate methods...

}
