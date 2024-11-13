import android.util.LruCache

class ImageCache {
    // Set up the cache size (for example, 10 MB)
    private val cacheSize = (Runtime.getRuntime().maxMemory() / 8).toInt()
    private val cache: LruCache<String, ByteArray> = LruCache(cacheSize)
    private var savedCodes: ArrayList<String> = ArrayList()

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
    fun storeImage(image: ByteArray?, key: String) {
        if (image == null) {
            return
        }
        cache.put(key, image)
        savedCodes.add(key)
    }

    // Retrieve image from cache by barcode
    fun retrieveImage(code: String): ByteArray? {
        val image = cache.get(code)
        return image
    }

    fun isImageSaved(code: String): Boolean {
        return savedCodes.contains(code)
    }

    // Optionally, add an eviction strategy (e.g., using size limit or time-based)
    fun clearCache() {
        cache.evictAll()  // Evict all cached images if needed
    }
}
