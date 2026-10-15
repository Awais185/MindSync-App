package com.example.frontend

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions

/**
 * On-device face presence (ML Kit) before starting background camera clips.
 * Identity match against the enrolled profile still uses [FaceTrackVerify] on a video frame.
 */
object FacePresenceDetector {
    private val detector by lazy {
        val options =
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setMinFaceSize(0.12f)
                .build()
        FaceDetection.getClient(options)
    }

    fun isUsableFace(face: Face): Boolean {
        val rotY = face.headEulerAngleY
        val rotX = face.headEulerAngleX
        if (rotY < -35f || rotY > 35f || rotX < -35f || rotX > 35f) {
            return false
        }
        val left = face.leftEyeOpenProbability
        val right = face.rightEyeOpenProbability
        if (left != null && right != null && left < 0.15f && right < 0.15f) {
            return false
        }
        return true
    }

    fun detectPresence(
        image: InputImage,
        onResult: (Boolean) -> Unit,
    ) {
        detector
            .process(image)
            .addOnSuccessListener { faces ->
                onResult(faces.any { isUsableFace(it) })
            }
            .addOnFailureListener {
                onResult(false)
            }
    }
}
