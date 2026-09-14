# 📍 QR Code Location Guide

## Where to Find the QR Code on the Website

### Page Layout Overview

```
┌─────────────────────────────────────────────────────────────┐
│  NAVIGATION BAR                                             │
│  [JA Noble Enterprise Inc. | Caltex San Pedro]   [Sign Up]  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  HERO SECTION                                               │
│  "Your Car Deserves the Best Care"                         │
│  [Book a Service]  [Our Services]                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  OUR SERVICES CAROUSEL                                      │
│  [Service 1] [Service 2] [Service 3] ...                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  WHY CHOOSE US                                              │
│  ✓ Caltex Authorized                                        │
│  ✓ Expert Mechanics                                         │
│  ✓ Track via App                                            │
└─────────────────────────────────────────────────────────────┘

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  📱 GET THE APP SECTION  ← QR CODE IS HERE!                ┃
┃                                                              ┃
┃  ┌─────────────────────┬───────────────────────────────┐   ┃
┃  │ LEFT COLUMN         │ RIGHT COLUMN                  │   ┃
┃  │                     │                               │   ┃
┃  │ 🔴 Mobile App       │   [Phone Mockup 1]           │   ┃
┃  │                     │   [Phone Mockup 2]           │   ┃
┃  │ Your AutoPro Portal │   [Phone Mockup 3]           │   ┃
┃  │ Right in Your       │                               │   ┃
┃  │ Pocket              │                               │   ┃
┃  │                     │                               │   ┃
┃  │ Download the        │                               │   ┃
┃  │ AutoPro app...      │                               │   ┃
┃  │                     │                               │   ┃
┃  │ ┌───────────────┐   │                               │   ┃
┃  │ │               │   │                               │   ┃
┃  │ │  ▓▓▓▓▓▓▓▓▓▓  │ ← QR CODE (Scan this!)          │   ┃
┃  │ │  ▓▓▓▓▓▓▓▓▓▓  │   │                               │   ┃
┃  │ │  ▓▓▓▓▓▓▓▓▓▓  │   │                               │   ┃
┃  │ │  ▓▓▓▓▓▓▓▓▓▓  │   │                               │   ┃
┃  │ │               │   │                               │   ┃
┃  │ └───────────────┘   │                               │   ┃
┃  │ Scan to download    │                               │   ┃
┃  │ 📱 http://...apk    │                               │   ┃
┃  └─────────────────────┴───────────────────────────────┘   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┌─────────────────────────────────────────────────────────────┐
│  FOOTER                                                     │
│  Contact Info | Links | Legal                              │
└─────────────────────────────────────────────────────────────┘
```

## Exact Section Details

### Section ID: `#get-app`

**Location:** Between "Why Choose Us" section and Footer

**HTML Structure:**
```html
<section id="get-app" style="background:#f4f6f8;...">
  <div style="grid-template-columns:1fr 1.4fr;">
    
    <!-- LEFT SIDE: Text + QR Code -->
    <div>
      <h2>Your AutoPro Portal, Right in Your Pocket</h2>
      <p>Download the AutoPro app and manage your entire fleet...</p>
      
      <!-- QR CODE IS HERE -->
      <div style="display:flex;flex-direction:column;">
        <div style="background:white;border-radius:14px;padding:14px;...">
          <img id="apkQrImg" width="130" height="130" />
        </div>
        <p>Scan to download the app</p>
        <p id="apkUrlDisplay">📱 Download URL appears here</p>
      </div>
    </div>
    
    <!-- RIGHT SIDE: 3 Phone Mockups -->
    <div>
      [Customer Dashboard Phone]
      [Welcome Screen Phone] ← Center, larger
      [PMS History Phone]
    </div>
    
  </div>
</section>
```

## Visual Appearance

### Desktop View (> 900px):
```
┌─────────────────────────────────────────────────────────────┐
│  🟦 Mobile App Badge                                        │
│                                                             │
│  Your AutoPro Portal,           [Phone 1]  [Phone 2]       │
│  Right in Your Pocket               ⬆️                      │
│                                   CENTER                     │
│  Download the AutoPro app           🔴                      │
│  and manage your entire                                     │
│  fleet...                        [Phone 3]                  │
│                                                             │
│  ┌───────────┐                                              │
│  │ QR CODE   │                                              │
│  │  ▓▓▓▓▓▓   │                                              │
│  │  ▓▓▓▓▓▓   │                                              │
│  └───────────┘                                              │
│  Scan to download                                           │
│  📱 URL here                                                │
└─────────────────────────────────────────────────────────────┘
```

### Tablet View (600px - 900px):
```
┌──────────────────────────────────┐
│  Your AutoPro Portal             │
│  Right in Your Pocket            │
│                                  │
│  ┌───────────┐                   │
│  │ QR CODE   │                   │
│  └───────────┘                   │
│                                  │
│  ──────────────────              │
│                                  │
│  [Phone 1]  [Phone 2]  [Phone 3]│
└──────────────────────────────────┘
```

### Mobile View (< 600px):
```
┌─────────────────┐
│ Your AutoPro    │
│ Portal          │
│                 │
│ ┌───────────┐   │
│ │ QR CODE   │   │
│ └───────────┘   │
│                 │
│ [Center Phone]  │ ← Only 1 phone shows
└─────────────────┘
```

## How to Navigate There

### From Homepage:
1. Scroll down past the hero section
2. Pass the services carousel
3. Pass the "Why Choose Us" section
4. You'll see: "Your AutoPro Portal, Right in Your Pocket"
5. **QR Code is in that section!**

### Direct Link:
```
http://localhost:5000/#get-app
```

## QR Code Specifications

```
╔═══════════════════════════════════╗
║  QR CODE DETAILS                  ║
╠═══════════════════════════════════╣
║ Size:         130px × 130px       ║
║ Resolution:   260×260 (API)       ║
║ Background:   White (#ffffff)     ║
║ Foreground:   Dark blue (#1a202c) ║
║ Error Level:  High (H)            ║
║ Border:       14px padding        ║
║ Shadow:       0 4px 20px rgba()   ║
║ Border Rad:   14px (outer)        ║
║               6px (inner)         ║
╚═══════════════════════════════════╝
```

## What Users See

### Before Scanning:
```
┌─────────────────────┐
│ [Mobile App Badge]  │
│                     │
│ Your AutoPro Portal │
│ Right in Your Pocket│
│                     │
│ Download the AutoPro│
│ app and manage your │
│ entire fleet...     │
│                     │
│ ┌─────────────────┐ │
│ │                 │ │
│ │    █████████    │ │
│ │    █ ███ ██    │ │  ← User points phone camera here
│ │    ████ ███    │ │
│ │    █████████    │ │
│ │                 │ │
│ └─────────────────┘ │
│ Scan to download    │
│ the app             │
│ 📱 localhost:5000/  │
│    download/autopro │
└─────────────────────┘
```

### After Scanning:
```
    [User's Phone]
┌──────────────────────┐
│ ☰  Chrome            │
├──────────────────────┤
│                      │
│  Open with           │
│                      │
│  🌐 Download         │
│  📱 AutoPro.apk      │
│     174.83 MB        │
│                      │
│  [ Download ]        │  ← User taps this
│                      │
└──────────────────────┘
```

## Styling & Colors

```
Section Background:  #f4f6f8 (light gray)
QR Container:        #ffffff (white)
Text Color:          #1a202c (dark)
Badge Background:    rgba(232,0,28,0.10) (light red)
Badge Border:        rgba(232,0,28,0.22)
Badge Text:          #E8001C (red)
URL Text:            #718096 (medium gray)
```

## Responsive Behavior

| Screen Width | Layout | QR Size | Phones Shown |
|--------------|--------|---------|--------------|
| > 900px      | 2 cols | 130px   | All 3        |
| 600-900px    | 1 col  | 130px   | All 3        |
| < 600px      | 1 col  | 130px   | Center only  |

## Testing Checklist

When you visit the page, you should see:

- [ ] Section with light gray background (#f4f6f8)
- [ ] Red badge saying "Mobile App"
- [ ] Heading: "Your AutoPro Portal, Right in Your Pocket"
- [ ] Description text about the app
- [ ] White rounded box with QR code inside
- [ ] QR code is clearly visible (black pattern on white)
- [ ] Text below: "Scan to download the app"
- [ ] URL display showing: `📱 http://localhost:5000/download/autopro.apk`
- [ ] 3 phone mockups on the right (desktop) or below (mobile)

## Common Issues

### QR Code Blank/White?
→ Check browser console for errors
→ Verify QR API is accessible: https://api.qrserver.com

### Wrong URL Shown?
→ Should match your browser's address bar origin
→ Check `window.location.origin` in console

### Section Not Visible?
→ Scroll down more - it's near the bottom
→ Check responsive view if on mobile

---

**Quick Test:** Open `http://localhost:5000` and press `Ctrl+F`, search for "Your AutoPro Portal" - it will jump to the QR code section!
