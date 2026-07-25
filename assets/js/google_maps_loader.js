// Lazily loads the Google Maps JS API (once per page) using the API key
// injected into the root layout as <meta name="google-maps-api-key">.
let loaderPromise = null

export function loadGoogleMaps() {
  if (window.google?.maps) return Promise.resolve(window.google.maps)
  if (loaderPromise) return loaderPromise

  const apiKey = document.querySelector("meta[name='google-maps-api-key']")?.getAttribute("content")
  if (!apiKey) return Promise.reject(new Error("Missing google-maps-api-key meta tag"))

  loaderPromise = new Promise((resolve, reject) => {
    window.__initGoogleMaps = () => resolve(window.google.maps)

    const script = document.createElement("script")
    script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&callback=__initGoogleMaps&libraries=places&v=weekly`
    script.async = true
    script.defer = true
    script.onerror = () => reject(new Error("Failed to load Google Maps"))
    document.head.appendChild(script)
  })

  return loaderPromise
}
