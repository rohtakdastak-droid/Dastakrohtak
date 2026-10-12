import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
import { Browser } from '@capacitor/browser';
import { supabase } from './supabase';

export async function initializeNativeAuth() {
  if (!Capacitor.isNativePlatform()) return;
  const handled = new Set<string>();
  async function callback(raw: string) {
    const url = new URL(raw);
    if (url.protocol !== 'com.dastak.app:' || url.host !== 'auth' || url.pathname !== '/callback') return;
    const code = url.searchParams.get('code');
    if (!code || handled.has(code)) return;
    handled.add(code);
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    await Browser.close().catch(() => undefined);
    if (error) {
      window.alert('Sign-in could not be completed. Please request a new sign-in link on this device.');
      return;
    }
    window.location.replace('/');
  }
  await App.addListener('appUrlOpen', ({ url }) => { void callback(url); });
  const launch = await App.getLaunchUrl();
  if (launch?.url) await callback(launch.url);
}
