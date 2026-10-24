# Weather card (component)
> **What:** the Home weather card: header, first briefing sentence, 24 hours that page. **Read when:** you change `WeatherCardContent`, the hourly carousel, or the option D header.
- Mockup: [weather-summary-card.html](weather-summary-card.html) · status in-flight:claude/weather-card-header-d-5a3fe5 (option D header; the card on main draws the "was" header) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Home/Weather/WeatherSummaryCard.swift`, `WeatherCardContent.swift`, `WeatherPagedCarousel.swift`, `WeatherCarouselPaging.swift`, `WeatherCardHour.swift`; branch only: `HassDesign/TickerLabel.swift`, `TickerPlan.swift` · Spec: `.agents/patterns/weather.md`, `.agents/design/weather-card-header.md` · Patterns: weather, motion
- States covered: target (option D, short and long condition), was (main header, including the squeezed numeral), compare, loading, error, empty, unavailable, night, narrow (Duo half), ax5, reduce-motion
- Motion: condition ticker, hour paging, number roll. Transition: opens the Weather sheet (see that mockup)
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (6 hours a page compact, 9 regular, 6 in a Duo half)
- Open notes: in-flight header; the kit WeatherCard differs from the app (static hours, 15 pt hour text, pulsing bars, 118 pt AX5 numeral), so this page uses `components/weather/_home-weather.js`; on the branch the header also stacks when the range overflows its column
