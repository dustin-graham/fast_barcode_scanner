package com.jhoogstraat.fast_barcode_scanner.scanner

import android.media.Image
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.android.gms.tasks.OnFailureListener
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage

interface OnDetectedListener<T> {
    fun onSuccess(codes: T, image: Image)
}

class MLKitBarcodeScanner(
    options: BarcodeScannerOptions,
    private val successListener: OnDetectedListener<List<Barcode>>,
    private val failureListener: OnFailureListener
) : ImageAnalysis.Analyzer {
    private val scanner = BarcodeScanning.getClient(options)

    @ExperimentalGetImage
    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val inputImage =
                InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            scanner.process(
                inputImage
            )
                .addOnSuccessListener { barcodes ->
                    successListener.onSuccess(barcodes, mediaImage)
                }
                .addOnFailureListener(failureListener)
                .addOnCompleteListener {  }
        }
    }
}