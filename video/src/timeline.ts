// Every cut sits on the score's measured beat grid (public/score.mp3, ElevenLabs Music).
// librosa: 117.5 BPM detected, fitted period 0.4995 s, first beat at 0.074 s.
// Bar hits at beats 0/4/8/12, the drop at beat 16 (8.07 s). Beats 24-40 of the original take are
// repeated once (spliced at beat 40) to give the product scenes more time, which moves the final
// chord to beat 65 (32.54 s).
export const FPS = 60;
export const DURATION = 39 * FPS;

export const beat = (k: number) => Math.round((0.074 + 0.4995 * k) * FPS);

export const T = {
  claude: 0,
  codex: beat(4),
  any: beat(8),
  grid: beat(12),
  everyAgent: beat(14),
  drop: beat(16),
  toolbar: beat(19),
  answer: beat(25),
  talk: beat(37),
  agents: beat(47),
  phone: beat(56),
  open: beat(65),
  end: beat(69),
};
