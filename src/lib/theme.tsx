import { createContext, useContext, useEffect, useState, ReactNode } from 'react';

type Theme = 'light' | 'dark' | 'system';
type Ctx = { theme: Theme; setTheme: (t: Theme) => void; resolved: 'light' | 'dark' };

const ThemeCtx = createContext<Ctx | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<Theme>(
    () => (localStorage.getItem('dastak.theme') as Theme) || 'system'
  );
  const [resolved, setResolved] = useState<'light' | 'dark'>('light');

  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => {
      const r = theme === 'system' ? (mq.matches ? 'dark' : 'light') : theme;
      setResolved(r);
      document.documentElement.classList.toggle('dark', r === 'dark');
    };
    apply();
    localStorage.setItem('dastak.theme', theme);
    mq.addEventListener('change', apply);
    return () => mq.removeEventListener('change', apply);
  }, [theme]);

  return <ThemeCtx.Provider value={{ theme, setTheme, resolved }}>{children}</ThemeCtx.Provider>;
}

export function useTheme() {
  const v = useContext(ThemeCtx);
  if (!v) throw new Error('useTheme outside provider');
  return v;
}
