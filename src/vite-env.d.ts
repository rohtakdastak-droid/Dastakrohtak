/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_ANON_KEY: string;
  readonly VITE_GOOGLE_MAPS_API_KEY?: string;
  readonly VITE_MAPBOX_TOKEN?: string;
  readonly VITE_FALLBACK_UPI_VPA?: string;
  readonly VITE_FALLBACK_UPI_NAME?: string;
}
interface ImportMeta { readonly env: ImportMetaEnv; }
