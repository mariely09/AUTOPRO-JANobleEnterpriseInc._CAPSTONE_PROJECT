# Caltex AutoPro Setup Guide

## Environment Setup

This project uses environment variables to keep sensitive credentials secure.

### 1. Create .env file

Copy the example file and fill in your credentials:

```bash
cp .env.example .env
```

Then edit `.env` with your actual values:

```env
SMTP_USER=your_email@gmail.com
SMTP_APP_PASSWORD=your_16_char_app_password
SMTP_FROM=Your Name <your_email@gmail.com>
```

### 2. Gmail App Password Setup

To get your Gmail App Password:

1. Go to your Google Account: https://myaccount.google.com/
2. Navigate to **Security** → **2-Step Verification** (enable if not already)
3. Scroll to **App Passwords**
4. Generate a new app password for "Mail"
5. Copy the 16-character password (format: `xxxx xxxx xxxx xxxx`)
6. Paste it in your `.env` file as `SMTP_APP_PASSWORD`

### 3. Firebase Service Account

Place your `serviceAccountKey.json` file in one of these locations:
- `automotive_website/serviceAccountKey.json`
- Project root: `AUTOMOTIVE_SERVICE/serviceAccountKey.json`

**Never commit this file to Git!** It's already in `.gitignore`.

### 4. Install Dependencies

#### For Website (Flask):
```bash
pip install -r requirements.txt
```

#### For AI Assistant:
```bash
cd ai_assistant
pip install -r requirements.txt
```

#### For Mobile App (Flutter):
```bash
cd automotive_mobile
flutter pub get
```

### 5. Run the Application

#### Website:
```bash
cd automotive_website
python caltexautopro.py
```

#### AI Assistant:
```bash
cd ai_assistant
python main.py
```

#### Mobile App:
```bash
cd automotive_mobile
flutter run
```

## Security Notes

⚠️ **NEVER commit these files to Git:**
- `.env` - Contains sensitive credentials
- `serviceAccountKey.json` - Firebase admin credentials
- `google-services.json` - Firebase Android configuration
- `GoogleService-Info.plist` - Firebase iOS configuration

✅ **Safe to commit:**
- `.env.example` - Template with placeholder values
- All source code files

## Troubleshooting

### Email not sending?
- Check that `SMTP_APP_PASSWORD` is correct (16 characters, no spaces)
- Verify 2-Step Verification is enabled on your Google account
- Make sure you're using an App Password, not your regular Gmail password

### Firebase errors?
- Ensure `serviceAccountKey.json` is in the correct location
- Check that the service account has the right permissions in Firebase Console

### Mobile app Google Sign-In not working?
- Verify SHA-1 fingerprint is added in Firebase Console
- Download latest `google-services.json` from Firebase Console
- Run `flutter clean` and rebuild
