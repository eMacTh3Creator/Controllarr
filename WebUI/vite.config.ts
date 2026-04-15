import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Controllarr WebUI is bundled into the .app at /Resources/WebUI/
// and served at the root. Use relative asset paths so it works no
// matter where the server roots it.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'es2022',
  },
  server: {
    // During `npm run dev` we proxy API calls to the running
    // Controllarr backend. Point this at wherever yours is running.
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8791',
        changeOrigin: true,
      },
    },
  },
})
