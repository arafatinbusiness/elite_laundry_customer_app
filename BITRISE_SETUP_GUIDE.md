# Bitrise iOS Build Setup Guide

## Prerequisites
1. GitHub account with your code pushed to a repository
2. Bitrise.io account (free tier available)
3. Apple Developer account (for code signing)

## Step-by-Step Setup

### 1. Push Your Code to GitHub
```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/yourusername/elite-laundry-customer-app.git
git push -u origin main
```

### 2. Connect Bitrise to Your Repository
1. Go to [bitrise.io](https://www.bitrise.io)
2. Click "Add App" → "Connect repository"
3. Select GitHub and authorize access
4. Choose your repository: `elite-laundry-customer-app`
5. Set branch: `main`

### 3. Configure App Settings on Bitrise
- **App title**: Elite Laundry Customer App
- **Bundle ID**: `com.example.eliteLaundryCustomerApp`
- **Project type**: Flutter
- **Stack**: macOS (Xcode 15.2+)

### 4. Code Signing Setup (CRITICAL)
1. **Generate certificates** in Apple Developer Portal:
   - iOS Distribution Certificate
   - App Store Provisioning Profile for your bundle ID

2. **Upload to Bitrise**:
   - Go to your app → Workflow → Code Signing
   - Upload `.p12` certificate + password
   - Upload `.mobileprovision` file

### 5. Trigger Your First Build
1. **Manual trigger**: Go to Builds → Start/Schedule a build
2. **Automatic**: Push to main branch (already configured in bitrise.yml)

## Expected Build Output
- **IPA file**: `build/ios/ipa/Elite Laundry Station.ipa`
- **Build time**: ~15-20 minutes
- **Status**: Success/Error logs available in Bitrise dashboard

## Troubleshooting Common Issues

### Code Signing Errors
- Ensure bundle ID matches in Apple Developer Portal and Xcode
- Check certificate expiration dates
- Verify provisioning profile includes your device UDIDs (for development)

### Flutter Version Mismatch
- Bitrise will automatically use Flutter 3.29.0 (as configured)
- If issues occur, check Flutter doctor logs in build

### Dependency Issues
- All dependencies are installed via `flutter pub get`
- Check pubspec.yaml for any platform-specific issues

## Next Steps After Successful Build
1. Download the IPA from Bitrise artifacts
2. Test on physical iOS devices
3. For App Store distribution: 
   - Update bundle ID to proper reverse-domain format
   - Create App Store Connect record
   - Submit for review

## Support Resources
- [Bitrise Flutter Documentation](https://devcenter.bitrise.io/en/getting-started/getting-started-with-flutter-apps.html)
- [Apple Developer Portal](https://developer.apple.com/account)
- [Flutter iOS Deployment Guide](https://flutter.dev/docs/deployment/ios)
