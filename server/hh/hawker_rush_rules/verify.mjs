// engine.mjs is the release snapshot of caspars-arcade/games/hawker-rush/public/engine.mjs.
import { readFileSync } from 'node:fs';
import * as E from './engine.mjs';

const MAX_TICKS = 30 * 60 * 10;
const index = (v, max, min = 0) => Number.isInteger(v) && v >= min && v < max;
const owns = (records, key) => typeof key === 'string' && Object.hasOwn(records, key);

function validAction(action) {
  if (!Array.isArray(action) || action.length < 3 || action.length > 4) return false;
  const [tick, kind, a, b = -1] = action;
  if (!index(tick, MAX_TICKS)) return false;
  switch (kind) {
    case 'base': return owns(E.BASES, a) && index(b, E.PREP, -1);
    case 'add': return owns(E.INGREDIENTS, a) && index(b, E.PREP, -1);
    case 'cook':
    case 'bin-burnt': return owns(E.STATIONS, a) && b === -1;
    case 'bin-dish': return index(a, E.PREP) && b === -1;
    case 'serve': return index(a, E.PREP) && index(b, E.SEATS, -1);
    case 'cook-dish': return index(a, E.PREP) && b === -1;
    case 'flip': return owns(E.STATIONS, a) && b === -1;
    case 'take': return owns(E.STATIONS, a) && index(b, E.PREP, -1);
    default: return false;
  }
}

function verify({mode, period, actions}) {
  if (!actions.every(validAction)) return null;
  // Allow fast taps and simultaneous inputs, while bounding bursts well above normal play.
  for (let i = 1; i < actions.length; i++) {
    if (actions[i][0] < actions[i - 1][0]) return null;
    if (i >= 32 && actions[i][0] - actions[i - 32][0] < 30) return null;
  }
  // (leaderboard runs are always solo: the spec has no players)
  const spec = mode === 'daily' ? E.daily(period).spec : E.speedRun(new Date(period + 'T00:00:00Z')).spec;
  const shift = E.createShift(spec);
  let i = 0;
  while (shift.phase === 'running' && shift.ticks < MAX_TICKS) {
    while (i < actions.length && actions[i][0] === shift.ticks) {
      const [, kind, a, b] = actions[i++];
      if (!E.act(shift, kind, a, b)) return null;
    }
    E.step(shift);
    shift.events.length = 0;
  }
  if (shift.phase !== 'over' || i !== actions.length) return null;
  const value = Math.round(100 * (mode === 'daily' ? shift.coins : E.speedTime(shift)));
  return {value, ticks: shift.ticks, served: shift.served};
}

process.stdout.write(JSON.stringify(verify(JSON.parse(readFileSync(0, 'utf8')))));
