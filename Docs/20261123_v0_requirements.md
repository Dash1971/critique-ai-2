# Critique AI 2.0 — accepted development brief

**Architecture update:** the current coach is on-device, with app-computed facts and validated model proposals. The original cloud/API-backend approach is parked, with no automatic cloud fallback or public server exposure. Raw model trials failed grounding; the protected pipeline is experimental and no model is release-approved. This changes the AI deployment method, not the requested tracker functionality or the requirement to use actual recorded data.

Status: unfinished standalone application, separate repository, separate database/storage, and TestFlight-only distribution. LockIn is not a dependency. No subscriptions, paywalls, premium memberships, locked features, or artificial usage caps.

## Identity and platforms

Use the supplied JPEG exactly as the brand source: white dotted infinity, pure black background, unchanged proportions, no added text/decorations/redesign. Only resample to required icon dimensions. Preserve the original asset. Use it for application icon, loading identity and favicon if a web surface is added.

Native mobile and desktop: iPhone, iPad, Mac. Dark by default, optional light theme. Black/dark gray surfaces, white type, subtle gradients, rounded cards, smooth accessible animation, consistent spacing, meaningful charts. Mobile bottom navigation, desktop sidebar. Respect Dynamic Type, contrast, VoiceOver and reduced motion.

## Mandatory functional modules

1. Dashboard: daily progress/completion, habit completion, workouts, goals, streaks, statistics, motivation, quick actions; live updates from actual activity.
2. Habits: create/edit/delete, completions, daily/weekly/monthly tracking, streaks, calendar history, percentages, categories, custom schedules, reminders and historical statistics.
3. Workouts: editable routines/exercises; sets/reps/weights; duration; rest timer; history; records/statistics/charts; muscle groups and schedules; calisthenics, weights, cardio, flexibility and general fitness.
4. AI coach: on-device inference using actual provided application data only; habits/consistency/workouts/goals/improvement/routines/productivity/constructive feedback/long-term progress. Never claim unprovided data was analyzed. No provider key in clients; any future cloud mode requires a separately configured secure backend.
5. Nutrition: meals, custom foods, editable calories/protein/carbohydrates/fat, water, history, daily overview, food categories.
6. Goals: daily/weekly/monthly/yearly; title/description/deadline/category/progress/completion/history; multiple concurrent goals.
7. Focus: configurable countdowns/work and breaks, reminders, session duration/history, daily statistics/productivity. Screen time only where supported; explicit manual versus automatic source labels and real native permissions. Never invent device data.
8. Profile: picture/username/account information, actual-activity-derived XP/levels/badges/streaks/habit/workout/overall/historical statistics. Automatic achievements.
9. Optional social: friends, profiles, progress comparison, weekly leaderboards, shared challenges, achievement sharing, privacy; private profiles supported. Real authentication/authorization for cloud features.
10. Calendar: select historical dates; habits/workouts/goals/focus/activity/progress.
11. Notifications: individually configurable habits/workouts/goals/focus/daily summary/streak reminders, permissions and truthful delivery state.
12. Settings: theme/account/profile/notifications/privacy, export/backup/restore/reset, AI configuration.

## Data and acceptance

Reliable database; autosave; supported synchronization; authentication for cloud; secure secrets; validation/errors; backup/restore; refresh/relaunch never erases saved data. Every button, navigation route and form must work. Loading/empty/error states; responsive performance; real-data charts/progress. Organized modules. Test every feature before marking complete. Report external services/permissions/setup honestly. No fake implementations or decorative controls.

## External dependencies still to resolve

- Optional social/synchronization services still need configuration and acceptance. The current local coach does not require hosting or provider credentials.
- New app's Apple registration/signing and any required Screen Time distribution entitlement. Existing LockIn registration/entitlements are not transferable permission for this new identifier.
- Source publication does not register or distribute an Apple application.

This document records requirements, not completion. A tested release is the objective, not a prototype or dashboard-only deliverable.
