#!/usr/bin/env python3
"""OpenIPC KMS player with a performance OSD (pango textoverlay, 1 Hz updates).

Pipeline order matters: text is drawn on the landscape frame BEFORE rotation, so
it rotates together with the video and stays upright when the device is held
sideways. No per-frame Python callbacks (keeps the pipeline at full speed).
"""
import os
import re
import time

import gi

gi.require_version('Gst', '1.0')
from gi.repository import GLib, Gst

Gst.init(None)


def _conf():
    c = {}
    try:
        with open('/etc/openipc-rx.conf') as f:
            for ln in f:
                ln = ln.strip()
                if ln and not ln.startswith('#') and '=' in ln:
                    k, v = ln.split('=', 1)
                    c[k.strip()] = v.strip()
    except Exception:
        pass
    return c


CONF = _conf()
if os.environ.get('FORWARD_ENABLE', CONF.get('FORWARD_ENABLE', '0')) == '1':
    PORT = int(os.environ.get('LOCAL_PORT', CONF.get('LOCAL_PORT', '5602')))
else:
    PORT = int(os.environ.get('LOCAL_PORT', CONF.get('RX_PORT', '5600')))

WFB_LOG = os.environ.get('WFB_LOG', '/tmp/wfb_rx.log')
OSD_FONT = os.environ.get('OSD_FONT', 'DejaVu Sans Mono 22')
CH = CONF.get('CH', '161')
PANEL_W, PANEL_H = 480, 800

S = {'fps': 0.0, 'avg': 0.0, 'frames': 0, 'drop': 0, 'rtp': 0, 'res': '-', 'bit': 0.0, 'lost': 0, 'rssi': '-',
     'cpu': 0.0, 'temp': 0.0, 'up': 0}
_cpu_prev = None


def read_cpu():
    global _cpu_prev
    try:
        with open('/proc/stat') as f:
            v = [int(x) for x in f.readline().split()[1:]]
        idle, total = v[3] + (v[4] if len(v) > 4 else 0), sum(v)
        if _cpu_prev:
            di, dt = idle - _cpu_prev[0], total - _cpu_prev[1]
            _cpu_prev = (idle, total)
            if dt > 0:
                return max(0.0, 100.0 * (1.0 - di / dt))
        _cpu_prev = (idle, total)
    except Exception:
        pass
    return 0.0


def read_temp():
    for i in range(6):
        try:
            with open('/sys/class/thermal/thermal_zone%d/temp' % i) as f:
                t = int(f.read().strip())
            if 0 < t < 200000:
                return t / 1000.0
        except Exception:
            continue
    return 0.0


def read_wfb():
    try:
        with open(WFB_LOG, 'rb') as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - 8192))
            tail = f.read().decode('utf-8', 'ignore')
    except Exception:
        return
    for line in tail.splitlines():
        if '\tRX_ANT\t' in line:
            try:
                v = line.split('\t')[-1].split(':')
                if len(v) > 1:
                    S['rssi'] = '%d dBm' % int(v[1])
            except Exception:
                pass
        elif '\tPKT\t' in line:
            try:
                v = line.split('\t')[-1].split(':')
                if len(v) >= 8:
                    S['lost'] = int(v[7]) + int(v[6])
                if len(v) >= 11:
                    S['bit'] = int(v[10]) * 8 / 1e6
                    S['rtp'] = int(v[9])
            except Exception:
                pass


DESC = (
    'udpsrc port=%d buffer-size=33554432 '
    'caps="application/x-rtp, media=(string)video, payload=(int)97, '
    'clock-rate=(int)90000, encoding-name=(string)H265" name=src '
    '! rtpjitterbuffer latency=15 mode=none '
    '! rtph265depay ! h265parse '
    '! video/x-h265,stream-format=byte-stream,alignment=au '
    '! mppvideodec name=dec '
    '! queue leaky=downstream max-size-buffers=3 max-size-time=0 max-size-bytes=0 '
    '! videoconvert '
    '! textoverlay name=osd text="" valignment=top halignment=left '
    '   shaded-background=true font-desc="%s" '
    '! videoflip method=counterclockwise '
    '! videoscale method=1 add-borders=true '
    '! video/x-raw,width=%d,height=%d '
    '! kmssink sync=false'
) % (PORT, OSD_FONT, PANEL_W, PANEL_H)

pipe = Gst.parse_launch(DESC)
osd = pipe.get_by_name('osd')
fpsel = None
dec = pipe.get_by_name('dec')


_fc = [0]


def on_frame(pad, info, _u):
    _fc[0] += 1
    return Gst.PadProbeReturn.OK


def on_fps(_el, fps, droprate, avgfps):
    S['fps'] = fps
    S['drop'] = droprate


def read_fps_props():
    if fpsel is None:
        return
    try:
        msg = fpsel.get_property('last-message') or ''
        m = re.search(r'rendered: (\d+), dropped: (\d+), current: ([0-9.]+), average: ([0-9.]+)', msg)
        if m:
            S['frames'] = int(m.group(1))
            S['drop'] = int(m.group(2))
            S['fps'] = float(m.group(3))
            S['avg'] = float(m.group(4))
    except Exception:
        pass


if fpsel is not None:
    try:
        fpsel.connect('fps-measurements', on_fps)
    except Exception:
        pass



def text():
    return '\n'.join([
        'RES %s   1280x720 @ %s' % (S['res'], CH),
        'BIT %.2f Mb/s  RTP %d p/s' % (S['bit'], S['rtp']),
        'LOST %d  RSSI %s' % (S['lost'], S['rssi']),
        'CPU %.1f%%  SoC %.1fC' % (S['cpu'], S['temp']),
        'UP %s' % time.strftime('%H:%M:%S', time.gmtime(S['up'])),
    ])


_low = [0]
_restarting = [False]


def _restart():
    # full process re-exec: a fresh DRM/GStreamer init is what actually heals it
    pipe.set_state(Gst.State.NULL)
    with open('/tmp/osd-restarts.log', 'a') as f:
        f.write('%s low-fps restart\n' % time.strftime('%H:%M:%S'))
    os.execv('/usr/bin/python3', ['/usr/bin/python3', '/usr/local/sbin/openipc-kms-osd.py'])
    return False


def tick():
    if dec is not None:
        c = dec.get_static_pad('src').get_current_caps()
        if c and c.get_size() > 0:
            st = c.get_structure(0)
            try:
                S['res'] = '%dx%d' % (st.get_value('width'), st.get_value('height'))
            except Exception:
                pass
    S['cpu'] = read_cpu()
    S['temp'] = read_temp()
    S['up'] += 1
    if not _restarting[0]:
        # self-heal: pipeline stuck at a very low rate (e.g. started before the
        # stream was flowing) -> rebuild it once
        if S['frames'] > 0 and S['fps'] < 5.0:
            _low[0] += 1
        else:
            _low[0] = 0
        if _low[0] >= 6:
            _restarting[0] = True
            GLib.timeout_add(100, _restart)
            _low[0] = 0
    read_wfb()
    read_fps_props()

    if osd is not None:
        osd.set_property('text', text())
    try:
        if os.path.exists('/tmp/osd-metrics.log') and os.path.getsize('/tmp/osd-metrics.log') > 200000:
            os.remove('/tmp/osd-metrics.log')
        with open('/tmp/osd-metrics.log', 'a') as f:
            f.write('%s fps=%.1f avg=%.1f frm=%d drp=%d res=%s bit=%.2f lost=%d rssi=%s cpu=%.1f temp=%.1f\n'
                    % (time.strftime('%H:%M:%S'), S['fps'], S['avg'], S['frames'], S['drop'], S['res'],
                       S['bit'], S['lost'], S['rssi'], S['cpu'], S['temp']))
    except Exception:
        pass
    return True


GLib.timeout_add(1000, tick)
pipe.set_state(Gst.State.PLAYING)

ctx = GLib.MainContext.default()
while True:
    try:
        while ctx.pending():
            ctx.iteration(False)
        time.sleep(0.03)
    except KeyboardInterrupt:
        break
pipe.set_state(Gst.State.NULL)
