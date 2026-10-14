// Run with: node --test supabase/functions/places-search/parse.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSuggestions } from './parse.ts';

test('keeps suggestions with coordinates and readable titles', () => {
  const s = parseSuggestions({
    predictions: [
      {
        description: 'Tilak Nagar, Rohtak, Haryana, India',
        structured_formatting: { main_text: 'Tilak Nagar', secondary_text: 'Rohtak, Haryana, India' },
        geometry: { location: { lat: 28.9, lng: 76.6 } },
      },
      { description: 'No coordinates, Rohtak' },
      { description: 'Model Town, Rohtak', geometry: { location: { lat: '28.88', lng: '76.59' } } },
    ],
  });
  assert.deepEqual(s, [
    { title: 'Tilak Nagar', subtitle: 'Rohtak, Haryana, India', description: 'Tilak Nagar, Rohtak, Haryana, India', lat: 28.9, lng: 76.6 },
    { title: 'Model Town', subtitle: 'Model Town, Rohtak', description: 'Model Town, Rohtak', lat: 28.88, lng: 76.59 },
  ]);
});

test('bad or empty responses give no suggestions', () => {
  assert.deepEqual(parseSuggestions(null), []);
  assert.deepEqual(parseSuggestions({ predictions: 'x' }), []);
  assert.deepEqual(parseSuggestions({ predictions: [{ description: 'X', geometry: { location: { lat: 999, lng: 0 } } }] }), []);
});

test('at most six suggestions are returned', () => {
  const many = Array.from({ length: 10 }, (_, i) => ({ description: `Place ${i}`, geometry: { location: { lat: 28, lng: 76 } } }));
  assert.equal(parseSuggestions({ predictions: many }).length, 6);
});
