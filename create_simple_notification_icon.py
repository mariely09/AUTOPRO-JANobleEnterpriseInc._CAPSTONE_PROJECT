"""
Create SIMPLE Android notification icon - pure white silhouette
Android requires simple flat white icon on transparent background
"""
from PIL import Image, ImageDraw
import os

print("\n" + "="*60)
print("🎨 CREATING SIMPLE WHITE NOTIFICATION ICON")
print("="*60)

# Notification icon sizes
sizes = [
    ('mdpi', 24),
    ('hdpi', 36),
    ('xhdpi', 48),
    ('xxhdpi', 72),
    ('xxxhdpi', 96),
]

base_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile\android\app\src\main\res'

print("\n🎨 Creating simple white circle icons...")

for density, size in sizes:
    folder = f'drawable-{density}'
    folder_path = os.path.join(base_path, folder)
    os.makedirs(folder_path, exist_ok=True)
    
    # Create pure white circle (simple shape that Android accepts)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Draw white circle with some padding
    padding = size // 6
    draw.ellipse(
        [padding, padding, size - padding, size - padding],
        fill=(255, 255, 255, 255)
    )
    
    # Draw letter "A" in center (for AutoPro)
    # Simple shape
    center = size // 2
    letter_size = size // 3
    
    # Draw "A" using simple shapes
    # Top point
    points = [
        (center, padding),  # top
        (center - letter_size//2, size - padding),  # bottom left
        (center + letter_size//2, size - padding),  # bottom right
    ]
    
    # Actually, let's just use a solid circle for maximum compatibility
    # Android is very strict about notification icons
    
    output_path = os.path.join(folder_path, 'ic_notification.png')
    img.save(output_path, 'PNG')
    
    file_size = os.path.getsize(output_path) / 1024
    print(f"   ✅ {density:8} ({size}x{size}px) - {file_size:.1f} KB")

print("\n" + "="*60)
print("✅ SIMPLE NOTIFICATION ICONS CREATED!")
print("="*60)

print("\n⚠️ NOTE:")
print("   Android notification icons MUST be:")
print("   - Pure white (#FFFFFF)")
print("   - Transparent background")
print("   - Simple shapes only")
print("   - No gradients or colors")
print()
print("   Created simple white circle icon")
print("   This will definitely work on all Android versions")
print()

print("📋 Next Steps:")
print("   1. ✅ Icons created")
print("   2. ⏳ Rebuild APK")
print("   3. ⏳ Upload to Firebase")
print("   4. ⏳ Test notification")
print()
