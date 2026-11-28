// App Locale – V12 – funzione "servizi" (V12: ricerca, percorso col traffico, dove arrivo, colonnine – TomTom)
// Fa da ponte verso i servizi esterni, così le chiavi restano sul server (Vault) e non nel codice pubblico.
//   ?a=tile&z=&x=&y=           tessere del traffico dal vivo (TomTom)
//   ?a=webcams&lat=&lng=&r=    webcam pubbliche vicine (Windy)
//   ?a=cerca&q=&lat=&lng=      ricerca posti e indirizzi con categorie, telefono e orari (TomTom)
//   ?a=percorso&lat=&lng=&tlat=&tlng=   quanto ci metto adesso: auto col traffico e a piedi (TomTom)
//   ?a=raggio&lat=&lng=&min=   dove arrivo in N minuti in auto col traffico (TomTom)
//   ?a=colonnine&lat=&lng=&r=  colonnine di ricarica vicine con disponibilità dal vivo (TomTom)
//   ?a=perche&lat=&lng=&cc=&region=&prov=   possibili motivi in un posto: incidenti e code, webcam,
//                               meteo (Open-Meteo), scioperi in Italia (dati MIT via onData), metro di Londra (TfL)
// Serve l'accesso all'app (verify_jwt attivo). Le chiavi sono in Vault: tomtom_key, windy_key.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "npm:postgres@3.4.5";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false, max: 1 });
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};
const json = (body: unknown, status = 200, maxAge = 60) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": `private, max-age=${maxAge}` },
  });

let keys: Record<string, string> = {}, keysAt = 0;
async function getKeys() {
  if (Date.now() - keysAt < 5 * 60e3) return keys;
  const rows = await sql<{ name: string; decrypted_secret: string }[]>`
    select name, decrypted_secret from vault.decrypted_secrets where name in ('tomtom_key', 'windy_key')`;
  keys = Object.fromEntries(rows.map((r) => [r.name, r.decrypted_secret.trim()]));
  keysAt = Date.now();
  return keys;
}

const toRad = (d: number) => (d * Math.PI) / 180;
const distM = (a: [number, number], b: [number, number]) => {
  // a, b = [lat, lng]
  const R = 6371e3, dLat = toRad(b[0] - a[0]), dLng = toRad(b[1] - a[1]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(h)));
};
const num = (v: string | null) => (v === null || v === "" ? NaN : Number(v));
const timeout = (ms: number) => AbortSignal.timeout(ms);

// ---------- webcam (Windy) ----------
async function webcams(lat: number, lng: number, rKm: number, limit = 30) {
  const k = (await getKeys()).windy_key;
  if (!k) return { attiva: false, webcams: [] };
  const url = `https://api.windy.com/webcams/api/v3/webcams?nearby=${lat.toFixed(4)},${lng.toFixed(4)},${Math.min(Math.max(rKm, 1), 250)}` +
    `&include=images,location,urls&limit=${limit}&lang=it`;
  const r = await fetch(url, { headers: { "x-windy-api-key": k }, signal: timeout(8000) });
  if (!r.ok) return { attiva: true, errore: `Windy ${r.status}`, webcams: [] };
  const d = await r.json();
  const list = (d.webcams || []).map((w: any) => ({
    id: w.webcamId,
    title: w.title,
    lat: w.location?.latitude,
    lng: w.location?.longitude,
    city: w.location?.city,
    img: w.images?.current?.preview || w.images?.current?.thumbnail,
    thumb: w.images?.current?.thumbnail || w.images?.current?.icon,
    updated: w.lastUpdatedOn,
    url: w.urls?.detail || `https://www.windy.com/webcams/${w.webcamId}`,
  })).filter((w: any) => w.lat != null && w.img)
    .map((w: any) => ({ ...w, d: distM([lat, lng], [w.lat, w.lng]) }))
    .sort((a: any, b: any) => a.d - b.d);
  return { attiva: true, webcams: list };
}

// ---------- incidenti e code (TomTom) ----------
const ICON: Record<number, string> = {
  0: "Problema", 1: "Incidente", 2: "Nebbia", 3: "Condizioni pericolose", 4: "Pioggia", 5: "Ghiaccio", 6: "Coda",
  7: "Corsia chiusa", 8: "Strada chiusa", 9: "Lavori", 10: "Vento", 11: "Allagamento", 14: "Veicolo in panne",
};
async function incidents(lat: number, lng: number) {
  const k = (await getKeys()).tomtom_key;
  if (!k) return { attiva: false, incidenti: [] };
  const dLat = 0.04, dLng = 0.04 / Math.cos(toRad(lat)); // circa 4–5 km
  const bbox = [lng - dLng, lat - dLat, lng + dLng, lat + dLat].map((v) => v.toFixed(5)).join(",");
  const fields = "{incidents{type,geometry{type,coordinates},properties{iconCategory,magnitudeOfDelay,events{description},startTime,endTime,from,to,delay,roadNumbers}}}";
  const url = `https://api.tomtom.com/traffic/services/5/incidentDetails?key=${k}&bbox=${bbox}` +
    `&fields=${encodeURIComponent(fields)}&language=it-IT&timeValidityFilter=present`;
  const r = await fetch(url, { signal: timeout(8000) });
  if (!r.ok) return { attiva: true, errore: `TomTom ${r.status}`, incidenti: [] };
  const d = await r.json();
  const out = (d.incidents || []).map((i: any) => {
    const g = i.geometry || {}, pts: number[][] = g.type === "Point" ? [g.coordinates] : g.coordinates || [];
    let best = Infinity, at: number[] = pts[0] || [lng, lat];
    for (const p of pts) { const m = distM([lat, lng], [p[1], p[0]]); if (m < best) { best = m; at = p; } }
    const pr = i.properties || {};
    return {
      tipo: ICON[pr.iconCategory] || "Problema",
      testo: (pr.events || []).map((e: any) => e.description).filter(Boolean).join(", "),
      strada: (pr.roadNumbers || []).join(", "),
      da: pr.from, a: pr.to,
      ritardo_s: pr.delay || 0,
      gravita: pr.magnitudeOfDelay ?? 0,
      d: best, lat: at[1], lng: at[0],
    };
  }).sort((a: any, b: any) => b.gravita - a.gravita || a.d - b.d).slice(0, 6);
  return { attiva: true, incidenti: out };
}

// ---------- meteo adesso (Open-Meteo, senza chiave) ----------
const WMO: Record<number, string> = {
  0: "Sereno", 1: "Poco nuvoloso", 2: "Parzialmente nuvoloso", 3: "Coperto", 45: "Nebbia", 48: "Nebbia con brina",
  51: "Pioviggine", 53: "Pioviggine", 55: "Pioviggine forte", 61: "Pioggia debole", 63: "Pioggia", 65: "Pioggia forte",
  66: "Pioggia gelata", 67: "Pioggia gelata forte", 71: "Neve debole", 73: "Neve", 75: "Neve forte", 77: "Nevischio",
  80: "Rovesci", 81: "Rovesci forti", 82: "Rovesci violenti", 85: "Rovesci di neve", 86: "Forti rovesci di neve",
  95: "Temporale", 96: "Temporale con grandine", 99: "Temporale forte con grandine",
};
async function meteo(lat: number, lng: number) {
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(3)}&longitude=${lng.toFixed(3)}` +
    `&current=temperature_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m&timezone=auto`;
  const r = await fetch(url, { signal: timeout(6000) });
  if (!r.ok) return null;
  const c = (await r.json()).current || {};
  const forte = c.weather_code >= 65 || c.wind_gusts_10m >= 60 || [95, 96, 99, 75, 82, 86].includes(c.weather_code);
  return {
    cielo: WMO[c.weather_code] || "—", temp: Math.round(c.temperature_2m), pioggia_mm: c.precipitation,
    vento: Math.round(c.wind_speed_10m), raffiche: Math.round(c.wind_gusts_10m), forte,
  };
}

// ---------- scioperi in Italia (MIT, ripubblicati in formato aperto da onData) ----------
let strikes: any[] = [], strikesAt = 0;
async function scioperi(region: string, prov: string) {
  if (Date.now() - strikesAt > 60 * 60e3) {
    const r = await fetch("https://raw.githubusercontent.com/ondata/liberiamoli-tutti/main/scioperi/data/mit/mit_data.jsonl", { signal: timeout(10000) });
    if (r.ok) {
      strikes = (await r.text()).split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
      strikesAt = Date.now();
    }
  }
  const romeDay = (offset: number) =>
    new Date(Date.now() + offset * 864e5).toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
  const oggi = romeDay(0), dopodomani = romeDay(2);
  const low = (s: string) => (s || "").toLowerCase().trim();
  const reg = low(region), pr = low(prov);
  return strikes
    .filter((s) => !low(s.stato).startsWith("revocat") && s.inizio_iso <= dopodomani && (s.fine_iso || s.inizio_iso) >= oggi)
    .map((s) => {
      const qui = (pr && low(s.provincia) === pr) ? 3 : (reg && low(s.regione) === reg) ? 2 : low(s.rilevanza) === "nazionale" ? 1 : 0;
      return { qui, settore: s.settore, chi: s.categoria, quando: s.inizio_iso === s.fine_iso || !s.fine_iso ? s.inizio : `${s.inizio}–${s.fine}`,
        inizio: s.inizio_iso, modalita: s.modalita, rilevanza: s.rilevanza, zona: s.provincia && s.provincia !== "Tutte" ? s.provincia : s.regione };
    })
    .filter((s) => s.qui > 0)
    .sort((a, b) => (a.inizio < b.inizio ? -1 : a.inizio > b.inizio ? 1 : b.qui - a.qui))
    .slice(0, 8)
    .map((s) => ({ ...s, oggi: s.inizio <= oggi }));
}

// ---------- metro e treni di Londra (TfL, senza chiave) ----------
async function tfl() {
  const r = await fetch("https://api.tfl.gov.uk/Line/Mode/tube,overground,elizabeth-line,dlr/Status", { signal: timeout(8000) });
  if (!r.ok) return [];
  const lines = await r.json();
  return lines.flatMap((l: any) => (l.lineStatuses || []).filter((s: any) => s.statusSeverity !== 10).map((s: any) => ({
    linea: l.name, stato: s.statusSeverityDescription, motivo: (s.reason || "").replace(/^[^:]+:\s*/, "").slice(0, 220),
  }))).slice(0, 8);
}
// ---------- ricerca (TomTom Search) ----------
const GEO_TYPE: Record<string, string> = {
  Country: "country", CountrySubdivision: "state", CountrySecondarySubdivision: "county", CountryTertiarySubdivision: "county",
  Municipality: "city", MunicipalitySubdivision: "suburb", Neighbourhood: "neighbourhood", PostalCodeArea: "postcode",
};
async function cerca(q: string, lat: number, lng: number) {
  const k = (await getKeys()).tomtom_key;
  if (!k) return { attiva: false, risultati: [] };
  const bias = Number.isFinite(lat) && Number.isFinite(lng) ? `&lat=${lat.toFixed(4)}&lon=${lng.toFixed(4)}` : "";
  const url = `https://api.tomtom.com/search/2/search/${encodeURIComponent(q.slice(0, 120))}.json?key=${k}&language=it-IT&limit=10` +
    `&openingHours=nextSevenDays${bias}`;
  const r = await fetch(url, { signal: timeout(8000) });
  if (!r.ok) return { attiva: true, errore: `TomTom ${r.status}`, risultati: [] };
  const d = await r.json();
  return {
    attiva: true,
    risultati: (d.results || []).map((x: any) => {
      const a = x.address || {}, vp = x.viewport || {};
      const name = x.poi?.name || (x.type === "Geography" ? (a.municipality || a.countrySubdivision || a.country || a.freeformAddress) : a.freeformAddress);
      return {
        name, lat: x.position?.lat, lng: x.position?.lon,
        addr: [a.freeformAddress, a.country].filter(Boolean).join(", "),
        type: x.type === "Geography" ? (GEO_TYPE[x.entityType] || "city") : x.type === "POI" ? "poi" : "street",
        cat: x.poi?.categories?.[0] || null,
        phone: x.poi?.phone || null, url: x.poi?.url || null,
        hours: x.poi?.openingHours?.timeRanges || null,
        bbox: vp.topLeftPoint ? [vp.btmRightPoint.lat, vp.topLeftPoint.lat, vp.topLeftPoint.lon, vp.btmRightPoint.lon] : [],
        d: Number.isFinite(x.dist) ? Math.round(x.dist) : null,
      };
    }).filter((x: any) => x.lat != null && x.name),
  };
}

// ---------- quanto ci metto adesso (TomTom Routing) ----------
async function percorso(lat: number, lng: number, tlat: number, tlng: number) {
  const k = (await getKeys()).tomtom_key;
  if (!k) return { attiva: false };
  const pts = `${lat.toFixed(5)},${lng.toFixed(5)}:${tlat.toFixed(5)},${tlng.toFixed(5)}`;
  const route = async (mode: string) => {
    const r = await fetch(`https://api.tomtom.com/routing/1/calculateRoute/${pts}/json?key=${k}&travelMode=${mode}` +
      (mode === "car" ? "&traffic=true&routeType=fastest&computeTravelTimeFor=all" : ""), { signal: timeout(8000) });
    if (!r.ok) return null;
    const s = (await r.json()).routes?.[0]?.summary;
    return s ? { min: Math.max(1, Math.round(s.travelTimeInSeconds / 60)), ritardo_min: Math.round((s.trafficDelayInSeconds || 0) / 60),
      km: Math.round(s.lengthInMeters / 100) / 10, arrivo: s.arrivalTime } : null;
  };
  const crow = distM([lat, lng], [tlat, tlng]);
  const [auto, piedi] = await Promise.all([route("car"), crow <= 12000 ? route("pedestrian") : Promise.resolve(null)]);
  return { attiva: true, auto, piedi };
}

// ---------- dove arrivo in N minuti (TomTom Reachable Range) ----------
async function raggio(lat: number, lng: number, min: number) {
  const k = (await getKeys()).tomtom_key;
  if (!k) return { attiva: false, area: [] };
  const r = await fetch(`https://api.tomtom.com/routing/1/calculateReachableRange/${lat.toFixed(5)},${lng.toFixed(5)}/json?key=${k}` +
    `&timeBudgetInSec=${Math.round(Math.min(Math.max(min, 5), 60) * 60)}&traffic=true&travelMode=car`, { signal: timeout(10000) });
  if (!r.ok) return { attiva: true, errore: `TomTom ${r.status}`, area: [] };
  const b = (await r.json()).reachableRange?.boundary || [];
  return { attiva: true, area: b.map((p: any) => [p.latitude, p.longitude]) };
}

// ---------- colonnine di ricarica con disponibilità (TomTom EV) ----------
async function colonnine(lat: number, lng: number, rKm: number) {
  const k = (await getKeys()).tomtom_key;
  if (!k) return { attiva: false, colonnine: [] };
  const r = await fetch(`https://api.tomtom.com/search/2/nearbySearch/.json?key=${k}&lat=${lat.toFixed(4)}&lon=${lng.toFixed(4)}` +
    `&radius=${Math.round(Math.min(Math.max(rKm, 1), 10) * 1000)}&limit=25&categorySet=7309&language=it-IT`, { signal: timeout(8000) });
  if (!r.ok) return { attiva: true, errore: `TomTom ${r.status}`, colonnine: [] };
  const list = ((await r.json()).results || []).filter((x: any) => x.position);
  const out = await Promise.all(list.map(async (x: any, i: number) => {
    const id = x.dataSources?.chargingAvailability?.id;
    let tot = 0, lib = 0, occ = 0, kw = 0, noto = false;
    (x.chargingPark?.connectors || []).forEach((c: any) => { kw = Math.max(kw, c.ratedPowerKW || 0); });
    if (id && i < 15) {
      try {
        const a = await fetch(`https://api.tomtom.com/search/2/chargingAvailability.json?key=${k}&chargingAvailability=${id}`, { signal: timeout(6000) });
        if (a.ok) (await a.json()).connectors?.forEach((c: any) => {
          noto = true; tot += c.total || 0; lib += c.availability?.current?.available || 0; occ += c.availability?.current?.occupied || 0;
          (c.availability?.perPowerLevel || []).forEach((p: any) => { kw = Math.max(kw, p.powerKW || 0); });
        });
      } catch { /* disponibilità non nota */ }
    }
    return { id: x.id, nome: x.poi?.name || "Colonnina", lat: x.position.lat, lng: x.position.lon,
      ind: x.address?.freeformAddress || "", d: Math.round(x.dist || 0), kw, tot, lib, occ, noto };
  }));
  return { attiva: true, colonnine: out };
}

const inLondon = (lat: number, lng: number) => lat > 51.28 && lat < 51.70 && lng > -0.52 && lng < 0.34;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const u = new URL(req.url), a = u.searchParams.get("a");
  try {
    if (a === "tile") {
      const z = num(u.searchParams.get("z")), x = num(u.searchParams.get("x")), y = num(u.searchParams.get("y"));
      if (![z, x, y].every(Number.isInteger) || z < 0 || z > 22) return json({ error: "tessera non valida" }, 400);
      const k = (await getKeys()).tomtom_key;
      if (!k) return new Response(null, { status: 204, headers: CORS });
      const r = await fetch(`https://api.tomtom.com/traffic/map/4/tile/flow/relative/${z}/${x}/${y}.png?key=${k}&tileSize=256&thickness=10`, { signal: timeout(8000) });
      return new Response(r.ok ? await r.arrayBuffer() : null, {
        status: r.ok ? 200 : r.status,
        headers: { ...CORS, "Content-Type": "image/png", "Cache-Control": "public, max-age=120" },
      });
    }
    const lat = num(u.searchParams.get("lat")), lng = num(u.searchParams.get("lng"));
    if (a === "cerca" && !(Number.isFinite(lat) && Number.isFinite(lng))) {
      const q = (u.searchParams.get("q") || "").trim();
      if (q.length < 2) return json({ error: "testo troppo corto" }, 400);
      return json(await cerca(q, NaN, NaN), 200, 300);
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return json({ error: "posizione non valida" }, 400);
    if (a === "cerca") {
      const q = (u.searchParams.get("q") || "").trim();
      if (q.length < 2) return json({ error: "testo troppo corto" }, 400);
      return json(await cerca(q, lat, lng), 200, 300);
    }
    if (a === "percorso") {
      const tlat = num(u.searchParams.get("tlat")), tlng = num(u.searchParams.get("tlng"));
      if (!Number.isFinite(tlat) || !Number.isFinite(tlng)) return json({ error: "destinazione non valida" }, 400);
      return json(await percorso(lat, lng, tlat, tlng), 200, 60);
    }
    if (a === "raggio") {
      const m = num(u.searchParams.get("min"));
      return json(await raggio(lat, lng, Number.isFinite(m) ? m : 15), 200, 120);
    }
    if (a === "colonnine") {
      const r = num(u.searchParams.get("r"));
      return json(await colonnine(lat, lng, Number.isFinite(r) ? r : 3), 200, 120);
    }
    if (a === "webcams") {
      const r = num(u.searchParams.get("r"));
      return json(await webcams(lat, lng, Number.isFinite(r) ? r : 10), 200, 300);
    }
    if (a === "perche") {
      const cc = (u.searchParams.get("cc") || "").toLowerCase();
      const [inc, cam, met, sc, tf] = await Promise.allSettled([
        incidents(lat, lng), webcams(lat, lng, 10, 6), meteo(lat, lng),
        cc === "it" ? scioperi(u.searchParams.get("region") || "", u.searchParams.get("prov") || "") : Promise.resolve(null),
        inLondon(lat, lng) ? tfl() : Promise.resolve(null),
      ]);
      const v = (p: PromiseSettledResult<any>) => (p.status === "fulfilled" ? p.value : null);
      return json({
        traffico: v(inc), webcam: v(cam), meteo: v(met), scioperi: v(sc), tfl: v(tf),
        ora: new Date().toISOString(),
      }, 200, 120);
    }
    return json({ error: "azione sconosciuta" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message }, 500);
  }
});
