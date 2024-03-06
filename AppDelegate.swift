//
//  AppDelegate.swift
//  CodeScribe-Posture-5
//
//  Created by William Altmann on 3/4/24.
//

import UIKit
import Foundation
import Vision
import SwiftUI
import AVFoundation
import Combine

import CoreVideo
import CoreMedia

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

struct VideoDisplayView: UIViewRepresentable {
    var frame: CMSampleBuffer                           // parameters must appear in same sequence as in the call
    var bodyObservations: [VNHumanBodyPoseObservation]
    @ObservedObject var frameManager: FrameManager
    var videoSize: CGSize
    var screenSize: CGSize

    func makeUIView(context: Context) -> UIView {       // Required for UIViewRepresentable
        let imageView = UIImageView()
        var rotate : CGFloat
        var orientStr : String = ""
        
        imageView.frame = CGRect(x:0,y:0,width:UIScreen.main.bounds.width,height:UIScreen.main.bounds.height)
        
        imageView.contentMode = .scaleAspectFit
        //imageView.contentMode = .scaleAspectFill // does not work
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        imageView.layer.borderColor = UIColor.red.cgColor
        imageView.layer.borderWidth = 2
        
        switch UIDevice.current.orientation {
        case .portrait:
            rotate = .pi * 0.5
            orientStr = "Portrait"
        case .portraitUpsideDown:
            rotate = 0
            orientStr = "PortraitUpsideDown"
        case .landscapeLeft:
            rotate = .pi * 0.5
            orientStr = "LandscapeLeft"
        case .landscapeRight:
            rotate = .pi
            orientStr = "LandscapeRight"
        case .faceUp:
            rotate = .pi
            orientStr = "FaceUp"
        case .faceDown:
            rotate = .pi * 0.5
            orientStr = "FaceDown"
        case .unknown:
            rotate = .pi * 0.5
            orientStr = "Unknown"
        default:
            rotate = .pi * 1.5
            orientStr = "default"
        }
        imageView.transform = CGAffineTransform(rotationAngle:rotate)

        // Calculate the scaled size
        let widthRatio = screenSize.width / videoSize.width
        let heightRatio = screenSize.height / videoSize.height
        let ratio = min(widthRatio, heightRatio)
        let scaledSize = CGSize(width: videoSize.width * ratio, height: videoSize.height * ratio)

        print("VideoDisplayView.makeUIView started....")
        
        let x = (screenSize.width - scaledSize.width) / 2
        let y = (screenSize.height - scaledSize.height) / 2
        imageView.frame = CGRect(origin: CGPoint(x: x, y: y), size: scaledSize)

        let screenStr = String(format:"[%4.2f,%4.2f]",screenSize.width,screenSize.height)
        let videoStr  = String(format:"[%4.2f,%4.2f]",videoSize.width,videoSize.height)
        let scaledStr = String(format:"[%4.2f,%4.2f]",scaledSize.width,scaledSize.height)
        let imageStr  = String(format:"[%4.2f,%4.2f]",imageView.frame.width,imageView.frame.height)
        print(String(format:"\tVideoDisplayView.makeUIView:\n\tscreen%@\n\tvideo%@\n\tscaled%@\n\timage%@\n\torient[%@]",screenStr,videoStr,scaledStr,imageStr,orientStr))
        
        print(".....VideoDisplayView.makeUIView finished")
        return imageView
    }

    func updateUIView(_ uiView: UIView, context: Context) {        // Required for UIViewRepresentable
        guard let imageView = uiView as? UIImageView else { return }
        if let sampleBuffer = self.frameManager.currentFrame,
           let image = imageFromSampleBuffer(sampleBuffer) {
            imageView.image = image
        }
    }
    
}


func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return nil
    }

    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        return nil
    }

    return UIImage(cgImage: cgImage)
}
