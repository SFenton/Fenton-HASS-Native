# Settings: Report an Issue and Request a Feature

> **What:** the Settings list's Feedback section and the feedback form it opens, as built: files, HIG decisions, filing and tests. **Read when:** changing `HassUI/Features/Settings/Feedback/` or `HassCore/Feedback/`. The issues it files are worked by the [triage agent](../../workflow/triage-agent.md).

## Source

Ported from FestivalNativeApps' in-app feedback form (`.agents/controls/feedback-form/{spec,ios}.md` and `FestivalUI/Features/Settings/Feedback/` there). The web dashboard has no equivalent (it runs inside Home Assistant), so this is a native-only section. Differences from Festival:

| Festival | Here | Why |
|---|---|---|
| The app posts to its service, which files on GitHub with a server token | The app files on GitHub itself with the person's fine-grained token (Issues: read and write on `SFenton/fenton-hass-requests` only) | No service to hold a token; Home Assistant must not duplicate it; a token shipped in the app is forbidden (AGENTS.md) |
| Public tracker, anonymous bodies | Private request repo; diagnostics name the Home Assistant user | Screenshots show the house; the household is trusted |
| Service transcodes media | `FeedbackMediaFitter` shrinks each file to GitHub's 10 MB attachment limit on the device | Same reason |
| Rows hidden until `/api/features` says so | Rows always shown; the form asks for a token when there is none | No feature flag service |
| Polls a job for the issue number | Synchronous: uploads, then creates the issue, then shows `#N` with View on GitHub | GitHub answers directly |

## Native

| Piece | File | Notes |
|---|---|---|
| Kinds, prefix rule, validation | `HassCore/Feedback/FeedbackKind.swift`, `FeedbackDraft.swift`, `FeedbackValidationIssue.swift` | `[Bug] `/`[Feature] ` kept by `setTitle`; lengths in UTF-16 |
| Issue body | `FeedbackIssue.compose` | Sections per filled box, `### Media` (images inline, videos as bare URLs, which GitHub plays), `### Diagnostics` table, `<!-- fenton-feedback:v1 -->`; `<!--` in typed text is escaped |
| Diagnostics | `FeedbackDiagnostics`, `HassUI/.../FeedbackDiagnosticsCollector.swift` | App version and build date, OS, device family + hardware id, window size/size class/orientation, Home Assistant version and connection, reporter's name, text size/VoiceOver/Reduce Motion/appearance, locale. Never a token, password or server address |
| GitHub | `GitHubFeedbackClient` over `FeedbackHTTPTransport` | `GET /user` + `GET /repos/…` to verify, `POST uploads.github.com/user-attachments/assets`, `POST /repos/…/issues`; errors mapped to fixed copy in `FeedbackFilingError` (never GitHub's text) |
| Token | `KeychainGitHubAccessStore` | Synchronizable (iCloud Keychain) so it is entered once per person, `AfterFirstUnlock`; the Home Assistant refresh token stays this-device-only |
| Media | `FeedbackLocationScrubber` (ported), `FeedbackMediaFitter`, `FeedbackPickedMedia` | Copy → strip location → fit to 10 MB (JPEG steps, then export presets) → count limit (4). Private copies in `tmp/fenton-feedback-media/<uuid>/`, purged when the sheet goes away |
| Form | `FeedbackFormModel`, `FeedbackFormSheet`, `FeedbackAttachmentStrip`/`Tile`, `FeedbackFieldHeader`, `SheetDismissAttemptObserver` | As Festival's sheet; progress "Uploading media n of m…" then "Filing your report on GitHub…"; Stop Sending only while media uploads |
| Token page | `GitHubAccessModel`, `GitHubAccessView` | Pushed inside the sheet; secure field, Save Token verifies before saving, Remove Token confirms, Create a Token on GitHub opens the pre-filled page |
| Entry | `FeedbackSettingsSection` in `SettingsScreen` | Its own "Feedback" section under the topics; `.feedbackFormSheet(item:)` presents it with `.hassSheet(.form)` (full height on iPhone, form sheet on iPad); the form and GitHub Access use `.modalChrome()` |
| Fixture | `FeedbackFixtureFiler`, `FENTON_FEEDBACK_FIXTURE=1` (connected) / `connect` (no token) | `fixture-token` verifies; titles with `fixture-failed` fail. Debug builds also read `FENTON_GITHUB_TOKEN` for a live run without typing a token into the UI |

## Decisions (HIG via `apple-hig`)

- **Cancel leading, Submit trailing**, discard confirmation on Cancel and swipe (HIG Sheets; HIG Modality: "If either a dismiss gesture or button could lose user-generated content, get confirmation before closing").
- **Visible explanations, not placeholders** (HIG Text fields), **Submit disabled with the reason shown** (HIG Entering data), including "Add a GitHub access token to send."
- **GitHub access leads the form when missing** and moves to the end ("Sending as @login") once set, so the first run explains the requirement before typing.
- **Secure field for the token** (HIG Entering data: secure text fields for sensitive data); removing it is confirmed (HIG Action sheets) because sending needs a new one.
- **Quick Look** for tapped media; no photo-library permission (`PhotosPicker` runs out of process; HIG Privacy).

## Test IDs

`settings.feedback.bug|feature`; `feedback.field.title|description|repro|expected`, `.close`, `.submit`, `.attach`, `.attach.media|files|progress`, `.attachments`, `.attachment.N[.remove]`, `.attachments.notice`, `.validation`, `.progress`, `.stop`, `.done`, `.view`, `.discard.confirm|cancel`, `.github`; `feedback.github.login|token|save|error|remove|remove.confirm|create`.

## Tests

- Unit (`HassCoreTests`): `FeedbackTests` (prefix, validation, platform, attachment policy and names, issue composition and escaping, diagnostics, GitHub client requests and error mapping over a stub transport, fixture, stores), `FeedbackLocationScrubberTests` (ported), `FeedbackMediaFitterTests`. `HassUITests`: `FeedbackFormModelTests` (admit/refuse, submit → filed, failures, cancel, access refresh, staging purge).
- Journeys (`FeedbackJourneyTests`, fixture only, never a real issue): rows open both forms with audits and AX5 relaunch, discard confirmation then filing #1, adding a token enables Submit (wrong token refused), failed filing keeps the form, screenshot capture.
