# Decisions for Pete: saving a finished workout (2026-10-05)

Two decisions before the finish screen (F10 S7), the swap sheet (S8) and watch sync (F17) are planned, and one
thing to know. No workout screen exists yet, so none of this shows in the app today.

## 1. A finished workout that will not save

You tap "Save workout" and the iPhone cannot store it: its storage is full, say. Ledger keeps the workout and
tries again each time you return to the app, so nothing is lost. But as built, it would still look like a
running workout, refuse every change, and "Discard" would save it as soon as the phone can. If the phone can
never store it, no other workout can start until you force-quit the app.

**Meanwhile, the screen** either keeps looking like a running workout (today) or, recommended and assumed
below, reads "Finished 6:42 pm · not saved yet", cannot be edited, and offers "Try again".

**May you throw the workout away?**
- **A. No.** "Try again" and "Close" only. A workout that can never be saved stays on the phone, out of History.
- **B. Yes, when you say so.** "Delete workout" asks you to confirm, then removes it from this iPhone: nothing
  in History, your program untouched.
- **C. Only when Ledger judges it hopeless.** "Delete workout" appears for a workout the phone refuses outright,
  never for a full disk.

Recommendation: **B**. You are never stuck, and nothing is lost unless you choose it. C makes the app guess
which failures are permanent. Once the watch syncs, a copy the watch already saved would not be deleted.

If you don't answer: A, on a workout that still looks like it is running.

## 2. An old swap that lands after you changed your mind

On Monday you swap Bench Press for Dumbbell Bench with "Also update program" on. That workout is saved late:
its save kept failing or, once the watch syncs, it sat on a watch that reached the phone on Thursday. On
Wednesday you set that slot to Incline Bench yourself. When Monday's workout is saved, what does your program
say?

- **A. Your later choice wins:** Incline Bench. Monday's workout is saved as you did it. Its program change is
  dropped, because the slot no longer holds Bench Press.
- **B. The swap wins:** Dumbbell Bench comes back, and nothing tells you. The code does this today.
- **C. The newer by the clock wins:** also Incline Bench here, but only if the phone's and the watch's clocks
  agree.

Recommendation: **A**. An older workout should not undo a change you made by hand, and A needs no clocks. It
would be built with the swap sheet.

If you don't answer: B stays. It is hard to reach on one phone; the watch makes it likely.

## 3. To know: the workout's log now goes with the save

While you lift, Ledger keeps a step-by-step log so that the workout survives a crash. It used to be deleted
just after the workout was saved to History. Now both happen in one step, so a crash can no longer leave a
workout both saved and "in progress". Nothing you see changes.

## What you do not need to read

- The ADR-004 amendment of 2026-10-05: the same points in engineering terms, for the record.
- The ADR-008 amendment and one changed sentence in the engineering standards: a test stand-in for the
  database now holds a lock so that it saves all or nothing, as the real one does. It never ships.
