"""Export the original geometric Crimson mark and Roku brand assets.
Optional development tool: Python + Pillow. No downloaded artwork or account data.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / 'images'
BG = (13, 14, 18, 255)
RED = (230, 56, 79, 255)
WHITE = (245, 242, 244, 255)

def font(size):
    return ImageFont.truetype(str(ROOT / 'fonts/OpenSans-Bold.ttf'), size)

def mark(size):
    scale = 4
    canvas = Image.new('RGBA', (256 * scale, 256 * scale))
    draw = ImageDraw.Draw(canvas)
    draw.arc((29*scale,29*scale,227*scale,227*scale), 40, 320, fill=RED, width=22*scale)
    draw.polygon([(112*scale,93*scale),(112*scale,163*scale),(170*scale,128*scale)], fill=WHITE)
    return canvas.resize((size,size), Image.Resampling.LANCZOS)

def icon(width,height):
    scale=3
    canvas=Image.new('RGBA',(width*scale,height*scale),BG)
    sign=mark(int(height*.52)*scale)
    canvas.alpha_composite(sign,((width*scale-sign.width)//2,int(height*.07)*scale))
    draw=ImageDraw.Draw(canvas)
    draw.text((width*scale/2,height*scale*.73),'CRIMSON',font=font(int(height*.12)*scale),fill=WHITE,anchor='mm')
    return canvas.resize((width,height),Image.Resampling.LANCZOS)

def main():
    IMAGES.mkdir(exist_ok=True)
    mark(256).save(IMAGES/'crimson-mark.png')
    icon(290,218).save(IMAGES/'crimson-icon-hd.png')
    icon(246,140).save(IMAGES/'crimson-icon-sd.png')
    splash=Image.new('RGBA',(1280,720),BG)
    splash.alpha_composite(mark(160),(560,196))
    draw=ImageDraw.Draw(splash)
    draw.text((640,412),'CRIMSON CINEMA',font=font(46),fill=WHITE,anchor='mm')
    draw.text((640,479),'MOVIES AND SHOWS. YOUR REMOTE.',font=font(16),fill=(173,176,188,255),anchor='mm')
    splash.save(IMAGES/'crimson-splash.png')
    (IMAGES/'crimson-mark.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path d="M204 192 A99 99 0 1 1 204 64" fill="none" stroke="#e6384f" stroke-width="22"/><path d="M112 93v70l58-35z" fill="#f5f2f4"/></svg>',encoding='utf-8')
    print('Generated Crimson mark, icons and splash.')

if __name__=='__main__':
    main()
