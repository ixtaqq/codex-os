Debug the issue I just described, in this order. Do not skip to a fix.

1. **Reproduce.** Find and run the smallest command that shows the failure. Paste its real output.
   If you cannot reproduce it, say so and state exactly what you would need — do not guess at a fix
   for a failure you have not seen.
2. **Locate.** Trace from the symptom to the code that produces it. Name files and line numbers.
3. **Explain.** State the cause in one or two sentences: what the code does versus what it should
   do, and why that produces this symptom.
4. **Fix.** The smallest change that addresses the cause. Not the symptom, not a workaround, and
   nothing unrelated bundled in.
5. **Prove it.** Re-run the reproduction. Paste the output. Then run the surrounding tests to show
   nothing else broke.

If the cause turns out to be somewhere I did not point you, say so plainly before fixing it.
