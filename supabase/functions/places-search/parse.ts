export type Suggestion = { title: string; subtitle: string; description: string; lat: number; lng: number };

/** Keeps only predictions that carry valid coordinates, so a chosen suggestion can always place the map pin. */
export function parseSuggestions(body: unknown, limit = 6): Suggestion[] {
  const predictions = (body as { predictions?: unknown[] })?.predictions;
  if (!Array.isArray(predictions)) return [];
  const out: Suggestion[] = [];
  for (const raw of predictions) {
    const p = raw as {
      description?: unknown;
      structured_formatting?: { main_text?: unknown; secondary_text?: unknown };
      geometry?: { location?: { lat?: unknown; lng?: unknown } };
    };
    const lat = Number(p?.geometry?.location?.lat);
    const lng = Number(p?.geometry?.location?.lng);
    const description = typeof p?.description === 'string' ? p.description.trim() : '';
    if (!description || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) continue;
    const main = p.structured_formatting?.main_text;
    const secondary = p.structured_formatting?.secondary_text;
    out.push({
      title: typeof main === 'string' && main.trim() ? main.trim() : description.split(',')[0].trim(),
      subtitle: typeof secondary === 'string' ? secondary.trim() : description,
      description: description.slice(0, 300),
      lat,
      lng,
    });
    if (out.length >= limit) break;
  }
  return out;
}
