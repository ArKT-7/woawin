# 🚀 Google Drive Upload Setup for CI/CD 

Setup guide to configure Google Drive file uploads via GitHub Actions on Windows runners.

---

## 📌 Why This Method?

- **Personal Drive Access:** Upload directly to your personal Google Drive account
- **Permanent Setup:** Includes the Publish App step so your authentication never expires
- **Automated Uploads:** Works seamlessly with GitHub Actions CI/CD workflows

---

## Step 1: Google Cloud Console Setup (One-Time)

### 1.1 Create a New Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click **Create Project** and name it `My-Uploader-Project`
3. Click **Create** and wait for setup to complete

### 1.2 Enable Google Drive API

1. In the top search bar, search for **"Google Drive API"**
2. Click the result and press **Enable**

### 1.3 Configure OAuth Consent Screen

1. Navigate to **APIs & Services > OAuth consent screen**
2. Click **Get Started** and enter project name (e.g., `Uploader-Project`)
3. Select **External** and click **Create**
4. Fill in the **Contact information** with your email
5. Click **Save and Continue** to proceed to **Data Access**

### 1.4 Configure Data Access

1. Go to **Data Access** section
2. Click **Add or Remove Scopes**
3. In the search box, paste: `https://www.googleapis.com/auth/drive.file`
4. Check the checkbox for this scope and click **Update**
5. Click **Save and Continue** on the final screen

### 1.5 Publish Your App (⚠️ CRITICAL STEP)

1. Go to the **Audience** tab
2. Under **Publishing Status**, click **Publish App** to make your token permanent (prevents 7-day expiration)
3. Confirm the action

### 1.6 Create OAuth Credentials

1. Navigate to **APIs & Services > Credentials**
2. Click **+ Create Credentials** > **OAuth client ID**
3. Select **Application type: Desktop app**
4. Name it: `Action-Client` (or your preferred name)
5. Click **Create**
6. Copy and save both:
   - **Client ID**
   - **Client Secret**

---

## Step 2: Generate Permanent Refresh Token

Because GitHub Actions cannot log in via browser, you must generate a refresh token on your personal PC.

### 2.1 Install Required Library

Open your terminal and run:

```bash
pip install google-auth-oauthlib
```

### 2.2 Create Token Generation Script

Create a file named `get_token.py` and paste the following code (replace placeholders with your values from Step 1.6):

```python
from google_auth_oauthlib.flow import InstalledAppFlow

CLIENT_ID = "YOUR_CLIENT_ID_HERE"
CLIENT_SECRET = "YOUR_CLIENT_SECRET_HERE"
SCOPES = ['https://www.googleapis.com/auth/drive.file']

flow = InstalledAppFlow.from_client_config(
    {"installed": {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token"
    }},
    SCOPES)

creds = flow.run_local_server(port=0)
print(f"\n--- COPY THIS REFRESH TOKEN ---\n{creds.refresh_token}\n--------------------------------")
```

### 2.3 Run the Script

1. Open terminal in the folder containing `get_token.py`
2. Run: `python get_token.py`
3. A browser window will open automatically
4. Sign in with your **Google Account**
5. Grant the requested permissions

### 2.4 Save Your Refresh Token

1. Look at your terminal output
2. Copy the long string shown between the dashes
3. Save this securely (you'll need it in Step 3)

---

## Step 3: Add GitHub Secrets

Navigate to your GitHub repository and add the following secrets:

**Location:** Repository **Settings > Secrets and variables > Actions**

| Secret Name | Value | Description |
|---|---|---|
| `GDRIVE_CLIENT_ID` | Your Client ID from Step 1.6 | OAuth Client ID |
| `GDRIVE_CLIENT_SECRET` | Your Client Secret from Step 1.6 | OAuth Client Secret |
| `GDRIVE_REFRESH_TOKEN` | Token from Step 2.4 | Permanent refresh token |
| `PARENT_ID` | Google Drive folder ID | The folder where files upload. Find in URL: `drive.google.com/drive/folders/ID_IS_HERE` |

---

## Step 4: Run GitHub Actions Workflow to build ISO/ESD

---

## ⚠️ Troubleshooting

### Token Expires After 7 Days
- **Cause:** You didn't click "PUBLISH APP" in Step 1.5
- **Solution:** Go back to OAuth consent screen, publish the app, and regenerate the token in Step 2

### "App Not Verified" Warning
- **What it means:** Google warns about unverified apps
- **Is it safe?** Yes, you can safely ignore this. Verification is only required if you share the app with 100+ strangers

### Upload Fails
1. Verify all four secrets are correctly set in GitHub
2. Ensure `PARENT_ID` is a valid Google Drive folder ID
3. Check that your Google Account has sufficient storage space

---

## Quick Reference Checklist

- [ ] Created Google Cloud Project
- [ ] Enabled Google Drive API
- [ ] Set up OAuth consent screen
- [ ] Added Drive API scope
- [ ] Published the app
- [ ] Created OAuth credentials (Desktop app)
- [ ] Generated refresh token on personal PC
- [ ] Added 4 secrets to GitHub repository
- [ ] Tested workflow to build ISO/ESD
