# Wide (tablet) layout — design

## Why

On a 13″ iPad the app showed the iPhone layout stretched edge to edge: small-looking text, 1000-pt-wide fields and buttons, half the screen empty. The App Store iPad screenshots looked the same. The goal is a layout that uses the width, for the iPad app itself and for its screenshots. The user tried a throwaway prototype (branch `spike/wide-layout`) on the 13″ iPad simulator and approved its look.

## Goals

- A two-pane layout on wide windows, chosen by window size, not device type: iPad, Android tablets and unfolded foldables all get it (the user asked to keep it for Android tablets).
- Send gets a live barcode preview on the right.
- Every new string translated into the app's seven languages.
- The phone layout stays exactly as it is.

## Non-goals

- Present, Live Scan, photo capture, the photo optimiser and dialogs: unchanged (Present already fills the screen).
- A list/detail Files screen: Files only gets a centred column, because tapping a file opens it and there is no detail view to show.
- Device-type checks (`Platform.isIOS`, iPad idiom).

## Approaches considered

1. Centred column plus side rail: cheap, but leaves the screen mostly empty.
2. **Two panes where it pays off (chosen):** fills the screen and gives the best screenshots, at the cost of a per-screen wide layout and a new preview feature.
3. Scaling everything up on iPad: rejected, because it reads as a blown-up phone app.

## Design

- **Wide test:** `isWide` = window width ≥ 840 pt and shorter side ≥ 600 pt. No iPhone qualifies, even in landscape (~440 pt shorter side). An iPad in a narrow Split View falls back to the phone layout on its own.
- **Shell:** on wide windows, `AppShell` uses a `NavigationRail` with labels on the left, in place of the bottom `NavigationBar`. The tabs and routes are the same.
- **Send:** the form sits in a 440-pt left pane, and `SendPreview` takes the rest.
  - The preview re-encodes 350 ms after the last change to the text, file or passphrase (in an isolate, like Present), then loops the source frames at the chosen frame delay.
  - Below it: "Frame k of N" and a Full screen button. Tapping the barcode or the button opens Present, exactly like the Present button.
  - Before there's any input, an empty pane says "Your barcode appears here as you type".
  - *My call:* the preview **includes the passphrase**, unlike the spike, so its N matches what Present and Share GIF produce. PBKDF2 runs at most once per pause in typing.
- **Import and Camera:** the form is on the left. The decoded result (`ResultCard`, scrollable) is on the right, with an empty pane saying "The decoded file appears here" until there's a result. On a phone the result stays under the form.
- **Files and About:** the existing content in a centred column, at most 680 pt wide.
- **Strings (3 new ARB keys × 7 languages):** the two empty-pane texts and "Full screen"; the frame counter reuses the existing `presentSource` ("Frame {i} of {n}"). The prototype's "· compressed" suffix is dropped.

## Testing

- **Widget tests at an iPad size (1032×1376) and a phone size:**
  - rail vs bottom bar;
  - two panes vs one column on Send, Import and Camera;
  - the result appears in the right pane on wide screens and under the form on phones;
  - typing on Send produces a preview, and its frame count matches `estimateFrames`;
  - an iPhone in landscape stays on the phone layout.
- Existing tests keep passing unchanged, since they run at phone size.
- Re-run `store-screens/capture.sh` for new iPad screenshots, adjusting the capture test only if it relies on bottom-bar finders.

## Left to the builder

Exact paddings and empty-pane styling, as in the spike; how the preview's isolate jobs are cancelled or ignored when superseded (stale results must never show); and the docs updates (`app/CLAUDE.md`).
