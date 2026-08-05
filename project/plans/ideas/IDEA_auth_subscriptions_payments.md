# Idea: Auth, Subscriptions & Payments

**Status:** Stub — needs dedicated design session
**Priority:** After BLE training loop works end-to-end on hardware

## Scope (to be designed)

- **Authentication** — Firebase Auth (email/password, Sign in with Apple, Google)
- **Subscription management** — StoreKit 2 for Apple platforms, Google Play Billing for Android
- **Payment gating** — What features are free vs. premium?
- **Session sync** — FirebaseSessionStore: SessionPersistence (already protocol-ready)
- **Account linking** — Cross-platform identity (same user on iOS + Android)

## Open Questions

- Freemium vs. paid-only vs. trial period?
- Which features gate behind subscription?
- Do we need server-side receipt validation?
- Offline grace period for expired subscriptions?
- Family sharing support?

## Dependencies

- Firebase SDK integration (not yet added)
- SessionPersistence protocol (already implemented)
- SettingsPersistence protocol (in progress)
