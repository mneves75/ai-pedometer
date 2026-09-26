// Score + SFX synthesized as one piece: C major, 120 BPM (beat 0.5 s), cues locked to index.html.
// Instruments reused from the whatsimovel brag synth; arrangement is new. Output: work/mix.wav.
import fs from "node:fs";

const SR = 48000, DUR = 21.0, N = Math.ceil(SR * DUR);
const TAU = Math.PI * 2;
const m2f = (m) => 440 * Math.pow(2, (m - 69) / 12);
let seed = 7654321;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const noise = () => rnd() * 2 - 1;

const bus = () => [new Float32Array(N), new Float32Array(N)];
const B = { drums: bus(), music: bus(), sfx: bus(), verb: bus() };

function place(dst, t0, sig, gain = 1, pan = 0, send = 0) {
  const i0 = Math.round(t0 * SR), a = (pan + 1) * Math.PI / 4;
  const gl = Math.cos(a) * gain * 1.414, gr = Math.sin(a) * gain * 1.414;
  for (let i = 0; i < sig.length; i++) {
    const j = i0 + i; if (j < 0 || j >= N) continue;
    dst[0][j] += sig[i] * gl; dst[1][j] += sig[i] * gr;
    if (send) { B.verb[0][j] += sig[i] * gl * send; B.verb[1][j] += sig[i] * gr * send; }
  }
}
function biquad(sig, type, fc, q = 0.707) {
  const out = new Float32Array(sig.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < sig.length; i++) {
    const f = Math.min(SR * 0.45, Math.max(20, typeof fc === "function" ? fc(i / SR) : fc));
    const w = TAU * f / SR, cs = Math.cos(w), al = Math.sin(w) / (2 * q);
    let b0, b1, b2; const a0 = 1 + al, a1 = -2 * cs, a2 = 1 - al;
    if (type === "lp") { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = b0; }
    else if (type === "hp") { b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = b0; }
    else { b0 = al; b1 = 0; b2 = -al; }
    const x = sig[i], y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x; y2 = y1; y1 = y; out[i] = y;
  }
  return out;
}
const gen = (dur, fn) => { const n = Math.round(dur * SR), o = new Float32Array(n); for (let i = 0; i < n; i++) o[i] = fn(i / SR, i); return o; };
const saw = (p) => 2 * (p - Math.floor(p + 0.5));

// ---------- instruments ----------
function kick(t0, g = 1, muffled = false) {
  let ph = 0;
  let s = gen(0.5, (t) => { const f = 44 + 115 * Math.exp(-t * 30); ph += f / SR; const a = Math.min(1, t / 0.002) * Math.exp(-t * 6.5); return Math.tanh(1.7 * Math.sin(TAU * ph) * a); });
  const click = biquad(gen(0.006, (t) => noise() * (1 - t / 0.006)), "hp", 2500);
  for (let i = 0; i < click.length; i++) s[i] += click[i] * 0.25;
  if (muffled) s = biquad(s, "lp", 170);
  place(B.drums, t0, s, 0.85 * g);
}
function clap(t0, g = 1) {
  const s = gen(0.35, (t) => { const burst = [0, 0.011, 0.022].reduce((acc, o) => acc + (t >= o ? Math.exp(-(t - o) / (o === 0.022 ? 0.09 : 0.008)) : 0), 0); return noise() * burst; });
  place(B.drums, t0, biquad(biquad(s, "bp", 1250, 0.9), "hp", 600), 0.36 * g, 0.05, 0.4);
}
function hat(t0, g = 1, open = false, pan = 0.2) {
  const s = gen(open ? 0.28 : 0.05, (t) => noise() * Math.exp(-t / (open ? 0.08 : 0.016)));
  place(B.drums, t0, biquad(biquad(s, "hp", 7800), "hp", 7800), 0.2 * g, pan, 0.08);
}
function snare(t0, g = 1) {
  let ph = 0;
  const s = gen(0.2, (t) => { ph += (190 + 40 * Math.exp(-t * 40)) / SR; return (Math.sin(TAU * ph) * 0.5 * Math.exp(-t * 30) + noise() * 0.8 * Math.exp(-t * 18)); });
  place(B.drums, t0, biquad(s, "hp", 200), 0.3 * g, -0.05, 0.22);
}
function crash(t0, g = 1, dur = 1.6) {
  const s = gen(dur, (t) => noise() * Math.exp(-t / (dur * 0.33)) * Math.min(1, t / 0.003));
  const f = biquad(biquad(s, "hp", 4500), "lp", 11000);
  place(B.drums, t0, f, 0.22 * g, -0.3, 0.3); place(B.drums, t0 + 0.004, f, 0.22 * g, 0.3, 0);
}
function boom(t0, g = 1) {
  let ph = 0;
  const s = gen(1.6, (t) => { ph += (36 + 28 * Math.exp(-t * 5)) / SR; return Math.sin(TAU * ph) * Math.exp(-t * 2.4) * Math.min(1, t / 0.004); });
  place(B.drums, t0, s, 0.65 * g);
}
function tom(t0, g = 1, f0 = 110) {
  let ph = 0;
  const s = gen(0.4, (t) => { ph += (f0 * (1 + 0.6 * Math.exp(-t * 25))) / SR; return Math.sin(TAU * ph) * Math.exp(-t * 9); });
  place(B.drums, t0, s, 0.4 * g, 0, 0.15);
}
function supersaw(t0, notes, dur, { g = 1, a = 0.004, d = 0.22, cut0 = 4200, cut1 = 900, cdec = 0.18, voices = 7, spread = 0.16, send = 0.3, sustain = 0 } = {}) {
  for (const m of notes) for (let v = 0; v < voices; v++) {
    const det = (v / (voices - 1) - 0.5) * 2 * spread; const f = m2f(m + det); let ph = rnd();
    const s = gen(dur, (t) => { ph += f / SR; const e = t < a ? t / a : sustain + (1 - sustain) * Math.exp(-(t - a) / d); const rel = t > dur - 0.05 ? (dur - t) / 0.05 : 1; return saw(ph) * e * rel; });
    const fl = biquad(s, "lp", (t) => cut1 + (cut0 - cut1) * Math.exp(-t / cdec), 0.9);
    place(B.music, t0, fl, (0.15 * g) / Math.sqrt(voices * notes.length), (v / (voices - 1) - 0.5) * 1.2, send);
  }
}
function bass(t0, m, dur = 0.22, g = 1) {
  const f = m2f(m); let p1 = 0, p2 = 0;
  const s = gen(dur, (t) => { p1 += f / SR; p2 += f * 1.005 / SR; const e = Math.min(1, t / 0.003) * Math.exp(-t / 0.16) * (t > dur - 0.02 ? (dur - t) / 0.02 : 1); return (saw(p1) * 0.6 + (p2 % 1 < 0.5 ? 0.5 : -0.5) * 0.4) * e; });
  const fl = biquad(s, "lp", (t) => 230 + 700 * Math.exp(-t / 0.05), 1.1);
  const sub = gen(dur, (t) => Math.sin(TAU * f * t) * Math.min(1, t / 0.004) * Math.exp(-t / 0.2) * (t > dur - 0.02 ? (dur - t) / 0.02 : 1));
  for (let i = 0; i < fl.length; i++) fl[i] = Math.tanh(1.3 * (fl[i] + sub[i] * 0.8));
  place(B.music, t0, fl, 0.36 * g);
}
function pluck(t0, m, g = 1, pan = 0, send = 0.35, dec = 0.16) {
  const f = m2f(m);
  const s = gen(dec * 5, (t) => { const e = Math.min(1, t / 0.002) * Math.exp(-t / dec); return (Math.sin(TAU * f * t) + 0.3 * Math.sin(TAU * 2 * f * t) * Math.exp(-t / 0.04) + 0.08 * saw(f * t)) * e; });
  place(B.sfx, t0, s, 0.18 * g, pan, send);
}
function pad(t0, notes, dur, g = 1, cutFrom = 600, cutTo = 2400) {
  for (const m of notes) for (let v = 0; v < 5; v++) {
    const f = m2f(m + (v - 2) * 0.08); let ph = rnd();
    const s = gen(dur, (t) => { ph += f / SR; const e = Math.min(1, t / 0.45) * (t > dur - 0.4 ? Math.max(0, (dur - t) / 0.4) : 1); return saw(ph) * e; });
    const fl = biquad(s, "lp", (t) => cutFrom + (cutTo - cutFrom) * Math.min(1, t / dur), 0.7);
    place(B.music, t0, fl, (0.08 * g) / Math.sqrt(5 * notes.length), (v - 2) * 0.35, 0.45);
  }
}
function riser(t0, t1, g = 1) {
  const dur = t1 - t0; let ph = 0;
  const s = gen(dur, (t) => { const p = t / dur; ph += (200 + 800 * p * p) / SR; return (noise() * 0.7 + Math.sin(TAU * ph) * 0.2) * Math.pow(p, 2.2); });
  place(B.sfx, t0, biquad(s, "bp", (t) => 400 + 6000 * Math.pow(t / dur, 2), 1.1), 0.36 * g, 0, 0.25);
}
function swell(t0, t1, g = 1) {
  const dur = t1 - t0;
  const s = gen(dur, (t) => noise() * Math.pow(t / dur, 3));
  place(B.sfx, t0, biquad(s, "hp", 5500), 0.22 * g, 0, 0.1);
}
function whoosh(tc, g = 1, dir = 1) {
  const dur = 0.42, t0 = tc - 0.3;
  const s = gen(dur, (t) => { const p = t / dur; return noise() * Math.sin(Math.PI * Math.pow(p, 0.7)) ** 2; });
  const f = biquad(s, "bp", (t) => { const p = t / dur; return 300 + 2800 * Math.sin(Math.PI * Math.pow(p, 0.8)); }, 1.4);
  const i0 = Math.round(t0 * SR);
  for (let i = 0; i < f.length; i++) { const j = i0 + i; if (j < 0 || j >= N) continue; const pan = dir * (i / f.length * 2 - 1) * 0.7, a = (pan + 1) * Math.PI / 4; B.sfx[0][j] += f[i] * Math.cos(a) * 0.4 * g; B.sfx[1][j] += f[i] * Math.sin(a) * 0.4 * g; B.verb[0][j] += f[i] * 0.07 * g; B.verb[1][j] += f[i] * 0.07 * g; }
}
function tick(t0, g = 1, fq = 3200, pan = 0) {
  const s = gen(0.02, (t) => (noise() * 0.5 + Math.sin(TAU * fq * t) * 0.6) * Math.exp(-t / 0.004));
  place(B.sfx, t0, biquad(s, "hp", 1800), 0.12 * g, pan, 0.05);
}

// ---------- arrangement (C major) ----------
const kicks = [];
const K = (t, g, m) => { kick(t, g, m); if (!m) kicks.push(t); };
const PENT = [72, 74, 76, 79, 81, 84, 86, 88, 91, 93];

// 1. Hook 0–3: muffled pulse, open pad, count ticks climb the pentatonic, headline pluck, riser, dry gap.
for (const t of [0, 0.5, 1.0, 1.5, 2.0, 2.5]) K(t, 0.5, true);
pad(0, [48, 55, 60, 64, 67, 74], 2.94, 1.1, 450, 2600);
bass(0, 36, 2.9, 0.3);
for (let k = 0; k < 18; k++) { const p = k / 17, t = 0.15 + 1.6 * (1 - Math.pow(1 - p, 1.8)); pluck(t, PENT[Math.min(9, Math.floor(p * 9.99))], 0.22 + 0.2 * p, (k % 2 ? 0.25 : -0.25), 0.25, 0.07); }
pluck(1.1, 76, 0.7, -0.15, 0.45, 0.25); pluck(1.12, 84, 0.55, 0.15, 0.45, 0.25);
riser(1.8, 2.94, 0.9); swell(2.3, 2.94, 0.9);

// 2–5. Body 3–18: one chord per bar.
const CH = [
  { t: 3, notes: [60, 64, 67], root: 36 },   // C
  { t: 5, notes: [59, 62, 67], root: 35 },   // G/B
  { t: 7, notes: [57, 60, 64], root: 33 },   // Am
  { t: 9, notes: [57, 60, 65], root: 29 },   // F
  { t: 11, notes: [60, 64, 67], root: 36 },  // C
  { t: 13, notes: [59, 62, 67], root: 31 },  // G
  { t: 15, notes: [57, 60, 64], root: 33 },  // Am
  { t: 17, notes: [57, 60, 65], root: 29 },  // F
];
const chordAt = (t) => CH.filter((c) => c.t <= t + 1e-6).pop();
const thinking = (t) => t >= 7.75 && t < 8.9;

// Drop at 3.0 (match cut).
K(3, 1.05); boom(3, 0.8); crash(3, 0.8, 1.8);
supersaw(3, [60, 64, 67, 72], 1.2, { g: 1.2, d: 0.5, cut0: 5000, cut1: 1200, cdec: 0.35, sustain: 0.1 });
whoosh(3.0, 0.8, 1);
for (const c of CH) pad(c.t, c.notes.map((n) => n + 12), 2.05, 0.75, 800, 2200);

for (let t = 3.5; t < 17.99; t += 0.5) K(t, thinking(t) ? 0.55 : 0.92, false);
for (let bar = 3; bar < 17.9; bar += 1) if (!thinking(bar + 0.5)) clap(bar + 0.5, 0.8);
for (let t = 3.25; t < 17.9; t += 0.5) hat(t, thinking(t) ? 0.4 : 0.9, false, 0.25);
for (let t = 6.5; t < 17.9; t += 0.25) if (Math.abs((t * 4) % 2) < 1e-6 && !thinking(t)) hat(t, 0.35, false, -0.25);
for (let t = 3; t < 17.95; t += 0.5) { const c = chordAt(t); bass(t + 0.25, c.root + (t >= 9 && Math.round(t * 2) % 2 ? 12 : 0), 0.22, thinking(t) ? 0.6 : 1); }
// Gentle 16th arpeggio from the coach scene on.
for (let t = 6.5, k = 0; t < 17.95; t += 0.125, k++) { if (thinking(t)) continue; const c = chordAt(t); const tones = [...c.notes.map((n) => n + 12), ...c.notes.map((n) => n + 24)]; pluck(t, tones[k % tones.length], 0.2, (k % 2 ? 0.35 : -0.35), 0.25, 0.07); }

// 3. Coach: move, send, thinking shimmer, answer lines, text land.
whoosh(6.5, 0.7, -1); crash(6.5, 0.35, 1.0);
tick(7.52, 0.9, 2400, 0.15); pluck(7.55, 84, 0.6, 0.15, 0.35, 0.1); pluck(7.58, 91, 0.35, 0.15, 0.35, 0.08);
{ for (let k = 0; k < 12; k++) pluck(7.8 + k * 0.095, PENT[4 + Math.floor(rnd() * 6)], 0.13, rnd() - 0.5, 0.7, 0.12); }
swell(8.4, 8.9, 0.5);
[72, 76, 79, 84, 88].forEach((m, i) => pluck(8.9 + i * 0.2, m, 0.45, (i / 4 - 0.5) * 0.5, 0.4, 0.14));
pluck(9.35, 79, 0.35, 0, 0.5, 0.3); pluck(9.37, 84, 0.3, 0, 0.5, 0.3);

// 4. Insights: two phones slide in.
whoosh(12.0, 0.6, 1); whoosh(12.2, 0.5, -1); crash(12.0, 0.35, 1.0);
[79, 84, 88].forEach((m, i) => pluck(12.1 + i * 0.12, m, 0.35, (i - 1) * 0.3, 0.4, 0.12));

// 5. Privacy: one bright pluck per check, then build into the outro.
whoosh(15.05, 0.45, 1);
[[76, 84], [79, 86], [84, 91]].forEach(([a, b], i) => { const t = 15.1 + i * 0.5; pluck(t + 0.05, a, 0.7, 0, 0.4, 0.18); pluck(t + 0.07, b, 0.5, 0.1, 0.4, 0.18); tom(t, 0.35, 150 + i * 30); });
riser(16.9, 17.94, 0.8); swell(17.4, 17.94, 0.8);
for (let t = 17.0; t < 17.5; t += 0.125) snare(t, 0.25 + (t - 17.0) * 0.5);
for (let t = 17.5; t < 17.94; t += 0.0625) snare(t, 0.45 + (t - 17.5) * 0.9);

// 6. Outro 18–21: resolve on C, half-time, icon pop, long tail.
K(18, 1.1); boom(18, 0.9); crash(18, 0.9, 2.2);
supersaw(18, [48, 60, 64, 67, 72, 76], 2.6, { g: 1.35, d: 1.1, cut0: 5500, cut1: 1300, cdec: 0.6, send: 0.45, sustain: 0.15 });
pad(18, [48, 55, 60, 64, 67, 74], 3.0, 1.2, 1300, 3000);
bass(18, 36, 2.4, 0.85);
pluck(18.12, 84, 0.55, -0.1, 0.5, 0.3); pluck(18.14, 88, 0.45, 0.1, 0.5, 0.3);
K(19, 0.6); clap(19, 0.45); K(20, 0.45);
for (let t = 18.5; t < 20.4; t += 0.5) hat(t, 0.5, false, 0.25);
{ for (let k = 0; k < 14; k++) pluck(18.65 + k * 0.03 + rnd() * 0.01, PENT[4 + Math.floor(rnd() * 6)], 0.16, rnd() - 0.5, 0.6, 0.07); }
pluck(19.12, 79, 0.3, 0, 0.6, 0.4);

// ---------- sidechain on the music bus ----------
const sc = new Float32Array(N).fill(1);
for (const t of kicks) { const i0 = Math.round(t * SR); for (let i = 0; i < SR * 0.3 && i0 + i < N; i++) { const x = i / SR; const g = 1 - 0.5 * (x < 0.004 ? x / 0.004 : Math.exp(-(x - 0.004) / 0.08)); sc[i0 + i] = Math.min(sc[i0 + i], g); } }
for (let c = 0; c < 2; c++) for (let i = 0; i < N; i++) B.music[c][i] *= sc[i];

// ---------- reverb (Freeverb) ----------
function freeverb(inp, spread) {
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((d) => ({ b: new Float32Array(Math.round((d + spread) * SR / 44100)), i: 0, f: 0 }));
  const aps = [556, 441, 341, 225].map((d) => ({ b: new Float32Array(Math.round((d + spread) * SR / 44100)), i: 0 }));
  const out = new Float32Array(N), fb = 0.86, damp = 0.3;
  for (let n = 0; n < N; n++) {
    const x = inp[n] * 0.015; let y = 0;
    for (const c of combs) { const o = c.b[c.i]; c.f = o * (1 - damp) + c.f * damp; c.b[c.i] = x + c.f * fb; c.i = (c.i + 1) % c.b.length; y += o; }
    for (const a of aps) { const bo = a.b[a.i]; const o = -y + bo; a.b[a.i] = y + bo * 0.5; a.i = (a.i + 1) % a.b.length; y = o; }
    out[n] = y;
  }
  return out;
}
const vL = freeverb(B.verb[0], 0), vR = freeverb(B.verb[1], 23);

{ const st = (arr) => { let pk = 0, ss = 0; for (let i = 0; i < N; i++) { const v = Math.abs(arr[i]); pk = Math.max(pk, v); ss += v * v; } return `pk ${pk.toFixed(2)} rms ${Math.sqrt(ss / N).toFixed(3)}`; };
  console.log("drums", st(B.drums[0]), "| music", st(B.music[0]), "| sfx", st(B.sfx[0]), "| verb", st(vL)); }

// ---------- master ----------
const L = new Float32Array(N), R = new Float32Array(N);
const gap = (t) => { for (const g of [2.94, 17.94]) if (t >= g && t < g + 0.06) return 0.08; return 1; };
for (let i = 0; i < N; i++) {
  const t = i / SR, gp = gap(t);
  const l = (B.drums[0][i] * 0.42 + B.music[0][i] * 0.95 + B.sfx[0][i] * 0.8) * gp + vL[i] * 2.4;
  const r = (B.drums[1][i] * 0.42 + B.music[1][i] * 0.95 + B.sfx[1][i] * 0.8) * gp + vR[i] * 2.4;
  const fade = t > DUR - 0.5 ? Math.max(0, (DUR - t) / 0.5) : 1, fin = Math.min(1, t / 0.004);
  L[i] = Math.tanh(l) * fade * fin; R[i] = Math.tanh(r) * fade * fin;
}
for (const ch of [L, R]) { let p = 0, q = 0; for (let i = 0; i < N; i++) { const y = ch[i] - p + 0.9995 * q; p = ch[i]; q = y; ch[i] = y; } }
let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
const norm = 0.89 / peak;
const pcm = Buffer.alloc(N * 4);
for (let i = 0; i < N; i++) { pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * norm)) * 32767), i * 4); pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * norm)) * 32767), i * 4 + 2); }
const hdr = Buffer.alloc(44);
hdr.write("RIFF", 0); hdr.writeUInt32LE(36 + pcm.length, 4); hdr.write("WAVE", 8); hdr.write("fmt ", 12); hdr.writeUInt32LE(16, 16); hdr.writeUInt16LE(1, 20); hdr.writeUInt16LE(2, 22); hdr.writeUInt32LE(SR, 24); hdr.writeUInt32LE(SR * 4, 28); hdr.writeUInt16LE(4, 32); hdr.writeUInt16LE(16, 34); hdr.write("data", 36); hdr.writeUInt32LE(pcm.length, 40);
fs.writeFileSync(new URL("./mix.wav", import.meta.url), Buffer.concat([hdr, pcm]));
console.log("mix.wav ok peak", peak.toFixed(3), "kicks", kicks.length);
