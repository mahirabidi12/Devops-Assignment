import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The build output lands in dist/, which is the only thing the
// second Dockerfile stage copies into the nginx image.
export default defineConfig({
  plugins: [react()],
});
