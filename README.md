# Wozz Landing Page

A beautiful, modern landing page for Wozz - a tool that finds expensive cloud cost bugs in your code before they hit production.

## Features

- 🎨 Clean, Apple-inspired design with Wizard of Oz theme
- 📱 Fully responsive
- ✨ Smooth animations and interactions
- 📝 Blog post about finding cost bugs in Airbyte
- 📧 Email collection forms (via Formspree)

## Setup

### 1. Formspree Configuration

The forms use Formspree for email collection. You need to:

1. Go to [Formspree.io](https://formspree.io) and create a free account
2. Create a new form
3. Copy your form ID (it will look like `xqwerty123`)
4. Replace `YOUR_FORM_ID` in both HTML files with your actual Formspree form ID

Search for `YOUR_FORM_ID` in:
- `index.html` (appears twice - hero form and CTA form)
- `airbyte-story.html` (if you add forms there)

### 2. Deploy to Vercel

#### Option A: Deploy via GitHub (Recommended)

1. Push this repository to GitHub:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/WozzHQ/wozz-app.git
   git push -u origin main
   ```

2. Go to [Vercel](https://vercel.com) and sign in with GitHub
3. Click "New Project"
4. Import your `wozz-app` repository
5. Vercel will auto-detect it's a static site
6. Click "Deploy"

#### Option B: Deploy via Vercel CLI

```bash
npm i -g vercel
vercel
```

### 3. Custom Domain (Optional)

1. In Vercel dashboard, go to your project settings
2. Navigate to "Domains"
3. Add your custom domain (e.g., `wozz.io`)

## File Structure

```
wozz-app/
├── index.html              # Main landing page
├── airbyte-story.html      # Blog post about Airbyte bug
├── vercel.json             # Vercel configuration
├── .gitignore              # Git ignore rules
└── README.md               # This file
```

## Local Development

Simply open `index.html` in your browser, or use a local server:

```bash
python3 -m http.server 8000
```

Then visit `http://localhost:8000`

## Security

- All external links use HTTPS
- Security headers configured in `vercel.json`
- No hardcoded credentials or API keys
- Forms use Formspree's secure endpoint

## License

Copyright © 2025 Wozz Inc. All rights reserved.

