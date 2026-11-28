#!/usr/bin/env python3
"""Actual-browser checks for the SiteForge interaction and motion runtimes.

SF-1101-006/008, SF-1104-004/006/008, SF-1105-002/006/008 (C10, ADR-0065);
SF-1106-006/008 key presses, bound text and announced opener state (C6/C7, ADR-0066).
Invoked by TransformModelTests.testInteractionAndMotionRuntimesActualBrowserFocusTrapEscapePlacementAndReveal
with one site compiled by MultiPageStaticBuildPlanner (fixture: interactions). It reuses the
Flow harness's owned temporary Chrome profile, loopback DevTools client and loopback static
server pattern (flow_runtime_browser.py): standard library only, no owner profile, network
destination, browser sandbox change or external asset. Every case is recorded; none is skipped.

Fixture (static layout, so every object is its own element and contents name their container):
an "Open dialog" button opens a modal whose two buttons are its contents; an "Open menu" button
near the left edge opens a menu (placement below) with three buttons; a container far down the
page reveals on scroll together with its text; a "Key panel" frame (the website adds it to the Tab order)
sets page variables on Enter, Down Arrow and Escape, and two texts show those variables.
"""
import argparse
import html
import http.server
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import tempfile
import threading
import time

SPEC = importlib.util.spec_from_file_location('flow_runtime_browser', Path(__file__).with_name('flow_runtime_browser.py'))
FLOW = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FLOW)

REQUIREMENTS = ['SF-1101-006', 'SF-1101-008', 'SF-1104-004', 'SF-1104-006', 'SF-1104-008', 'SF-1105-002',
                'SF-1105-006', 'SF-1105-008', 'SF-1106-006', 'SF-1106-008']
CASES = ['runtimes-load-from-the-site', 'modal-opens-centred-with-backdrop-and-focus',
         'modal-keeps-tab-focus-inside', 'escape-closes-modal-and-restores-focus',
         'menu-opens-below-trigger-and-arrow-keys-move', 'menu-flips-above-at-viewport-edge',
         'reveal-on-scroll-includes-container-contents', 'reduced-motion-and-no-javascript-keep-content-visible',
         'key-press-runs-only-on-the-focused-object', 'bound-text-starts-with-value-and-follows-variable',
         'openers-announce-popup-and-expanded-state']
FIXTURE = 'interactions'
# Labels written by the Swift fixture (TransformModelTests.interactionBrowserFixture).
OPEN_DIALOG, OPEN_MENU = 'Open dialog', 'Open menu'
DIALOG_ITEMS, MENU_ITEMS = ('Confirm', 'Cancel'), ('First', 'Second', 'Third')
# Values the fixture's variables take: Status starts Ready, Enter sets Entered, Escape sets Escaped;
# Step starts 0 and Down Arrow sets 2. Bound texts are listed in page order (Status, Step).
STATUS_VALUES, STEP_VALUES = ('Ready', 'Entered', 'Escaped'), ('0', '2')
GAP = 8           # EventGraphRuntime `gap` between a trigger and a placed overlay
TOLERANCE = 1.5   # CSS pixels; translate values are rounded to whole pixels
KEYS = {'Tab': 9, 'Enter': 13, 'Escape': 27, 'End': 35, 'Home': 36, 'ArrowUp': 38, 'ArrowDown': 40}


def key_events(key, shift=False):
    """DevTools Input.dispatchKeyEvent parameters for one key press (down, then up)."""
    if key not in KEYS:
        raise ValueError(f'Unsupported key {key}')
    # CDP translates these portable key codes for the host. Providing the
    # Windows code again as the native code can deactivate headless Chrome
    # on macOS after Enter and suspend the page's animation frames.
    base = dict(key=key, code=key, windowsVirtualKeyCode=KEYS[key], modifiers=8 if shift else 0)
    return [dict(base, type='rawKeyDown'), dict(base, type='keyUp')]


def union(rects):
    """Bounding box {x, y, w, h} of DOMRect-like dicts with a size; None when there is none."""
    sized = [rect for rect in rects if rect and (rect['w'] > 0 or rect['h'] > 0)]
    if not sized:
        return None
    left, top = min(r['x'] for r in sized), min(r['y'] for r in sized)
    right, bottom = max(r['x'] + r['w'] for r in sized), max(r['y'] + r['h'] for r in sized)
    return dict(x=left, y=top, w=right - left, h=bottom - top)


def element_text(markup):
    """The text of one element's outer HTML: tags removed, character references decoded, trimmed."""
    return html.unescape(re.sub(r'<[^>]*>', '', markup)).strip()


def centred(box, viewport, tolerance=TOLERANCE):
    """True when a box that fits the viewport sits in its centre."""
    width, height = viewport
    return (abs(box['x'] + box['w'] / 2 - width / 2) <= tolerance
            and abs(box['y'] + box['h'] / 2 - height / 2) <= tolerance)


# In-page helpers: find a control by its label, an overlay's group (itself plus its contents),
# the element with focus, and rectangles. Node identifiers are random, so labels are used.
PAGE = r"""
window.__sf = {
  control: label => Array.from(document.querySelectorAll('button,a')).find(item => item.textContent.trim() === label) || null,
  overlay: kind => document.querySelector('[data-siteforge-overlay="' + kind + '"]'),
  group: element => [element].concat(Array.from(document.querySelectorAll('[data-siteforge-within~="' + element.getAttribute('data-siteforge-node') + '"]'))),
  rect: element => { const r = element.getBoundingClientRect(); return {x: r.x, y: r.y, w: r.width, h: r.height}; },
  focused: () => document.activeElement ? document.activeElement.textContent.trim() : '',
  shown: element => !!element && element.getClientRects().length > 0 && getComputedStyle(element).display !== 'none',
  keyPanel: () => document.querySelector('[data-siteforge-events][tabindex="0"]'),
  bound: () => Array.from(document.querySelectorAll('[data-siteforge-text-variable]')).map(element => element.textContent.trim()),
};
true
"""


class Page:
    """Drives one compiled page through the Flow harness's owned browser."""

    def __init__(self, browser):
        self.browser = browser
        self.loads = 0

    def evaluate(self, program):
        return self.browser.page.evaluate(program)

    def load(self, url, scripts=True):
        self.loads += 1
        target = f'{url}?load={self.loads}'
        self.browser.page.call('Page.navigate', dict(url=target))
        deadline = time.monotonic() + 15
        if scripts:
            probe = (f"document.URL==={json.dumps(target)}&&document.readyState==='complete'"
                     "&&!!document.querySelector('[data-siteforge-events]')")
            while time.monotonic() < deadline:
                if self.evaluate(probe):
                    self.evaluate(PAGE)
                    self.frames('after page load')
                    return
                time.sleep(0.05)
        else:
            while time.monotonic() < deadline:
                root = self.browser.document()
                if root and root.get('documentURL') == target and self.browser.query_count('[data-siteforge-overlay]') == 2:
                    time.sleep(0.3)
                    return
                time.sleep(0.1)
        raise RuntimeError(f'Compiled website did not finish loading: {target}')

    def frames(self, reason):
        try:
            self.browser.frames(2)
        except TimeoutError as error:
            ready = self.evaluate("({visibility:document.visibilityState,ready:document.readyState})")
            raise TimeoutError(f'Animation frames did not arrive {reason}: {ready}') from error

    def press(self, key, shift=False):
        for event in key_events(key, shift):
            self.browser.page.call('Input.dispatchKeyEvent', event)
        self.frames(f'after {key} input')

    def click(self, label):
        control = self.evaluate(f"(()=>{{const e=__sf.control({json.dumps(label)});return e?{{rect:__sf.rect(e),disabled:e.disabled}}:null;}})()")
        if not control:
            raise AssertionError(f'control {label} is missing')
        if control.get('disabled'):
            raise AssertionError(f'control {label} stayed disabled after the interaction runtime loaded')
        rect = control['rect']
        x, y = rect['x'] + rect['w'] / 2, rect['y'] + rect['h'] / 2
        self.browser.page.call('Input.dispatchMouseEvent', dict(type='mouseMoved', x=x, y=y, button='none', buttons=0))
        for kind, buttons in (('mousePressed', 1), ('mouseReleased', 0)):
            self.browser.page.call('Input.dispatchMouseEvent', dict(type=kind, x=x, y=y, button='left', buttons=buttons,
                                                                    clickCount=1))
        self.frames(f'after clicking {label}')
        return rect

    def overlay_state(self, kind):
        return self.evaluate(f"""(()=>{{const o=__sf.overlay({json.dumps(kind)});if(!o)return null;
            const group=__sf.group(o);return {{hidden:o.hidden,flat:o.hasAttribute('data-siteforge-flat'),
            members:group.length-1,shownMembers:group.slice(1).filter(__sf.shown).length,
            rects:group.map(__sf.rect),translate:group.map(e=>e.style.translate),
            backdrops:document.querySelectorAll('.sf-overlay-backdrop').length,focused:__sf.focused(),
            viewport:[innerWidth,innerHeight]}};}})()""")

    def computed(self, selector, name):
        """A computed style value through DOM/CSS, which also works with scripts disabled."""
        root = self.browser.document()
        node = self.browser.page.call('DOM.querySelector', dict(nodeId=root['nodeId'], selector=selector))['nodeId']
        if not node:
            raise AssertionError(f'missing element {selector}')
        style = self.browser.page.call('CSS.getComputedStyleForNode', dict(nodeId=node))['computedStyle']
        return next((entry['value'] for entry in style if entry['name'] == name), None)

    def outer_html(self, selector):
        """An element's markup through DOM, which also works with scripts disabled."""
        root = self.browser.document()
        node = self.browser.page.call('DOM.querySelector', dict(nodeId=root['nodeId'], selector=selector))['nodeId']
        if not node:
            raise AssertionError(f'missing element {selector}')
        return self.browser.page.call('DOM.getOuterHTML', dict(nodeId=node))['outerHTML']

    def attribute(self, selector, name):
        root = self.browser.document()
        node = self.browser.page.call('DOM.querySelector', dict(nodeId=root['nodeId'], selector=selector))['nodeId']
        if not node:
            raise AssertionError(f'missing element {selector}')
        values = self.browser.page.call('DOM.getAttributes', dict(nodeId=node))['attributes']
        return dict(zip(values[::2], values[1::2])).get(name)


def run_cases(page, base, captures):
    """Runs every case in CASES order; each case loads a fresh document."""
    cases = []
    site = base + FIXTURE + '/index.html'

    def record(name, body):
        started = time.perf_counter()
        try:
            detail = body()
            cases.append(dict(case=name, outcome='passed', seconds=time.perf_counter() - started, detail=detail))
        except Exception as error:
            cases.append(dict(case=name, outcome='failed', seconds=time.perf_counter() - started,
                              detail=f'{type(error).__name__}: {error}'))

    def require(condition, message):
        if not condition:
            raise AssertionError(message)

    def loaded():
        page.load(site)
        runtime = page.evaluate("""(()=>({scripts:Array.from(document.scripts).map(s=>s.getAttribute('src')),
            origin:Array.from(document.scripts).every(s=>!s.src||new URL(s.src).origin===location.origin),
            ready:document.documentElement.classList.contains('sf-motion-ready')}))()""")
        scripts = ' '.join(value or '' for value in runtime['scripts'])
        require('siteforge-events.js' in scripts and 'siteforge-motion.js' in scripts, f'runtime scripts missing {runtime}')
        require(runtime['origin'], f'non-local script {runtime}')
        require(runtime['ready'], f'motion runtime did not start {runtime}')
        for kind in ('modal', 'menu'):
            state = page.overlay_state(kind)
            require(state and state['hidden'] and state['flat'], f'{kind} does not start hidden with contents {state}')
            require(state['members'] >= 2 and state['shownMembers'] == 0, f'{kind} contents visible while closed {state}')
        return runtime

    def open_modal():
        page.load(site)
        page.click(OPEN_DIALOG)
        state = page.overlay_state('modal')
        require(state and not state['hidden'], f'modal did not open {state}')
        require(state['backdrops'] == 1, f'modal backdrop missing {state}')
        require(state['shownMembers'] == state['members'], f'modal contents hidden {state}')
        require(state['focused'] == DIALOG_ITEMS[0], f'focus did not move into the modal {state}')
        box = union(state['rects'])
        require(box and FLOW.VIEWPORT[0] >= box['w'] and FLOW.VIEWPORT[1] >= box['h'], f'modal group does not fit {box}')
        require(centred(box, state['viewport']), f'modal group not centred {box} in {state["viewport"]}')
        page.browser.capture(captures, 'modal-open', box)
        return dict(box=box, translate=state['translate'])

    def tab_trap():
        page.load(site)
        page.click(OPEN_DIALOG)
        order = [page.evaluate('__sf.focused()')]
        page.press('Tab', shift=True)
        order.append(page.evaluate('__sf.focused()'))
        page.press('Tab')
        order.append(page.evaluate('__sf.focused()'))
        expected = [DIALOG_ITEMS[0], DIALOG_ITEMS[-1], DIALOG_ITEMS[0]]
        require(order == expected, f'focus left the modal or did not wrap: {order}, expected {expected}')
        return order

    def escape():
        page.load(site)
        page.click(OPEN_DIALOG)
        page.press('Escape')
        state = page.overlay_state('modal')
        require(state['hidden'] and state['backdrops'] == 0, f'Escape did not close the modal {state}')
        require(state['shownMembers'] == 0, f'modal contents stayed visible {state}')
        require(all(value == '' for value in state['translate']), f'placement not reset {state}')
        require(state['focused'] == OPEN_DIALOG, f'focus did not return to the opener {state}')
        return state

    def menu_below():
        page.load(site)
        trigger = page.click(OPEN_MENU)
        state = page.overlay_state('menu')
        require(state and not state['hidden'], f'menu did not open {state}')
        box = union(state['rects'])
        require(abs(box['y'] - (trigger['y'] + trigger['h'] + GAP)) <= TOLERANCE, f'menu not below trigger {box} {trigger}')
        require(abs(box['x'] - trigger['x']) <= TOLERANCE, f'menu not aligned with trigger start {box} {trigger}')
        require(state['focused'] == MENU_ITEMS[0], f'focus did not move into the menu {state}')
        page.browser.capture(captures, 'menu-below', union([box, trigger]))
        order = []
        for key in ('ArrowDown', 'End', 'Home', 'ArrowUp', 'ArrowDown'):
            page.press(key)
            order.append(page.evaluate('__sf.focused()'))
        expected = [MENU_ITEMS[1], MENU_ITEMS[-1], MENU_ITEMS[0], MENU_ITEMS[-1], MENU_ITEMS[0]]
        require(order == expected, f'arrow keys moved focus {order}, expected {expected}')
        return dict(box=box, trigger=trigger, order=order)

    def menu_flips():
        try:
            page.browser.viewport(FLOW.VIEWPORT[0], 700)
            page.load(site)
            trigger = page.click(OPEN_MENU)
            state = page.overlay_state('menu')
            box = union(state['rects'])
            require(trigger['y'] + trigger['h'] + GAP + box['h'] > 700 - GAP, f'fixture does not reach the viewport edge {trigger} {box}')
            require(abs(box['y'] + box['h'] - (trigger['y'] - GAP)) <= TOLERANCE, f'menu did not flip above {box} {trigger}')
            return dict(box=box, trigger=trigger)
        finally:
            page.browser.viewport(*FLOW.VIEWPORT)

    def reveal():
        page.load(site)
        before = page.evaluate("""(()=>{const c=document.querySelector('[data-siteforge-entrance]');
            const m=__sf.group(c).slice(1);return {count:m.length,container:getComputedStyle(c).opacity,
            members:m.map(e=>getComputedStyle(e).opacity),entered:c.classList.contains('sf-motion-entered')};})()""")
        require(before['count'] >= 1, f'container contents are not grouped {before}')
        require(not before['entered'] and before['container'] == '0' and all(v == '0' for v in before['members']),
                f'content below the fold is not waiting for its reveal {before}')
        page.evaluate("document.querySelector('[data-siteforge-entrance]').scrollIntoView({block:'center'})")
        done = FLOW.wait_until(lambda: page.evaluate("""(()=>{const c=document.querySelector('[data-siteforge-entrance]');
            return __sf.group(c).every(e=>e.classList.contains('sf-motion-entered')&&getComputedStyle(e).opacity==='1');})()"""), 5)
        require(done, 'container and contents did not reveal together')
        return before

    def visible_without_motion():
        page.browser.page.call('Emulation.setEmulatedMedia', dict(media='', features=[dict(name='prefers-reduced-motion', value='reduce')]))
        try:
            page.load(site)
            reduced = page.evaluate("""(()=>{const c=document.querySelector('[data-siteforge-entrance]');
                return {ready:document.documentElement.classList.contains('sf-motion-ready'),
                opacities:__sf.group(c).map(e=>getComputedStyle(e).opacity)};})()""")
        finally:
            page.browser.page.call('Emulation.setEmulatedMedia', dict(media='', features=[]))
        require(not reduced['ready'] and all(v == '1' for v in reduced['opacities']), f'Reduce Motion hid content {reduced}')
        page.browser.page.call('Emulation.setScriptExecutionDisabled', dict(value=True))
        try:
            page.load(site, scripts=False)
            page.browser.page.call('DOM.enable')
            page.browser.page.call('CSS.enable')
            modal = page.attribute('[data-siteforge-overlay="modal"]', 'data-siteforge-node')
            content = f'[data-siteforge-within~="{modal}"]'
            disabled = dict(modalDisplay=page.computed('[data-siteforge-overlay="modal"]', 'display'),
                            contentDisplay=page.computed(content, 'display'),
                            revealOpacity=page.computed('[data-siteforge-entrance]', 'opacity'))
        finally:
            page.browser.page.call('Emulation.setScriptExecutionDisabled', dict(value=False))
        require(disabled['modalDisplay'] == 'none' and disabled['contentDisplay'] == 'none',
                f'closed modal or its contents visible without JavaScript {disabled}')
        require(disabled['revealOpacity'] == '1', f'reveal hid content without JavaScript {disabled}')
        return dict(reduced=reduced, disabled=disabled)

    def key_presses():
        page.load(site)
        panel = page.evaluate("(()=>{const p=__sf.keyPanel();return p?{tabindex:p.getAttribute('tabindex'),tag:p.tagName}:null;})()")
        require(panel and panel['tabindex'] == '0', f'the key panel is not in the Tab order {panel}')
        start = page.evaluate('__sf.bound()')
        require(start == [STATUS_VALUES[0], STEP_VALUES[0]], f'bound texts start as {start}')
        page.press('Enter')
        require(page.evaluate('__sf.bound()') == start, 'Enter ran although its object did not have focus')
        page.evaluate('__sf.keyPanel().focus()')
        scrolled = page.evaluate('scrollY')
        observed = []
        for key in ('Enter', 'ArrowDown', 'Escape'):
            page.press(key)
            observed.append(page.evaluate('__sf.bound()'))
        expected = [[STATUS_VALUES[1], STEP_VALUES[0]], [STATUS_VALUES[1], STEP_VALUES[1]], [STATUS_VALUES[2], STEP_VALUES[1]]]
        require(observed == expected, f'key presses changed {observed}, expected {expected}')
        require(page.evaluate('scrollY') == scrolled, 'Down Arrow on the focused object also scrolled the page')
        return dict(panel=panel, observed=observed)

    def bound_text():
        page.load(site)
        regions = page.evaluate("Array.from(document.querySelectorAll('[data-siteforge-text-variable]'))"
                                ".map(e=>({live:e.getAttribute('aria-live'),atomic:e.getAttribute('aria-atomic')}))")
        require(len(regions) == 2 and all(value == dict(live='polite', atomic='true') for value in regions),
                f'bound text is not a polite live region {regions}')
        require(page.evaluate('__sf.bound()') == [STATUS_VALUES[0], STEP_VALUES[0]], 'bound text does not start with the variables')
        page.browser.page.call('Emulation.setScriptExecutionDisabled', dict(value=True))
        try:
            page.load(site, scripts=False)
            page.browser.page.call('DOM.enable')
            static = element_text(page.outer_html('[data-siteforge-text-variable]'))
        finally:
            page.browser.page.call('Emulation.setScriptExecutionDisabled', dict(value=False))
        require(static == STATUS_VALUES[0], f'without JavaScript the bound text reads {static!r}, not the starting value')
        return dict(regions=regions, static=static)

    def openers():
        page.load(site)
        probe = (f"(()=>{{const e=__sf.control({json.dumps(OPEN_DIALOG)});"
                 "return {popup:e.getAttribute('aria-haspopup'),expanded:e.getAttribute('aria-expanded')};})()")
        before = page.evaluate(probe)
        page.click(OPEN_DIALOG)
        opened = page.evaluate(probe)
        backdrop = page.evaluate("(()=>{const b=document.querySelector('.sf-overlay-backdrop');return b?b.getAttribute('aria-hidden'):null;})()")
        page.press('Escape')
        closed = page.evaluate(probe)
        require(before == dict(popup='dialog', expanded='false'), f'the opener does not announce its dialog before use {before}')
        require(opened['expanded'] == 'true' and backdrop == 'true', f'open state not announced {opened}, backdrop {backdrop}')
        require(closed['expanded'] == 'false' and page.evaluate('__sf.focused()') == OPEN_DIALOG,
                f'closed state or focus return is wrong {closed}')
        return dict(before=before, opened=opened, closed=closed, backdrop=backdrop)

    for name, body in zip(CASES, [loaded, open_modal, tab_trap, escape, menu_below, menu_flips, reveal,
                                  visible_without_motion, key_presses, bound_text, openers]):
        record(name, body)
    return cases


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True, help='directory containing the interactions/ site')
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    args.captures.mkdir(parents=True, exist_ok=True)
    if not (args.root / FIXTURE / 'index.html').is_file():
        raise SystemExit(f'Missing compiled fixture site: {FIXTURE}')
    cases, version, failure, browser = [], None, None, None

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *values, **options):
            super().__init__(*values, directory=str(args.root), **options)

        def log_message(self, *values):
            pass

    def expire(*_):
        raise TimeoutError(f'browser checks exceeded {args.timeout} seconds')

    signal.signal(signal.SIGALRM, expire)
    signal.alarm(args.timeout)
    parent = os.getppid()

    def watch_parent():
        while True:
            time.sleep(0.5)
            if os.getppid() != parent:
                os.kill(os.getpid(), signal.SIGALRM)
                return

    threading.Thread(target=watch_parent, daemon=True).start()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}/'
    try:
        chrome = FLOW.browser_executable()
        with tempfile.TemporaryDirectory(prefix='siteforge-interaction-browser-') as profile:
            with (args.captures / 'chrome.log').open('wb') as log:
                browser = FLOW.Browser(chrome, profile, log)
                version = browser.version
                cases = run_cases(Page(browser), base, args.captures)
                browser.close()
                browser = None
    except BaseException as error:
        failure = f'{type(error).__name__}: {error}'
    finally:
        signal.alarm(0)
        if browser:
            browser.close()
        server.shutdown()
        server.server_close()
    recorded = {entry['case'] for entry in cases}
    for name in CASES:
        if name not in recorded:
            cases.append(dict(case=name, outcome='failed', seconds=0, detail=failure or 'not executed'))
    passed = sum(entry['outcome'] == 'passed' for entry in cases)
    args.report.write_text(json.dumps(dict(version=1, kind='actual-local-browser-checks', requirements=REQUIREMENTS,
        browser=version, failure=failure, cases=cases, total=len(cases), passed=passed,
        failed=len(cases) - passed), indent=2, default=str) + '\n')
    return 0 if passed == len(CASES) == len(cases) else 1


if __name__ == '__main__':
    raise SystemExit(main())
