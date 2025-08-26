# Password Reset Setup Guide

This guide explains how to set up and use the password reset functionality in the Indoor Navigation app.

## Overview

The password reset flow works as follows:
1. User enters email in the reset password screen
2. Supabase sends a password reset email with a deep link
3. User clicks the link, which opens the mobile app
4. User enters a new password in the app
5. Password is updated and user can log in

## Setup Instructions

### 1. Configure Supabase

In your Supabase project dashboard:

1. Go to **Authentication → Settings → URL Configuration**
2. Add the following redirect URLs:
   - `com.example.indoornavigation://auth/callback` (for mobile deep links)
   - `http://localhost:3000/reset-password.html` (for testing with HTML page)

### 2. Mobile App Configuration

The mobile app is already configured with:
- Deep link handling in `main.dart`
- Android manifest with intent filters
- New password screen (`NewPasswordScreen`)
- Updated `SupabaseService` with password reset methods

### 3. Testing the Flow

#### Option A: Test with Mobile Device

1. Run the app on a device: `flutter run`
2. Go to the login screen and tap "Forgot Password?"
3. Enter an email address and tap "Send Reset Link"
4. Check your email for the reset link
5. Tap the link on your mobile device
6. The app should open and navigate to the new password screen
7. Enter your new password and tap "Update Password"

#### Option B: Test with HTML Page (Development)

1. Update the redirect URL in `supabase_service.dart` to use the HTML page:
   ```dart
   redirectTo: 'http://localhost:3000/reset-password.html',
   ```

2. Serve the HTML file:
   ```bash
   # Using Python
   python -m http.server 3000
   
   # Or using Node.js
   npx serve -p 3000 .
   ```

3. Follow the same steps as Option A, but the email link will open the HTML page
4. Click "Open App & Reset Password" on the HTML page to launch the mobile app

## Troubleshooting

### Deep Links Not Working

1. **Android**: Check that the intent filters are correctly added to `AndroidManifest.xml`
2. **iOS**: Add URL scheme to `ios/Runner/Info.plist` (not implemented yet)
3. **Testing**: Use `adb shell am start -W -a android.intent.action.VIEW -d "com.example.indoornavigation://auth/callback#access_token=test&refresh_token=test&type=recovery" com.example.place_recognition_app`

### Email Not Received

1. Check spam/junk folder
2. Verify email address is correct
3. Check Supabase project logs for any errors
4. Ensure SMTP is properly configured in Supabase

### App Doesn't Open from Email

1. Make sure the app is installed on the device
2. Check that deep link URLs match between Supabase config and app config
3. Test the deep link manually using the adb command above

### Password Update Fails

1. Check that the tokens are being extracted correctly from the URL
2. Verify network connectivity
3. Check Supabase project logs for authentication errors

## Customization

### Change Deep Link Scheme

1. Update the scheme in `AndroidManifest.xml`
2. Update the scheme in `supabase_service.dart`
3. Update the scheme in `reset-password.html`

### Customize Email Template

1. Go to Supabase dashboard → Authentication → Email Templates
2. Edit the "Reset Password" template
3. Customize the email content and styling

### Add iOS Support

1. Add URL scheme to `ios/Runner/Info.plist`:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLName</key>
           <string>com.example.indoornavigation</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>com.example.indoornavigation</string>
           </array>
       </dict>
   </array>
   ```

## Security Notes

- The access and refresh tokens are passed via URL parameters, which is secure for this use case
- Tokens have a limited lifespan and can only be used once for password reset
- The app validates tokens before allowing password changes
- Always use HTTPS in production environments
