# Password recovery OTP setup

In your hosted Supabase project, open Authentication → Email Templates → Reset Password.
Replace the email body with the contents of `supabase/templates/recovery.html` and save.
The required variable is `{{ .Token }}`; a default template containing only
`{{ .ConfirmationURL }}` sends a link instead of a visible code.

For server-side password enforcement, open Authentication password security settings:
set minimum password length to 8 and require uppercase letters, numbers and symbols.
The app validates these requirements and confirmation before updating the password.

Test with a real registered account:
1. Run the app: Welcome appears even when a session was saved.
2. Log in → Forgot your password → submit your registered email.
3. An invalid/expired code must not open the New password screen.
4. Enter the emailed code. New password and confirmation appear.
5. Reject passwords missing a capital letter, number, symbol, or 8-character length.
6. Reject a different confirmation. Save a valid password, then log in with it.
7. Cancel after verification: the recovery session is signed out locally.
8. Confirm the name fix still shows your account name in Home and Profile.

Flutter/Dart SDK was not available in the editing environment, so app execution
and real email delivery must be checked in your Flutter environment after setup.
