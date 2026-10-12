import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import type { Session } from '@supabase/supabase-js';

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
  return supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: window.location.origin } });
}

export async function signInWithGoogle() {
  // Requires Google provider enabled in Supabase → Auth → Providers.
  // Free: Google Cloud OAuth client in the free tier, Supabase handles the exchange.
  return supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: window.location.origin },
  });
}

export async function signOut() {
  return supabase.auth.signOut();
}
