// Play vs CPU — the online-multiplayer v0 (Decision 038,
// docs/ONLINE-MULTIPLAYER-PLAYBOOK.md §5). Mirror of BotOpponent.swift and
// Bots.kt — keep the three in lockstep.
//
// HONESTY RULE (learning-orientation, non-negotiable): a bot is always
// visibly labeled CPU. Never present a bot as a human.
import { Scoring } from './engine.js';

export const BOTS = {
  rookie: { id: 'rookie', name: 'Rookie Rae', baseSkill: 0.55,
    categorySkill: { sports: 0.15, film: 0.10, science: -0.12 }, speedMean: 6.5, speedSigma: 0.45 },
  regular: { id: 'regular', name: 'Trivia Tina', baseSkill: 0.70,
    categorySkill: { history: 0.10, arts: 0.08, sports: -0.10 }, speedMean: 5.5, speedSigma: 0.40 },
  ace: { id: 'ace', name: 'Ace Botsworth', baseSkill: 0.85,
    categorySkill: { science: 0.10, geography: 0.08, music: -0.08 }, speedMean: 4.0, speedSigma: 0.35 },
};

// Adapts to the player's recent accuracy so solo-vs-CPU stays a fair fight.
export function houseBot(playerAccuracy) {
  return { id: 'house', name: 'The House', baseSkill: Math.min(0.90, Math.max(0.35, playerAccuracy)),
    categorySkill: {}, speedMean: 5.0, speedSigma: 0.40 };
}

export function botById(id, playerAccuracy) {
  return BOTS[id] || houseBot(playerAccuracy);
}

function difficultyAdj(d) { return d <= 2 ? 0.15 : d >= 4 ? -0.20 : 0; }

function gaussian() { // Box–Muller
  const u1 = Math.max(Math.random(), Number.EPSILON);
  const u2 = Math.random();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

// Resolve what this bot does with this question, inside `window` seconds.
export function resolveBot(bot, categoryId, difficulty, correctIndex, optionCount, windowSecs) {
  const p = Math.min(0.98, Math.max(0.02,
    bot.baseSkill + (bot.categorySkill[categoryId] || 0) + difficultyAdj(difficulty)));
  if (Math.random() < 0.05) return { botId: bot.id, choiceIndex: null, seconds: null }; // freeze
  const correct = Math.random() < p;
  let t = Math.exp(Math.log(bot.speedMean) + gaussian() * bot.speedSigma);
  if (correct) t *= 0.85; // knowing feels fast
  t = Math.min(Math.max(t, 0.8), Math.max(1.0, windowSecs - 0.5));
  let choice = correctIndex;
  if (!correct) {
    const wrong = [];
    for (let i = 0; i < Math.max(optionCount, 2); i++) if (i !== correctIndex) wrong.push(i);
    choice = wrong[Math.floor(Math.random() * wrong.length)];
  }
  return { botId: bot.id, choiceIndex: choice, seconds: t };
}

// The running vs-CPU match beside the player's engine-scored game.
export class VsMatch {
  constructor(bots) {
    this.seats = bots.map((bot) => ({ bot, score: 0, streak: 0, lastCorrect: null }));
    this.pending = [];
    this._committed = -1;
  }
  beginQuestion(q, windowSecs) {
    this.pending = this.seats.map((s) =>
      resolveBot(s.bot, q.categoryID, q.difficulty, q.correctIndex, q.options.length, windowSecs));
  }
  commit(q, index, budget) {
    if (index === this._committed) return; // reveal fires once
    this._committed = index;
    for (const s of this.seats) {
      const a = this.pending.find((x) => x.botId === s.bot.id);
      if (!a) continue;
      const correct = a.choiceIndex === q.correctIndex;
      s.lastCorrect = a.choiceIndex == null ? false : correct;
      if (correct) {
        s.streak += 1;
        s.score += Scoring.points(true, a.seconds ?? budget, budget, s.streak);
      } else {
        s.streak = 0;
      }
    }
  }
  get standings() { return [...this.seats].sort((a, b) => b.score - a.score); }
}
