"""
Create Android notification icon from AutoPro logo
Convert logo to WHITE SILHOUETTE (keeping the logo shape)
Android requires white-only notification icons
"""
from PIL import Image, ImageOps, ImageDraw
import os

print("\n" + "="*60)
print("🎨 CREATING LOGO NOTIFICATION ICON (WHITE SILHOUETTE)")
print("="*60)

# Source logo
logo_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_website\static\img\LOGO_AUTOPRO.png'

if not os.path.exists(logo_path):
    print(f"❌ Logo not found: {logo_path}")
    exit(1)

print(f"\n📁 Loading logo: {logo_path}")

# Load original logo
original = Image.open(logo_path).convert('RGBA')
print(f"   Original size: {original.size}")

# Notification icon sizes
sizes = [
    ('mdpi', 24),
    ('hdpi', 36),
    ('xhdpi', 48),
    ('xxhdpi', 72),
    ('xxxhdpi', 96),
]

base_path = r'c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile\android\app\src\main\res'

print(f"\n🎨 Creating white silhouette icons (keeping logo shape)...")

for density, size in sizes:
    folder = f'drawable-{density}'
    folder_path = os.path.join(base_path, folder)
    os.makedirs(folder_path, exist_ok=True)
    
    print(f"\n   {density:8} ({size}x{size}px)")
    
    # Resize logo maintaining aspect ratio
    logo_copy = original.copy()
    
    # Calculate size with padding
    padding = size // 8  # Small padding
    target_size = size - (padding * 2)
    
    # Resize logo to fit
    logo_copy.thumbnail((target_size, target_size), Image.Resampling.LANCZOS)
    
    # Create transparent canvas
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Calculate position to center logo
    x = (size - logo_copy.width) // 2
    y = (size - logo_copy.height) // 2
    
    # Paste resized logo
    canvas.paste(logo_copy, (x, y), logo_copy)
    
    # Convert to WHITE SILHOUETTE
    # Get alpha channel (transparency)
    r, g, b, alpha = canvas.split()
    
    # Create pure white image
    white = Image.new('RGB', (size, size), (255, 255, 255))
    
    # Create final icon: white color with original alpha
    white_silhouette = Image.new('RGBA', (size, size))
    white_silhouette.paste(white, (0, 0))
    white_silhouette.putalpha(alpha)
    
    # Save
    output_path = os.path.join(folder_path, 'ic_notification.png')
    white_silhouette.save(output_path, 'PNG', optimize=True)
    
    file_size = os.path.getsize(output_path) / 1024
    print(f"      ✅ Created: {file_size:.1f} KB")

print("\n" + "="*60)
print("✅ LOGO NOTIFICATION ICONS CREATED!")
print("="*60)

print("\n📋 What was created:")
print("   • White silhouette of AutoPro logo")
print("   • Keeps the logo shape/outline")
print("   • Pure white (#FFFFFF) color only")
print("   • Transparent background")
print("   • 5 sizes for all screen densities")

print("\n✅ This will show:")
print("   • Logo shape is visible (not just circle)")
print("   • White color (Android requirement)")
print("   • Works on all Android versions")

print("\n📋 Next Steps:")
print("   1. ✅ Logo icons created")
print("   2. ⏳ Rebuild APK")
print("   3. ⏳ Upload to Firebase")
print("   4. ⏳ Install and test")
print()
