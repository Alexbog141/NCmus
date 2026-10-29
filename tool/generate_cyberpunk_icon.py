import os
import math
from PIL import Image, ImageDraw, ImageFilter

def create_cyberpunk_icon(size=1024):
    # Work on a 2x canvas for super-sampling anti-aliasing
    canvas_size = size * 2
    img = Image.new("RGBA", (canvas_size, canvas_size), (7, 8, 12, 255))
    
    # 1. Background deep glow
    bg_glow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg_glow)
    
    center_x = canvas_size // 2
    center_y = int(canvas_size * 0.48)
    
    # Concentric ambient glows
    for r in range(int(canvas_size * 0.45), 0, -12):
        factor = 1.0 - (r / (canvas_size * 0.45))
        # Violet to Cyan shift
        cr = int(157 * factor * 0.25)
        cg = int(78 * factor * 0.15 + 240 * factor * 0.15)
        cb = int(221 * factor * 0.35 + 255 * factor * 0.35)
        alpha = int(45 * factor)
        bg_draw.ellipse(
            [center_x - r, center_y - r, center_x + r, center_y + r],
            fill=(cr, cg, cb, alpha)
        )
    
    img = Image.alpha_composite(img, bg_glow)
    
    # 2. Outer Glassmorphism Squircle Badge
    badge_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    badge_draw = ImageDraw.Draw(badge_layer)
    
    margin = int(canvas_size * 0.08)
    corner_radius = int(canvas_size * 0.22)
    badge_box = [margin, margin, canvas_size - margin, canvas_size - margin]
    
    # Squircle dark surface
    badge_draw.rounded_rectangle(badge_box, radius=corner_radius, fill=(13, 17, 26, 235))
    
    # Squircle border with gradient (Cyan #00F0FF -> Violet #9D4EDD)
    border_width = int(canvas_size * 0.012)
    
    # Draw border on separate layer to blur/glow
    border_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border_layer)
    border_draw.rounded_rectangle(
        badge_box,
        radius=corner_radius,
        outline=(0, 240, 255, 180),
        width=border_width
    )
    
    # Add violet gradient overlay to the bottom of the border
    gradient_mask = Image.new("L", (canvas_size, canvas_size), 0)
    g_draw = ImageDraw.Draw(gradient_mask)
    for y in range(margin, canvas_size - margin):
        ratio = (y - margin) / (canvas_size - 2 * margin)
        g_draw.line([(margin, y), (canvas_size - margin, y)], fill=int(ratio * 255))
        
    violet_border = Image.new("RGBA", (canvas_size, canvas_size), (157, 78, 221, 220))
    border_layer.paste(violet_border, (0, 0), gradient_mask)
    
    # Glow for border
    border_glow = border_layer.filter(ImageFilter.GaussianBlur(radius=int(canvas_size * 0.02)))
    badge_layer = Image.alpha_composite(badge_layer, border_glow)
    badge_layer = Image.alpha_composite(badge_layer, border_layer)
    
    img = Image.alpha_composite(img, badge_layer)
    
    # 3. Waveform equalizer bars behind / beside note
    wave_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    wave_draw = ImageDraw.Draw(wave_layer)
    
    # Equalizer heights relative to center
    bar_count = 13
    bar_width = int(canvas_size * 0.026)
    bar_gap = int(canvas_size * 0.038)
    total_bar_width = bar_count * bar_width + (bar_count - 1) * bar_gap
    start_x = (canvas_size - total_bar_width) // 2
    baseline_y = int(canvas_size * 0.54)
    
    # Height pattern resembling frequency spectrum
    height_factors = [0.25, 0.45, 0.70, 0.95, 0.65, 0.40, 0.85, 1.0, 0.75, 0.55, 0.80, 0.50, 0.30]
    max_bar_height = int(canvas_size * 0.38)
    
    for i in range(bar_count):
        bx = start_x + i * (bar_width + bar_gap)
        bh = int(max_bar_height * height_factors[i])
        by1 = baseline_y - bh // 2
        by2 = baseline_y + bh // 2
        
        # Color interpolation across the bars: Cyan (0, 240, 255) to Violet (157, 78, 221)
        t = i / (bar_count - 1)
        r = int(0 * (1 - t) + 157 * t)
        g = int(240 * (1 - t) + 78 * t)
        b = int(255 * (1 - t) + 221 * t)
        
        # Draw bar
        wave_draw.rounded_rectangle([bx, by1, bx + bar_width, by2], radius=bar_width // 2, fill=(r, g, b, 230))
        
    # Glow for equalizer wave
    wave_glow = wave_layer.filter(ImageFilter.GaussianBlur(radius=int(canvas_size * 0.025)))
    img = Image.alpha_composite(img, wave_glow)
    img = Image.alpha_composite(img, wave_layer)
    
    # 4. Stylized Futuristic Music Note (Beamed Eighth Note with sharp cyber angles)
    note_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    note_draw = ImageDraw.Draw(note_layer)
    
    # Left note head
    head1_cx = int(canvas_size * 0.36)
    head1_cy = int(canvas_size * 0.64)
    head_rx = int(canvas_size * 0.09)
    head_ry = int(canvas_size * 0.065)
    
    # Right note head
    head2_cx = int(canvas_size * 0.64)
    head2_cy = int(canvas_size * 0.54)
    
    stem_width = int(canvas_size * 0.038)
    
    # Note head 1 (rotated ellipse)
    def draw_tilted_ellipse(draw, cx, cy, rx, ry, angle_deg, fill):
        # Draw tilted ellipse via polygon
        points = []
        angle_rad = math.radians(angle_deg)
        cos_a = math.cos(angle_rad)
        sin_a = math.sin(angle_rad)
        for step in range(36):
            theta = math.radians(step * 10)
            ex = rx * math.cos(theta)
            ey = ry * math.sin(theta)
            rot_x = cx + ex * cos_a - ey * sin_a
            rot_y = cy + ex * sin_a + ey * cos_a
            points.append((rot_x, rot_y))
        draw.polygon(points, fill=fill)
        
    # Left head & stem
    draw_tilted_ellipse(note_draw, head1_cx, head1_cy, head_rx, head_ry, -24, (0, 240, 255, 255))
    stem1_x = head1_cx + int(head_rx * 0.72)
    stem_top_y = int(canvas_size * 0.28)
    note_draw.rounded_rectangle([stem1_x - stem_width, stem_top_y, stem1_x, head1_cy], radius=stem_width // 4, fill=(0, 240, 255, 255))
    
    # Right head & stem
    draw_tilted_ellipse(note_draw, head2_cx, head2_cy, head_rx, head_ry, -24, (157, 78, 221, 255))
    stem2_x = head2_cx + int(head_rx * 0.72)
    stem2_top_y = int(canvas_size * 0.22)
    note_draw.rounded_rectangle([stem2_x - stem_width, stem2_top_y, stem2_x, head2_cy], radius=stem_width // 4, fill=(157, 78, 221, 255))
    
    # Connecting Beam (gradient from cyan to violet)
    beam_height = int(canvas_size * 0.065)
    beam_poly = [
        (stem1_x - stem_width, stem_top_y),
        (stem2_x, stem2_top_y),
        (stem2_x, stem2_top_y + beam_height),
        (stem1_x - stem_width, stem_top_y + beam_height),
    ]
    note_draw.polygon(beam_poly, fill=(120, 140, 245, 255))
    
    # Secondary cyber beam
    sub_beam_h = int(canvas_size * 0.038)
    sub_beam_offset = int(canvas_size * 0.085)
    sub_beam_poly = [
        (stem1_x - stem_width, stem_top_y + sub_beam_offset),
        (stem2_x, stem2_top_y + sub_beam_offset),
        (stem2_x, stem2_top_y + sub_beam_offset + sub_beam_h),
        (stem1_x - stem_width, stem_top_y + sub_beam_offset + sub_beam_h),
    ]
    note_draw.polygon(sub_beam_poly, fill=(80, 200, 255, 255))
    
    # Inner glowing core of note heads
    inner_rx = int(head_rx * 0.5)
    inner_ry = int(head_ry * 0.5)
    draw_tilted_ellipse(note_draw, head1_cx, head1_cy, inner_rx, inner_ry, -24, (255, 255, 255, 240))
    draw_tilted_ellipse(note_draw, head2_cx, head2_cy, inner_rx, inner_ry, -24, (255, 255, 255, 240))
    
    # Glowing neon aura for the note
    note_glow_cyan = note_layer.filter(ImageFilter.GaussianBlur(radius=int(canvas_size * 0.03)))
    note_glow_bright = note_layer.filter(ImageFilter.GaussianBlur(radius=int(canvas_size * 0.012)))
    
    img = Image.alpha_composite(img, note_glow_cyan)
    img = Image.alpha_composite(img, note_glow_bright)
    img = Image.alpha_composite(img, note_layer)
    
    # 5. Dynamic Cyber Pulse Wave Line cutting across lower section
    pulse_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    pulse_draw = ImageDraw.Draw(pulse_layer)
    
    pulse_points = []
    py_base = int(canvas_size * 0.77)
    px_start = int(canvas_size * 0.16)
    px_end = int(canvas_size * 0.84)
    
    step_count = 120
    for s in range(step_count + 1):
        ratio = s / step_count
        px = px_start + (px_end - px_start) * ratio
        # Sine wave with exponential envelope centered around middle
        env = math.exp(-((ratio - 0.5) ** 2) / 0.05)
        py = py_base - math.sin(ratio * math.pi * 8) * (canvas_size * 0.065) * env
        pulse_points.append((px, py))
        
    pulse_line_width = int(canvas_size * 0.008)
    for p in range(len(pulse_points) - 1):
        t = p / len(pulse_points)
        cr = int(0 * (1 - t) + 157 * t)
        cg = int(240 * (1 - t) + 78 * t)
        cb = int(255 * (1 - t) + 221 * t)
        pulse_draw.line([pulse_points[p], pulse_points[p+1]], fill=(cr, cg, cb, 230), width=pulse_line_width)
        
    pulse_glow = pulse_layer.filter(ImageFilter.GaussianBlur(radius=int(canvas_size * 0.016)))
    img = Image.alpha_composite(img, pulse_glow)
    img = Image.alpha_composite(img, pulse_layer)
    
    # Downscale to desired final size using high-quality Lanczos resampling
    final_img = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

def main():
    os.makedirs("assets/icon", exist_ok=True)
    os.makedirs("windows/runner/resources", exist_ok=True)
    
    print("Generating 1024x1024 master icon...")
    master = create_cyberpunk_icon(1024)
    master.save("assets/icon/app_icon_1024.png", format="PNG")
    
    print("Generating 512x512 app_icon.png...")
    icon_512 = master.resize((512, 512), Image.Resampling.LANCZOS)
    icon_512.save("assets/icon/app_icon.png", format="PNG")
    
    print("Generating Windows app_icon.ico...")
    # Multi-resolution ICO: 256, 128, 64, 48, 32, 16
    ico_sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    master.save(
        "windows/runner/resources/app_icon.ico",
        format="ICO",
        sizes=ico_sizes
    )
    
    print("Generating Android launcher icons...")
    android_sizes = {
        "mipmap-mdpi": (48, 48),
        "mipmap-hdpi": (72, 72),
        "mipmap-xhdpi": (96, 96),
        "mipmap-xxhdpi": (144, 144),
        "mipmap-xxxhdpi": (192, 192),
    }
    
    for folder, dim in android_sizes.items():
        dir_path = os.path.join("android/app/src/main/res", folder)
        os.makedirs(dir_path, exist_ok=True)
        out_path = os.path.join(dir_path, "ic_launcher.png")
        resized = master.resize(dim, Image.Resampling.LANCZOS)
        resized.save(out_path, format="PNG")
        print(f"  -> Saved {out_path} ({dim[0]}x{dim[1]})")
        
    print("Icon generation completed successfully!")

if __name__ == "__main__":
    main()
