//
//  MovieFileManager2.swift
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

//----------------------------------------------------------------------------------------
// Handle frame input from either a movie file or live camera feed.
//----------------------------------------------------------------------------------------

enum VideoFrameSource {
    case liveCamera
    case movieFile
}

// Global variable to select the source
var frameSource: VideoFrameSource = .movieFile  // input movie file
var frameCount: Int = 0

class FrameManager: ObservableObject {
    @Published var currentFrame: CMSampleBuffer? {
        didSet {
            updateElapsedTime()
        }
    }
    @Published var videoSize: CGSize?  // Add this to store video dimensions
    @Published var frameCount: Int = 0
    @Published var elapsedTime: Double = 0
    @Published var prevElapsedTime: Double = 0
    @Published var videoTime: Double = 0
    @Published var frameRate: Double = 0
    @Published var frameSize: CGSize = CGSize(width:1920,height:1080)
    
    var startTime: Date?
    
    let showGrid : Bool = false
    
    private func updateElapsedTime() {
        guard let currentFrame = currentFrame else { return }

        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        let prevElapsed = self.elapsedTime
        DispatchQueue.main.async {
            self.elapsedTime = elapsed
            self.prevElapsedTime = prevElapsed
            self.videoTime = self.videoTime + (1.0 / self.frameRate)
        }
    }
    
    func startProcessing() {
        resetTimer()
        // Other start processing logic...
    }
    
    func resetTimer() {
        startTime = Date()
    }

}

//----------------------------------------------------------------------------------------------------------
//----------------------------------------------------------------------------------------------------------
class MovieFileManager {
    @Published var currentFrame: CMSampleBuffer?
    private var assetReader: AVAssetReader?
    private let videoOutputQueue = DispatchQueue(label: "VideoOutputQueue")
    private var asset: AVAsset?
    private var videoTrack: AVAssetTrack?
    private var videoURL: URL  // Store the video URL
    private var videoOrientation: UIImage.Orientation?
    private var processedImage: UIImage? = nil

    var frameManager: FrameManager
    var onReadyToRead: (() -> Void)?

    //------------------------------------------------------------------------------------------------------
    // init
    //------------------------------------------------------------------------------------------------------
    init(url: URL, frameManager: FrameManager) {
        print("MovieFileManager.init begins....")
        print("\tMovieFileManager.init.frameManager: \(ObjectIdentifier(frameManager))")
        self.videoURL = url                       // Assign the URL to the property
        self.frameManager = frameManager
        self.asset = AVAsset(url: url)
        
        self.asset?.loadTracks(withMediaType: .video) { [weak self] tracks, error in
            print("\tMovieFileManager.init: attempt to loadTracks...")
            guard let self = self else {
                print("\tMovieFileManager.init self-self fails")
                return
            }

            print("\tMovieFileManager.init: succeeded at 'self = self'. Attempt videoTrack = tracks?.first....")
            if let videoTrack = tracks?.first {
                print("\tMovieFileManager.init: succeeded at videoTrack = tracks?.first")
                self.videoTrack = videoTrack
                let (vOrientation,isPortrait) = determineVideoOrientation(from: videoTrack)
                self.videoOrientation = vOrientation
                if isPortrait {
                    print("\tMovieFileManager.init video is portrait orientation")
                }
                else {
                    print("\tMovieFileManager.init video is not portrait orientation")
                }
                
                self.frameManager.frameRate = Double(videoTrack.nominalFrameRate)
                self.frameManager.videoSize = videoTrack.naturalSize

                do {
                    self.assetReader = try AVAssetReader(asset: self.asset!)
                    self.setupReader(with: videoTrack)
                    // Call the onReadyToRead callback here, after the asset reader is set up
                    self.onReadyToRead?()
                } catch {
                    print("Error initializing AVAssetReader: \(error)")
                }
            } else {
                print("Error: No video tracks found")
            }
        }
        print("...MovieFileManager.init completes")
    }

    //------------------------------------------------------------------------------------------------------
    // setupReader
    //------------------------------------------------------------------------------------------------------
    private func setupReader(with videoTrack: AVAssetTrack) {
        print("MovieFileManager.setupReader() begins....")
        do {
            self.assetReader = try AVAssetReader(asset: self.asset!)
            let outputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            if assetReader!.canAdd(readerOutput) {
                print("\tMovieFileManager.setupReader succeeds at assetReader!.canAdd")
                assetReader!.add(readerOutput)
            } else {
                print("Couldn't add reader output")
            }
        } catch {
            print("\tMovieFileManager.setupReader Error initializing AVAssetReader: \(error)")
        }
        
        if NSClassFromString("VNImageRequestHandler") != nil {
            print("MovieFileManager.setupReader(): Vision framework is available")
        } else {
            print("MovieFileManager.setupReader(): Vision framework is not available")
        }

        self.frameManager.startProcessing()
        
        print("MovieFileManager.setupReader() finishes....")
    }

    //------------------------------------------------------------------------------------------------------
    // startReading
    //
    // Add detection of human body and mapping of skeleton onto the video frame
    //------------------------------------------------------------------------------------------------------
    func startReading(completion: @escaping (CMSampleBuffer?) -> Void) {
        guard let assetReader = self.assetReader, assetReader.status != .reading else {
            print("AssetReader not ready or already reading")
            return
        }

        assetReader.startReading()

        videoOutputQueue.async {
            while assetReader.status == .reading {
                if let sampleBuffer = assetReader.outputs.first?.copyNextSampleBuffer() {
                    self.processFrame(sampleBuffer: sampleBuffer) { modifiedBuffer in
                        DispatchQueue.main.async {
                            self.frameManager.currentFrame = modifiedBuffer
                            self.frameManager.frameCount += 1
                            completion(modifiedBuffer)
                        }
                    }
                }
            }

            if assetReader.status == .completed {
                DispatchQueue.main.async {
                    print("Asset reader completed")
                    completion(nil)
                }
            }
        }
    }

    //------------------------------------------------------------------------------------------------------
    // processFrame
    //
    // read in a sampleBuffer and call function to find human body pose, then overlay annotations,
    // then return a new sampleBuffer.
    //------------------------------------------------------------------------------------------------------
    private func processFrame(sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?) -> Void) {
        if frameCount%6 == 0 {
            detectHumanBodyPose(in: sampleBuffer) { observations in
                let modifiedBuffer = self.overlayBodyAnnotations(on: sampleBuffer, using: observations)
                completion(modifiedBuffer)
            }
            detectHumanHandPose(in: sampleBuffer) { observations in
                let modifiedBuffer = self.overlayHandAnnotations(on: sampleBuffer, using: observations)
                completion(modifiedBuffer)
            }
        }
    }

    //------------------------------------------------------------------------------------------------------
    // detectHumanBodyPose
    //
    // read in a sampleBuffer and return human body observations according to the list in targetBodyJoints[].
    //------------------------------------------------------------------------------------------------------
    private func detectHumanBodyPose(in sampleBuffer: CMSampleBuffer, completion: @escaping ([VNHumanBodyPoseObservation]) -> Void) {
        // Convert CMSampleBuffer to CIImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Error: Could not get image buffer from sample buffer")
            completion([])
            return
        }
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)

        // Create a Vision request for detecting human body poses
        let request = VNDetectHumanBodyPoseRequest { request, error in
            guard error == nil else {
                print("Body pose detection error: \(error!.localizedDescription)")
                completion([])
                return
            }

            // Process the results
            let observations = request.results as? [VNHumanBodyPoseObservation] ?? []
            completion(observations)
        }

        // Perform the request using a request handler
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform body pose request: \(error)")
            completion([])
        }
    }
    
    //------------------------------------------------------------------------------------------------------
    // detectHumanHandPose
    //
    // read in a sampleBuffer and return human hand observations according to the list in targetHandJoints[].
    //------------------------------------------------------------------------------------------------------
    private func detectHumanHandPose(in sampleBuffer: CMSampleBuffer, completion: @escaping ([VNHumanHandPoseObservation]) -> Void) {
        // Convert CMSampleBuffer to CIImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("detectHumanHandPose: Error: Could not get image buffer from sample buffer")
            completion([])
            return
        }
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)

        // Create a Vision request for detecting human body poses
        let request = VNDetectHumanHandPoseRequest { request, error in
            guard error == nil else {
                print("detectHumanHandPose: Hand pose detection error: \(error!.localizedDescription)")
                completion([])
                return
            }

            // Process the results
            let observations = request.results as? [VNHumanHandPoseObservation] ?? []
            completion(observations)
        }

        // Perform the request using a request handler
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform body pose request: \(error)")
            completion([])
        }
    }

    //------------------------------------------------------------------------------------------------------
    // overlayBodyAnnotations
    //
    // read in a sampleBuffer and a list of joints in observations[] and return a new sampleBuffer
    // with dots overlaid on each detected joint.
    //------------------------------------------------------------------------------------------------------
    func overlayBodyAnnotations(on sampleBuffer: CMSampleBuffer, using observations: [VNHumanBodyPoseObservation]) -> CMSampleBuffer? {
        guard let uiImage = convertSampleBufferToUIImage(sampleBuffer) else {
            return nil
        }

        // Perform drawing on the UIImage
        let annotatedImage = drawBodyAnnotations(on: uiImage, using: observations,jointNames:targetBodyJoints)

        // Convert back to CMSampleBuffer if needed
        guard let newSampleBuffer=convertUIImageToSampleBuffer(image:annotatedImage) else {
            print("Error in converting image back to sampleBuffer")
            return nil
        }
        return newSampleBuffer
    }

    //------------------------------------------------------------------------------------------------------
    // overlayHandAnnotations
    //
    // read in a sampleBuffer and a list of joints in observations[] and return a new sampleBuffer
    // with dots overlaid on each detected joint.
    //------------------------------------------------------------------------------------------------------
    func overlayHandAnnotations(on sampleBuffer: CMSampleBuffer, using observations: [VNHumanHandPoseObservation]) -> CMSampleBuffer? {
        guard let uiImage = convertSampleBufferToUIImage(sampleBuffer) else {
            return nil
        }

        // Perform drawing on the UIImage
        let annotatedImage = drawHandAnnotations(on: uiImage, using: observations,jointNames:targetHandJoints)

        // Convert back to CMSampleBuffer if needed
        guard let newSampleBuffer=convertUIImageToSampleBuffer(image:annotatedImage) else {
            print("Error in converting image back to sampleBuffer")
            return nil
        }
        return newSampleBuffer
    }

    //------------------------------------------------------------------------------------------------------
    // drawAnnotations
    //
    // read in a UIImage and draw circle at each joint location, returning a new UIIImage.
    //
    // NOTES: when image [H,W] = 1920x1080 and video was recorded in landscape mode.
    //   gridHeight,gridWidth  =  108x 192
    //   rectHeight,rectWidth  =  108x 192
    // stringX,Y,Height,Width  =   85,32.5,43,22,28
    // ===>  video is oriented with top at right when iPhone is in portrait mode with button at bottom
    //       text in grid is aligned with the video
    //       overlay text (FrameCount, etc.) is oriented rightside-up with iPhone in portrait mode as above
    //       7.5 columns and 6 rows in the grid, with lowest=21 and highest=87
    //       grid cells are numbered from upper-right to upper-left, then from top to bottom of iPhone
    // therefore:
    // Rows are incremented horizontally across the portrait-orientation view, consistent with video.
    // Scaling is wrong in both dimensions.
    //
    //------------------------------------------------------------------------------------------------------

    func drawBodyAnnotations(on image: UIImage,
                         using observations: [VNHumanBodyPoseObservation],
                         jointNames: [VNHumanBodyPoseObservation.JointName]) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        let spotDiameter  = 40.0
        let spotRadius    = spotDiameter / 2.0
        let pathThickness =  8.0
        let minConfidence : VNConfidence = 0.3
        let wristJointName : VNHumanBodyPoseObservation.JointName(wristJoint)

        let context = UIGraphicsGetCurrentContext()
        context?.setStrokeColor(UIColor.white.cgColor)
        context?.setLineWidth(1.0)

        // Drawing the grid
        if self.frameManager.showGrid {
            let gridSize   = 10 // For example, a 10x10 grid
            let gridHeight = image.size.height / CGFloat(gridSize)     //DEBUG
            let gridWidth  = image.size.width  / CGFloat(gridSize)     //DEBUG
            for row in 0..<gridSize {
                for column in 0..<gridSize {
                    let colFloat = CGFloat(column)
                    let rowFloat = CGFloat(row)
                    let rect = CGRect(x:rowFloat*gridWidth,y:colFloat*gridHeight,width: gridWidth, height: gridHeight)
                    context?.stroke(rect)
                    
                    // Numbering each grid square
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    let attrs = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 36), NSAttributedString.Key.paragraphStyle: paragraphStyle, NSAttributedString.Key.foregroundColor: UIColor.white]
                    let labelNumber = (row * gridSize + column)
                    let string = "\(labelNumber)"
                    let size = string.size(withAttributes: attrs)
                    let posX = rect.midX - size.width/2.0
                    let posY = rect.midY - size.height/2.0
                    let stringRect = CGRect(x: posX, y: posY, width: size.width, height: size.height)
                    
                    //print("drawAnnotations:\n\tgrid[H,W]=\(gridHeight),\(gridWidth)\n" +
                    //      "\trect[H,W]=\(rect.height),\(rect.width)\n" +
                    //      "\tstringRect[X,Y,H,W]=\(stringRect.minX),\(stringRect.minY),\(stringRect.height),\(stringRect.width)\n")
                    
                    string.draw(with: stringRect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                }
            }
        }

        // Overlaying joints on the image
        //print("drawAnnotations: \(observations.count) observations, \(targetBodyJoints.count) targetBodyJoints")
        context?.setFillColor(UIColor.green.cgColor)
        context?.setStrokeColor(UIColor.red.cgColor)   // Set the line color
        context?.setLineWidth(pathThickness)           // Set the line thickness
        for observation in observations {
            for (jointFirst,jointSecond) in targetBones {
                if let joint1 = try? observation.recognizedPoint(jointFirst), joint1.confidence > minConfidence {
                    if let joint2 = try? observation.recognizedPoint(jointSecond), joint2.confidence > minConfidence {
                        let posX1 = (joint1.x) * image.size.width
                        let posY1 = (1.0 - joint1.y) * image.size.height
                        let joint1Point = CGPoint(x: posX1, y: posY1)
                        let posX2 = (joint2.x) * image.size.width
                        let posY2 = (1.0 - joint2.y) * image.size.height
                        let joint2Point = CGPoint(x: posX2, y: posY2)

                        context?.move(to: joint1Point)    // Move to the first joint position
                        context?.addLine(to: joint2Point) // Draw line to the second joint position
                        context?.strokePath()             // Stroke the path (draw the line)
                    }
                }
            }
            for jointName in jointNames {
                if let joint = try? observation.recognizedPoint(jointName), joint.confidence > 0.5 {
                    let posX = (joint.x) * image.size.width
                    let posY = (1.0 - joint.y) * image.size.height
                    let jointPoint = CGPoint(x: posX, y: posY)
                    context?.fillEllipse(in: CGRect(x: jointPoint.x - spotRadius,
                                                    y: jointPoint.y - spotRadius,
                                                    width: spotDiameter,
                                                    height: spotDiameter))
                }
            }
        }

        let overlayedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return overlayedImage ?? image
    }
    
    func drawHandAnnotations(on image: UIImage,
                         using observations: [VNHumanHandPoseObservation],
                         jointNames: [VNHumanHandPoseObservation.JointName]) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        let spotDiameter  = 40.0
        let spotRadius    = spotDiameter / 2.0
        let pathThickness =  8.0
        let minConfidence : VNConfidence = 0.3

        let context = UIGraphicsGetCurrentContext()
        context?.setStrokeColor(UIColor.white.cgColor)
        context?.setLineWidth(1.0)

        // Overlaying joints on the image
        //print("drawAnnotations: \(observations.count) observations, \(targetHandJoints.count) targetHandJoints")
        context?.setFillColor(UIColor.orange.cgColor)
        context?.setStrokeColor(UIColor.brown.cgColor)   // Set the line color
        context?.setLineWidth(pathThickness)           // Set the line thickness
        for observation in observations {
            for (jointFirst,jointSecond) in targetHandBones {
                if let joint1 = try? observation.recognizedPoint(jointFirst), joint1.confidence > minConfidence {
                    if let joint2 = try? observation.recognizedPoint(jointSecond), joint2.confidence > minConfidence {
                        let posX1 = (joint1.x) * image.size.width
                        let posY1 = (1.0 - joint1.y) * image.size.height
                        let joint1Point = CGPoint(x: posX1, y: posY1)
                        let posX2 = (joint2.x) * image.size.width
                        let posY2 = (1.0 - joint2.y) * image.size.height
                        let joint2Point = CGPoint(x: posX2, y: posY2)

                        context?.move(to: joint1Point)    // Move to the first joint position
                        context?.addLine(to: joint2Point) // Draw line to the second joint position
                        context?.strokePath()             // Stroke the path (draw the line)
                    }
                }
            }
            for jointName in jointNames {
                if let joint = try? observation.recognizedPoint(jointName), joint.confidence > 0.5 {
                    let posX = (joint.x) * image.size.width
                    let posY = (1.0 - joint.y) * image.size.height
                    let jointPoint = CGPoint(x: posX, y: posY)
                    context?.fillEllipse(in: CGRect(x: jointPoint.x - spotRadius,
                                                    y: jointPoint.y - spotRadius,
                                                    width: spotDiameter,
                                                    height: spotDiameter))
                }
            }
        }

        let overlayedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return overlayedImage ?? image
    }

    //------------------------------------------------------------------------------------------------------
    // convertSampleBufferToUIImage
    //
    // CONVERSION ROUTINE
    // convert from sampleBuffer to UIImage
    //------------------------------------------------------------------------------------------------------
    func convertSampleBufferToUIImage(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
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

    //------------------------------------------------------------------------------------------------------
    // convertUIImageToSampleBuffer
    //
    // CONVERSION ROUTINE
    // convert from UIImage to sampleBuffer
    //------------------------------------------------------------------------------------------------------
    func convertUIImageToSampleBuffer(image: UIImage) -> CMSampleBuffer? {
        // Ensure the image has CGImage
        guard let cgImage = image.cgImage else { return nil }

        // Create a CVPixelBuffer from the image
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, cgImage.width, cgImage.height, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(unwrappedPixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        // Create a CMSampleBuffer from the CVPixelBuffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime.invalid, decodeTimeStamp: CMTime.invalid)
        var videoInfo: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: unwrappedPixelBuffer,
                                                     formatDescriptionOut: &videoInfo)

        if let videoInfo = videoInfo {
            CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: unwrappedPixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: videoInfo, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
        }

        return sampleBuffer
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
    
    func getVideoSize() -> CGSize? {
        guard let track = asset?.tracks(withMediaType: .video).first else {
            return nil
        }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
    
    func addCornerDotsToImage(_ image: UIImage) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))

        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.red.cgColor)

        let dotSize: CGFloat = 10  // Size of the corner dot
        let dotRadius = dotSize / 2

        // Coordinates for the corners
        let topLeft = CGPoint(x: dotRadius, y: dotRadius)
        let topRight = CGPoint(x: image.size.width - dotRadius, y: dotRadius)
        let bottomLeft = CGPoint(x: dotRadius, y: image.size.height - dotRadius)
        let bottomRight = CGPoint(x: image.size.width - dotRadius, y: image.size.height - dotRadius)

        // Draw dots in each corner
        let corners = [topLeft, topRight, bottomLeft, bottomRight]
        for corner in corners {
            context?.fillEllipse(in: CGRect(x: corner.x - dotRadius, y: corner.y - dotRadius, width: dotSize, height: dotSize))
        }

        let imageWithDots = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return imageWithDots ?? image
    }
    
}

func determineVideoOrientation(from track: AVAssetTrack) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
    let transform = track.preferredTransform

    if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
        return (.right, true)
    } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
        return (.left, true)
    } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
        return (.up, false)
    } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
        return (.down, false)
    } else {
        return (.up, false) // Default assumption
    }
}
