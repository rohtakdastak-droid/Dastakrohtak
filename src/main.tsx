import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import './index.css';
import { ThemeProvider } from './lib/theme';
import { initializeNativeAuth } from './lib/nativeAuth';
import { setupNativePushListeners } from './lib/nativePush';

void initializeNativeAuth();
setupNativePushListeners();

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </ThemeProvider>
  </React.StrictMode>
);
