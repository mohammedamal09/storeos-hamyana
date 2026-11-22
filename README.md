# StoreOS | Hamyana

Bilingual POS for one store and one sales terminal, built with Next.js 16 and Firebase Firestore.

## Local setup

1. Copy `.env.example` to `.env.local` and add the Firebase Web App configuration.
2. Run `npm run dev` and open `/login`.
3. The first online launch creates Admin (`0000`) and Cashier (`1234`), starter categories, and five products.

## Verification

Run `npm run lint`, `npm run typecheck`, `npm test`, and `npm run build` before release.

## Offline operation

Firestore uses durable IndexedDB persistence with multi-tab coordination. Pending writes are retained locally and synchronize automatically after reconnection. Do not clear browser site data while work is pending.
