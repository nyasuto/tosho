#!/bin/bash

# Create a simple book icon using ImageMagick-style commands via sips
# Create a base 1024x1024 image first

# Create base icon using a solid color and some basic shapes
# Since we don't have ImageMagick, we'll create a simple icon using available tools

# Create a simple PNG icon using built-in macOS tools
python3 << 'PYTHON_EOF'
from PIL import Image, ImageDraw
import os

def create_app_icon():
    # Create base image
    img = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Draw a book-like icon
    # Book cover (main rectangle)
    book_color = (74, 144, 226)  # Nice blue color
    margin = 150
    book_rect = (margin, margin, 1024-margin, 1024-margin-50)
    draw.rounded_rectangle(book_rect, radius=30, fill=book_color)
    
    # Book spine shadow
    spine_color = (50, 100, 180)
    spine_rect = (margin, margin, margin+40, 1024-margin-50)
    draw.rounded_rectangle(spine_rect, radius=15, fill=spine_color)
    
    # Book pages
    pages_color = (245, 245, 240)
    pages_rect = (margin+20, margin+20, 1024-margin-20, 1024-margin-30)
    draw.rounded_rectangle(pages_rect, radius=20, fill=pages_color)
    
    # Text lines on the page
    line_color = (100, 100, 100)
    for i in range(5):
        y = margin + 100 + i * 60
        draw.rounded_rectangle((margin+60, y, 1024-margin-100, y+20), radius=5, fill=line_color)
    
    return img

# Try to create icon with PIL
try:
    icon = create_app_icon()
    icon.save('/tmp/base_icon.png', 'PNG')
    print("Base icon created successfully")
except ImportError:
    print("PIL not available, creating simple icon with other method")
    # Fallback: create a simple colored square
    import subprocess
    subprocess.run([
        'sips', '--createMask', '--setProperty', 'format', 'png',
        '--out', '/tmp/base_icon.png',
        '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns'
    ])

PYTHON_EOF

# Check if base icon was created
if [ ! -f "/tmp/base_icon.png" ]; then
    # Fallback: use system icon as base
    sips -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookIcon.icns --out /tmp/base_icon.png 2>/dev/null || \
    sips -s format png /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns --out /tmp/base_icon.png
fi

# Create all required sizes from base icon
sizes=(16 32 128 256 512)
scales=(1 2)

for size in "${sizes[@]}"; do
    for scale in "${scales[@]}"; do
        actual_size=$((size * scale))
        if [ $scale -eq 1 ]; then
            filename="icon_${size}x${size}.png"
        else
            filename="icon_${size}x${size}@${scale}x.png"
        fi
        
        echo "Creating $filename (${actual_size}x${actual_size})"
        sips -z $actual_size $actual_size /tmp/base_icon.png --out "$filename"
    done
done

# Clean up
rm -f /tmp/base_icon.png

echo "All icon files created successfully!"
ls -la *.png
