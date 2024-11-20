import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class ImageHelper {
    private var savedCodes: MutableMap<String, String> = mutableMapOf()

    private object Holder {
        val INSTANCE = ImageHelper()
    }

    companion object {
        @JvmStatic
        fun getInstance(): ImageHelper {
            return Holder.INSTANCE
        }
    }

    // Store image to the path with barcode as filename
    private fun storeImage(imageBytes: ByteArray?, key: String, context: Context) {
        val externalFilesDirectory = context.cacheDir;
        val imageFile: File

        try {
            externalFilesDirectory.mkdirs()
            val barcodeDirectory = File(externalFilesDirectory, "barcode_images")
            if (!barcodeDirectory.exists()) {
                barcodeDirectory.mkdirs()
            }

            imageFile = File.createTempFile(key, ".jpeg", barcodeDirectory)
        } catch (e: IOException) {
            throw RuntimeException(e)
        }

        try {
            FileOutputStream(imageFile).use { fos ->
                fos.write(imageBytes)
            }
            savedCodes[key] = imageFile.absolutePath
        } catch (e: IOException) {
            e.printStackTrace()
        }
    }

    private fun isImageSaved(code: String): Boolean {
        return savedCodes.contains(code)
    }

    // Retrieve image from cache by barcode
    fun retrieveImagePath(code: String): String? {
        return savedCodes[code]
    }

    fun clearCache(context: Context) {
        savedCodes.clear()
        val externalFilesDirectory = context.cacheDir
        val barcodeDirectory = File(externalFilesDirectory, "barcode_images")
        if (barcodeDirectory.exists()) {
            barcodeDirectory.deleteRecursively()
        }
    }

    suspend fun storeImageToCache(image: Image, code: String, context: Context) {
        if (isImageSaved(code)) {
            return
        }
        if (image.format == ImageFormat.YUV_420_888) {
            withContext(Dispatchers.IO) {
                image.use { img ->
                    val yBuffer = img.planes[0].buffer // Y
                    val uBuffer = img.planes[1].buffer // U
                    val vBuffer = img.planes[2].buffer // V

                    val ySize = yBuffer.remaining()
                    val uSize = uBuffer.remaining()
                    val vSize = vBuffer.remaining()

                    val nv21 = ByteArray(ySize + uSize + vSize)

                    // Copy Y channel
                    yBuffer[nv21, 0, ySize]

                    // Copy VU channel (assuming NV21 format)
                    vBuffer[nv21, ySize, vSize]
                    uBuffer[nv21, ySize + vSize, uSize]

                    val yuvImage = YuvImage(nv21, ImageFormat.NV21, img.width, img.height, null)
                    val out = ByteArrayOutputStream()
                    yuvImage.compressToJpeg(Rect(0, 0, img.width, img.height), 100, out)
                    val jpegBytes = out.toByteArray()
                    storeImage(jpegBytes, code, context)
                }
            }
        } else {
            throw IllegalArgumentException("Unsupported image format")
        }
    }
}
