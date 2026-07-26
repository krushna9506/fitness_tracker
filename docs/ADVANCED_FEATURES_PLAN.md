# Pulse advanced features plan

## 1. Natural-language workout logging

The Log Workout sheet accepts a short human description such as `ran 5k in 28 minutes`.

1. The app reads `GEMINI_API_KEY` from a local `.env` file (copied from `.env.example`); the real file is ignored by Git.
2. It sends a single-turn request to `gemini-2.5-flash-lite` with a strict JSON-only contract:

```json
{"exercise_type":"string","duration_minutes":0,"estimated_calories":0}
```

3. The request uses Gemini structured output (`application/json` plus a schema) and requires no prose or Markdown. The application still defensively removes accidental code fences and validates all fields.
4. A local MET lookup estimates calories using `calories = MET × 70kg × duration_minutes / 60`. A Gemini calorie estimate is rejected when it is non-positive, exceeds 20 kcal/minute, or differs from the MET estimate by more than the larger of 250 kcal or 85% of the fallback.
5. The parsed values populate an editable review card and the existing manual fields. Nothing is saved until the user presses **Save workout**. HTTP 429 and parsing/API failures retain the structured manual form and explain the fallback.

### Key handling

`.env` prevents accidental repository commits, but a browser build still exposes any client-side key to a determined user. For a production public web release, replace the direct client request with an authenticated server proxy and rate limit it. For the free-tier development/mobile flow, restrict the key in Google AI Studio to the Gemini API and known app/web origins.

## 2. Predictive trend analysis

The Progress/Insights page creates one daily-calorie data point for each of the last 56 days (zero for rest days). It fits ordinary least squares to `y = a + bx`, where `x` is the day index:

```text
b = Σ((x - x̄)(y - ȳ)) / Σ((x - x̄)²)
a = ȳ - b × x̄
predicted calories on day x = a + b × x
```

For the current week, actual calories are used through today; future days use `max(0, a + bx)`. The sum is compared with the user’s weekly calorie target and described in plain language.

For anomaly checking, the log flow builds a rolling 28-day series of daily totals, calculates population standard deviation `σ`, and flags a proposed day if the updated daily total exceeds `mean + 2σ` (and a 300-kcal practical floor). The user can cancel or save anyway.

## 3. Native device extensions (follow-on)

- **Bluetooth / wearables:** add `flutter_blue_plus` only to Android/iOS builds. Implement a device-permission flow, a service/characteristic adapter per supported wearable, and a visible connection-state indicator. Bluetooth is not consistently available in all browsers and must not be simulated as real data.
- **Pose-count assist (stretch):** add `google_mlkit_pose_detection`, `camera`, and Android/iOS permissions. Count reps through a calibrated joint-angle state machine, show confidence, and keep the manual counter as the source of truth. This requires testing on physical phones and is intentionally not enabled in the web build.
