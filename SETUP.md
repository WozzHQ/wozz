# Quick Setup Guide

## Step 1: Set Up Formspree (Email Collection)

1. Go to https://formspree.io and sign up (free)
2. Click "New Form"
3. Name it "Wozz Beta Signups" or similar
4. Copy your Form ID (looks like `xqwerty123`)
5. Open `index.html` and replace `YOUR_FORM_ID` with your actual Form ID (appears twice)

## Step 2: Push to GitHub

Run these commands in your terminal:

```bash
cd /Users/rohankumar/Desktop/Wozz-app

# Initialize git repository
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: Wozz landing page"

# Create main branch
git branch -M main

# Add your GitHub repository as remote (replace with your actual repo URL)
git remote add origin https://github.com/WozzHQ/wozz-app.git

# Push to GitHub
git push -u origin main
```

**Note:** If the repository doesn't exist on GitHub yet:
1. Go to https://github.com/WozzHQ
2. Click "New repository"
3. Name it `wozz-app`
4. Don't initialize with README (we already have one)
5. Copy the repository URL and use it in the `git remote add` command above

## Step 3: Deploy to Vercel

1. Go to https://vercel.com
2. Sign in with your GitHub account
3. Click "New Project"
4. Import the `wozz-app` repository
5. Vercel will auto-detect it's a static site
6. Click "Deploy"
7. Your site will be live in ~30 seconds!

## Step 4: Custom Domain (Optional)

1. In Vercel dashboard, go to your project
2. Click "Settings" → "Domains"
3. Add your custom domain (e.g., `wozz.io`)
4. Follow Vercel's DNS instructions

## Testing Forms

After setting up Formspree:
1. Submit a test email through the form
2. Check your Formspree dashboard to confirm it's working
3. You'll receive email notifications for each submission

## Troubleshooting

- **Forms not working?** Make sure you replaced `YOUR_FORM_ID` in `index.html`
- **Vercel deployment failed?** Check that all files are committed and pushed to GitHub
- **Need help?** Check the main README.md for more details

