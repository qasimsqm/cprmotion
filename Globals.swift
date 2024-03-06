//
//  Globals.swift
//  CodeScribe-Posture-3
//
//  Created by William Altmann on 2/29/24.
//

import Vision
import UIKit
import Foundation
import SwiftUI
import AVFoundation
import Combine

let jointNames: [VNHumanBodyPoseObservation.JointName] = [
    .nose,
    .leftEye,
    .rightEye,
    .leftEar,
    .rightEar,
    .leftShoulder,
    .rightShoulder,
    .neck,
    .leftElbow,
    .rightElbow,
    .leftWrist,
    .rightWrist,
    .leftHip,
    .rightHip,
    .root, // Base of the spine
    .leftKnee,
    .rightKnee,
    .leftAnkle,
    .rightAnkle
]

var jointPositions: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

let targetBodyJoints: [VNHumanBodyPoseObservation.JointName] = [
    .leftShoulder,
    .rightShoulder,
    .leftElbow,
    .rightElbow,
    .leftWrist,
    .rightWrist
    // Add other joints as needed
]

let targetBones: [(VNHumanBodyPoseObservation.JointName,VNHumanBodyPoseObservation.JointName)] = [
    (.leftShoulder,.rightShoulder),
    (.leftShoulder,.leftElbow),
    (.leftElbow,.leftWrist),
    (.rightShoulder,.rightElbow),
    (.rightElbow,.rightWrist)
]

//------------------------------------------------------------------------------------------------------
//
//------------------------------------------------------------------------------------------------------
/*
 thumbTip
 thumbIP
 thumbMP
 thumbCMC
 indexTIP
 indexDIP
 indexPIP
 indexMCP
 middleTip
 middleDIP
 middlePIP
 middleMCP
 ringTip
 ringDIP
 ringPIP
 ringMCP
 littleTip
 littleDIP
 littlePIP
 littleMCP
 wrist
 */

let targetHandJoints: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .indexTip
//    .middleTip,
//    .ringTip,
//    .littleTip,
//    .thumbTip
]

let targetHandBones: [(VNHumanHandPoseObservation.JointName,VNHumanHandPoseObservation.JointName)] = [
    (.wrist,.indexTip)
//    (.wrist,.middleTip),
//    (.wrist,.ringTip),
//    (.wrist,.littleTip),
//    (.wrist,.thumbTip)
]
