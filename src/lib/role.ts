import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import { useSession } from './auth';

export type Role = 'customer' | 'vendor' | 'delivery' | 'admin';

export function useRole() {
  const { session, loading: authLoading } = useSession();
  const [role, setRole] = useState<Role | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!session) {
      setRole(null);
      setLoading(authLoading);
      return;
    }
    supabase
      .from('profiles')
      .select('role')
      .eq('id', session.user.id)
      .single()
      .then(({ data }) => {
        setRole((data?.role as Role) ?? 'customer');
        setLoading(false);
      });
  }, [session, authLoading]);

  return { role, loading, session };
}
