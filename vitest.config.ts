import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    setupFiles: ['./tests/security/setup.ts'],
    testTimeout: 30000,
  },
});
