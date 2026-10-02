"""Checks a video against the test pattern: displayed size, duration, and for a crop rect
(normalized, displayed coordinates) and a trim start, the colors at sample points of the frame
at `t` seconds (ffmpeg decodes with the rotation applied, as a player displays it)."""
import json, subprocess, sys, io
from PIL import Image

def probe(path):
    out = subprocess.run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',path],capture_output=True,text=True).stdout
    d = json.loads(out)
    v = next(s for s in d['streams'] if s['codec_type']=='video')
    rot = 0
    for sd in v.get('side_data_list',[]):
        if 'rotation' in sd: rot = int(sd['rotation'])
    w, h = int(v['width']), int(v['height'])
    if rot % 180: w, h = h, w
    audio = any(s['codec_type']=='audio' for s in d['streams'])
    return dict(codec=v['codec_name'], w=w, h=h, rot=rot, dur=float(d['format']['duration']), audio=audio,
                transfer=v.get('color_transfer','?'), fps=v.get('avg_frame_rate'))

def frame(path, t):
    png = subprocess.run(['ffmpeg','-v','error','-ss',str(t),'-i',path,'-frames:v','1','-f','image2pipe','-vcodec','png','-'],capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert('RGB')

def classify(c):
    r,g,b = c
    if r>180 and g<90 and b<90: return 'red'
    if g>180 and r<90 and b<90: return 'green'
    if b>180 and r<90 and g<90: return 'blue'
    if r>180 and g>180 and b>180: return 'white'
    return 'gray%d' % round((r+g+b)/3)

def expected(x, y, crop):
    # (x, y) normalized in the output -> source displayed coordinates.
    l,t,r,b = crop
    sx, sy = l + x*(r-l), t + y*(b-t)
    if 0.45 <= sy <= 0.55: return 'band'
    return {(0,0):'red',(1,0):'green',(0,1):'blue',(1,1):'white'}[(int(sx>=0.5), int(sy>=0.5))]

def check(path, crop=(0,0,1,1), t=0.5, src_t=None, src_dur=None):
    p = probe(path); img = frame(path, t); W,H = img.size
    ok = True; rows = []
    l,tp,r,b = crop
    # Points avoiding the quadrant edges and the band edges by a margin.
    pts = [(0.1,0.1),(0.9,0.1),(0.1,0.9),(0.9,0.9)]
    edge_x = (0.5-l)/(r-l)
    if 0.05 < edge_x < 0.95: pts += [(edge_x-0.04,0.15),(edge_x+0.04,0.15)]
    for (x,y) in pts:
        e = expected(x,y,crop); got = classify(img.getpixel((int(x*(W-1)),int(y*(H-1)))))
        if e != 'band' and got != e: ok = False
        rows.append(f'({x:.2f},{y:.2f}) exp {e} got {got}')
    band_y = ((0.5)-tp)/(b-tp)
    band = None
    if 0 < band_y < 1 and src_t is not None:
        g = img.getpixel((W//2, int(band_y*(H-1))))
        band = round(sum(g)/3)
        # The band is luma Y = 255 * t / duration in limited range (16..235), decoded to RGB.
        exp = round(min(255, max(0, (255*src_t/src_dur - 16) * 255 / 219)))
        rows.append(f'band gray {band} (expected ~{exp} for source t={src_t:.2f}s)')
        if abs(band-exp) > 12: ok = False
    return ok, p, rows

if __name__ == '__main__':
    path = sys.argv[1]
    ok, p, rows = check(path, t=float(sys.argv[2]) if len(sys.argv)>2 else 0.5, src_t=float(sys.argv[2]) if len(sys.argv)>2 else 0.5, src_dur=float(sys.argv[3]) if len(sys.argv)>3 else None)
    print(('OK ' if ok else 'FAIL ') + json.dumps(p)); [print('   ', r) for r in rows]
