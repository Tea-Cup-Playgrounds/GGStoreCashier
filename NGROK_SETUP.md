# Ngrok Setup Guide

Ngrok creates a public URL that tunnels to your local API, allowing you to test the Flutter app on physical devices or share your API with others.

## Why Use Ngrok?

- **Physical Device Testing**: Test on real phones without being on the same WiFi
- **Remote Testing**: Share your API with team members or testers
- **Webhook Testing**: Receive webhooks from external services
- **HTTPS**: Get a free HTTPS URL for testing secure connections

## Setup Steps

### 1. Create Ngrok Account

1. Go to [https://ngrok.com/](https://ngrok.com/)
2. Sign up for a free account
3. After login, go to "Your Authtoken" page: [https://dashboard.ngrok.com/get-started/your-authtoken](https://dashboard.ngrok.com/get-started/your-authtoken)
4. Copy your authtoken (looks like: `2abc123def456ghi789jkl0mnop1qrs_2tuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`)

### 2. Add Authtoken to `.env`

Open your `.env` file in the project root and add:

```env
# Database
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=gg_store

# API
PORT=3000
JWT_SECRET=your_secret_key

# Ngrok
NGROK_AUTHTOKEN=2abc123def456ghi789jkl0mnop1qrs_2tuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ

# API Timeout
API_TIMEOUT=30000
```

### 3. Run the Server

```bash
npm run dev
```

You'll see output like:

```
Server running on port 3000
Socket.IO enabled for real-time updates
API Docs: http://localhost:3000/api/docs

ngrok public URL : https://abc123.ngrok.io
API Docs           : https://abc123.ngrok.io/api/docs

✅ app/.env updated with ngrok URL
```

The server automatically:

1. Starts ngrok tunnel
2. Gets the public URL
3. Writes it to `app/.env` so Flutter uses it

### 4. Verify It Works

**Test in browser:**

```
https://abc123.ngrok.io/api/health
```

Should return:

```json
{
  "status": "OK",
  "message": "Server is running"
}
```

**Check Flutter config:**

```bash
cat app/.env
```

Should show:

```env
API_BASE_URL=https://abc123.ngrok.io
API_TIMEOUT=30000
```

### 5. Run Flutter App

Now when you run the Flutter app, it will connect via the ngrok URL:

```bash
cd app
fvm flutter run
```

Or use VS Code Run & Debug → "Flutter (Mobile App via FVM)"

## Without Ngrok (Emulator Only)

If you don't add `NGROK_AUTHTOKEN`, the server will:

1. Skip ngrok tunnel
2. Write `http://10.0.2.2:3000` to `app/.env` (Android emulator localhost)
3. Work fine for emulator testing

```bash
npm run dev
```

Output:

```
Server running on port 3000
⚠️  NGROK_AUTHTOKEN not set — skipping ngrok tunnel
✅ app/.env updated with emulator URL: http://10.0.2.2:3000
```

## Ngrok Free Tier Limits

- **1 online ngrok process** at a time
- **40 connections/minute**
- **Random URL** each time (e.g., `https://abc123.ngrok.io` changes on restart)
- **2 hour session limit** (tunnel closes after 2 hours, restart to get new URL)

### Paid Plans ($8/month+):

- Custom subdomain (e.g., `https://myapp.ngrok.io`)
- Longer sessions
- More connections
- Reserved domains

## Troubleshooting

### "Invalid authtoken" error

- Double-check you copied the full token from ngrok dashboard
- Make sure there are no extra spaces in `.env`
- Token should be one long string with no line breaks

### Ngrok URL changes every restart

- This is normal on free tier
- The server auto-updates `app/.env` each time
- Just restart the Flutter app to pick up the new URL

### Flutter still connects to old URL

1. Stop the Flutter app
2. Check `app/.env` has the new ngrok URL
3. Restart Flutter app (hot reload won't pick up .env changes)

### "Tunnel not found" in browser

- Make sure the server is running (`npm run dev`)
- Check the console for the ngrok URL
- Try the URL in an incognito window (some browsers cache redirects)

### Rate limit errors

- Free tier has 40 connections/minute
- If you hit this, wait a minute or upgrade to paid plan
- Reduce unnecessary API calls in your Flutter app

## Alternative: Using Your Local IP (No Ngrok)

If you just want to test on a physical device on the same WiFi:

1. Find your computer's local IP:

   ```bash
   # Windows
   ipconfig
   # Look for IPv4 Address (e.g., 192.168.1.100)

   # Mac/Linux
   ifconfig | grep "inet "
   ```

2. Manually edit `app/.env`:

   ```env
   API_BASE_URL=http://192.168.1.100:3000
   API_TIMEOUT=30000
   ```

3. Make sure Windows Firewall allows port 3000

4. Run the server without ngrok:

   ```bash
   npm run dev
   ```

5. Connect your phone to the same WiFi and run the Flutter app

## Summary

**With Ngrok:**

- Add `NGROK_AUTHTOKEN` to `.env`
- Run `npm run dev`
- Server auto-updates `app/.env` with public URL
- Works on any device, anywhere

**Without Ngrok:**

- Don't add `NGROK_AUTHTOKEN`
- Run `npm run dev`
- Server auto-updates `app/.env` with `10.0.2.2:3000`
- Works on emulator only

The server handles everything automatically — you just need to add the authtoken if you want ngrok.
