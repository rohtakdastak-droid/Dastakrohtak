import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowLeft, Mail, Lock, Sparkles, UtensilsCrossed, UserPlus, KeyRound } from 'lucide-react';
import { signInWithEmail, signInWithPassword, signInWithGoogle, signUpWithPassword, resetPassword } from '../lib/auth';

type Tab = 'login' | 'signup' | 'magic';

export default function Login() {
  const [tab, setTab] = useState<Tab>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [sent, setSent] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [googleBusy, setGoogleBusy] = useState(false);
  const [resetSent, setResetSent] = useState(false);
  const nav = useNavigate();

  async function submitLogin(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    const { error } = await signInWithPassword(email, password);
    setBusy(false);
    if (error) setErr(error.message);
    else nav('/');
  }

  async function submitSignup(e: React.FormEvent) {
    e.preventDefault();
    if (password.length < 6) { setErr('Password must be at least 6 characters.'); return; }
    setBusy(true);
    setErr(null);
    const { error } = await signUpWithPassword(email, password);
    setBusy(false);
    if (error) {
      setErr(error.message);
    } else {
      setSent(true);
    }
  }

  async function submitMagicLink(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    const { error } = await signInWithEmail(email);
    setBusy(false);
    if (error) setErr(error.message);
    else setSent(true);
  }

  async function handleForgotPassword() {
    if (!email) { setErr('Enter your email first.'); return; }
    setBusy(true);
    setErr(null);
    const { error } = await resetPassword(email);
    setBusy(false);
    if (error) setErr(error.message);
    else setResetSent(true);
  }

  async function google() {
    setErr(null);
    setGoogleBusy(true);
    const { error } = await signInWithGoogle();
    setGoogleBusy(false);
    if (error) setErr(error.message);
  }

  function switchTab(t: Tab) {
    setTab(t);
    setErr(null);
    setSent(false);
    setResetSent(false);
  }

  return (
    <div className="page-enter flex min-h-full flex-col bg-gradient-to-br from-brand-500 via-brand-600 to-brand-700">
      <div className="px-6 pt-6">
        <button onClick={() => nav(-1)} className="flex h-10 w-10 items-center justify-center rounded-2xl bg-white/20 text-white backdrop-blur transition hover:bg-white/30">
          <ArrowLeft size={18} />
        </button>
      </div>

      <div className="flex flex-1 flex-col items-center justify-center px-6 py-6">
        <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-white/20 backdrop-blur">
          <UtensilsCrossed size={30} className="text-white" />
        </div>
        <div className="mt-3 flex items-center gap-2">
          <Sparkles size={14} className="text-yellow-300" />
          <span className="text-xs font-semibold text-white/80">Welcome to</span>
        </div>
        <div className="mt-1 text-3xl font-bold tracking-tight text-white">Dastak</div>
        <div className="mt-1 text-center text-xs text-white/60">
          Delicious food from your favourite restaurants & cafes
        </div>
      </div>

      <div className="rounded-t-[2rem] bg-white px-5 pb-8 pt-6 shadow-2xl dark:bg-neutral-900">
        <button onClick={google} disabled={googleBusy} className="flex w-full items-center justify-center gap-3 rounded-2xl border border-neutral-200 bg-white px-4 py-3 text-sm font-semibold text-neutral-700 shadow-sm transition hover:shadow-md active:scale-[0.98] dark:border-neutral-700 dark:bg-neutral-800 dark:text-neutral-200">
          <GoogleIcon /> {googleBusy ? 'Opening Google…' : 'Continue with Google'}
        </button>

        <div className="my-4 flex items-center gap-3 text-xs text-neutral-400">
          <div className="h-px flex-1 bg-neutral-200 dark:bg-neutral-800" />
          OR
          <div className="h-px flex-1 bg-neutral-200 dark:bg-neutral-800" />
        </div>

        {/* Tabs */}
        <div className="mb-4 flex rounded-2xl bg-neutral-100 p-1 dark:bg-neutral-800">
          {([
            { key: 'login' as Tab, icon: <KeyRound size={12} />, label: 'Login' },
            { key: 'signup' as Tab, icon: <UserPlus size={12} />, label: 'Sign Up' },
            { key: 'magic' as Tab, icon: <Mail size={12} />, label: 'Magic Link' },
          ]).map(({ key, icon, label }) => (
            <button
              key={key}
              onClick={() => switchTab(key)}
              className={`flex flex-1 items-center justify-center gap-1 rounded-xl py-2 text-xs font-semibold transition-all ${
                tab === key ? 'bg-white text-neutral-900 shadow-sm dark:bg-neutral-700 dark:text-white' : 'text-neutral-500'
              }`}
            >
              {icon} {label}
            </button>
          ))}
        </div>

        {tab === 'login' && (
          <form onSubmit={submitLogin} className="space-y-2.5">
            <div className="relative">
              <Mail size={15} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-400" />
              <input type="email" required className="input pl-10 py-2.5 text-sm" placeholder="you@email.com" value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <div className="relative">
              <Lock size={15} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-400" />
              <input type="password" required className="input pl-10 py-2.5 text-sm" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} />
            </div>
            <button className="btn-primary w-full" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
            <button type="button" onClick={handleForgotPassword} className="w-full text-center text-xs font-medium text-brand-600 hover:underline">
              Forgot password?
            </button>
            {resetSent && (
              <div className="animate-scale-in rounded-xl bg-emerald-50 p-3 text-xs text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-200">
                Password reset email sent! Check your inbox.
              </div>
            )}
          </form>
        )}

        {tab === 'signup' && (
          <form onSubmit={submitSignup} className="space-y-2.5">
            <div className="relative">
              <Mail size={15} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-400" />
              <input type="email" required className="input pl-10 py-2.5 text-sm" placeholder="you@email.com" value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <div className="relative">
              <Lock size={15} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-400" />
              <input type="password" required minLength={6} className="input pl-10 py-2.5 text-sm" placeholder="Create password (min 6 chars)" value={password} onChange={(e) => setPassword(e.target.value)} />
            </div>
            <button className="btn-primary w-full" disabled={busy}>{busy ? 'Creating account…' : 'Create account'}</button>
            {sent && (
              <div className="animate-scale-in rounded-xl bg-emerald-50 p-3 text-xs text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-200">
                Account created! Check email to confirm, then sign in.
              </div>
            )}
          </form>
        )}

        {tab === 'magic' && (
          <form onSubmit={submitMagicLink} className="space-y-2.5">
            <div className="relative">
              <Mail size={15} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-400" />
              <input type="email" required className="input pl-10 py-2.5 text-sm" placeholder="you@email.com" value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <button className="btn-primary w-full" disabled={busy}>{busy ? 'Sending…' : 'Send magic link'}</button>
            {sent && (
              <div className="animate-scale-in rounded-xl bg-emerald-50 p-3 text-xs text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-200">
                Check your email for the sign-in link.
              </div>
            )}
          </form>
        )}

        {err && (
          <div className="mt-3 animate-scale-in rounded-xl bg-red-50 p-3 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200">{err}</div>
        )}

        <div className="mt-4 text-center text-xs text-neutral-500">
          By continuing you agree to Dastak's terms.
          <br />
          <Link to="/" className="mt-1 inline-block font-semibold text-brand-600">Continue browsing →</Link>
        </div>
      </div>
    </div>
  );
}

function GoogleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true">
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.9 32.4 29.4 35.5 24 35.5c-6.4 0-11.5-5.1-11.5-11.5S17.6 12.5 24 12.5c2.9 0 5.6 1.1 7.6 2.9l5.7-5.7C33.6 6.4 29 4.5 24 4.5 13.2 4.5 4.5 13.2 4.5 24S13.2 43.5 24 43.5 43.5 34.8 43.5 24c0-1.2-.1-2.3-.3-3.5z" />
      <path fill="#FF3D00" d="M6.3 14.1l6.6 4.8C14.6 15.1 18.9 12.5 24 12.5c2.9 0 5.6 1.1 7.6 2.9l5.7-5.7C33.6 6.4 29 4.5 24 4.5 16.3 4.5 9.6 8.9 6.3 14.1z" />
      <path fill="#4CAF50" d="M24 43.5c5 0 9.5-1.9 12.9-5l-6-5c-1.8 1.3-4.2 2-6.9 2-5.3 0-9.8-3.3-11.4-7.9l-6.5 5C9.4 39 16.1 43.5 24 43.5z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.3 4.1-4.3 5.5l6 5c-.4.4 6.5-4.7 6.5-14.5 0-1.2-.1-2.3-.3-3.5z" />
    </svg>
  );
}
