package com.example.frontend

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * One-shot front-camera JPEG + [FaceTrackVerify] while the Flutter activity is foreground.
 */
object ActivityFaceVerifier {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val surfaceReleaseExecutor = Executors.newSingleThreadExecutor()

    fun verify(activity: FlutterFragmentActivity): Boolean {
        if (!TrackerPrefs.faceVerified(activity)) return true
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val done = CountDownLatch(1)
        val capturedHolder = arrayOfNulls<File>(1)
        val errorHolder = arrayOfNulls<String>(1)

        mainHandler.post {
            val lifecycle = CamLifecycle()
            var provider: ProcessCameraProvider? = null

            fun cleanup() {
                try {
                    provider?.unbindAll()
                } catch (_: Exception) {
                }
                try {
                    lifecycle.destroy()
                } catch (_: Exception) {
                }
                done.countDown()
            }

            try {
                provider = ProcessCameraProvider.getInstance(activity).get()
                val imageCapture =
                    ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setFlashMode(ImageCapture.FLASH_MODE_OFF)
                        .build()
                val preview =
                    Preview.Builder().build().also { p ->
                        p.setSurfaceProvider { request ->
                            val surfaceTexture =
                                android.graphics.SurfaceTexture(0).apply {
                                    setDefaultBufferSize(16, 16)
                                }
                            val surface = Surface(surfaceTexture)
                            request.provideSurface(
                                surface,
                                surfaceReleaseExecutor,
                            ) {
                                try {
                                    surface.release()
                                    surfaceTexture.release()
                                } catch (_: Exception) {
                                }
                            }
                        }
                    }

                provider.unbindAll()
                provider.bindToLifecycle(
                    lifecycle,
                    CameraSelector.DEFAULT_FRONT_CAMERA,
                    preview,
                    imageCapture,
                )
                val outFile =
                    File(activity.cacheDir, "session_face_${System.currentTimeMillis()}.jpg").apply {
                        parentFile?.mkdirs()
                    }
                val opts = ImageCapture.OutputFileOptions.Builder(outFile).build()
                imageCapture.takePicture(
                    opts,
                    ContextCompat.getMainExecutor(activity),
                    object : ImageCapture.OnImageSavedCallback {
                        override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                            capturedHolder[0] = outFile
                            cleanup()
                        }

                        override fun onError(exc: ImageCaptureException) {
                            errorHolder[0] = exc.message ?: "capture"
                            try {
                                outFile.delete()
                            } catch (_: Exception) {
                            }
                            cleanup()
                        }
                    },
                )
            } catch (e: Exception) {
                errorHolder[0] = e.message ?: "bind"
                cleanup()
            }
        }

        val finished = done.await(22, TimeUnit.SECONDS)
        if (!finished) {
            mainHandler.post {
                try {
                    ProcessCameraProvider.getInstance(activity).get().unbindAll()
                } catch (_: Exception) {
                }
            }
            return false
        }

        val err = errorHolder[0]
        val file = capturedHolder[0]
        if (err != null || file == null || !file.exists() || file.length() < 512L) {
            try {
                file?.delete()
            } catch (_: Exception) {
            }
            return false
        }

        val ok = FaceTrackVerify.verifyStillImage(activity.applicationContext, file)
        try {
            file.delete()
        } catch (_: Exception) {
        }
        return ok
    }

    private class CamLifecycle : LifecycleOwner {
        private val registry = LifecycleRegistry(this)

        init {
            registry.currentState = Lifecycle.State.RESUMED
        }

        fun destroy() {
            registry.currentState = Lifecycle.State.DESTROYED
        }

        override val lifecycle: Lifecycle
            get() = registry
    }
}
