import { Capacitor } from '@capacitor/core';
import { PushNotifications } from '@capacitor/push-notifications';
import { supabase } from './supabase';

export function isNativePush(): boolean {
  return Capacitor.isNativePlatform();
}

export async function registerNativePush(userId: string): Promise<boolean> {
  if (!isNativePush()) return false;

  let permStatus = await PushNotifications.checkPermissions();
  if (permStatus.receive === 'prompt') {
    permStatus = await PushNotifications.requestPermissions();
  }
  if (permStatus.receive !== 'granted') return false;

  return new Promise<boolean>((resolve) => {
    let resolved = false;

    PushNotifications.addListener('registration', async (token) => {
      if (resolved) return;
      resolved = true;
      const { error } = await supabase.from('fcm_tokens').upsert(
        {
          user_id: userId,
          token: token.value,
          platform: Capacitor.getPlatform(),
        },
        { onConflict: 'token' }
      );
      resolve(!error);
    });

    PushNotifications.addListener('registrationError', () => {
      if (!resolved) {
        resolved = true;
        resolve(false);
      }
    });

    PushNotifications.register();
  });
}

export async function unregisterNativePush(): Promise<void> {
  if (!isNativePush()) return;
  try {
    const token = await getCurrentFcmToken();
    if (token) {
      await supabase.from('fcm_tokens').delete().eq('token', token);
    }
  } catch { /* ignore */ }
}

async function getCurrentFcmToken(): Promise<string | null> {
  try {
    const result = await PushNotifications.checkPermissions();
    if (result.receive !== 'granted') return null;
    return new Promise((resolve) => {
      PushNotifications.addListener('registration', (t) => resolve(t.value));
      PushNotifications.addListener('registrationError', () => resolve(null));
      PushNotifications.register();
    });
  } catch {
    return null;
  }
}

export function setupNativePushListeners(): void {
  if (!isNativePush()) return;

  PushNotifications.addListener('pushNotificationReceived', (notification) => {
    console.log('[NativePush] Received in foreground:', notification);
  });

  PushNotifications.addListener('pushNotificationActionPerformed', (action) => {
    const data = action.notification.data;
    if (data?.order_id) {
      window.location.href = `/orders/${data.order_id}`;
    }
  });
}
