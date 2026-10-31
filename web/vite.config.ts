import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

// In development the API is proxied, so the browser sees one origin and the API's httpOnly
// session cookie just works. API_URL (in web/.env.local) points at the running API.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const target = env.API_URL || 'http://localhost:3000';
  return {
    plugins: [react(), tailwindcss()],
    server: {
      port: Number(env.WEB_PORT) || 5173,
      proxy: {
        '/api': { target, changeOrigin: true },
        '/uploads': { target, changeOrigin: true },
      },
    },
  };
});
