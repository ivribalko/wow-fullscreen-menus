local _, NS = ...

-- Layout centralizes shared presentation dimensions and timing.
NS.Layout = {
    edgeMargin = 14,
    topPadding = 8,
    maxScale = 1.5,
    rowGap = 6,
    backgroundAlpha = 0.8,
    fadeDuration = 0.12,
    refreshInterval = 0.5,
    discoveryInterval = 1,
    retryInitialDelay = 0.05,
    retryMaximumDelay = 2,
}
