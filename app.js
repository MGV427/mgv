/* ============================================================================
 * OffTheCouch — scan the area near you for things that get you off the couch.
 *
 * How it works:
 *  1. Ask the browser for your location (the "scan origin").
 *  2. Query the free OpenStreetMap Overpass API for REAL nearby places within
 *     the chosen radius — parks, gyms, community centres, volunteering spots,
 *     arts venues, markets, sports pitches, libraries, etc.
 *  3. A built-in recommendation engine scores every place against your age +
 *     interests + mood, ranks them, and writes a "what to expect" insight.
 *  4. (Optional) If you supply an Anthropic API key, the top picks get richer
 *     insights written by Claude (claude-opus-4-8), called directly from the
 *     browser. Everything works without a key.
 * ========================================================================== */

"use strict";

/* ------------------------------------------------------------------ config */

// Each interest maps to a category with: emoji, an OSM tag filter set, an
// "energy"/"social" profile used for age-fit, and the reason it gets you off
// the couch.
const CATEGORIES = {
  volunteering: {
    label: "Volunteering & giving back",
    emoji: "🤝",
    color: "#4dd4c4",
    filters: [
      'amenity=social_facility', 'office=charity', 'amenity=community_centre',
      'social_facility', 'amenity=food_bank',
    ],
    action: "pitch in and meet good people",
  },
  fitness: {
    label: "Fitness & gyms",
    emoji: "🏋️",
    color: "#ff7a59",
    filters: [
      'leisure=fitness_centre', 'leisure=sports_centre', 'amenity=gym',
      'leisure=fitness_station', 'sport=fitness',
    ],
    action: "break a sweat",
  },
  sports: {
    label: "Team & pickup sports",
    emoji: "⚽",
    color: "#ffb14e",
    filters: [
      'leisure=pitch', 'leisure=stadium', 'leisure=track',
      'leisure=sports_hall', 'sport=soccer', 'sport=basketball', 'sport=tennis',
    ],
    action: "get in a game with other people",
  },
  outdoors: {
    label: "Parks & the outdoors",
    emoji: "🌳",
    color: "#7bd67b",
    filters: [
      'leisure=park', 'leisure=nature_reserve', 'leisure=garden',
      'tourism=viewpoint', 'leisure=dog_park', 'natural=beach',
    ],
    action: "get outside and move",
  },
  water: {
    label: "Swimming & water",
    emoji: "🏊",
    color: "#5bc7ff",
    filters: [
      'leisure=swimming_pool', 'leisure=water_park', 'sport=swimming',
      'leisure=marina',
    ],
    action: "get in the water",
  },
  arts: {
    label: "Arts & culture",
    emoji: "🎨",
    color: "#8b7cf6",
    filters: [
      'tourism=museum', 'tourism=gallery', 'tourism=artwork',
      'amenity=arts_centre', 'amenity=theatre',
    ],
    action: "feed your curiosity",
  },
  music: {
    label: "Live music & nightlife",
    emoji: "🎶",
    color: "#ff6db3",
    filters: [
      'amenity=nightclub', 'amenity=music_venue', 'amenity=bar',
      'amenity=pub', 'amenity=cinema',
    ],
    action: "get out for the night",
  },
  food: {
    label: "Cafés & food scene",
    emoji: "☕",
    color: "#d99a6c",
    filters: [
      'amenity=cafe', 'amenity=restaurant', 'amenity=marketplace',
      'amenity=food_court', 'shop=coffee',
    ],
    action: "grab a table and hang out",
  },
  learning: {
    label: "Learning & libraries",
    emoji: "📚",
    color: "#6ea8ff",
    filters: [
      'amenity=library', 'amenity=community_centre', 'amenity=college',
      'amenity=university', 'amenity=language_school',
    ],
    action: "pick up something new",
  },
  games: {
    label: "Games & recreation",
    emoji: "🎳",
    color: "#f2c14e",
    filters: [
      'leisure=bowling_alley', 'leisure=amusement_arcade', 'leisure=escape_game',
      'leisure=trampoline_park', 'shop=games', 'leisure=adult_gaming_centre',
    ],
    action: "have some low-stakes fun with people",
  },
  markets: {
    label: "Markets & local events",
    emoji: "🛍️",
    color: "#ff9f68",
    filters: [
      'amenity=marketplace', 'shop=farm', 'amenity=events_venue',
      'amenity=community_centre',
    ],
    action: "wander, browse and bump into your neighbours",
  },
};

const OVERPASS_ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

/* --------------------------------------------------------------- elements */

const el = (id) => document.getElementById(id);
const form = el("profile-form");
const interestsBox = el("interests");
const radiusInput = el("radius");
const radiusLabel = el("radius-label");
const setupSection = el("setup");
const statusSection = el("status");
const statusText = el("status-text");
const resultsSection = el("results");
const resultsMeta = el("results-meta");
const cardsBox = el("cards");
const emptySection = el("empty");

const state = { interests: new Set(["outdoors", "food", "fitness"]) };

/* ---------------------------------------------------------------- init UI */

function buildInterestChips() {
  interestsBox.innerHTML = "";
  for (const [key, cat] of Object.entries(CATEGORIES)) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip";
    chip.dataset.key = key;
    chip.setAttribute("aria-pressed", state.interests.has(key) ? "true" : "false");
    chip.innerHTML = `<span class="em">${cat.emoji}</span> ${cat.label}`;
    chip.addEventListener("click", () => toggleInterest(key, chip));
    interestsBox.appendChild(chip);
  }
}

function toggleInterest(key, chip) {
  if (state.interests.has(key)) state.interests.delete(key);
  else state.interests.add(key);
  chip.setAttribute("aria-pressed", state.interests.has(key) ? "true" : "false");
}

function fmtRadius(m) {
  return m >= 1000 ? `${(m / 1000).toFixed(m % 1000 === 0 ? 0 : 1)} km` : `${m} m`;
}

radiusInput.addEventListener("input", () => {
  radiusLabel.textContent = fmtRadius(Number(radiusInput.value));
});

/* ------------------------------------------------------------- view state */

function show(section) {
  for (const s of [setupSection, statusSection, resultsSection, emptySection]) {
    s.hidden = s !== section;
  }
  if (section !== setupSection) window.scrollTo({ top: 0, behavior: "smooth" });
}

function setStatus(msg) { statusText.textContent = msg; }

/* --------------------------------------------------------------- geometry */

function haversine(aLat, aLon, bLat, bLon) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

function prettyDistance(m) {
  if (m < 950) return `${Math.round(m / 10) * 10} m away`;
  return `${(m / 1000).toFixed(1)} km away`;
}

function walkMinutes(m) { return Math.max(1, Math.round(m / 80)); } // ~4.8 km/h

/* --------------------------------------------------------- overpass query */

function buildQuery(lat, lon, radius, interests) {
  // Union of every filter across the selected interest categories.
  const seen = new Set();
  const clauses = [];
  for (const key of interests) {
    for (const f of CATEGORIES[key].filters) {
      if (seen.has(f)) continue;
      seen.add(f);
      const [k, v] = f.split("=");
      const tag = v ? `["${k}"="${v}"]` : `["${k}"]`;
      clauses.push(`  node${tag}(around:${radius},${lat},${lon});`);
      clauses.push(`  way${tag}(around:${radius},${lat},${lon});`);
    }
  }
  return `[out:json][timeout:25];\n(\n${clauses.join("\n")}\n);\nout center tags 250;`;
}

async function runOverpass(query) {
  let lastErr;
  for (const endpoint of OVERPASS_ENDPOINTS) {
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "data=" + encodeURIComponent(query),
      });
      if (!res.ok) throw new Error(`Overpass ${res.status}`);
      return await res.json();
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr || new Error("Overpass unreachable");
}

/* ----------------------------------------------------- classify + collect */

// Map a raw OSM element's tags back to one of our categories.
function classify(tags) {
  for (const [key, cat] of Object.entries(CATEGORIES)) {
    for (const f of cat.filters) {
      const [k, v] = f.split("=");
      if (v ? tags[k] === v : tags[k] != null) return key;
    }
  }
  return null;
}

function collectPlaces(json, origin, interests) {
  const out = [];
  const usedNames = new Set();
  for (const elm of json.elements || []) {
    const tags = elm.tags || {};
    const name = tags.name || tags["name:en"];
    if (!name) continue; // unnamed nodes are rarely useful destinations

    const lat = elm.lat ?? elm.center?.lat;
    const lon = elm.lon ?? elm.center?.lon;
    if (lat == null || lon == null) continue;

    const catKey = classify(tags);
    if (!catKey) continue;

    // De-dupe by name+category (Overpass often returns node + way for one spot)
    const dedupe = `${name}|${catKey}`;
    if (usedNames.has(dedupe)) continue;
    usedNames.add(dedupe);

    const dist = haversine(origin.lat, origin.lon, lat, lon);
    out.push({
      id: `${elm.type}/${elm.id}`,
      name,
      catKey,
      tags,
      lat,
      lon,
      dist,
      wanted: interests.has(catKey),
    });
  }
  return out;
}

/* ------------------------------------------------------- recommender (AI) */
/* A transparent scoring model — this is the "AI of our choosing" that narrows
 * the raw scan down to what fits YOU. It weighs interest match, distance, how
 * social/active the place is, and age-fit, then ranks. */

const AGE_PROFILE = (age) => {
  if (age < 18) return "teen";
  if (age < 26) return "youngadult";
  if (age < 40) return "adult";
  if (age < 60) return "midlife";
  return "senior";
};

// crude fit: how much a category suits a life stage (0..1 nudge)
const AGE_FIT = {
  teen:       { games: 1, sports: 1, music: 0.4, learning: 0.8, arts: 0.8, water: 0.9, outdoors: 0.8, volunteering: 0.7, fitness: 0.6, food: 0.7, markets: 0.6 },
  youngadult: { music: 1, fitness: 1, games: 0.9, sports: 0.9, food: 1, arts: 0.9, outdoors: 0.9, volunteering: 0.9, water: 0.8, learning: 0.9, markets: 0.9 },
  adult:      { fitness: 1, outdoors: 1, food: 0.9, volunteering: 1, arts: 0.9, markets: 0.9, learning: 0.9, sports: 0.8, music: 0.7, games: 0.8, water: 0.8 },
  midlife:    { outdoors: 1, volunteering: 1, arts: 1, learning: 1, markets: 1, food: 0.9, fitness: 0.9, water: 0.8, games: 0.6, sports: 0.6, music: 0.5 },
  senior:     { volunteering: 1, outdoors: 1, arts: 1, learning: 1, markets: 0.9, food: 0.9, water: 0.8, fitness: 0.7, games: 0.6, music: 0.4, sports: 0.4 },
};

function scorePlace(place, ctx) {
  const cat = CATEGORIES[place.catKey];
  let score = 0;

  // 1. Interest match — the biggest lever.
  score += place.wanted ? 55 : 12;

  // 2. Distance — closer is better, gently decaying.
  const frac = place.dist / ctx.radius;
  score += (1 - Math.min(frac, 1)) * 25;

  // 3. Age fit.
  const fit = AGE_FIT[ctx.ageBand]?.[place.catKey] ?? 0.7;
  score += fit * 12;

  // 4. Signals that a place is genuinely social / worth a trip.
  const t = place.tags;
  if (t.website || t["contact:website"]) score += 3;
  if (t.opening_hours) score += 2;
  if (t.description) score += 2;
  if (t.wheelchair === "yes") score += 1;

  // 5. Mood keyword nudge.
  if (ctx.vibeWords.length) {
    const hay = `${place.name} ${cat.label} ${t.description || ""}`.toLowerCase();
    for (const w of ctx.vibeWords) if (w.length > 2 && hay.includes(w)) score += 4;
  }

  // Tiny jitter so identical scores don't always order the same way.
  score += Math.random() * 1.5;
  return score;
}

/* ----------------------------------------------------- insight generation */

// Built-in "what to expect" writer. Varied templates keyed by category so it
// reads like a helpful friend, not a form letter.
function localInsight(place, ctx) {
  const cat = CATEGORIES[place.catKey];
  const mins = walkMinutes(place.dist);
  const near = place.dist < 950
    ? `Just a ~${mins} min walk away`
    : `About ${(place.dist / 1000).toFixed(1)} km out`;

  const t = place.tags;
  const hours = t.opening_hours && t.opening_hours.length < 40
    ? ` Listed hours: ${t.opening_hours}.` : "";
  const desc = t.description ? ` ${t.description}` : "";

  const lines = {
    volunteering: `${near}, this is a spot to ${cat.action} — walk in, ask how you can help, and you'll be surrounded by people doing something good.`,
    fitness: `${near}. Good place to ${cat.action}; go once and it stops feeling like a big deal to go again.`,
    sports: `${near}. Turn up, watch for a game forming, and ask to join — pickup sport is the fastest way to meet people who'll actually text you back.`,
    outdoors: `${near}. Fresh air, a bit of a walk, zero pressure — the easiest possible way to ${cat.action} today.`,
    water: `${near}. Bring a towel and ${cat.action} — a swim resets your whole day.`,
    arts: `${near}. Wander in to ${cat.action}; you'll leave with something to talk about and a head that feels lighter.`,
    music: `${near}. Check what's on tonight — even solo, this is a low-effort way to ${cat.action} and be around energy.`,
    food: `${near}. Grab a seat, ${cat.action}, and let the place do the socialising for you — regulars talk to strangers here.`,
    learning: `${near}. Free-ish, quiet, welcoming — the kind of place where you ${cat.action} and meet people mid-conversation.`,
    games: `${near}. Round up one or two people (or just show up) and ${cat.action}. Hard to stay glued to the couch here.`,
    markets: `${near}. Go ${cat.action}; markets are the rare place where making small talk feels completely normal.`,
  };

  return (lines[place.catKey] || `${near}. A nearby spot to ${cat.action}.`) + desc + hours;
}

/* -------------------------------------------- optional Claude enhancement */

async function claudeInsights(places, ctx, apiKey) {
  const list = places.map((p, i) =>
    `${i + 1}. ${p.name} — category: ${CATEGORIES[p.catKey].label}, ${prettyDistance(p.dist)}`
  ).join("\n");

  const prompt =
`A user is looking to "get off their couch" and do something that gets them up, social or productive.
User: ${ctx.age} years old. Interests: ${[...ctx.interests].map(k => CATEGORIES[k].label).join(", ")}.` +
(ctx.vibe ? ` Mood/notes: "${ctx.vibe}".` : "") +
`\n\nHere are real nearby places found by scanning their area:\n${list}\n\n` +
`For EACH numbered place, write one warm, specific, 1-2 sentence "what to expect" that nudges them to actually go. Be concrete about the social/active payoff. No preamble.\n` +
`Return ONLY a JSON array of strings, one per place, in order. Example: ["...", "..."]`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "anthropic-dangerous-direct-browser-access": "true",
    },
    body: JSON.stringify({
      model: "claude-opus-4-8",
      max_tokens: 1200,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!res.ok) throw new Error(`Claude ${res.status}`);
  const data = await res.json();
  const text = (data.content || []).filter(b => b.type === "text").map(b => b.text).join("");
  const match = text.match(/\[[\s\S]*\]/);
  if (!match) throw new Error("Unexpected Claude response");
  const arr = JSON.parse(match[0]);
  if (!Array.isArray(arr)) throw new Error("Claude did not return a list");
  return arr;
}

/* ------------------------------------------------------------- rendering */

function renderCards(places) {
  cardsBox.innerHTML = "";
  for (const p of places) {
    const cat = CATEGORIES[p.catKey];
    const card = document.createElement("article");
    card.className = "card";
    card.style.setProperty("--cat-color", cat.color);

    const tags = [];
    if (p.tags.opening_hours && p.tags.opening_hours.length < 24) tags.push(p.tags.opening_hours);
    if (p.tags.cuisine) tags.push(p.tags.cuisine.replace(/;/g, ", "));
    if (p.tags.sport) tags.push(p.tags.sport.replace(/;/g, ", "));
    if (p.tags.wheelchair === "yes") tags.push("♿ accessible");
    if (p.tags.fee === "no") tags.push("free");

    const mapUrl = `https://www.openstreetmap.org/?mlat=${p.lat}&mlon=${p.lon}#map=18/${p.lat}/${p.lon}`;
    const site = p.tags.website || p.tags["contact:website"];

    card.innerHTML = `
      <div class="card-top">
        <span class="card-cat">${cat.emoji} ${cat.label}</span>
        <span class="card-dist">${prettyDistance(p.dist)}</span>
      </div>
      <h3 class="card-name"></h3>
      <p class="card-insight ${p.aiInsight ? "ai" : ""}"></p>
      <div class="card-tags"></div>
      <div class="card-foot">
        <a class="card-link" href="${mapUrl}" target="_blank" rel="noopener">📍 Map</a>
        ${site ? `<a class="card-link" href="${escapeAttr(site)}" target="_blank" rel="noopener">🔗 Website</a>` : ""}
      </div>`;

    card.querySelector(".card-name").textContent = p.name;
    card.querySelector(".card-insight").textContent = p.aiInsight || p.insight;
    const tagBox = card.querySelector(".card-tags");
    for (const tg of tags.slice(0, 4)) {
      const s = document.createElement("span");
      s.className = "tag";
      s.textContent = tg;
      tagBox.appendChild(s);
    }
    cardsBox.appendChild(card);
  }
}

function escapeAttr(s) {
  return String(s).replace(/"/g, "%22").replace(/[<>]/g, "");
}

function showError(msg) {
  const banner = document.createElement("div");
  banner.className = "error-banner";
  banner.textContent = msg;
  resultsSection.prepend(banner);
}

/* ------------------------------------------------------------- main flow */

function getLocation() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error("Your browser doesn't support location."));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ lat: pos.coords.latitude, lon: pos.coords.longitude }),
      (err) => reject(new Error(
        err.code === 1
          ? "Location permission was denied. Enable it and try again to scan around you."
          : "Couldn't get your location. Check your connection and try again."
      )),
      { enableHighAccuracy: false, timeout: 12000, maximumAge: 300000 }
    );
  });
}

async function runScan(ctx) {
  show(statusSection);

  setStatus("Locating you…");
  let origin;
  try {
    origin = await getLocation();
  } catch (err) {
    show(setupSection);
    alert(err.message);
    return;
  }

  setStatus(`Scanning ${fmtRadius(ctx.radius)} around you for real places…`);
  let json;
  try {
    json = await runOverpass(buildQuery(origin.lat, origin.lon, ctx.radius, ctx.interests));
  } catch (err) {
    show(setupSection);
    alert("The place-scanning service is busy right now. Give it a few seconds and try again.");
    return;
  }

  setStatus("Matching places to you…");
  let places = collectPlaces(json, origin, ctx.interests);

  if (!places.length) { show(emptySection); return; }

  // Score, rank, keep the top matches.
  const scoreCtx = {
    radius: ctx.radius,
    ageBand: AGE_PROFILE(ctx.age),
    vibeWords: (ctx.vibe || "").toLowerCase().split(/[^a-z]+/).filter(Boolean),
  };
  for (const p of places) p.score = scorePlace(p, scoreCtx);
  places.sort((a, b) => b.score - a.score);

  // Prefer variety: cap any single category so results don't all look alike.
  const perCatCap = 4;
  const catCount = {};
  const picked = [];
  for (const p of places) {
    catCount[p.catKey] = (catCount[p.catKey] || 0) + 1;
    if (catCount[p.catKey] <= perCatCap) picked.push(p);
    if (picked.length >= 18) break;
  }
  places = picked;

  // Built-in insights for everyone.
  for (const p of places) p.insight = localInsight(p, ctx);

  // Optional Claude upgrade for the top picks.
  if (ctx.apiKey) {
    setStatus("Asking Claude to size up your top picks…");
    try {
      const top = places.slice(0, 8);
      const ai = await claudeInsights(top, ctx, ctx.apiKey);
      top.forEach((p, i) => { if (ai[i]) p.aiInsight = ai[i]; });
    } catch (err) {
      // Non-fatal: fall back to built-in insights.
      console.warn("Claude enhancement failed:", err);
    }
  }

  // Render.
  resultsSection.querySelectorAll(".error-banner").forEach(n => n.remove());
  const wantLabels = [...ctx.interests].map(k => CATEGORIES[k].emoji).join(" ");
  resultsMeta.textContent =
    `${places.length} matches within ${fmtRadius(ctx.radius)} · age ${ctx.age} · ${wantLabels}` +
    (ctx.apiKey ? " · ✦ Claude-enhanced" : "");
  renderCards(places);
  show(resultsSection);

  if (ctx.apiKey && !places.some(p => p.aiInsight)) {
    showError("Couldn't reach Claude (check the key or your plan). Showing built-in insights instead.");
  }
}

/* ------------------------------------------------------------- listeners */

form.addEventListener("submit", (e) => {
  e.preventDefault();
  const age = Number(el("age").value);
  if (!age || age < 10) { el("age").focus(); return; }
  if (state.interests.size === 0) {
    alert("Pick at least one thing you're into so we can match you.");
    return;
  }
  runScan({
    age,
    interests: new Set(state.interests),
    vibe: el("vibe").value.trim(),
    radius: Number(radiusInput.value),
    apiKey: el("apikey").value.trim(),
  });
});

el("rescan").addEventListener("click", () => show(setupSection));
el("empty-back").addEventListener("click", () => show(setupSection));

/* --------------------------------------------------------------- startup */

buildInterestChips();
radiusLabel.textContent = fmtRadius(Number(radiusInput.value));
