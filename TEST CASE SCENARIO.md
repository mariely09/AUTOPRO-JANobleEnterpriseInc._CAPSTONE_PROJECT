# Test Case Scenarios

## Module: User Registration

| Step No. | Step Details | Expected Result |
|----------|-------------|-----------------|
| 1 | Launch the app and navigate to the Login screen. Tap **"Sign Up"** at the bottom of the screen. | The Registration screen opens displaying fields: First Name, Last Name, Email Address, Password, and Confirm Password. |
| 2 | Leave all fields empty and tap **"Create Account"**. | A snackbar error appears: *"Please fill in all fields."* Registration does not proceed. |
| 3 | Fill in First Name and Last Name only. Leave Email, Password, and Confirm Password empty. Tap **"Create Account"**. | A snackbar error appears: *"Please fill in all fields."* Registration does not proceed. |
| 4 | Fill in all fields but enter mismatched passwords (e.g., Password: `Test123`, Confirm Password: `Test456`). Tap **"Create Account"**. | A snackbar error appears: *"Passwords do not match."* Registration does not proceed. |
| 5 | Fill in all fields with a password shorter than 6 characters (e.g., `abc`). Tap **"Create Account"**. | A snackbar error appears: *"Password must be at least 6 characters."* Registration does not proceed. |
| 6 | Fill in all fields with a valid email that is already registered in Firebase. Tap **"Create Account"**. | A snackbar error appears: *"An account with this email already exists."* Registration does not proceed. |
| 7 | Fill in all fields with an invalid email format (e.g., `notanemail`). Tap **"Create Account"**. | A snackbar error appears: *"Please enter a valid email address."* Registration does not proceed. |
| 8 | Fill in all fields correctly with a valid email and matching password (minimum 6 characters). Tap **"Create Account"**. | A loading spinner appears on the button. Firebase account is created. A Firestore document is saved under `users/{uid}` with role `customer` and status `active`. A green snackbar shows: *"Account created successfully! You can now sign in."* The app navigates back to the Login screen. |
| 9 | While typing a password, observe the password field. | The password field is masked by default. Once at least one character is typed, a visibility toggle icon appears on the right side of the field. |
| 10 | Tap the visibility toggle icon on the Password field. | The password text becomes visible. Tapping again re-masks the password. |
| 11 | Repeat Step 10 for the Confirm Password field. | The confirm password text toggles between visible and masked states. |
| 12 | On the Registration screen, tap **"Sign In"** at the bottom. | The Registration screen closes and the app returns to the Login screen. |
| 13 | Fill in all fields correctly and press the **Enter/Done** key on the keyboard from the Confirm Password field. | The registration flow is triggered as if the **"Create Account"** button was tapped. |

---

## Module: User Login

| Step No. | Step Details | Expected Result |
|----------|-------------|-----------------|
| 1 | Launch the app. The Login screen is displayed with Email Address and Password fields, a **"Sign In"** button, and a **"Continue with Google"** button. | Login screen loads correctly with all elements visible. |
| 2 | Leave both Email and Password fields empty. Tap **"Sign In"**. | A snackbar error appears: *"Please enter email and password."* Login does not proceed. |
| 3 | Enter a registered email but an incorrect password. Tap **"Sign In"**. | A snackbar error appears: *"Invalid email or password."* Login does not proceed. |
| 4 | Enter an email that does not exist in Firebase. Tap **"Sign In"**. | A snackbar error appears: *"Invalid email or password."* Login does not proceed. |
| 5 | Enter credentials for a user whose Firestore `status` field is `inactive`. Tap **"Sign In"**. | The user is signed out from Firebase. A snackbar error appears: *"Your account has been deactivated. Please contact the administrator."* Login does not proceed. |
| 6 | Enter credentials for a user whose Firestore `status` field is `pending`. Tap **"Sign In"**. | The user is signed out from Firebase. A snackbar error appears: *"Your account is pending admin approval. You will be notified by email once approved."* Login does not proceed. |
| 7 | Enter valid credentials for a user with role `customer` and status `active`. Tap **"Sign In"**. | A loading spinner appears. The app navigates to the **Customer Dashboard**. OneSignal login is triggered with the user's Firebase UID. |
| 8 | Enter valid credentials for a user with role `staff` and status `active`. Tap **"Sign In"**. | A loading spinner appears. The app navigates to the **Staff Dashboard**. OneSignal login is triggered with the user's Firebase UID. |
| 9 | Enter valid credentials for a user with role `admin` and status `active`. Tap **"Sign In"**. | A loading spinner appears. The app navigates to the **Admin Dashboard**. OneSignal login is triggered with the user's Firebase UID. |
| 10 | Enter valid credentials for a user with `mustChangePassword: true` in Firestore. Tap **"Sign In"**. | The app navigates to the **Change Password** screen instead of the role-based dashboard. |
| 11 | While typing a password, observe the password field. | The password field is masked by default. Once at least one character is typed, a visibility toggle icon appears. |
| 12 | Tap the visibility toggle icon on the Password field. | The password text becomes visible. Tapping again re-masks it. |
| 13 | Fill in valid credentials and press the **Enter/Done** key on the keyboard from the Password field. | The login flow is triggered as if the **"Sign In"** button was tapped. |
| 14 | Tap **"Forgot Password?"** link. | The app navigates to the **Forgot Password** screen. |
| 15 | Tap **"Sign Up"** at the bottom of the Login screen. | The app navigates to the **Registration** screen. |
| 16 | Tap **"Continue with Google"**. Select a Google account that exists in Firestore with role `customer`. | The app signs in via Google and navigates to the **Customer Dashboard**. OneSignal login is triggered with the Firebase UID. |
| 17 | Tap **"Continue with Google"**. Select a Google account that exists in Firestore with `mustChangePassword: true`. | The app navigates to the **Change Password** screen. |
| 18 | Tap **"Continue with Google"**. Select a Google account whose Firestore `status` is `inactive`. | A snackbar error appears: *"Your account has been deactivated. Please contact the administrator."* |
| 19 | Tap **"Continue with Google"**. Select a Google account that does not exist in Firestore. | A snackbar error appears: *"User account not found. Please contact the administrator to register your account."* |
| 20 | Tap **"Continue with Google"** and cancel the Google account picker without selecting an account. | The Google sign-in dialog closes. No error is shown. The Login screen remains active. |
| 21 | Attempt login with no internet connection. | A Firebase network error is thrown. A relevant error snackbar is displayed. The login spinner stops. |
