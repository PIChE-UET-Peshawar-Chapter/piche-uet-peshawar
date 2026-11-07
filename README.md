# PICHE UET Peshawar website: setup guide

Files: `index.html` (the whole website), `schema.sql` (database, security rules, photo storage).
Not yet tested against a live Supabase project: follow the checklist at the end after setup.

## 1. Supabase (database, login, photos)
1. Create a free account and a new project at supabase.com. Save the database password.
2. SQL Editor > New query > paste all of `schema.sql` > Run.
3. Run this line with your own email to make yourself administrator:
   `insert into staff (email, role) values ('you@example.com','admin');`
4. Authentication > Sign In / Providers: keep Email enabled. Authentication > Email Templates > "Magic Link": replace the body with a line that shows the code, for example `Your PICHE sign-in code is {{ .Token }}`. Do the same for "Confirm signup".
5. Project Settings > API: copy the **Project URL** and the **anon public** key.
6. Open `index.html`, find `const SB_URL='',SB_KEY='';` near the top of the script, and paste the two values between the quotes.

The default Supabase email sender is limited to a few emails per hour. Before launch, add your own SMTP service under Authentication > SMTP Settings.

## 2. GitHub and Vercel (publishing)
1. Create a GitHub repository and upload `index.html` (and `schema.sql`, `README.md`).
2. At vercel.com choose Add New > Project, import the repository, and deploy. No build settings are needed.
3. Supabase > Authentication > URL Configuration: set Site URL to your Vercel address.
4. QR codes use the address the site is opened from, so open and test the final domain before printing cards.

## 3. Domain
Buy a domain (for example picheuetpeshawar.org), then Vercel > Settings > Domains > add it and follow the DNS steps. HTTPS is automatic. Update the Site URL in Supabase to the domain.

## 4. Backups
Free Supabase projects have no automatic backups. Export members to Excel from the admin dashboard regularly, or upgrade the plan for daily backups.

## 5. Test checklist
Register a test student, then sign in as staff, approve them, check the ID card and PDF, scan the QR link, sign in as that member with registration number and email code, and confirm the public directory shows no phone, address or email.
Use sample data only until everything passes.
