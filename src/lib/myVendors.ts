import { useEffect, useState } from 'react';
import { supabase, type Vendor } from './supabase';
import { useSession } from './auth';

export function useMyVendors() {
  const { session } = useSession();
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!session) {
      setVendors([]);
      setLoading(false);
      return;
    }
    supabase
      .from('vendor_members')
      .select('vendor:vendors(*)')
      .eq('user_id', session.user.id)
      .eq('status', 'active')
      .then(({ data }) => {
        const vs = (data ?? []).map((r: any) => r.vendor).filter(Boolean) as Vendor[];
        setVendors(vs);
        setLoading(false);
      });
  }, [session?.user.id]);

  return { vendors, loading };
}
