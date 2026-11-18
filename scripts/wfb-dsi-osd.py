#!/usr/bin/python3
import glob, os, re, select, struct, threading, time
import cairo, gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib
Gst.init(None)

LOG = '/tmp/wfb_rx.log'
PAGES = 2
page = 0
frames = 0
last_frames = 0
last_t = 0.0
cpu_prev = None
stats = {'wfb': {'ok': False, 'age': 99.0, 'ch': 161, 'freq': 5805, 'rssi': 0,
                 'bit': 0.0, 'rtp': 0, 'lost': 0}, 'rk': {}, 'fps': 0.0}

def fread(p):
    try:
        return open(p).read().strip()
    except Exception:
        return ''

def read_cpu():
    global cpu_prev
    try:
        v = [int(x) for x in open('/proc/stat').readline().split()[1:]]
    except Exception:
        return 0.0
    idle = v[3] + (v[4] if len(v) > 4 else 0)
    tot = sum(v)
    p = 0.0
    if cpu_prev:
        di, dt = idle - cpu_prev[0], tot - cpu_prev[1]
        if dt > 0:
            p = max(0.0, 100.0 * (1.0 - di / dt))
    cpu_prev = (idle, tot)
    return p

def read_temp():
    soc = gpu = mx = 0.0
    for z in glob.glob('/sys/class/thermal/thermal_zone*'):
        try:
            t = int(fread(z + '/temp')) / 1000.0
        except Exception:
            continue
        typ = fread(z + '/type')
        if 'soc' in typ:
            soc = t
        elif 'gpu' in typ:
            gpu = t
        else:
            mx = max(mx, t)
    return soc or mx, gpu or mx

def read_mem():
    d = {}
    try:
        for l in open('/proc/meminfo'):
            if l.startswith(('MemTotal:', 'MemAvailable:')):
                d[l.split(':')[0]] = int(l.split()[1])
    except Exception:
        return 0.0, 0.0, 0.0
    tot = d.get('MemTotal', 1)
    av = d.get('MemAvailable', 0)
    return 100.0 * (tot - av) / tot, (tot - av) / 1048576.0, tot / 1048576.0

def read_freqs():
    def dev(n):
        try:
            return int(int(fread('/sys/class/devfreq/' + n + '/cur_freq')) / 1e6)
        except Exception:
            return 0
    try:
        cpu = int(int(fread('/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq')) / 1e3)
    except Exception:
        cpu = 0
    return cpu, dev('dmc'), dev('fde60000.gpu'), dev('fde40000.npu'), dev('fdf80200.rkvdec')

def read_wfb():
    w = dict(stats['wfb'])
    try:
        st = os.stat(LOG)
        w['age'] = max(0.0, time.time() - st.st_mtime)
        w['ok'] = w['age'] < 2.5
        with open(LOG, 'rb') as f:
            f.seek(max(0, st.st_size - 8192))
            tail = f.read().decode('utf-8', 'ignore')
    except Exception:
        return w
    for l in tail.splitlines():
        if '\tRX_ANT\t' in l:
            f = l.split('\t')
            try:
                w['freq'] = int(f[2].split(':')[0])
                w['rssi'] = int(f[4].split(':')[1])
                w['ch'] = (w['freq'] - 5000) // 5 if w['freq'] >= 5000 else (w['freq'] - 2407) // 5
            except Exception:
                pass
        elif '\tPKT\t' in l:
            try:
                v = l.split('\t')[2].split(':')
                if len(v) >= 11:
                    w['lost'] = int(v[6]) + int(v[7])
                    w['rtp'] = int(v[9])
                    w['bit'] = int(v[10]) * 8 / 1e6
            except Exception:
                pass
    return w

def read_rk():
    cpu = read_cpu()
    try:
        load = float(fread('/proc/loadavg').split()[0])
    except Exception:
        load = 0.0
    soc, gpu = read_temp()
    mp, mu, mt = read_mem()
    cf, ddr, gf, npu, vdec = read_freqs()
    up = '-'
    try:
        s = int(float(fread('/proc/uptime').split()[0]))
        up = '%02d:%02d:%02d' % (s // 3600, (s % 3600) // 60, s % 60)
    except Exception:
        pass
    return {'cpu': cpu, 'load': load, 'soc': soc, 'gpu': gpu, 'mem': mp, 'used': mu,
            'total': mt, 'cf': cf, 'ddr': ddr, 'gpu_f': gf, 'npu': npu, 'vdec': vdec, 'up': up}

def update():
    global frames, last_frames, last_t
    stats['wfb'] = read_wfb()
    stats['rk'] = read_rk()
    now = time.monotonic()
    dt = now - last_t
    if dt > 0.2:
        stats['fps'] = (frames - last_frames) / dt
        last_frames = frames
        last_t = now
    return True

def build_lines():
    w, r, fps = stats['wfb'], stats['rk'], stats['fps']
    if page == 0:
        if not w['ok']:
            return ['WFB LINK  1/2', 'NO DATA', 'age %.1fs' % w['age'], '', 'TOUCH -> RK3566']
        return ['WFB LINK  1/2',
                'CH %d  %d MHz' % (w['ch'], w['freq']),
                'RSSI %d dBm' % w['rssi'],
                'BIT %.2f Mb/s' % w['bit'],
                'RTP %d p/s' % w['rtp'],
                'LOST %d' % w['lost'],
                'FPS %.0f' % fps,
                'STREAM 7669206',
                'TOUCH -> RK3566']
    return ['RK3566  2/2',
            'CPU %.0f%%  %.2f GHz' % (r.get('cpu', 0), r.get('cf', 0) / 1000.0),
            'LOAD %.2f' % r.get('load', 0),
            'SOC %.0fC  GPU %.0fC' % (r.get('soc', 0), r.get('gpu', 0)),
            'MEM %.0f%% %.1f/%.1fG' % (r.get('mem', 0), r.get('used', 0), r.get('total', 0)),
            'DDR %d  GPU %d' % (r.get('ddr', 0), r.get('gpu_f', 0)),
            'NPU %d  VDEC %d' % (r.get('npu', 0), r.get('vdec', 0)),
            'UP %s' % r.get('up', '-'),
            'TOUCH -> WFB']

def draw_box(cr, lines):
    x, y, w, h = 8, 8, 400, 240
    cr.set_source_rgba(0, 0, 0, 0.45)
    cr.rectangle(x, y, w, h)
    cr.fill()
    cr.set_source_rgba(1, 1, 1, 0.25)
    cr.set_line_width(2)
    cr.rectangle(x, y, w, h)
    cr.stroke()
    cr.select_font_face('DejaVu Sans Mono', cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    cr.set_font_size(16)
    cr.set_source_rgb(0.3, 1.0, 0.7)
    cr.move_to(x + 12, y + 26)
    cr.show_text(lines[0])
    cr.select_font_face('DejaVu Sans Mono', cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(13)
    cr.set_source_rgb(1, 1, 1)
    yy = y + 54
    for line in lines[1:-1]:
        cr.move_to(x + 12, yy)
        cr.show_text(line)
        yy += 20
    cr.set_font_size(12)
    cr.set_source_rgb(1.0, 0.85, 0.2)
    cr.move_to(x + 12, y + h - 16)
    cr.show_text(lines[-1])

def on_draw(osd, cr, ts, dur):
    global frames
    frames += 1
    draw_box(cr, build_lines())

def find_touch():
    try:
        for b in open('/proc/bus/input/devices').read().split('\n\n'):
            if 'CST128 TouchScreen' in b:
                m = re.search(r'Handlers=(.*)', b)
                if m:
                    for e in m.group(1).split():
                        if e.startswith('event'):
                            return '/dev/input/' + e
    except Exception:
        pass
    return '/dev/input/event5'

def touch_loop():
    global page
    path = find_touch()
    print('touch: ' + path, flush=True)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except Exception as e:
        print('touch open failed: %s' % e, flush=True)
        return
    ev = struct.Struct('llHHi')
    last = 0.0
    while True:
        try:
            r, _, _ = select.select([fd], [], [], 1.0)
            if not r:
                continue
            data = os.read(fd, ev.size * 64)
        except Exception:
            time.sleep(1)
            continue
        for i in range(0, len(data) - ev.size + 1, ev.size):
            sec, usec, typ, code, val = ev.unpack_from(data, i)
            hit = (typ == 1 and code == 330 and val == 1) or \
                  (typ == 3 and code in (0, 1, 53, 54, 57) and val > 0)
            if hit:
                now = time.monotonic()
                if now - last > 0.4:
                    last = now
                    page = (page + 1) % PAGES
                    print('page %d' % page, flush=True)

DESC = ('udpsrc port=5600 buffer-size=33554432 '
        'caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" '
        '! rtpjitterbuffer latency=0 mode=none ! rtph265depay ! h265parse '
        '! video/x-h265,stream-format=byte-stream,alignment=au ! mppvideodec '
        '! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0 '
        '! videoconvert ! videoscale add-borders=true '
        '! video/x-raw,width=480,height=800 ! videoconvert ! video/x-raw,format=BGRA '
        '! cairooverlay name=osd ! kmssink sync=false')

loop = None

def on_msg(bus, msg):
    if msg.type == Gst.MessageType.ERROR:
        err, dbg = msg.parse_error()
        print('ERROR: %s %s' % (err, dbg), flush=True)
        if loop:
            loop.quit()
    elif msg.type == Gst.MessageType.EOS:
        print('EOS', flush=True)
        if loop:
            loop.quit()

def main():
    global loop
    pipe = Gst.parse_launch(DESC)
    osd = pipe.get_by_name('osd')
    osd.connect('draw', on_draw)
    bus = pipe.get_bus()
    bus.add_signal_watch()
    bus.connect('message', on_msg)
    pipe.set_state(Gst.State.PLAYING)
    update()
    GLib.timeout_add(500, update)
    threading.Thread(target=touch_loop, daemon=True).start()
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        pipe.set_state(Gst.State.NULL)

if __name__ == '__main__':
    main()
