"""Pure checks for the Flow runtime browser harness helpers (no browser)."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock
import zlib

SPEC = importlib.util.spec_from_file_location('flow_runtime_browser', Path(__file__).with_name('flow_runtime_browser.py'))
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def encode_png(width, height, pixels, channels=3, filters=(0,)):
    """Forward PNG filters per row (cycled), matching the specification."""
    stride = width * channels
    raw, previous = bytearray(), bytes(stride)
    for y in range(height):
        row = pixels[y * stride:(y + 1) * stride]
        kind = filters[y % len(filters)]
        out = bytearray()
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            predict = (0, a, b, (a + b) // 2, paeth(a, b, c))[kind]
            out.append((row[x] - predict) & 255)
        raw += bytes([kind]) + out
        previous = row

    def chunk(tag, body):
        return struct.pack('!I', len(body)) + tag + body + struct.pack('!I', zlib.crc32(tag + body) & 0xffffffff)

    header = struct.pack('!IIBBBBB', width, height, 8, 2 if channels == 3 else 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(bytes(raw))) + chunk(b'IEND', b'')


def gradient(width, height, channels=3):
    data = bytearray()
    for y in range(height):
        for x in range(width):
            data += bytes([(x * 37 + y * 11) % 256, (x * 5 + y * 53) % 256, (x * y) % 256])
            if channels == 4:
                data.append(255 - (x + y) % 256)
    return bytes(data)


class FlowRuntimeBrowserHelperTests(unittest.TestCase):
    def test_missing_browser_reports_actionable_prerequisite(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.dict(HARNESS.os.environ, {'SITEFORGE_CHROME': str(Path(directory) / 'missing')}):
                with self.assertRaisesRegex(RuntimeError, 'set SITEFORGE_CHROME'):
                    HARNESS.browser_executable()

    def test_browser_override_requires_executable_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'browser'
            path.write_text('fixture')
            path.chmod(0o600)
            with mock.patch.dict(HARNESS.os.environ, {'SITEFORGE_CHROME': str(path)}):
                with self.assertRaisesRegex(RuntimeError, 'executable Google Chrome'):
                    HARNESS.browser_executable()
                path.chmod(0o700)
                self.assertEqual(HARNESS.browser_executable(), path)

    def test_png_decoder_inverts_every_filter_for_rgb_and_rgba(self):
        for channels in (3, 4):
            pixels = gradient(9, 7, channels)
            for filters in ((0,), (1,), (2,), (3,), (4,), (0, 1, 2, 3, 4)):
                with self.subTest(channels=channels, filters=filters):
                    width, height, decoded_channels, decoded = HARNESS.png_pixels(encode_png(9, 7, pixels, channels, filters))
                    self.assertEqual((width, height, decoded_channels), (9, 7, channels))
                    self.assertEqual(decoded, pixels)

    def test_png_decoder_rejects_unsupported_or_truncated_input(self):
        with self.assertRaises(ValueError):
            HARNESS.png_pixels(b'not a png')
        valid = encode_png(2, 2, gradient(2, 2))
        broken = valid.replace(b'IDAT', b'IDAX')
        with self.assertRaises(Exception):
            HARNESS.png_pixels(broken)

    def test_pixel_difference_counts_threshold_and_region(self):
        base = bytearray(gradient(10, 6))
        first = encode_png(10, 6, bytes(base))
        self.assertEqual(HARNESS.pixel_difference(first, first)['changedPixels'], 0)
        changed = bytearray(base)
        changed[(2 * 10 + 3) * 3] = (changed[(2 * 10 + 3) * 3] + 40) % 256
        changed[(4 * 10 + 8) * 3 + 1] = (changed[(4 * 10 + 8) * 3 + 1] + 2) % 256
        second = encode_png(10, 6, bytes(changed))
        everything = HARNESS.pixel_difference(first, second)
        self.assertEqual(everything['changedPixels'], 1)
        self.assertEqual(everything['pixels'], 60)
        self.assertEqual(HARNESS.pixel_difference(first, second, (0, 0, 3, 6))['changedPixels'], 0)
        self.assertEqual(HARNESS.pixel_difference(first, second, (3, 2, 1, 1))['changedPixels'], 1)
        with self.assertRaises(ValueError):
            HARNESS.pixel_difference(first, encode_png(9, 6, gradient(9, 6)))

    def test_raster_budget_matches_runtime_caps(self):
        self.assertTrue(HARNESS.raster_within_budget(1024, 768))
        self.assertTrue(HARNESS.raster_within_budget(1, 1))
        self.assertFalse(HARNESS.raster_within_budget(1025, 10))
        self.assertFalse(HARNESS.raster_within_budget(10, 769))
        self.assertFalse(HARNESS.raster_within_budget(0, 10))
        self.assertTrue(HARNESS.raster_within_budget(1024, 768) and 1024 * 768 <= 786432)

    def test_runtime_script_check_accepts_development_file_and_release_bundle(self):
        digest = 'a' * 64
        self.assertTrue(HARNESS.loads_effects_runtime([dict(src='siteforge-effects.js', parts=None)]))
        self.assertTrue(HARNESS.loads_effects_runtime([dict(src=None, parts=None),
                                                       dict(src=f'../siteforge-runtime.{digest}.js', parts='navigation effects')]))
        self.assertFalse(HARNESS.loads_effects_runtime([dict(src=f'siteforge-runtime.{digest}.js', parts='navigation motion')]))
        self.assertFalse(HARNESS.loads_effects_runtime([dict(src='siteforge-runtime.js', parts='effects')]))
        self.assertFalse(HARNESS.loads_effects_runtime([dict(src=f'siteforge-runtime.{digest[:-1]}.js', parts='effects')]))
        self.assertFalse(HARNESS.loads_effects_runtime([dict(src=None, parts=None)]))
        self.assertFalse(HARNESS.loads_effects_runtime([]))

    def test_case_list_is_complete_unique_and_requirement_scoped(self):
        self.assertEqual(len(HARNESS.CASES), 11)
        self.assertEqual(len(set(HARNESS.CASES)), len(HARNESS.CASES))
        self.assertTrue(all(value.startswith('SF-') for value in HARNESS.REQUIREMENTS))


if __name__ == '__main__':
    unittest.main()
