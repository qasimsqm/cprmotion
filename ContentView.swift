//
//  ContentView.swift
//  CodeScribe-Posture-3
//
//  Created by William Altmann on 2/28/24.
//

import UIKit
import Foundation
import Vision
import SwiftUI
import AVFoundation
import Combine

//-------------------------------------------------------------------------------------
// NOTES:
//
// ARHumanBodyDetection does not work in the simulator. Need an iPhone.
//
// makeSkeleton - construct skeleton from observed joints and connections from an
//                array or dictionary which includes the shape at each node. Include
//                dots and bars, with color coding, thickness, etc.
// plotSkeleton - plot the shapes onto a scaled and rotated View, perhaps as a level
//                in a ZStack.
//
// ==> For video filmed in Portrait and phone held in Portrait, it works okay.
//     Scaling is off because film does not fit onto Phone screen.
//     If Grid plotting is disabled, the app can run faster than the video time.
//
// Movie span   - Build a frame of the proper size to let the movie capture hand
//                movement to all 4 corners of the frame. Set the camera at a
//                distance that the frame barely fits within the screen dimensions.
//              - Add a colored frame around the UIView, at the top level. Make this
//                part of the skeleton?
//
//-------------------------------------------------------------------------------------
// 2024-03-05   - in ProcessFrame(), analyze and annotate only 1/6 of frames. The
//                frames sent to the iPhone display are still smooth and the
//                processing time stays comfortably ahead of the actual time.
//-------------------------------------------------------------------------------------

//let movieFileName = "RPReplay_Final1709072401"
//let movieFileName = "CodeScribeCPR-2024-02-29-0845"
//let movieFileName = "CodeScribe HD60 2024-03-01-1700"   // hands on bolster, Portrait
//let movieFileName = "CodeScribe 4K60 2024-03-04-1230" // does not scale to fit display
//let movieFileName = "CodeScribe 1080p 2024-03-04-1230"  // rotated clockwise 90'
//let movieFileName = "CodeScribe HD60 2024-03-04-1230"
//let movieFileName = "CodeScribe HD60 2024-03-04-1500"   // portrait orientation when filmed
//let movieFileName = "CodeScribe HD60 2024-03-04-1800"   // landscape orientation when filmed
//let movieFileName = "CodeScribe HD60 2024-03-05-0230"   // hands on bolster, full view, Portrait
let movieFileName = "CodeScribe HD60 2024-03-05-0830"   // hands on bolster, full view, Portrait

struct ContentView: View {
    @StateObject private var frameManager = FrameManager()
    @State       private var movieFileManager: MovieFileManager?
    @State       private var sampleBuffer: CMSampleBuffer? // Ensure this gets updated

    var body: some View {
        Group {
            if let movieFileManager = movieFileManager {
                let videoSize = movieFileManager.getVideoSize() ?? CGSize(width: 320, height: 240)
                MovieFileModeView(frameManager: frameManager,
                                  currentFrame: frameManager.currentFrame,
                                  frameCount: frameManager.frameCount,
                                  wallClockTime: frameManager.elapsedTime,
                                  onReset:resetApp,
                                  videoSize:videoSize)
            }
            else {
                Text("Loading movie...")
            }
        }
        .onAppear {
            print("ContentView appeared, setting up video source")
            print("\tContentView.frameManager: \(ObjectIdentifier(frameManager))")
            setupVideoSource()
            //if let movieFileURL = Bundle.main.url(forResource: movieFileName, withExtension: "mov") {
            //    logVideoMetadata(for: movieFileURL)
            //}
        }
    }
    
    private func resetApp() {
        // Reset the app state or navigate back to the home screen
        // For example, resetting frame manager properties
        print("ContentView: resetApp()")
        frameManager.currentFrame = nil
        frameManager.frameCount = 0
        frameManager.elapsedTime = 0
        exit(0) // DEBUG

        // If you had a navigation mechanism, navigate back here
    }
    
    struct CameraLiveFeedView: View {
        var body: some View {
            Text("Live Camera Feed")
        }
    }
    
    struct MovieFileModeView: View {
        //- - - - - - - - - - - - - - - - - - - - - - - - the following are arguments for calling MovieFileModeView
        @ObservedObject var frameManager: FrameManager
        var currentFrame: CMSampleBuffer?
        var frameCount: Int
        var wallClockTime: Double
        var onReset: () -> Void
        var videoSize: CGSize
        //- - - - - - - - - - - - - - - - - - - - - - - -
        
        var body: some View {
            if let frame = frameManager.currentFrame {
                ZStack {
                    VideoDisplayView(frame: frame, bodyObservations: [],    // arguments in same order as declared
                                     frameManager:frameManager,
                                     videoSize: UIScreen.main.bounds.size,
                                     screenSize: UIScreen.main.bounds.size)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .edgesIgnoringSafeArea(.all) // To ensure full screen is used
                    VStack {
                        Text("Frame Count:  \(frameManager.frameCount)")
                            .foregroundColor(Color.white)
                        Text("Clock   Time: \(frameManager.videoTime, specifier: "%.3f") sec")
                            .foregroundColor(Color.white)
                        Text("Process Time: \(frameManager.elapsedTime, specifier: "%.3f") sec")
                            .foregroundColor(Color.white)
                        Text("\(movieFileName)")
                            .foregroundColor(Color.white)
                        Button("Reset", action: onReset)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        }
    }

    private func setupVideoSource() {
        switch frameSource {
        case .liveCamera:
            let x = 0
            //self.movieFileManager = nil
        case .movieFile:
            if let movieFileURL = Bundle.main.url(forResource: movieFileName, withExtension: "mov") {
                print("\tsetupVideoSource.frameManager: \(ObjectIdentifier(self.frameManager))")
                self.movieFileManager = MovieFileManager(url: movieFileURL, frameManager: self.frameManager)
                self.movieFileManager?.onReadyToRead = {
                    self.movieFileManager?.startReading { sampleBuffer in
                        guard let sampleBuffer = sampleBuffer else { return }
                        DispatchQueue.main.async {
                            self.frameManager.currentFrame = sampleBuffer
                        }
                    }
                }
            } else {
                print("Error: Movie file not found")
            }
        }

    }
    
    func logVideoMetadata(for url: URL) {
        let asset = AVAsset(url: url)

        // Load the track information
        print("logVideoMetadata:")
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError? = nil
            let status = asset.statusOfValue(forKey: "tracks", error: &error)

            if status == .loaded {
                guard let track = asset.tracks(withMediaType: .video).first else {
                    print("No video track found")
                    return
                }
                self.frameManager.videoSize = track.naturalSize

                // Print out basic information
                print("\tTrack dimensions: \(track.naturalSize)")
                print("\tNominal frame rate: \(track.nominalFrameRate)")

                // Determine video orientation
                let transform = track.preferredTransform
                let videoAngle = atan2(transform.b, transform.a) * 180 / .pi

                var orientation = "Unknown"
                if videoAngle == 0 { orientation = "Landscape (Home button on right)" }
                if videoAngle == 180 { orientation = "Landscape (Home button on left)" }
                if videoAngle == 90 { orientation = "Portrait (Home button at bottom)" }
                if videoAngle == -90 { orientation = "Portrait (Home button at top)" }

                print("\tVideo orientation: \(orientation)")
            } else {
                print("\tError loading tracks: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

}

#Preview {
    ContentView()
}
