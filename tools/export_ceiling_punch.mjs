// Fixtures for the Ceiling Punch replay check on the server (server/hh/arcade.py): towers and whole runs made by the
// browser's own engine. Run from the repo root, with the RuleReaper repo next to this one (or RULEREAPER=path):
//   node tools/export_ceiling_punch.mjs > server/tests/fixtures/ceiling_punch.json
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(process.env.RULEREAPER ?? '../RuleReaper');
const E = await import(pathToFileURL(resolve(root, 'games/ceiling-punch/public/engine.mjs')).href);

const towers = [];
for (const seed of [1, 2, 7, 99, 4242, 123456789, 4294967295, 2654435769]) {
  towers.push({ seed, ceilings: Array.from({ length: 80 }, (_, n) => E.ceilingAt(seed, n)) });
}

// whole runs: a pretend player taps at crack centres (gold first when greedy), with a little timing noise
function rngOf(a) { return () => ((a = (Math.imul(a, 1664525) + 1013904223) >>> 0) / 4294967296); }
const runs = [];
for (let i = 0; i < 40; i++) {
  const rng = rngOf(1000 + i);
  const seed = Math.floor(rng() * 2 ** 32) >>> 0;
  const greedy = i % 2 === 0;
  const noise = [0, 4, 9][i % 3];
  const run = E.createRun(seed);
  E.tap(run);
  const taps = [];
  let ticks = 0, target = null, calm = 0;
  while (run.phase !== 'lost' && ticks < 120 * 600) {
    if (run.phase === 'running') calm++; else calm = 0;
    if (run.phase === 'running' && target === null && calm > 25) {
      const ahead = s => (run.direction > 0 ? s[1] > run.x + 6 : s[0] < run.x - 6);
      const gold = E.doubleWindows(run.seed, run.floor).filter(ahead);
      const spans = E.ceilingAt(run.seed, run.floor).filter(ahead);
      const pick = (greedy && gold.length ? gold : spans).sort((a, b) => (run.direction > 0 ? a[0] - b[0] : b[0] - a[0]))[0];
      if (pick) target = (pick[0] + pick[1]) / 2 + (rng() - .5) * 2 * noise;
    }
    if (target !== null && run.phase === 'running' && (run.direction > 0 ? run.x >= target : run.x <= target)) {
      taps.push(ticks);
      E.tap(run);
      target = null;
    }
    E.step(run);
    ticks++;
    if (target !== null && run.phase === 'running' && (target > E.END || target < E.EDGE)) target = null;
  }
  runs.push({ seed, taps, floor: run.floor, ticks });
}
// odd taps: during a smash (ignored), and a run that just waits for the flood
runs.push({ seed: 5, taps: [], floor: 0, ticks: 0 });
console.log(JSON.stringify({ engine: 1, towers, runs, nextSeed: [0, 1, 12345, 4294967295].map(s => [s, E.nextSeed(s)]) }));
