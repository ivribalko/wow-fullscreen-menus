local _, NS = ...

-- Layout centralizes shared presentation dimensions and timing.
NS.Layout = {
    edgeMargin = 14,
    modelSideInset = 0.02,
    modelBottomInset = 0.08,
    modelWidth = 0.28,
    modelHeight = 0.76,
    modelScale = 1,
    modelCameraDistance = 5.5,
    modelCameraHeight = 1.4,
    modelCameraFieldOfView = math.rad(40),
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
