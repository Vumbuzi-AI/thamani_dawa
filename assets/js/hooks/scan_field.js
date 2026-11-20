// A wedge scanner can emit Enter between parts of one symbol. Swallow it so
// the field does not submit early. The input's debounced phx-change then
// sends the whole accumulated value as one event.
export const ScanField = {
  mounted() {
    this.onKeydown = (event) => {
      if (event.key === "Enter") event.preventDefault()
    }

    this.el.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.onKeydown)
  },
}
