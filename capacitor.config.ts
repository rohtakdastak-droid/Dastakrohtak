import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.dastak.app',
  appName: 'Dastak',
  webDir: 'dist',
  server: {
    androidScheme: 'https'
  },
  android: {
    buildOptions: {
      signingType: 'apksigner'
    },
    backgroundColor: '#FAFAFA'
  },
  backgroundColor: '#FAFAFA'
};

export default config;
