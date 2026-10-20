"""Approximate scene previews from verify.lua --export; no native UI or simulator.

Requires Pillow. Example:
  lua5.3 bin/wizard/verify.lua --export scenes.json
  python bin/wizard/render_previews.py scenes.json docs/images/helicopter_setup
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FONT_PATHS = (Path('C:/Windows/Fonts/arial.ttf'), Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
FONT = next((p for p in FONT_PATHS if p.exists()), None)


def font(size):
    return ImageFont.truetype(str(FONT), size) if FONT else ImageFont.load_default(size=size)


def wrap(draw, text, face, width):
    lines = []
    for paragraph in str(text).splitlines():
        current = ''
        for word in paragraph.split():
            candidate = (current + ' ' + word).strip()
            if current and draw.textlength(candidate, font=face) > width:
                lines.append(current)
                current = word
            else:
                current = candidate
        lines.append(current)
    return lines


def render(scene):
    width, height = scene['width'], scene['height']
    image = Image.new('RGB', (width, height), '#edf1f5')
    draw = ImageDraw.Draw(image)
    large = width >= 700
    size = 20 if large else 13 if width >= 480 else 12
    for item in scene['children']:
        kind = item['type']
        x, y, w, h = (item.get(k, 0) for k in ('x', 'y', 'w', 'h'))
        if kind == 'rectangle':
            if item.get('filled'):
                draw.rectangle((x,y,x+w,y+h), fill='#edf1f5')
            else:
                draw.rectangle((x,y,x+w,y+h), outline='#74889b', width=2)
        elif kind == 'line':
            draw.line([tuple(p) for p in item['pts']], fill='#74889b', width=2)
        elif kind == 'label':
            face = font((26 if large else 17) if item.get('font') == 1 else size)
            text = str(item.get('text', ''))
            lines = wrap(draw, text, face, w)
            line_h = size + 3
            if h:
                lines = lines[:max(1, int(h / line_h))]
            for n,line in enumerate(lines):
                draw.text((x,y+n*line_h),line,font=face,fill='#26394c')
        elif kind in ('button','momentaryButton','choice','numberEdit'):
            draw.rounded_rectangle((x,y,x+w,y+h),radius=4,fill='#fff',outline='#9caab8',width=1)
            face = font(size)
            text = item.get('text')
            if text is None:
                value = item.get('get', '')
                if kind == 'choice':
                    values = item['values']
                    text = values[int(value)-1] if isinstance(value,(int,float)) and 1 <= value <= len(values) else '?'
                else:
                    text = item.get('display',str(value))
            while draw.textlength(str(text),font=face) > w-12 and size > 8:
                size -= 1
                face = font(size)
            draw.text((x+w/2,y+h/2),str(text),anchor='mm',font=face,fill='#26394c')
            if kind == 'choice':
                draw.polygon(((x+w-12,y+h/2-2),(x+w-6,y+h/2-2),(x+w-9,y+h/2+2)),fill='#74889b')
            size = 20 if large else 13 if width >= 480 else 12
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scenes',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    scenes = json.loads(args.scenes.read_text())
    for width,height,label in ((480,272,'small'),(800,480,'large')):
        selected = [s for s in scenes if s['width']==width and s['height']==height]
        selected.sort(key=lambda s:s['step'])
        scale = 1 if label=='small' else 0.6
        tile_w,tile_h = round(width*scale),round(height*scale)
        sheet = Image.new('RGB',(tile_w*3+40,(tile_h+32)*math.ceil(len(selected)/3)+62),'#fff')
        draw = ImageDraw.Draw(sheet)
        draw.text((12,10),f'Helicopter Setup - {width} x {height} code previews (desktop fonts)',font=font(18),fill='#26394c')
        for i,s in enumerate(selected):
            picture = render(s)
            picture.save(args.output/f'{s["step"]:02d}-{label}.png')
            if scale != 1:
                picture=picture.resize((tile_w,tile_h),Image.Resampling.LANCZOS)
            x,y=10+(i%3)*(tile_w+10),46+(i//3)*(tile_h+32)
            sheet.paste(picture,(x,y))
            draw.text((x,y+tile_h+3),f'{s["step"]:02d} {s["name"]}',font=font(14),fill='#26394c')
        sheet.save(args.output/f'overview-{label}.png')
    print(f'Rendered {len(scenes)} exported scenes; 38 individual images and two overview sheets.')


if __name__=='__main__':
    main()
