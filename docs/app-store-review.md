# App Store review

## Version 1.8.0 (24), submitted 14 October 2026

Built from the clean release tag `v1.8.0`, commit
`4fadcefc39af901b860b9967c619a943d43961c9`. Transporter delivered build 24 on
14 October 2026 at 01:28 Europe/Berlin. App Store Connect completed processing
and accepted the submission with status **Waiting for Review**.

Submission: `d2b2886f-3f21-4dbc-afd5-7039a403c902`.
Build: `b79c6914-83c3-4118-af36-c46370f19fa5`.
Automatic publication after approval is retained. China mainland remains the
only excluded storefront, with 174 storefronts available. German and English
descriptions and release notes were updated for Parakeet and model preloading.
Review instructions describe the one-time model preparation. Source versions
and the changelog were not changed for the App Store upload.

See [submission evidence](reports/2026-10-14-appstore-1.8.0/REPORT.md).

## Version 1.7.0, historical review and resolution

Review of 2 October 2026: submission `24906f41-5b19-4c82-b3fe-796de5c3a88d`,
app `6817328154`, version 1.7.0 (22).

Apple rejected the China mainland distribution under Guideline 5 because the
metadata references OpenAI and the app supports compatible online AI endpoints.
Apple explicitly offered removing the China mainland storefront as an alternative
to deactivating affected functionality and removing all related metadata there.

## Applied resolution

Exclude **China mainland** from distribution and retain the existing configurable
endpoints elsewhere. Do not merely rename the provider or hide the term OpenAI:
that does not deactivate the functionality identified by Apple. A China-specific
build requires a separately designed and verified restriction, including metadata
and screenshots, rather than a locale or UI-language check.

China mainland was excluded with Daniel's explicit approval on 3 October 2026.
The saved availability showed 174 regions after reload, down from 175. All other
storefront selections were retained. The existing review instructions were
preserved and the update below was appended, saved and verified after reload.
Build 1.7.0 (23) was delivered with Transporter on 3 October 2026 at 03:22 local
time. After processing, build 23 replaced build 22 in version 1.7.0, and the
existing submission was resubmitted. App Store Connect confirmed **Waiting for
Review** (`Warten auf Prüfung`) for both the submission and app version.
At the start of the 1.8.0 submission on 14 October 2026, App Store Connect
confirmed that 1.7.0 (23) was **Ready for Distribution**.

1. Open [STTBar in App Store Connect](https://appstoreconnect.apple.com/apps/6817328154).
2. Open **Pricing and Availability → App Availability → Manage → Manage
   Availability**. Deselect **China mainland**. Preserve the existing choices for
   other regions, including Hong Kong and Macao; they are separate storefronts.
3. Review the resulting region list, continue with Next and Confirm, then reopen
   it to verify that China mainland is excluded. Apple's current procedure is in
   [Manage availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/).
4. Upload the signed corrected package, select its processed build and update
   review notes. Build 23 is the next candidate after rejected build 22; check for
   an already uploaded build 23 before uploading and use a higher number if needed.
5. Update the review notes and resubmit after verifying the saved availability.
   Do not state that functionality was regionally disabled if using exclusion.

## Appended Review Notes

Saved after verifying that China mainland has been excluded, under
`Update for resubmission (build 23):`:

> We have removed the China mainland storefront from STTBar's App Store
> availability, as suggested in your review message under Guideline 5. STTBar
> will not be distributed on the China mainland App Store. Its configurable
> transcription and optional AI cleanup endpoints remain available in the other
> selected storefronts. Please review the corrected submission with this updated
> availability.

The update is saved in App Store Connect. No separate Resolution Center message
was sent. The existing automatic publication after approval is retained with
Daniel's explicit resubmission authorization.

## Corrected package

```bash
STT_BUILD_NUMBER=23 bash macos-app/build-appstore.sh \
  /path/to/STTBar_Mac_App_Store.provisionprofile /path/to/generated-output
```

The output directory must be disposable: the build script replaces it. Do not
manually edit source versions or `CHANGELOG.md`. The script embeds the profile,
adds the profile's team identifiers and signs with Apple Distribution and the
Mac installer distribution identity. The corrected entitlement grants access to
files explicitly selected in Open/Save panels.

Before upload, verify the app signature, installer signature, bundle version,
embedded profile and signed entitlements. Full Store processing and App Review
are independent of a successful local build. Use a clean release commit when
producing the final public artifact; a local review build records `-dirty` when
it includes uncommitted changes.

The delivered package records `f09a5ce-dirty`, version 1.7.0 and build 23. Its
SHA-256 is `a8c19f365edc4f0b72f239386e2c77ec3d9c8703d47cc33bccca35ecca9511ce`.
The tested source changes remain uncommitted on local `develop`; no GitHub
release or push was performed.
