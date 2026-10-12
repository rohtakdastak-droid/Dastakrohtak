import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import type { Session } from '@supabase/supabase-js';
import { Capacitor } from '@capacitor/core';
import { Browser } from '@capacitor/browser';

export function authRedirectUrl() {
  return Capacitor.isNativePlatform() ? 'com.dastak.app://auth/callback' : window.location.origin + '/';
}

export function useSession() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);
  return { session, loading };
}

export async function signInWithEmail(email: string) {
  return supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: authRedirectUrl() } });
}

export async function signInWithGoogle() {
  // Requires Google provider enabled in Supabase → Auth → Providers.
  // Free: Google Cloud OAuth client in the free tier, Supabase handles the exchange.
  try {
  const response = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/auth/v1/settings`, {
    headers: { apikey: import.meta.env.VITE_SUPABASE_ANON_KEY },
  });
  if (!response.ok) throw new Error('Unable to reach sign-in service. Please retry.');
  const settings = await response.json();
  if (!settings.external?.google) return { error: { message: 'Google sign-in is not enabled yet. Please use email sign-in or contact support.' } };
  const native = Capacitor.isNativePlatform();
  const result = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: authRedirectUrl(), skipBrowserRedirect: native },
  });
  if (native && result.data.url && !result.error) await Browser.open({ url: result.data.url });
  return result;
  } catch (error) {
    return { error: { message: error instanceof Error ? error.message : 'Sign-in failed. Please retry.' } };
  }
}

export async function signOut() {
  return supabase.auth.signOut();
}
