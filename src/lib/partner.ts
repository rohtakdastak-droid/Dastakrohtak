import { useEffect, useState } from 'react';
import { supabase } from './supabase';
import { useSession } from './auth';

export type PartnerProfile = {
  user_id: string;
  vehicle_type: string | null;
  vehicle_number: string | null;
  profile_photo_path: string | null;
  partner_qr_code: string | null;
  approved_at: string | null;
  is_online: boolean;
};

export type PartnerAccount = {
  profile: PartnerProfile | null;
  status: 'active' | 'pending' | 'suspended' | 'rejected' | 'unknown';
  display_name: string | null;
};

export function usePartner() {
  const { session } = useSession();
  const [data, setData] = useState<PartnerAccount | null>(null);
  const [loading, setLoading] = useState(true);

  async function load() {
    if (!session) {
      setData(null);
      setLoading(false);
      return;
    }
    const [p, dp] = await Promise.all([
      supabase.from('profiles').select('role,status,display_name').eq('id', session.user.id).single(),
      supabase.from('delivery_partner_profiles').select('*').eq('user_id', session.user.id).maybeSingle(),
    ]);
    setData({
      profile: (dp.data as PartnerProfile) ?? null,
      status: (p.data?.status as any) ?? 'unknown',
      display_name: p.data?.display_name ?? null,
    });
    setLoading(false);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.user.id]);

  return { data, loading, reload: load };
}
