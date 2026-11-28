"""Pure checks for the interaction and motion runtime browser harness helpers (no browser)."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('interaction_runtime_browser',
                                              Path(__file__).with_name('interaction_runtime_browser.py'))
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


class InteractionRuntimeBrowserHelperTests(unittest.TestCase):
    def test_key_events_press_then_release_with_shift_modifier(self):
        down, up = HARNESS.key_events('Tab', shift=True)
        self.assertEqual((down['type'], up['type']), ('rawKeyDown', 'keyUp'))
        self.assertEqual((down['key'], down['code'], down['windowsVirtualKeyCode']), ('Tab', 'Tab', 9))
        self.assertEqual(down['modifiers'], 8)
        self.assertEqual(HARNESS.key_events('Escape')[0]['modifiers'], 0)
        self.assertEqual([HARNESS.key_events(key)[0]['windowsVirtualKeyCode'] for key in ('ArrowDown', 'ArrowUp', 'Home', 'End')],
                         [40, 38, 36, 35])
        self.assertEqual(HARNESS.key_events('Enter')[0]['windowsVirtualKeyCode'], 13)
        self.assertTrue(all('nativeVirtualKeyCode' not in event for event in HARNESS.key_events('Enter')))
        with self.assertRaises(ValueError):
            HARNESS.key_events('F13')

    def test_union_ignores_empty_rectangles(self):
        box = HARNESS.union([dict(x=10, y=20, w=100, h=40), dict(x=0, y=0, w=0, h=0), dict(x=30, y=50, w=100, h=30)])
        self.assertEqual(box, dict(x=10, y=20, w=120, h=60))
        self.assertIsNone(HARNESS.union([dict(x=5, y=5, w=0, h=0)]))
        self.assertIsNone(HARNESS.union([]))

    def test_centred_uses_the_viewport_centre_and_tolerance(self):
        self.assertTrue(HARNESS.centred(dict(x=620, y=400, w=200, h=100), (1440, 900)))
        self.assertTrue(HARNESS.centred(dict(x=621, y=401, w=200, h=100), (1440, 900)))
        self.assertFalse(HARNESS.centred(dict(x=623, y=400, w=200, h=100), (1440, 900)))
        self.assertFalse(HARNESS.centred(dict(x=620, y=0, w=200, h=100), (1440, 900)))

    def test_case_list_is_complete_unique_and_requirement_scoped(self):
        self.assertEqual(len(HARNESS.CASES), 11)
        self.assertEqual(len(set(HARNESS.CASES)), len(HARNESS.CASES))
        self.assertTrue(all(value.startswith('SF-') for value in HARNESS.REQUIREMENTS))
        self.assertEqual(HARNESS.GAP, 8, 'must match the runtime gap in EventGraphRuntime')

    def test_element_text_strips_tags_and_decodes_references(self):
        markup = '<p data-siteforge-node="x" aria-live="polite">Ready &lt;now&gt; &amp; then</p>'
        self.assertEqual(HARNESS.element_text(markup), 'Ready <now> & then')
        self.assertEqual(HARNESS.element_text('<p><span data-siteforge-text> 42 </span></p>'), '42')
        self.assertEqual(HARNESS.STATUS_VALUES[0], 'Ready', 'must match the Swift fixture')

    def test_reuses_the_flow_harness_browser_and_prerequisite(self):
        self.assertTrue(callable(HARNESS.FLOW.browser_executable))
        self.assertEqual(HARNESS.FLOW.VIEWPORT, (1440, 900))


if __name__ == '__main__':
    unittest.main()
