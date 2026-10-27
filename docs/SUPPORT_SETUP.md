# Support MonoView

Optional, repeatable one-time tips live in Settings → Support MonoView. Every app feature remains available without payment. There is no subscription, entitlement, supporter badge or purchase prompt on launch.

## App Store Connect setup

Create these **Consumable** in-app purchases for the app's bundle identifier:

| Product ID | Display name | Suggested price point |
| --- | --- | --- |
| `com.monoview.support.small` | Small support | USD 1.99 |
| `com.monoview.support.development` | Support development | USD 4.99 |
| `com.monoview.support.extra` | Extra support | USD 9.99 |

Set localized metadata, prices and availability, complete the required agreements/tax/banking setup, and submit the purchases for Apple's review with the app as appropriate. These price points are suggestions. The app always displays Apple's localized `Product.displayPrice`, never a hardcoded currency or amount.

The local StoreKit file does **not** create or publish App Store Connect products. Until Apple supplies these exact IDs, the normal scheme may show “Support options are unavailable”; users can close the screen and continue using the app.

## Local testing

Select the shared **MonoView Support Testing** scheme and run in Simulator. Its StoreKit configuration provides simulated products; local purchases do not charge money. The normal MonoView scheme has no local configuration and uses the actual store environment. Never ship the configuration as a substitute for live products.

Run `MonoViewUITests/SupportUITests` serially: StoreKitTest changes a shared test environment. The tests configure StoreKit before launching the app and exercise repeat support, failure/retry, Ask to Buy approval, unavailable products and large text. The configuration is a resource of the UI test bundle only, not the application.

Before release, also verify purchases on a physical device through Apple's sandbox/TestFlight with App Store Connect products. Confirm the system confirmation sheet, localized prices, cancellation, payment restrictions and pending approvals.

## Transaction behavior

Only verified support consumables receive a thank-you and are finished. The app observes unfinished transactions and transaction updates, including delayed approvals. Cancellation is quiet. A failed purchase leaves the app available and can be retried. An unverified purchase asks the user to check Apple purchase history before retrying. Consumed tips do not grant access or need an entitlement restoration flow.

This is support for the developer's work, not a charitable donation campaign.

Automated cancellation injection in this Xcode version returns `StoreKitError.unknown` rather than a cancellation; its local dialog was not exposed to the UI runner. Cancellation handling is implemented but still needs manual sandbox/device validation.
