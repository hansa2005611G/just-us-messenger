# Just Us

A small, private web messenger for two people. GitHub Pages serves the frontend; Supabase provides email/password sign-in, live messages, and temporary file storage.

## Included

- Email/password accounts for two approved email addresses.
- Live one-to-one text messages.
- Private image and document sharing up to 20 MB per file.
- A recipient-only, one-time download button.
- Automatic removal of the file from Supabase Storage after the recipient's browser has received it.
- A chat note remains with the file name and “Downloaded and removed” status. The file bytes are never put in the chat database; the database keeps only the message and file details.
- Supabase row-level security policies that limit chat and storage access to the two approved accounts.
- A GitHub Actions workflow to publish the frontend to GitHub Pages.

If the recipient never downloads a file, it stays in private Storage until they do. The current version does not add an age-based expiry.

## Set up Supabase Free

1. Create a Supabase project.
2. Run `supabase/setup.sql` in the Supabase SQL Editor before either person creates an account. It creates the private 20 MB file bucket, chat tables, security policies, approved-email enrollment, one-time download handling, and the live-message subscription.
3. Add the two lowercase email addresses that should be allowed to use the chat to `private.chat_allowed_emails`. Keep these addresses in Supabase and out of the public repository. For this project, the two addresses have already been added to the connected Supabase project.
4. Under **Authentication → URL Configuration**, set the GitHub Pages address as the site URL and add it as a redirect URL. Keep email/password sign-in enabled. Set up custom SMTP under **Authentication → SMTP Settings** so Supabase can send account confirmation emails to both people. Supabase's default mailer only sends to members of your Supabase organization and is limited to two messages per hour. Keep email confirmation enabled so each person proves they own their address before signing in.
5. Copy `.env.example` to `.env.local`. Add your Supabase project URL and publishable key from **Project Settings → API**.
6. For local preview, run `npm install`, then `npm run dev`. The SQL allowlist must already contain your two email addresses.

The SQL allowlist accepts only the two addresses you enter. Each person creates an account with their own email and password, then confirms their email before signing in. Other addresses cannot join the chat.

## Publish on GitHub Pages

1. In this repository’s **Settings → Secrets and variables → Actions → Variables**, add:
   - VITE_SUPABASE_URL
   - VITE_SUPABASE_PUBLISHABLE_KEY
2. Set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**.
3. Push to `main`. The included workflow builds and publishes the site.

The publishable Supabase key is included in the web app by design; database and file access depend on the SQL security policies. Never place a Supabase service_role key in the frontend, GitHub Pages build variables, or this repository.

## File removal behavior

When the recipient clicks Download once, the browser first receives the complete file, then starts saving it, removes the object from the private Storage bucket, and updates the chat note. The database keeps the file name, size, and removed status, but clears the Storage path. The browser cannot verify that the user kept the downloaded copy on their device.

Supabase Free currently includes 1 GB of Storage and a 50 MB maximum upload size; this app uses a lower 20 MB limit. Free projects can pause after a week without activity, so the first visit after a long quiet period may require the project to wake up. See [Supabase pricing](https://supabase.com/pricing) and [Storage file limits](https://supabase.com/docs/guides/storage/uploads/file-limits).
