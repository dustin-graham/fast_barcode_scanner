import android.graphics.Bitmap
import android.util.LruCache
import java.io.ByteArrayOutputStream


class ImageCache {
    // Set up the cache size (for example, 10 MB)
    private val cacheSize = (Runtime.getRuntime().maxMemory() / 8).toInt()
    private val cache: LruCache<String, Bitmap> = LruCache(cacheSize)
    private var savedCodes : ArrayList<String> = ArrayList()
    private object Holder {
        val INSTANCE = ImageCache()
    }

    companion object {
        @JvmStatic
        fun getInstance(): ImageCache {
            return Holder.INSTANCE
        }
    }

    // Store image in cache with barcode as key
    fun storeImage(image: Bitmap, key: String) {
        cache.put(key, image)
        savedCodes.add(key)
    }

    // Retrieve image from cache by barcode
    fun retrieveImage(code: String): ByteArray? {
        val image = cache.get(code)
        var byteArray: ByteArray? = null
        if(image != null){
            val stream = ByteArrayOutputStream()
            image.compress(Bitmap.CompressFormat.JPEG, 100, stream)
            byteArray = stream.toByteArray()
        }
        return byteArray
    }

    fun isImageSaved(code: String): Boolean {
        return savedCodes.contains(code)
    }

    // Optionally, add an eviction strategy (e.g., using size limit or time-based)
    fun clearCache() {
        cache.evictAll()  // Evict all cached images if needed
    }
}
