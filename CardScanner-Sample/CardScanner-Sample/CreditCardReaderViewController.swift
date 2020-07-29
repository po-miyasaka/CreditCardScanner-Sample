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
    private var roiFrame: CGRect?
    // このViewのレイヤーに、黒透明のViewにクレカの大きさにmaskされたレイヤーを乗せる
    @IBOutlet private weak var croppedView: UIView!

    // カメラとViewやOutputをつなげるセッション
    var session = AVCaptureSession()
    //　inputとなるカメラの情報,背面カメラとか。
    var videoDeviceInput: AVCaptureDeviceInput!
    //　カメラからinputした情報をアウトプットする場所に関する情報。この場合AVCaptureVideoDataOutputSampleBufferDelegateのメソッド
    var videoDeviceOutput: AVCaptureVideoDataOutput!
    typealias CardNumber = String
    var creditCardNumberCandidates: [CardNumber: Int] = [:]

    typealias ExpireDate = (String, String)
    var expireDateCandidates: [String: Int] = [:]

    var decidedExpireDate: ExpireDate? = nil
    var decidedCreditCardNumber: String? = nil

    typealias ReadCardInfoCompletion = ((CardNumber, ExpireDate) -> ())
    var readCardInfoCompletion: ReadCardInfoCompletion

    init(readCardInfoCompletion: @escaping ReadCardInfoCompletion) {
        self.readCardInfoCompletion = readCardInfoCompletion
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
    
    override func viewDidLayoutSubviews() {
        // 黒いきりぬきViewのセットアップ
        setupCroppedView()
    }
    
    func setupCroppedView() {
        guard roiFrame == nil else { return }
        let backLayer = CALayer()
        backLayer.frame = previewView.bounds
        backLayer.backgroundColor = UIColor.black.withAlphaComponent(0.8).cgColor

        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(roundedRect: creditCardFrameView.frame, cornerRadius: 10.0)

        path.append(UIBezierPath(rect: previewView.bounds))
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd

        backLayer.mask = maskLayer
        croppedView.layer.addSublayer(backLayer)

        let imageHeight: CGFloat = 1920
        let imageWidth: CGFloat = 1080

        let ratioHeight = imageHeight / previewView.frame.height
        let ratioWidth =  imageWidth / previewView.frame.width

        roiFrame = CGRect(x: creditCardFrameView.frame.origin.x * ratioWidth,
                               y: creditCardFrameView.frame.origin.y * ratioHeight,
                               width: creditCardFrameView.frame.width * ratioWidth,
                               height: creditCardFrameView.frame.height * ratioHeight)
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
        session.sessionPreset = .hd1920x1080

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
        videoDeviceOutput.connection(with: .video)?.videoOrientation = .portrait
        videoDeviceOutput.connections.forEach {
            $0.videoOrientation = .portrait
        }
        self.videoDeviceOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDeviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global())
        self.session.addOutput(self.videoDeviceOutput)
    }

    func setupPreview() {
        previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewView.session = session
        previewView.session?.connections.forEach {
            $0.videoOrientation = .portrait
        }

    }

    func setupBarButtonItem() {
        let barButtonItem =  UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.leftBarButtonItem = barButtonItem
    }

    

    @objc func cancel() {
        navigationController?.dismiss(animated: true, completion: nil)
    }

    let semaphore = DispatchSemaphore(value: 1)
//    ここにカメラ映像の情報が連続で渡される。
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){

//        処理を一つ一つすすめるため、排他制御（不要かも）
        semaphore.wait()
        defer {semaphore.signal()}

//        sampleBufferからCGImageをとりだすためのボイラープレート
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        guard let fullCameraImage = cgImage,
              let roiFrame = roiFrame,
            let croppedImage = fullCameraImage.cropping(to: roiFrame) else {
            return
        }


        let request = VNRecognizeTextRequest {[weak self] request, _ in
            guard let strongSelf = self else { return }
//            画像解析情報がここにわたされる。
             guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
             let recognizedText = observations
                .compactMap { $0.topCandidates(1).first?.string }.joined().split(separator: " ").joined()


            guard !recognizedText.isEmpty else { return }

//            クレカの有効期限を抽出
            if let expireDate = strongSelf.expireDateString(recognizedText) {
                let key = expireDate.0 + expireDate.1
                let count = strongSelf.expireDateCandidates[key] ?? 0
                strongSelf.expireDateCandidates[key] = count + 1
                if count > 2 {
                strongSelf.decidedExpireDate = expireDate
                }
            }

//            クレカのカード番号を抽出
            if let cardNum = strongSelf.cardNumber(recognizedText) {
                let key = cardNum
                let count = strongSelf.creditCardNumberCandidates[key] ?? 0
                strongSelf.creditCardNumberCandidates[key] = count + 1
                if count > 2 {
                strongSelf.decidedCreditCardNumber = cardNum
                }
            }

            if let dccn = strongSelf.decidedCreditCardNumber,
                let de = strongSelf.decidedExpireDate {
                DispatchQueue.main.async {
                    strongSelf.session.stopRunning()
                    strongSelf.readCardInfoCompletion(dccn, de)
                    strongSelf.dismiss(animated: true, completion: nil)

                }
            }
         }

        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: croppedImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
    }

    func expireDateString(_ string: String) -> ExpireDate? {
        guard let regex = try? NSRegularExpression(pattern: ".*(0[1-9]|1[0-2])\\/([1-2][0-9])") else {
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


    func cardNumber(_ string: String) -> CardNumber? {
        
        guard let regex = try? NSRegularExpression(pattern: "([0-9]{16})|(3[0-9]{14})") else {
            return nil
        }

        let result = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))

        return result.first.flatMap{ Range($0.range(at: 0), in: string) }.flatMap{String(string[$0])}
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

