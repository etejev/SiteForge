#!/usr/bin/env python3
"""Actual-browser checks for the one shared SiteForge Flow runtime.

SF-1101-003/004/006, SF-1103-002/003/004/006, SF-1201-003/004, SF-1204-003/004.
Invoked by SupportSettingsTests.testFlowRuntimeActualBrowserDeformationFallbacksAndLifecycle
with sites compiled by MultiPageStaticBuildPlanner and written in the Static Release profile
(fixtures: small, large, link), so the Flow runtime loads from the one content-hashed
runtime file (OD-042, ADR-0124).
Standard library only: an owned temporary Chrome profile, loopback DevTools and a
loopback static server. No owner profile, network destination, browser sandbox
change or external asset. Every case is recorded; none is skipped.
"""
import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import signal
import socket
import struct
import subprocess
import tempfile
import threading
import time
import zlib

REQUIREMENTS = ['SF-1101-003', 'SF-1101-004', 'SF-1101-006', 'SF-1103-002', 'SF-1103-003', 'SF-1103-004',
                'SF-1103-006', 'SF-1201-003', 'SF-1201-004', 'SF-1204-003', 'SF-1204-004']
CASES = ['webgl-and-shared-runtime-available', 'pointer-movement-deforms-gradient',
         'radius-and-strength-scale-deformation', 'pointer-leave-returns-to-static-rest',
         'single-pending-frame-budget', 'reduced-motion-keeps-static-gradient',
         'no-hover-keeps-static-gradient', 'javascript-disabled-keeps-static-gradient-and-links',
         'removal-and-pagehide-dispose-runtime', 'decorative-canvas-never-intercepts-pointer',
         'resize-keeps-bounded-canvas-matched']
VIEWPORT = (1440, 900)
CHANGED_CHANNEL_DELTA = 6
MAXIMUM_RASTER = (1024, 768, 786432)
EXAMPLE_LINK = 'a[href="https://example.com"]'
RUNTIME_BUNDLE = re.compile(r'(?:^|/)siteforge-runtime\.[0-9a-f]{64}\.js$')


def loads_effects_runtime(scripts):
    """True when a page loads the Flow runtime: Development's readable siteforge-effects.js, or
    Static Release's one content-hashed siteforge-runtime.<sha256>.js naming the effects part."""
    for script in scripts:
        source = script.get('src') or ''
        parts = (script.get('parts') or '').split()
        if source.endswith('siteforge-effects.js') or (RUNTIME_BUNDLE.search(source) and 'effects' in parts):
            return True
    return False


def browser_executable():
    candidate = Path(os.environ.get('SITEFORGE_CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'))
    if not candidate.is_file() or not os.access(candidate, os.X_OK):
        raise RuntimeError('Flow browser verification requires executable Google Chrome. '
                           'Install Chrome from its official source, or set SITEFORGE_CHROME '
                           f'to its executable path. Unavailable prerequisite: {candidate}')
    return candidate


class Protocol:
    """Minimal RFC 6455 client for a loopback DevTools endpoint."""

    def __init__(self, url):
        from urllib.parse import urlsplit
        target = urlsplit(url)
        if target.hostname not in ('127.0.0.1', 'localhost'):
            raise ValueError('DevTools endpoint must be loopback')
        self.socket = socket.create_connection((target.hostname, target.port), timeout=20)
        self.buffer = b''
        self.serial = 0
        self.events = []
        key = base64.b64encode(os.urandom(16)).decode()
        self.socket.sendall((f'GET {target.path} HTTP/1.1\r\nHost: {target.netloc}\r\nUpgrade: websocket\r\n'
                             f'Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
        while b'\r\n\r\n' not in self.buffer:
            chunk = self.socket.recv(4096)
            if not chunk:
                raise RuntimeError('Browser protocol handshake closed')
            self.buffer += chunk
        header, self.buffer = self.buffer.split(b'\r\n\r\n', 1)
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
        if not header.startswith(b'HTTP/1.1 101') or accept not in header:
            raise RuntimeError('Browser protocol handshake rejected')

    def read(self, count):
        while len(self.buffer) < count:
            chunk = self.socket.recv(max(4096, count - len(self.buffer)))
            if not chunk:
                raise RuntimeError('Browser protocol connection closed')
            self.buffer += chunk
        value, self.buffer = self.buffer[:count], self.buffer[count:]
        return value

    def send(self, payload, opcode=1):
        mask = os.urandom(4)
        size = len(payload)
        if size < 126:
            length = bytes([size | 128])
        elif size < 65536:
            length = bytes([126 | 128]) + struct.pack('!H', size)
        else:
            length = bytes([127 | 128]) + struct.pack('!Q', size)
        self.socket.sendall(bytes([128 | opcode]) + length + mask + bytes(v ^ mask[i % 4] for i, v in enumerate(payload)))

    def receive(self):
        fragments = []
        while True:
            first, second = self.read(2)
            size = second & 127
            if size == 126:
                size = struct.unpack('!H', self.read(2))[0]
            elif size == 127:
                size = struct.unpack('!Q', self.read(8))[0]
            if size > 64 * 1024 * 1024:
                raise RuntimeError('Browser protocol frame budget exceeded')
            mask = self.read(4) if second & 128 else None
            payload = self.read(size)
            if mask:
                payload = bytes(v ^ mask[i % 4] for i, v in enumerate(payload))
            opcode = first & 15
            if opcode == 8:
                raise RuntimeError('Browser protocol closed')
            if opcode == 9:
                self.send(payload, 10)
                continue
            if opcode == 10:
                continue
            if opcode not in (0, 1):
                raise RuntimeError('Unexpected browser protocol frame')
            fragments.append(payload)
            if first & 128:
                return json.loads(b''.join(fragments))

    def call(self, method, parameters=None):
        self.serial += 1
        self.send(json.dumps(dict(id=self.serial, method=method, params=parameters or {})).encode())
        while True:
            try:
                reply = self.receive()
            except socket.timeout as error:
                raise TimeoutError(f'Chrome did not answer {method}') from error
            if reply.get('id') == self.serial:
                if 'error' in reply:
                    raise RuntimeError(f'{method}: {reply["error"]}')
                return reply.get('result', {})
            if len(self.events) < 500:
                self.events.append(reply)

    def evaluate(self, program):
        reply = self.call('Runtime.evaluate', dict(expression=program, returnByValue=True, awaitPromise=True))
        if 'exceptionDetails' in reply:
            raise RuntimeError(f'Page evaluation failed: {reply["exceptionDetails"].get("text")}')
        return reply.get('result', {}).get('value')

    def close(self):
        self.socket.close()


def png_pixels(data):
    """Decodes an 8-bit, non-interlaced RGB/RGBA PNG (Chrome's screenshot format)."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Not a PNG')
    offset, compressed, header = 8, [], None
    while offset < len(data):
        size = struct.unpack('!I', data[offset:offset + 4])[0]
        tag, body = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + size]
        offset += size + 12
        if tag == b'IHDR':
            header = struct.unpack('!IIBBBBB', body)
        elif tag == b'IDAT':
            compressed.append(body)
        elif tag == b'IEND':
            break
    if header is None:
        raise ValueError('PNG has no header')
    width, height, depth, color, _, _, interlace = header
    if depth != 8 or color not in (2, 6) or interlace != 0:
        raise ValueError('Unsupported PNG layout')
    channels = 3 if color == 2 else 4
    stride = width * channels
    raw = zlib.decompress(b''.join(compressed))
    if len(raw) != height * (stride + 1):
        raise ValueError('Truncated PNG data')
    rows, previous, offset = [], bytearray(stride), 0

    def paeth(a, b, c):
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        return a if pa <= pb and pa <= pc else b if pb <= pc else c

    for _ in range(height):
        kind = raw[offset]
        offset += 1
        row = bytearray(raw[offset:offset + stride])
        offset += stride
        if kind > 4:
            raise ValueError('Unsupported PNG filter')
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            predict = (0, a, b, (a + b) // 2, paeth(a, b, c))[kind]
            row[x] = (row[x] + predict) & 255
        rows.append(bytes(row))
        previous = row
    return width, height, channels, b''.join(rows)


def pixel_difference(first, second, region=None):
    """Counts pixels whose summed RGB delta exceeds CHANGED_CHANNEL_DELTA."""
    wa, ha, ca, pa = png_pixels(first)
    wb, hb, cb, pb = png_pixels(second)
    if (wa, ha) != (wb, hb):
        raise ValueError(f'Capture sizes differ: {(wa, ha)} vs {(wb, hb)}')
    x, y, w, h = region or (0, 0, wa, ha)
    changed = total = error = 0
    for row in range(max(0, int(y)), min(ha, int(y + h))):
        for column in range(max(0, int(x)), min(wa, int(x + w))):
            delta = sum(abs(pa[(row * wa + column) * ca + i] - pb[(row * wb + column) * cb + i]) for i in range(3))
            changed += delta > CHANGED_CHANNEL_DELTA
            error += delta
            total += 1
    return dict(changedPixels=changed, meanChannelDifference=error / max(1, total * 3), pixels=total)


def raster_within_budget(width, height):
    limit_w, limit_h, limit_area = MAXIMUM_RASTER
    return 1 <= width <= limit_w and 1 <= height <= limit_h and width * height <= limit_area


class Browser:
    """Owned headless Chrome page driving actual compiled output."""

    def __init__(self, chrome, profile, log):
        self.process = subprocess.Popen([str(chrome), '--headless=new', '--remote-debugging-address=127.0.0.1',
            '--remote-debugging-port=0', '--user-data-dir=' + profile, '--no-first-run', '--no-default-browser-check',
            '--disable-extensions', '--disable-background-networking', '--disable-component-update', '--disable-sync',
            '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
            '--disable-backgrounding-occluded-windows', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
            '--hide-scrollbars', '--force-device-scale-factor=1', f'--window-size={VIEWPORT[0]},{VIEWPORT[1]}',
            'about:blank'], stdout=log, stderr=log, start_new_session=True)
        port_file = Path(profile) / 'DevToolsActivePort'
        deadline = time.monotonic() + 30
        while not port_file.exists() or len(port_file.read_text().splitlines()) < 2:
            if self.process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Owned Chrome failed to start')
            time.sleep(0.05)
        port, endpoint = port_file.read_text().splitlines()[:2]
        self.browser = Protocol(f'ws://127.0.0.1:{port}{endpoint}')
        self.version = self.browser.call('Browser.getVersion')
        target = self.browser.call('Target.createTarget', dict(url='about:blank'))['targetId']
        self.page = Protocol(f'ws://127.0.0.1:{port}/devtools/page/{target}')
        self.page.call('Page.enable')
        self.page.call('Runtime.enable')
        self.page.call('Page.bringToFront')
        self.viewport(*VIEWPORT)

    def viewport(self, width, height):
        self.size = (width, height)
        self.page.call('Emulation.setDeviceMetricsOverride',
                       dict(width=width, height=height, deviceScaleFactor=1, mobile=False))

    def navigate(self, url, scripts=True):
        """Loads a fresh document; a unique query prevents reusing the previous one."""
        self.loads = getattr(self, 'loads', 0) + 1
        target = f'{url}{"&" if "?" in url else "?"}load={self.loads}'
        self.page.call('Page.navigate', dict(url=target))
        deadline = time.monotonic() + 15
        if scripts:
            probe = (f"document.URL==={json.dumps(target)}&&document.readyState==='complete'"
                     "&&!!document.querySelector('[data-siteforge-flow]')&&!!window.SiteForgeDecorativeEffects")
            while time.monotonic() < deadline:
                if self.page.evaluate(probe):
                    self.frames(3)
                    return
                time.sleep(0.05)
        else:
            while time.monotonic() < deadline:
                root = self.document()
                if root and root.get('documentURL') == target and self.query_count('[data-siteforge-flow]') == 1:
                    time.sleep(0.5)
                    return
                time.sleep(0.1)
        raise RuntimeError(f'Compiled website did not finish loading: {target}')

    def document(self):
        try:
            return self.page.call('DOM.getDocument', dict(depth=0))['root']
        except RuntimeError:
            return None

    def query_count(self, selector):
        root = self.document()
        if not root:
            return -1
        try:
            return len(self.page.call('DOM.querySelectorAll', dict(nodeId=root['nodeId'], selector=selector))['nodeIds'])
        except RuntimeError:
            return -1

    def frames(self, count=1):
        self.page.evaluate('new Promise(r=>{let n=%d;const f=()=>(--n<=0)?r(true):requestAnimationFrame(f);'
                           'requestAnimationFrame(f);})' % max(1, count))

    def statistics(self):
        return self.page.evaluate('window.SiteForgeDecorativeEffects?window.SiteForgeDecorativeEffects.statistics():null')

    def rect(self, selector='[data-siteforge-flow]'):
        value = self.page.evaluate("(()=>{const e=document.querySelector(%s);if(!e)return null;"
                                   "const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};})()"
                                   % json.dumps(selector))
        if not value:
            raise RuntimeError(f'Missing element {selector}')
        return value

    def capture(self, directory, name, rect):
        x, y = max(0, int(rect['x'])), max(0, int(rect['y']))
        w = max(1, min(int(rect['w']), self.size[0] - x))
        h = max(1, min(int(rect['h']), self.size[1] - y))
        data = base64.b64decode(self.page.call('Page.captureScreenshot', dict(format='png', fromSurface=True,
            captureBeyondViewport=False, clip=dict(x=x, y=y, width=w, height=h, scale=1)))['data'])
        (directory / (name + '.png')).write_bytes(data)
        return data

    def move(self, x, y):
        self.page.call('Input.dispatchMouseEvent', dict(type='mouseMoved', x=x, y=y, button='none', buttons=0))

    def sweep(self, rect, row=0.5, steps=24):
        """Horizontal pointer path inside the element; returns pending-frame samples."""
        left = rect['x'] + max(4.0, rect['w'] * 0.15)
        right = min(rect['x'] + rect['w'] * 0.85, self.size[0] - 4)
        y = min(rect['y'] + rect['h'] * row, self.size[1] - 4)
        samples = []
        for index in range(steps):
            self.move(left + (right - left) * index / (steps - 1), y)
            self.frames(1)
            value = self.statistics() or {}
            samples.append(value.get('pendingFrames', -1))
        return samples

    def leave(self):
        self.move(self.size[0] - 2, self.size[1] - 2)

    def flow_state(self):
        return self.page.evaluate("(()=>{const e=document.querySelector('[data-siteforge-flow]');"
                                  "const c=e&&e.querySelector('.sf-flow-canvas');return {hasElement:!!e,hasCanvas:!!c,"
                                  "canvasHidden:c?c.hidden:true,ready:e?e.classList.contains('sf-flow-ready'):false,"
                                  "background:e?getComputedStyle(e).backgroundImage:'',canvasCount:document.querySelectorAll('.sf-flow-canvas').length};})()")

    def close(self):
        try:
            self.browser.call('Browser.close')
        except Exception:
            pass
        for client in (getattr(self, 'page', None), getattr(self, 'browser', None)):
            if client:
                try:
                    client.close()
                except Exception:
                    pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait()


def wait_until(predicate, timeout, interval=0.05):
    deadline = time.monotonic() + timeout
    value = predicate()
    while not value and time.monotonic() < deadline:
        time.sleep(interval)
        value = predicate()
    return value


def run_cases(browser, base, captures):
    """Runs every case in CASES order; a failed prerequisite fails dependants explicitly."""
    cases, state = [], {}

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

    def need(key):
        require(key in state, f'prerequisite {key} is unavailable')
        return state[key]

    def site(name):
        return base + name + '/index.html'

    def deformation(name):
        browser.navigate(site(name))
        rect = browser.rect()
        rest = browser.capture(captures, f'{name}-resting', rect)
        resting = browser.flow_state()
        require(resting['canvasHidden'] and not resting['ready'], f'{name}: canvas visible before input {resting}')
        require('linear-gradient' in resting['background'], f'{name}: static gradient missing {resting}')
        samples = browser.sweep(rect)
        moving = browser.capture(captures, f'{name}-moving', rect)
        active = browser.flow_state()
        return dict(rect=rect, rest=rest, moving=moving, samples=samples, active=active,
                    difference=pixel_difference(rest, moving), statistics=browser.statistics())

    def available():
        browser.navigate(site('large'))
        webgl = browser.page.evaluate("(()=>{const c=document.createElement('canvas');const g=c.getContext('webgl');"
                                      "if(!g)return null;const i=g.getExtension('WEBGL_debug_renderer_info');"
                                      "return {vendor:i?g.getParameter(i.UNMASKED_VENDOR_WEBGL):g.getParameter(g.VENDOR),"
                                      "renderer:i?g.getParameter(i.UNMASKED_RENDERER_WEBGL):g.getParameter(g.RENDERER)};})()")
        require(webgl, 'WebGL is unavailable in the owned test browser; the runtime cannot be exercised')
        runtime = browser.page.evaluate("(()=>({version:window.SiteForgeDecorativeEffects.version,"
                                        "scripts:Array.from(document.scripts).map(s=>({src:s.getAttribute('src'),"
                                        "parts:s.getAttribute('data-siteforge-runtime')})),"
                                        "origin:Array.from(document.scripts).every(s=>!s.src||new URL(s.src).origin===location.origin)}))()")
        require(runtime['version'] == 1, f'unexpected runtime {runtime}')
        require(loads_effects_runtime(runtime['scripts']), f'runtime script missing {runtime}')
        require(runtime['origin'], f'non-local script {runtime}')
        state['webgl'] = webgl
        return dict(webgl=webgl, runtime=runtime)

    def deforms():
        need('webgl')
        large = deformation('large')
        state['large'] = large
        changed = large['difference']['changedPixels']
        require(not large['active']['canvasHidden'] and large['active']['ready'], f'canvas not active {large["active"]}')
        require(changed >= 1000, f'pointer movement changed only {changed} pixels')
        return dict(difference=large['difference'], statistics=large['statistics'])

    def scales():
        large = need('large')
        small = deformation('small')
        state['small'] = small
        a, b = small['difference'], large['difference']
        require(b['changedPixels'] > 3 * a['changedPixels'], f'large radius/strength did not dominate: {a} vs {b}')
        require(b['meanChannelDifference'] > a['meanChannelDifference'], f'mean difference did not grow: {a} vs {b}')
        return dict(small=a, large=b)

    def rests():
        large = need('large')
        browser.navigate(site('large'))
        rect = browser.rect()
        browser.sweep(rect)
        browser.leave()
        settled = wait_until(lambda: (lambda s: s['canvasHidden'] and not s['ready'])(browser.flow_state()), 15)
        require(settled, f'flow did not return to rest {browser.flow_state()}')
        browser.frames(2)
        after = browser.capture(captures, 'large-returned', rect)
        difference = pixel_difference(large['rest'], after)
        statistics = browser.statistics()
        require(difference['changedPixels'] <= difference['pixels'] * 0.002, f'rest differs from static {difference}')
        require(statistics['active'] == 0 and statistics['pendingFrames'] == 0, f'work continued after rest {statistics}')
        state['rest-samples'] = statistics
        return dict(difference=difference, statistics=statistics)

    def budget():
        samples = need('large')['samples'] + need('small')['samples']
        require(samples and all(0 <= value <= 1 for value in samples), f'pending frame samples {samples}')
        settled = need('rest-samples')
        require(settled['instances'] == 1, f'unexpected instance count {settled}')
        return dict(samples=len(samples), maximumPending=max(samples), settled=settled)

    def static_fallback(label):
        large = need('large')
        browser.navigate(site('large'))
        rect = browser.rect()
        browser.sweep(rect, steps=12)
        statistics, flow = browser.statistics(), browser.flow_state()
        capture = browser.capture(captures, label, rect)
        difference = pixel_difference(large['rest'], capture)
        require(statistics['instances'] == 0 and flow['canvasCount'] == 0, f'{label}: runtime allocated {statistics} {flow}')
        require('linear-gradient' in flow['background'], f'{label}: static gradient missing {flow}')
        require(difference['changedPixels'] <= difference['pixels'] * 0.002, f'{label}: differs from static {difference}')
        return dict(statistics=statistics, difference=difference)

    def reduced_motion():
        browser.page.call('Emulation.setEmulatedMedia', dict(media='', features=[dict(name='prefers-reduced-motion', value='reduce')]))
        try:
            return static_fallback('large-reduced-motion')
        finally:
            browser.page.call('Emulation.setEmulatedMedia', dict(media='', features=[]))

    def no_hover():
        browser.page.call('Emulation.setTouchEmulationEnabled', dict(enabled=True, maxTouchPoints=1))
        try:
            browser.navigate(site('large'))
            hover = browser.page.evaluate("matchMedia('(hover: hover) and (pointer: fine)').matches")
            require(hover is False, 'the owned browser could not emulate a no-hover, coarse-pointer device')
            return static_fallback('large-no-hover')
        finally:
            browser.page.call('Emulation.setTouchEmulationEnabled', dict(enabled=False))

    def scripts_disabled():
        browser.navigate(site('link'))
        rect = browser.rect()
        enabled = browser.capture(captures, 'link-resting', rect)
        browser.page.call('Emulation.setScriptExecutionDisabled', dict(value=True))
        try:
            browser.navigate(site('link'), scripts=False)
            disabled = browser.capture(captures, 'link-scripts-disabled', rect)
            canvases, links = browser.query_count('.sf-flow-canvas'), browser.query_count(EXAMPLE_LINK)
        finally:
            browser.page.call('Emulation.setScriptExecutionDisabled', dict(value=False))
        difference = pixel_difference(enabled, disabled)
        require(canvases == 0, f'canvas present without JavaScript: {canvases}')
        require(links >= 1, f'links missing without JavaScript: {links}')
        require(difference['changedPixels'] <= difference['pixels'] * 0.002, f'static design changed {difference}')
        return dict(difference=difference, links=links)

    def disposal():
        browser.navigate(site('large'))
        browser.sweep(browser.rect(), steps=8)
        require(browser.statistics()['instances'] == 1, 'runtime did not start')
        browser.page.evaluate("document.querySelector('[data-siteforge-flow]').remove()")
        removed = wait_until(lambda: browser.statistics()['instances'] == 0, 5)
        require(removed, f'removed element retained an instance {browser.statistics()}')
        browser.navigate(site('large'))
        browser.sweep(browser.rect(), steps=8)
        browser.page.evaluate("window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:false}))")
        browser.frames(2)
        statistics, flow = browser.statistics(), browser.flow_state()
        require(statistics['instances'] == 0 and statistics['active'] == 0 and statistics['pendingFrames'] == 0,
                f'pagehide retained work {statistics}')
        require(flow['hasElement'] and flow['canvasCount'] == 0 and 'linear-gradient' in flow['background'],
                f'pagehide did not restore the static design {flow}')
        return dict(statistics=statistics)

    def passthrough():
        need('webgl')
        browser.navigate(site('link'))
        rect = browser.rect()
        browser.sweep(rect, row=0.2, steps=12)
        probe = browser.page.evaluate("(()=>{const f=document.querySelector('[data-siteforge-flow]');"
            "const c=f.querySelector('.sf-flow-canvas');const a=document.querySelector(%s);"
            "const r=a.getBoundingClientRect(),q=f.getBoundingClientRect();"
            "const link=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);"
            "const plain=document.elementFromPoint(q.x+q.width-12,q.y+q.height-12);"
            "return {canvasVisible:!!c&&!c.hidden,pointerEvents:c?getComputedStyle(c).pointerEvents:'',"
            "ariaHidden:c?c.getAttribute('aria-hidden'):'',linkHit:!!link&&(link===a||a.contains(link)),"
            "plainHit:plain===f,canvasHit:link===c||plain===c};})()" % json.dumps(EXAMPLE_LINK))
        require(probe['canvasVisible'], f'canvas not active {probe}')
        require(probe['pointerEvents'] == 'none' and probe['ariaHidden'] == 'true', f'decorative canvas exposed {probe}')
        require(probe['linkHit'] and probe['plainHit'] and not probe['canvasHit'], f'canvas intercepted input {probe}')
        return probe

    def resize():
        need('webgl')
        browser.navigate(site('large'))
        observations = []
        try:
            for width in (1440, 768, 390):
                browser.viewport(width, VIEWPORT[1])
                browser.frames(2)
                samples = browser.sweep(browser.rect(), steps=10)
                value = browser.page.evaluate("(()=>{const e=document.querySelector('[data-siteforge-flow]');"
                    "const c=e.querySelector('.sf-flow-canvas');const a=c.getBoundingClientRect(),b=e.getBoundingClientRect();"
                    "return {hidden:c.hidden,width:c.width,height:c.height,cssWidth:a.width,cssHeight:a.height,"
                    "elementWidth:b.width,elementHeight:b.height};})()")
                value['viewport'], value['maximumPending'] = width, max(samples)
                observations.append(value)
                require(not value['hidden'], f'canvas inactive at {width}: {value}')
                require(abs(value['cssWidth'] - value['elementWidth']) <= 1 and abs(value['cssHeight'] - value['elementHeight']) <= 1,
                        f'canvas does not match element at {width}: {value}')
                require(raster_within_budget(value['width'], value['height']), f'raster budget exceeded at {width}: {value}')
                require(max(samples) <= 1, f'pending frames at {width}: {samples}')
        finally:
            browser.viewport(*VIEWPORT)
        return observations

    for name, body in zip(CASES, [available, deforms, scales, rests, budget, reduced_motion, no_hover,
                                  scripts_disabled, disposal, passthrough, resize]):
        record(name, body)
    return cases, state.get('webgl')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True, help='directory containing small/, large/ and link/ sites')
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    args.captures.mkdir(parents=True, exist_ok=True)
    for name in ('small', 'large', 'link'):
        if not (args.root / name / 'index.html').is_file():
            raise SystemExit(f'Missing compiled fixture site: {name}')
    cases, webgl, version, failure, browser = [], None, None, None, None

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
        chrome = browser_executable()
        with tempfile.TemporaryDirectory(prefix='siteforge-browser-') as profile:
            with (args.captures / 'chrome.log').open('wb') as log:
                browser = Browser(chrome, profile, log)
                version = browser.version
                cases, webgl = run_cases(browser, base, args.captures)
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
        browser=version, webgl=webgl, failure=failure, cases=cases, total=len(cases), passed=passed,
        failed=len(cases) - passed), indent=2, default=str) + '\n')
    return 0 if passed == len(CASES) == len(cases) else 1


if __name__ == '__main__':
    raise SystemExit(main())
