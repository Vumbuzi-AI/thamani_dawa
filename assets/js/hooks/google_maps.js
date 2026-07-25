import {loadGoogleMaps} from "../google_maps_loader"

// Generic Google Maps location picker hook.
//
// Mount on a <div> that will contain the map. Configure via data attributes:
//   data-lat-input   - id of the latitude number input to sync
//   data-lng-input   - id of the longitude number input to sync
//   data-address-input - (optional) id of a text input to geocode/autocomplete
//   data-lat / data-lng - (optional) initial coordinates
//
// Clicking the map, dragging the marker, or picking a places autocomplete
// result all update the lat/lng inputs (and dispatch "input" so LiveView's
// phx-change validation picks up the change).
const DEFAULT_CENTER = {lat: -1.286389, lng: 36.817223} // Nairobi

export const GoogleMaps = {
  mounted() {
    loadGoogleMaps().then(maps => this.setup(maps)).catch(err => console.error(err))
  },

  setup(maps) {
    const latInput = document.getElementById(this.el.dataset.latInput)
    const lngInput = document.getElementById(this.el.dataset.lngInput)
    const addressInput = this.el.dataset.addressInput
      ? document.getElementById(this.el.dataset.addressInput)
      : null

    const initialLat = parseFloat(this.el.dataset.lat || latInput?.value)
    const initialLng = parseFloat(this.el.dataset.lng || lngInput?.value)
    const hasInitial = Number.isFinite(initialLat) && Number.isFinite(initialLng)
    const center = hasInitial ? {lat: initialLat, lng: initialLng} : DEFAULT_CENTER

    const map = new maps.Map(this.el, {center, zoom: hasInitial ? 15 : 6})
    const geocoder = new maps.Geocoder()
    const marker = new maps.Marker({map, position: center, draggable: true})

    // Keep the map hidden until a location is actually picked, so the
    // "new site" form doesn't lead with an empty map centered on nowhere.
    if (!hasInitial) this.el.classList.add("hidden")

    const reveal = () => {
      if (this.el.classList.contains("hidden")) {
        this.el.classList.remove("hidden")
        maps.event.trigger(map, "resize")
      }
    }

    const setCoords = ({lat, lng}) => {
      reveal()
      marker.setPosition({lat, lng})
      map.panTo({lat, lng})
      if (latInput) {
        latInput.value = lat
        latInput.dispatchEvent(new Event("input", {bubbles: true}))
      }
      if (lngInput) {
        lngInput.value = lng
        lngInput.dispatchEvent(new Event("input", {bubbles: true}))
      }
    }

    map.addListener("click", e => setCoords({lat: e.latLng.lat(), lng: e.latLng.lng()}))
    marker.addListener("dragend", e => setCoords({lat: e.latLng.lat(), lng: e.latLng.lng()}))

    if (addressInput) {
      const autocomplete = new maps.places.Autocomplete(addressInput)
      autocomplete.bindTo("bounds", map)
      autocomplete.addListener("place_changed", () => {
        const place = autocomplete.getPlace()
        if (place.geometry?.location) {
          setCoords({lat: place.geometry.location.lat(), lng: place.geometry.location.lng()})
        } else if (place.name) {
          geocoder.geocode({address: place.name}).then(({results}) => {
            if (results[0]) {
              const loc = results[0].geometry.location
              setCoords({lat: loc.lat(), lng: loc.lng()})
            }
          })
        }
      })
    }

    this.map = map
    this.marker = marker
  },

  destroyed() {
    this.map = null
    this.marker = null
  }
}
