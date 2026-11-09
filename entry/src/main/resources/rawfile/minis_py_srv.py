import os
import sys
import time

# Long-lived interpreter for the python_execute tool. The app writes a request
# file (`id=<n>\n<code>`) into the workspace and polls this file for a marker;
# every request reuses the same globals, so imports and variables survive
# between tool calls.
DIR = '/var/minis/workspace/.minis-py'
REQ = DIR + '/req.txt'
OUT = DIR + '/out.txt'
READY = DIR + '/ready.txt'

# The app truncates to 20000 characters; keep the file small enough that
# polling it every few milliseconds stays cheap even on iSH's slow filesystem.
LIMIT = 100000

os.makedirs(DIR, exist_ok=True)
try:
    os.chdir('/var/minis/workspace')
except OSError:
    pass


class Sink(object):
    """Captures stdout/stderr into out.txt, capped at LIMIT characters."""

    def __init__(self):
        self.left = LIMIT
        self.cut = False

    def write(self, text):
        if not text:
            return 0
        if self.left <= 0:
            self.cut = True
            return len(text)
        data = text[:self.left]
        with open(OUT, 'a') as handle:
            handle.write(data)
        self.left -= len(data)
        if len(data) < len(text):
            self.cut = True
        return len(text)

    def flush(self):
        pass


def dump_exc():
    # `import traceback` pulls in linecache, tokenize, textwrap and friends:
    # about 4.5 seconds on iSH. Pay that only when a request actually fails.
    try:
        import traceback
    except BaseException:
        return
    try:
        traceback.print_exc(file=sys.stderr)
    except BaseException:
        pass


def mark(rid, ms, status):
    with open(OUT, 'a') as handle:
        handle.write('\n__MINIS_DONE__ %d %d %d\n' % (rid, ms, status))
        handle.flush()


sink = Sink()
sys.stdout = sink
sys.stderr = sink
try:
    open(OUT, 'w').close()
except OSError:
    pass
with open(READY, 'w') as handle:
    handle.write(str(os.getpid()))

ns = {'__name__': '__main__'}
last = 0
warm = [
    'json', 're', 'sqlite3', 'hashlib', 'datetime', 'math',
    'random', 'collections', 'itertools', 'base64', 'csv', 'subprocess',
    'socket', 'urllib.parse',
]
idle_since = time.monotonic()

while True:
    try:
        text = open(REQ, 'r').read()
    except OSError:
        text = ''
    rid = 0
    if text:
        head, _, code = text.partition('\n')
        try:
            rid = int(head.strip().split('=')[1])
        except Exception:
            rid = 0
    if rid <= last:
        now = time.monotonic()
        # Import one common module only after a quiet second. A request that
        # arrives mid-import waits for it, exactly as it would have paid that
        # import on first use; idle time is otherwise wasted.
        if warm and now - idle_since > 1.0:
            name = warm.pop(0)
            try:
                __import__(name)
            except BaseException:
                pass
            idle_since = time.monotonic()
        time.sleep(0.02)
        continue
    last = rid
    sink.left = LIMIT
    sink.cut = False
    try:
        open(OUT, 'w').close()
    except OSError:
        pass
    started = time.monotonic()
    status = 0
    try:
        exec(compile(code, '<minis-python>', 'exec'), ns)
    except SystemExit:
        # exit() in user code must not take the resident interpreter down.
        status = 0
    except BaseException:
        status = 1
        dump_exc()
    ms = int((time.monotonic() - started) * 1000)
    if sink.cut:
        try:
            with open(OUT, 'a') as handle:
                handle.write('\n[... output truncated at %d characters ...]' % LIMIT)
        except OSError:
            pass
    mark(rid, ms, status)
    idle_since = time.monotonic()
