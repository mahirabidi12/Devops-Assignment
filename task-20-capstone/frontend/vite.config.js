import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // In development the API runs on a different port. In production nginx
    // proxies /api to the backend Service instead, so no origin is baked in.
    proxy: { '/api': 'http://localhost:8000' },
  },
})
