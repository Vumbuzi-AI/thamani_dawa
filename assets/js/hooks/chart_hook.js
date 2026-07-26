// Renders a Chart.js chart on a <canvas>. Chart.js itself is loaded globally
// via a <script> tag in root.html.heex (see that file), so `window.Chart` is
// used directly rather than an npm/vendor import.
//
// Configure via data attributes on the canvas:
//   data-chart-type    - Chart.js chart type ("line", "bar", ...)
//   data-chart-data    - JSON-encoded Chart.js `data` config
//   data-chart-options - JSON-encoded Chart.js `options` config
//
// Re-renders (destroy + recreate) whenever LiveView patches those attributes,
// e.g. when a date-range filter changes.
export const Chart = {
  mounted() {
    this.render()
  },

  updated() {
    this.render()
  },

  destroyed() {
    this.chart?.destroy()
  },

  render() {
    this.chart?.destroy()

    const {chartType, chartData, chartOptions} = this.el.dataset
    this.chart = new window.Chart(this.el, {
      type: chartType,
      data: JSON.parse(chartData),
      options: chartOptions ? JSON.parse(chartOptions) : {}
    })
  }
}
