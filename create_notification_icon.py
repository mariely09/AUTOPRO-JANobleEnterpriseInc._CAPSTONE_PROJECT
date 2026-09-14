"""
Create Android notification icon from AutoPro logo
Notification icons must be white silhouette on transparent background
"""
from PIL import Image, ImageDraw, ImageOps
import os

print("\n" + "="*60)
print("🎨 CREATING NOTIFICATION ICON FROM LOGO")
print("="*60)

# Source logo
logo_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_website\static\img\LOGO_AUTOPRO.png'

if not os.path.exists(logo_path):
    print(f"❌ Logo not found: {logo_path}")
    exit(1)

print(f"\n📁 Loading logo: {logo_path}")

# Load original logo
original = Image.open(logo_path)
print(f"   Original size: {original.size}")

# Notification icon sizes (Android densities)
# Format: (density_name, size_px, folder_name)
sizes = [
    ('mdpi', 24, 'drawable-mdpi'),
    ('hdpi', 36, 'drawable-hdpi'),
    ('xhdpi', 48, 'drawable-xhdpi'),
    ('xxhdpi', 72, 'drawable-xxhdpi'),
    ('xxxhdpi', 96, 'drawable-xxxhdpi'),
]

# Base path for drawable folders
base_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile\android\app\src\main\res'

print(f"\n🎨 Creating notification icons...")

for density, size, folder in sizes:
    print(f"\n   {density:8} ({size}x{size}px)")
    
    # Create output folder if not exists
    folder_path = os.path.join(base_path, folder)
    os.makedirs(folder_path, exist_ok=True)
    
    # Resize logo to target size
    resized = original.copy()
    resized.thumbnail((size, size), Image.Resampling.LANCZOS)
    
    # Create white silhouette on transparent background
    # Convert to RGBA if not already
    if resized.mode != 'RGBA':
        resized = resized.convert('RGBA')
    
    # Create new image with transparent background
    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Paste resized logo centered
    offset_x = (size - resized.size[0]) // 2
    offset_y = (size - resized.size[1]) // 2
    icon.paste(resized, (offset_x, offset_y), resized)
    
    # Convert to white silhouette
    # Get alpha channel
    alpha = icon.split()[3]
    
    # Create white image
    white = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    
    # Apply alpha to white
    icon_white = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    icon_white.putalpha(alpha)
    
    # Save
    output_path = os.path.join(folder_path, 'ic_notification.png')
    icon_white.save(output_path, 'PNG')
    
    file_size = os.path.getsize(output_path) / 1024
    print(f"      ✅ Created: {output_path}")
    print(f"         Size: {file_size:.1f} KB")

print("\n" + "="*60)
print("✅ NOTIFICATION ICONS CREATED!")
print("="*60)

print("\n📋 Created files:")
for density, size, folder in sizes:
    path = os.path.join(base_path, folder, 'ic_notification.png')
    if os.path.exists(path):
        print(f"   ✅ {folder}/ic_notification.png ({size}x{size}px)")

print("\n⚠️ IMPORTANT:")
print("   AndroidManifest.xml must be updated to use ic_notification")
print("   Currently configured to use: @mipmap/ic_launcher")
print("   Need to change to: @drawable/ic_notification")

print("\n📋 Next Steps:")
print("   1. ✅ Notification icons created")
print("   2. ⏳ Update AndroidManifest.xml")
print("   3. ⏳ Rebuild APK")
print("   4. ⏳ Test notification icon")
print()
