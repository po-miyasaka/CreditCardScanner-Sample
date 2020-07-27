//
//  CreditCardReaderViewController.swift
//  Component
//
//  Created by miyasaka on 2020/07/26.
//

import UIKit
import AVKit
import Vision
import AVFoundation
import VideoToolbox

@available(iOS 13.0, *)
final class CreditCardReaderViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // カメラから見える景色を表示するView
    @IBOutlet private weak var previewView: PreviewView!
    // クレカの形の表す枠線のFrameを取得するためだけのView。
    @IBOutlet private weak var creditCardFrameView: UIView!
    // このViewのレイヤーに、黒透明のViewにクレカの大きさにmaskされたレイヤーを乗せる
    @IBOutlet private weak var croppedView: UIView!

    // カメラとViewやOutputをつなげるセッション
    var session = AVCaptureSession()
    //　inputとなるカメラの情報,背面カメラとか。
    var videoDeviceInput: AVCaptureDeviceInput!
    //　カメラからinputした情報をアウトプットする場所に関する情報。この場合AVCaptureVideoDataOutputSampleBufferDelegateのメソッド
    var videoDeviceOutput: AVCaptureVideoDataOutput!

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // キャンセルボタンの設定
        setupBarButtonItem()
        // カメラの許可をとって、其の結果しだいで動作をかえる。
        authoricationCamera { [weak self] authoriazed in
            guard let strongSelf = self else {
                return
            }
            guard authoriazed else {
                strongSelf.dismiss(animated: false, completion: nil)
                return
            }
            // 黒いきりぬきViewのセットアップ
            strongSelf.setupCroppedView()
            //　カメラセッションの設定を始める
            strongSelf.session.beginConfiguration()
            //　カメラセッションのインプットについての設定
            strongSelf.addInput()
            //　カメラセッションのアウトプットについての設定
            strongSelf.addOutput()
            //　これまでの設定を適用
            strongSelf.session.commitConfiguration()
            //　カメラからの映像をViewにも表示するための設定
            strongSelf.setupPreview()
            //　カメラセッションスタート
            strongSelf.session.startRunning()
        }
    }

    func setupCroppedView() {
        let backLayer = CALayer()
        backLayer.frame = view.bounds
        backLayer.backgroundColor = UIColor.black.withAlphaComponent(0.8).cgColor

        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(roundedRect: creditCardFrameView.frame, cornerRadius: 10.0)

        path.append(UIBezierPath(rect: view.bounds))
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd

        backLayer.mask = maskLayer
        croppedView.layer.addSublayer(backLayer)
    }

    func authoricationCamera(authorizedHandler: @escaping ((Bool) -> Void) ) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizedHandler(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                authorizedHandler(granted)
            })
        default:
            authorizedHandler(false)
        }
    }

    func addInput() {
        session.sessionPreset = .hd4K3840x2160

        var defaultVideoDevice: AVCaptureDevice?

        if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            defaultVideoDevice = dualCameraDevice
        } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            defaultVideoDevice = backCameraDevice
        } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            defaultVideoDevice = frontCameraDevice
        }

        guard let videoDevice = defaultVideoDevice,
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
            session.canAddInput(videoDeviceInput) else {
            return
        }
        session.addInput(videoDeviceInput)
    }

    func addOutput() {

        self.videoDeviceOutput = AVCaptureVideoDataOutput()
        self.videoDeviceOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDeviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global())
        self.session.addOutput(self.videoDeviceOutput)
    }

    func setupPreview() {
        previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewView.session = session
    }

    func setupBarButtonItem() {
        let barButtonItem =  UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: nil,
            action: #selector(dismiss(animated:completion:))
        )
        navigationItem.leftBarButtonItem = barButtonItem
    }

    let semaphore = DispatchSemaphore(value: 1)
//    ここにカメラ映像の情報が連続で渡される。
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){

//        処理を一つ一つすすめるため、排他制御（不要かも）
        semaphore.wait()

//        sampleBufferからCGImageをとりだすためのボイラープレート
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let fullCameraImage = cgImage else {
            return
        }

        let request = VNRecognizeTextRequest {[weak self] request, _ in
//            画像解析情報がここにわたされる。
             guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
             let recognizedText = observations
                 .compactMap { $0.topCandidates(1).first?.string }


            guard !recognizedText.isEmpty else { return }

//            クレカの有効期限を抽出
            let expirery = recognizedText.filter{ !$0.isEmpty }.compactMap {
                expireDateString($0)
            }
            print(expirery)
//            クレカのカード番号を抽出
            let cardNum = recognizedText.filter{ !$0.isEmpty }.compactMap {
                cardNumber($0)
            }
            print(cardNum)

            //　TODO:　複数回このハンドラーが呼ばれた後に、情報を精査して、さらに正しい情報を抽出する必要がある。


         }

        let handler = VNImageRequestHandler(cgImage: fullCameraImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }

        semaphore.signal()

    }
}

class PreviewView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        return layer
    }

    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}

func expireDateString(_ string: String) -> (String, String)? {
    guard let regex = try? NSRegularExpression(pattern: "^.*(0[1-9]|1[0-2])\\/([1-2][0-9])$") else {
        return nil
    }

    let result = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))

    if result.count == 0 {
        return nil
    }

    guard let nsrange1 = result.first?.range(at: 1),
        let range1 = Range(nsrange1, in: string) else { return nil }
    guard let nsrange2 = result.first?.range(at: 2),
        let range2 = Range(nsrange2, in: string) else { return nil }

    return (String(string[range1]), String(string[range2]))
}


func cardNumber(_ string: String) -> (String, String)? {
    // 調整中。
    guard let regex = try? NSRegularExpression(pattern: "    (?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|6011[0-9]{12}|3(?:0[0-5]|[68][0-9])[0-9]{11}|3[47]{13}|(?:2131|1800|35[0-9]{3})[0-9]{11})") else {
        return nil
    }

    let result = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))

    if result.count == 0 {
        return nil
    }

    guard let nsrange1 = result.first?.range(at: 1),
        let range1 = Range(nsrange1, in: string) else { return nil }
    guard let nsrange2 = result.first?.range(at: 2),
        let range2 = Range(nsrange2, in: string) else { return nil }

    return (String(string[range1]), String(string[range2]))
}
