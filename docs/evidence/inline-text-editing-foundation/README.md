# SF-AUTHORING-008 Inline Plain-Text Editing Evidence

This directory retains reproducible capacity evidence for the bounded inline
plain-text editing foundation mapped to `SF-0406-001` through `SF-0406-008`.

Run:

```sh
scripts/run-inline-text-editing-evidence.sh
scripts/check-inline-text-editing-evidence.py
```

`measurements.json` records the named local environment, raw Debug-test samples,
resident-memory high water, methodology, and limitations. The production
registry validates and prepares the same atomic canonical property command used
by the application; editor drafts, caret/selection ranges, marked text, and
clipboard data are not serialized or retained in the evidence.

Running-app screenshots retained here are exported from the verified UI journey:

- `inline-text-draft.png` — native editor, visible editing surface, and draft.
- `committed-plain-text.png` — committed authored scene after one transaction.
- `cancelled-text-restored.png` — cancelled editor removal and selection/status
  restoration. The authored layer had not visibly repainted at capture time;
  the same UI journey proves exact canonical restoration by reopening the editor
  and asserting the committed text before clipboard operations.

The measurements are capacity evidence, not final cross-hardware budgets.
Production typography, rich text, OS-level IME/VoiceOver acceptance, and
incremental renderer performance remain outside this bounded slice.
