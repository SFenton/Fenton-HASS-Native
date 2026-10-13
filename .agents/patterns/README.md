# Patterns

> **What:** cross-screen behaviors with one canonical component each. **Read when:** touching any shared behavior.

| Pattern | Canonical component | Web source |
|---|---|---|
| [dynamic-grid.md](dynamic-grid.md) | `HassDesign/DynamicGridLayout.swift` | `src/components/core/DynamicGrid.tsx` |
| [entity-tile.md](entity-tile.md) | `HassDesign/GlassTile.swift` | `src/components/core/GlassTile.tsx` |
| [status-rail.md](status-rail.md) | `HassUI/Features/Home/StatusRail.swift` | `src/components/hass/StatusRail.tsx` |
| [room-overview-sheet.md](room-overview-sheet.md) | `HassUI/Common/RoomOverview/RoomOverviewSheet.swift` | `src/pages/AtAGlancePage.tsx` (`LightsSheet`, `OccupancySheet`, `ContactSheet`, …) |
| [modal-sheet.md](modal-sheet.md) | `HassDesign/HassModal.swift` (`HassModal`, `SheetCloseItem`, `hassSheet()`), `HassUI/Common/ModalTabBar.swift` | `src/components/core/ModalSheet.tsx`, `ModalTabNav.tsx` |
| [header-edge-fade.md](header-edge-fade.md) | `HassDesign/HeaderEdgeFade.swift` | `src/hooks/ui/useScrollMask.ts` (FestivalNativeApps `ModalTopEdgeFade`) |
| [page-backdrop.md](page-backdrop.md) | `HassUI/Common/HouseBackdrop.swift` | `src/components/shell/AppShell.module.css` `.backdrop` |
| [media-remote.md](media-remote.md) | `HassUI/Features/MediaRemote/MediaRemoteSheet.swift` | `src/components/hass/MediaRemoteModalContent.tsx` |
| [floating-actions.md](floating-actions.md) | `HassDesign/FloatingActionBar.swift`, `HassDesign/FilterSheet.swift` | `src/components/core/FloatingActionButton.tsx`, `src/components/shell/DashboardFloatingAction.tsx` |
| [image-card.md](image-card.md) | `HassDesign/ImageCard.swift` | `src/components/hass/recipes/RecipeCard.tsx` |
| [vacuum-sheet.md](vacuum-sheet.md) | `HassUI/Features/Vacuums/VacuumSheet.swift` | `src/components/hass/VacuumCard.tsx` |
| [valetudo-map.md](valetudo-map.md) | `HassUI/Features/Vacuums/ValetudoMapView.swift` | `src/components/hass/ValetudoMapCard.tsx` |
| [thermostat-dial.md](thermostat-dial.md) | `HassDesign/ThermostatDial/ThermostatDial.swift` | `src/components/hass/CircularControlDial.tsx` |
| [schedule-date-fields.md](schedule-date-fields.md) | `HassDesign/ScheduleDateFields.swift` | `NativePickerField` in `ScheduleConfirmationForm` |
| [info-box.md](info-box.md) | `HassDesign/InfoBox.swift` | `src/components/core/InfoBox.tsx` |
| [status-pill.md](status-pill.md) | `HassDesign/StatusPill.swift` | `src/components/core/StatusPill.tsx` |
| [option-picker.md](option-picker.md) | `HassDesign/OptionPickerSheet.swift` | `src/components/core/OptionPickerDialog.tsx` |
| [bedroom-devices.md](bedroom-devices.md) | `HassUI/Features/Bedroom/BedSideSheet.swift`, `WakeLightSheet.swift` | `src/components/hass/wakeLights/`, SleepyPod in `DashboardViewPage.tsx` |
| [room-device-sheets.md](room-device-sheets.md) | `HassUI/Features/RoomDevices/` | `src/components/hass/*ModalContent.tsx` (fan, purifier, humidifier, grill) |
| [settings-section.md](settings-section.md) | `HassDesign/SettingsSection.swift` | `src/components/core/SettingsSection.tsx` |
| [optimistic-actions.md](optimistic-actions.md) | `HassCore/Optimism/OptimisticActions.swift` | `src/hooks/useOptimisticState.ts`, `src/components/hass/optimisticActionState.ts` |
| [content-gate.md](content-gate.md) | `HassDesign/Loading/ContentGate.swift` | `src/components/hass/recipes/useRecipeCollection.ts` (criteria phases) |
| [image-cache.md](image-cache.md) | `HassDesign/Images/ImagePipeline.swift`, `CachedImage.swift` | browser HTTP cache (`decoding="async"` images) |
| [telemetry.md](telemetry.md) | `HassTelemetry/`, `HassUI/Diagnostics/` | none (native only) |
| [weather.md](weather.md) | `HassUI/Features/Home/Weather/WeatherSummaryCard.swift`, `WeatherSheet.swift`, `WeatherPagedCarousel.swift`; logic in `HassCore/Weather` | `src/components/hass/WeatherSummary.tsx`, `useWeatherForecasts.ts`, `weatherPresentation.ts`, `weatherDayBriefing.ts` |
