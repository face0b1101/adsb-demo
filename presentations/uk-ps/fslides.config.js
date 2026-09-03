module.exports = {
  name: 'adsb-uk-public-sector',
  title: 'Real-time situational awareness - Elastic for UK public sector',
  slidesDir: 'slides',
  repo: 'face0b1101/adsb-demo',

  // Slide filenames in order, relative to the slides/ directory
  slides: [
    'cover.html',
    'problem.html',
    'analogue.html',
    'flow.html',
    'live-picture.html',
    'context.html',
    'drill.html',
    'explore.html',
    'journey.html',
    'site.html',
    'briefing.html',
    'watchlist.html',
    'signal.html',
    'triage.html',
    'analyst.html',
    'your-data.html',
    'recap.html',
    'close.html',
  ],

  // Human-readable labels for the overview panel (must match slides array length)
  labels: [
    'Cover',
    'Why it matters',
    'Any moving thing',
    'Picture to action',
    'Live picture',
    'Place context',
    'Drill to one',
    'Ask in English',
    'Where it has been',
    'Around a site',
    'Morning briefing',
    'Watch-list',
    'The signal',
    'First triage',
    'Analyst time',
    'Your data',
    'Recap',
    'Over to the system',
  ],

  // Extra settle time for the animated flow slide when exporting to PDF
  pdfOverrides: {
    'flow.html': { wait: 3500 },
  },
};
