import {AbsoluteFill, Audio, Easing, Img, OffthreadVideo, Sequence, getStaticFiles, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {ShaderScene} from './Shader';
import {T, beat, DURATION} from './timeline';
import {C, CompactTab, Dot, FONT, Headline, Icon, Keycap, MONO, Panel, Penguin, Provider, Spinner, Toolbar, useSpring} from './ui';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);

// Background plates: public/footage/<name>.mp4 (a real clip) or <name>.jpg (a still, animated with a slow
// push and drift) replaces the procedural scene of the same name.
const footage = new Set(getStaticFiles().map((f) => f.name));
const Still: React.FC<{src: string; drift: [number, number]}> = ({src, drift}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const p = frame / Math.max(1, Math.min(durationInFrames, 300));
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Img src={src} style={{width: '100%', height: '100%', objectFit: 'cover', transform: `scale(${1.08 + 0.07 * p}) translate(${drift[0] * p}%, ${drift[1] * p}%)`}} />
      <AbsoluteFill style={{background: 'radial-gradient(ellipse at center, transparent 55%, rgba(0,0,0,0.28) 100%)'}} />
    </AbsoluteFill>
  );
};
const Footage: React.FC<{name: string; fallback: React.ReactNode; drift?: [number, number]}> = ({name, fallback, drift = [-1.2, 0.4]}) =>
  footage.has(`footage/${name}.mp4`) ? (
    <OffthreadVideo src={staticFile(`footage/${name}.mp4`)} muted style={{width: '100%', height: '100%', objectFit: 'cover'}} />
  ) : footage.has(`footage/${name}.jpg`) ? (
    <Still src={staticFile(`footage/${name}.jpg`)} drift={drift} />
  ) : (
    <>{fallback}</>
  );

const Push: React.FC<{children: React.ReactNode; from?: number; to?: number; len: number}> = ({children, from = 1.06, to = 1, len}) => {
  const frame = useCurrentFrame();
  const s = interpolate(frame, [0, len], [from, to], {...clamp, easing: Easing.out(Easing.quad)});
  return <AbsoluteFill style={{transform: `scale(${s})`}}>{children}</AbsoluteFill>;
};

const Paper: React.FC<{grid?: boolean; children?: React.ReactNode}> = ({grid, children}) => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(ellipse at 50% 45%, #FFFFFF 0%, ${C.paper} 60%, #E9E9E6 100%)`,
      fontFamily: FONT,
    }}
  >
    {grid ? (
      <AbsoluteFill
        style={{
          backgroundImage: 'linear-gradient(rgba(0,0,0,0.045) 1px, transparent 1px), linear-gradient(90deg, rgba(0,0,0,0.045) 1px, transparent 1px)',
          backgroundSize: '64px 64px',
          backgroundPosition: '-1px -1px',
          maskImage: 'radial-gradient(ellipse at center, black 30%, transparent 78%)',
        }}
      />
    ) : null}
    {children}
  </AbsoluteFill>
);

// ── 1. Cold open: penguins somewhere warm, one shot per agent, cut on the score's bar hits ──────────────

const Title: React.FC<{children: React.ReactNode; lift?: number; ink?: string}> = ({children, lift = 0, ink = '#fff'}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [2, 20], [0, 1], {...clamp, easing: ease});
  const s = interpolate(frame, [0, 120], [1.04, 1.0], clamp);
  const corner = (x: number | string, y: number | string) => (
    <div style={{position: 'absolute', left: x, top: y, width: 9, height: 9, borderRadius: 5, background: ink, opacity: p * 0.85}} />
  );
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
      <div style={{position: 'relative', padding: '34px 64px', transform: `translateY(${-lift}px) scale(${s})`, opacity: p, filter: p < 1 ? `blur(${(1 - p) * 12}px)` : undefined}}>
        {corner(0, 0)}
        {corner(0, 'calc(100% - 9px)')}
        {corner('calc(100% - 9px)', 0)}
        {corner('calc(100% - 9px)', 'calc(100% - 9px)')}
        <div style={{display: 'flex', alignItems: 'center', gap: 26, color: ink, fontFamily: FONT, fontSize: 108, fontWeight: 600, letterSpacing: '-0.045em', position: 'relative', textShadow: '0 1px 8px rgba(0,0,0,0.25)'}}>
          {children}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const PenguinSilhouette: React.FC<{x: number; y: number; s: number; phase: number}> = ({x, y, s, phase}) => {
  const frame = useCurrentFrame();
  const t = frame / 60 + phase;
  const bob = Math.abs(Math.sin(t * 5.2)) * 4 * s;
  const sway = Math.sin(t * 5.2) * 5;
  return (
    <g transform={`translate(${x + frame * 0.55 * s},${y - bob}) scale(${s})`}>
      <ellipse cx="22" cy="58" rx="40" ry="6" fill="rgba(40,50,80,0.16)" />
      <g transform={`rotate(${sway} 0 50)`}>
        <ellipse cx="-6" cy="56" rx="9" ry="4" fill="#E0A040" />
        <ellipse cx="8" cy="57" rx="9" ry="4" fill="#E0A040" />
        <path d="M-4-50c14 0 22 10 22 24 0 10 8 22 10 42 3 28-10 42-30 42S-32 44-30 16c2-22 8-30 8-42 0-12 6-24 18-24z" fill="#15161B" />
        <path d="M10-24c8 6 10 16 10 28 0 18 8 30 6 46-2 12-10 16-20 16-6 0-12-4-12-14 0-20 10-36 10-54 0-10 2-18 6-22z" fill="#F5F2EA" />
        <ellipse cx="9" cy="-26" rx="5" ry="8" fill="#F3B23C" transform="rotate(-20 9 -26)" />
        <path d="M16-42l14 4-14 3z" fill="#2A2A30" />
        <path d="M-14-6c-10 14-12 30-8 44 4-12 8-26 10-40z" fill="#0C0D10" />
      </g>
    </g>
  );
};

const HerdScene: React.FC = () => {
  const frame = useCurrentFrame();
  const herd = Array.from({length: 11}, (_, i) => ({x: -160 + i * 185 + (i % 3) * 30, y: 650 + Math.sin(i * 1.7) * 16 + i * 14, s: 1.05 + i * 0.07, phase: i * 0.37}));
  return (
    <AbsoluteFill style={{background: 'linear-gradient(180deg, #A9BCD6 0%, #DCE4EE 38%, #F6F1EA 52%, #FFFFFF 100%)'}}>
      <div style={{position: 'absolute', left: 1280, top: 300, width: 520, height: 520, borderRadius: '50%', background: 'radial-gradient(circle, rgba(255,238,205,0.95) 0%, rgba(255,214,160,0.35) 30%, transparent 70%)'}} />
      <svg width="1920" height="1080" style={{position: 'absolute', inset: 0}}>
        <path d="M0 560 Q 480 520 960 548 T 1920 540 V1080 H0z" fill="#EEF1F6" />
        <path d="M0 600 Q 600 580 1100 600 T 1920 610 V1080 H0z" fill="#F8F9FB" />
        {herd.map((p, i) => (
          <PenguinSilhouette key={i} {...p} />
        ))}
      </svg>
      <AbsoluteFill style={{background: 'linear-gradient(180deg, rgba(255,255,255,0) 60%, rgba(255,255,255,0.4) 100%)', backdropFilter: 'none'}} />
      <AbsoluteFill style={{background: `rgba(255,248,236,${0.08 + 0.04 * Math.sin(frame / 20)})`}} />
    </AbsoluteFill>
  );
};

const TerminalMark: React.FC<{size: number; color?: string}> = ({size, color = '#fff'}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="4" width="18" height="16" rx="3" />
    <path d="M7 10l3 2.5L7 15M12.5 15H17" />
  </svg>
);

// ── 2. Agents converge on one inbox ───────────────────────────────────────────────────────

const Chip: React.FC<{at: number; x: number; y: number; children: React.ReactNode; mono?: boolean}> = ({at, x, y, children, mono}) => {
  const frame = useCurrentFrame();
  const p = useSpring(at, {damping: 15, stiffness: 200, mass: 0.6});
  const out = interpolate(frame, [52, 64], [1, 0], clamp);
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        transform: `translate(-50%,-50%) scale(${0.7 + 0.3 * p})`,
        opacity: p * out,
        padding: mono ? '14px 22px' : '16px 24px',
        background: mono ? 'rgba(10,132,255,0.07)' : 'rgba(255,255,255,0.92)',
        borderRadius: 10,
        boxShadow: mono ? 'none' : '0 1px 0 rgba(0,0,0,0.05), 0 8px 24px rgba(0,0,0,0.05)',
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        fontFamily: mono ? MONO : FONT,
        fontSize: mono ? 24 : 22,
        fontWeight: mono ? 500 : 650,
        letterSpacing: mono ? 0 : '0.12em',
        color: mono ? '#3A6FB0' : C.ink,
        whiteSpace: 'nowrap',
      }}
    >
      {children}
    </div>
  );
};

const Converge: React.FC = () => {
  const frame = useCurrentFrame();
  const drop = T.drop - T.grid; // 120
  const dots = Array.from({length: 18}, (_, i) => {
    const a = (i / 18) * Math.PI * 2;
    const r0 = 520 + (i % 4) * 90;
    const start = {x: 960 + Math.cos(a) * r0, y: 540 + Math.sin(a) * r0 * 0.6};
    const corner = [
      {x: 470, y: 440},
      {x: 1450, y: 440},
      {x: 470, y: 640},
      {x: 1450, y: 640},
    ][i % 4];
    const gather = interpolate(frame, [30, 64], [0, 1], {...clamp, easing: ease});
    const fly = interpolate(frame, [drop + 50, drop + 80], [0, 1], {...clamp, easing: Easing.in(Easing.cubic)});
    const x = start.x + (corner.x - start.x) * gather + (1880 - corner.x) * fly + Math.sin(frame / 18 + i) * 6 * (1 - gather);
    const y = start.y + (corner.y - start.y) * gather + (540 - corner.y) * fly;
    const size = i < 4 ? 18 : 12;
    const show = i < 4 ? 1 : 1 - gather;
    return <div key={i} style={{position: 'absolute', left: x, top: y, width: size, height: size, marginLeft: -size / 2, marginTop: -size / 2, borderRadius: '50%', background: C.beak, opacity: show * interpolate(frame, [0, 10], [0, 1], clamp)}} />;
  });
  const slam = useSpring(drop, {damping: 13, stiffness: 220, mass: 0.7});
  const tab = useSpring(drop + 60, {damping: 20, stiffness: 120});
  const zoom = interpolate(frame, [drop - 2, drop + 6], [1.0, 1.035], clamp) - interpolate(frame, [drop + 6, drop + 60], [0, 0.035], {...clamp, easing: ease});
  return (
    <Paper grid>
      <AbsoluteFill style={{transform: `scale(${zoom})`}}>
        <Chip at={4} x={560} y={330}>
          <Provider name="claude" size={30} color={C.ink} /> CLAUDE CODE
        </Chip>
        <Chip at={10} x={1360} y={330}>
          <Provider name="openai" size={30} color={C.ink} /> CODEX
        </Chip>
        <Chip at={16} x={960} y={760}>
          <TerminalMark size={30} color={C.ink} /> ANY AGENT
        </Chip>
        <Chip at={22} x={700} y={560} mono>
          you@mac:~/web$ claude
        </Chip>
        <Chip at={26} x={1260} y={520} mono>
          you@mac:~/api$ codex
        </Chip>
        <Chip at={30} x={1240} y={700} mono>
          $ one ask --question "Ship it?"
        </Chip>
        {dots}
        <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
          <div style={{display: 'flex', fontFamily: FONT, fontSize: 132, fontWeight: 650, letterSpacing: '-0.05em', color: C.ink}}>
            <Headline text="Every agent." delay={T.everyAgent - T.grid} size={132} />
            <span style={{display: 'inline-block', opacity: slam, transform: `scale(${1.25 - 0.25 * slam})`, filter: `blur(${(1 - slam) * 14}px)`}}>One inbox.</span>
          </div>
        </AbsoluteFill>
        <div style={{position: 'absolute', right: 26 - (1 - tab) * 60, top: 474, opacity: tab}}>
          <CompactTab attention />
        </div>
      </AbsoluteFill>
    </Paper>
  );
};

// ── 3. The toolbar asks for you ───────────────────────────────────────────────────────────

const ToolbarScene: React.FC = () => {
  const frame = useCurrentFrame();
  const tip = useSpring(TB.tip, {damping: 14, stiffness: 200, mass: 0.6});
  const expand = useSpring(TB.expand, {damping: 18, stiffness: 120});
  const cam = interpolate(frame, [0, 180], [1.04, 1.0], clamp);
  return (
    <Paper>
      <AbsoluteFill style={{transform: `scale(${cam})`, transformOrigin: '50% 50%'}}>
        <div style={{position: 'absolute', right: 26, top: 474, opacity: 1 - expand, transform: `scaleY(${1 + expand * 0.5})`}}>
          <CompactTab attention />
        </div>
        <div style={{position: 'absolute', right: 40, top: 540, transform: `translateY(-50%) translateX(${(1 - expand) * 40}px)`, opacity: expand}}>
          <Toolbar dots={[C.working, C.waiting, C.idle, C.working]} spinning={[0, 3]} scale={1.3} />
        </div>
        <div
          style={{
            position: 'absolute',
            right: 80 + expand * 70,
            top: 446 + expand * -150,
            transform: `scale(${tip})`,
            transformOrigin: 'right center',
            opacity: tip,
            padding: '12px 18px',
            borderRadius: 14,
            background: '#111113',
            color: '#fff',
            fontFamily: FONT,
            fontSize: 22,
            fontWeight: 550,
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            boxShadow: '0 10px 30px rgba(0,0,0,0.25)',
            whiteSpace: 'nowrap',
          }}
        >
          <Dot color={C.waiting} size={10} pulse /> 2 working · 1 need an answer
        </div>
      </AbsoluteFill>
      <div style={{position: 'absolute', left: 150, top: 400, width: 760}}>
        <Headline text="Know the moment an agent needs you." delay={10} size={84} />
      </div>
    </Paper>
  );
};

// ── 4. Type the answer ────────────────────────────────────────────────────────────────────

// Scene-local frames, shared with the sound cues below.
const TB = {tip: 12, expand: 84};
const AN = {reply: 'A separate page, please.', space: 30, typeAt: 62, perChar: 3, enter: 150, k: 286, e: 328};
const TK = {tap1: 30, tap2: 54, pill: 58, typeAt: 72, perChar: 2.5, suggest: 104, send: 150, message: 'Make the orders page faster'};
const PH = {rise: 50, banner: 66, title: 110, typeAt: 150, perChar: 4, send: 196, reply: 'Run it'};

const typedText = (frame: number, text: string, at: number, perChar: number) => text.slice(0, Math.max(0, Math.floor((frame - at) / perChar)));
const Caret: React.FC<{color?: string}> = ({color = C.beak}) => {
  const frame = useCurrentFrame();
  return <span style={{opacity: Math.floor(frame / 15) % 2 ? 0 : 1, color, marginLeft: 1}}>|</span>;
};

const CardHeader: React.FC<{title: string; status: React.ReactNode; provider: 'claude' | 'openai'; where: string}> = ({title, status, provider, where}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 14, marginBottom: 18}}>
    <Provider name={provider} size={30} />
    <div>
      <div style={{fontSize: 24, fontWeight: 650, letterSpacing: '-0.01em'}}>{title}</div>
      <div style={{fontSize: 16, color: C.dim, marginTop: 3, display: 'flex', alignItems: 'center', gap: 8}}>
        {status} · {where}
      </div>
    </div>
  </div>
);

const AnswerScene: React.FC = () => {
  const frame = useCurrentFrame();
  const enter = useSpring(0, {damping: 20, stiffness: 110});
  const typed = typedText(frame, AN.reply, AN.typeAt, AN.perChar);
  const sending = frame >= AN.enter;
  const undo = interpolate(frame, [AN.enter, AN.enter + 120], [0, 1], clamp);
  const sent = frame >= AN.enter + 120;
  const swap = interpolate(frame, [AN.k, AN.k + 14], [0, 1], {...clamp, easing: ease});
  const clear = interpolate(frame, [AN.e + 2, AN.e + 24], [0, 1], {...clamp, easing: Easing.in(Easing.cubic)});
  const tilt = interpolate(frame, [0, 360], [-16, -8], clamp);
  return (
    <Paper>
      <div style={{position: 'absolute', left: 150, top: 380, width: 620}}>
        <Headline text="Just type your answer." delay={4} size={96} />
      </div>
      <div style={{position: 'absolute', left: 150, top: 660, display: 'flex', gap: 22}}>
        <Keycap label="space" at={AN.space} wide hint="reply" />
        <Keycap label="↵ return" at={AN.enter} wide hint="send" />
        <Keycap label="K" at={AN.k} hint="next card" />
        <Keycap label="E" at={AN.e} hint="clear" />
      </div>
      <div style={{position: 'absolute', right: 150, top: 360, perspective: 1600}}>
        <div style={{transform: `translateX(${(1 - enter) * 500}px) rotateY(${tilt}deg) rotateX(4deg)`, opacity: enter, transformStyle: 'preserve-3d'}}>
          <div style={{position: 'absolute', transform: `translateX(${-swap * 120}px) scale(${1 - swap * 0.06})`, opacity: 1 - swap}}>
            <Panel width={760} style={{padding: 30}}>
              <CardHeader title="Settings page" provider="claude" where="studio / web" status={<><Dot color={C.waiting} size={9} /> Waiting for your answer</>} />
              <div style={{fontSize: 21, color: C.dim, lineHeight: 1.45, padding: '16px 18px', borderRadius: 14, background: C.row}}>
                The layout is ready. One question before I build it: should account settings live on a separate page, in a modal, or as a tab in Profile?
              </div>
              <div style={{marginTop: 18, height: 58, borderRadius: 14, background: C.row, border: `1px solid ${sending ? 'rgba(50,215,75,0.45)' : 'rgba(255,255,255,0.12)'}`, display: 'flex', alignItems: 'center', padding: '0 18px', fontSize: 22, position: 'relative', overflow: 'hidden'}}>
                <div style={{position: 'absolute', left: 0, top: 0, bottom: 0, width: `${undo * 100}%`, background: 'rgba(50,215,75,0.16)'}} />
                <span style={{position: 'relative', display: 'flex', alignItems: 'center', gap: 10, color: typed ? C.text : C.dim}}>
                  {typed || 'Type your answer…'}
                  {!sending && frame >= AN.space ? <Caret /> : null}
                </span>
              </div>
              <div style={{marginTop: 12, height: 22, fontSize: 17, color: C.dim, display: 'flex', alignItems: 'center', gap: 8}}>
                {sent ? (
                  <>{Icon.check(15)} Sent to claude-web</>
                ) : sending ? (
                  <>Sending to Settings page… <span style={{marginLeft: 'auto', color: C.text, fontWeight: 600}}>Undo  esc</span></>
                ) : (
                  <>Send ↵</>
                )}
              </div>
            </Panel>
          </div>
          <div style={{transform: `translateX(${(1 - swap) * 140 + clear * 700}px) scale(${0.94 + swap * 0.06})`, opacity: swap * (1 - clear)}}>
            <Panel width={760} style={{padding: 30}}>
              <CardHeader title="Keyboard navigation" provider="openai" where="studio / api" status={<>{Icon.check(14)} Finished just now</>} />
              <div style={{fontSize: 22, padding: '18px 20px', borderRadius: 14, background: C.row, lineHeight: 1.45}}>Onboarding copy is in. Three screens, tests green.</div>
            </Panel>
          </div>
        </div>
      </div>
    </Paper>
  );
};

// ── 5. Chat ──────────────────────────────────────────────────────────────────────

const TalkScene: React.FC = () => {
  const frame = useCurrentFrame();
  const message = TK.message;
  const typed = typedText(frame, message, TK.typeAt, TK.perChar);
  const pill = useSpring(TK.pill, {damping: 18, stiffness: 140});
  const suggest = useSpring(TK.suggest, {damping: 18, stiffness: 160});
  const pending = frame >= TK.send && frame < TK.send + 120;
  const sent = frame >= TK.send + 120;
  return (
    <Paper>
      <div style={{position: 'absolute', left: 150, top: 360, width: 800}}>
        <Headline text="Chat with any agent." delay={4} size={96} sub="Double-tap Control to open the chat. Open One suggests who should get your message." subDelay={14} />
      </div>
      <div style={{position: 'absolute', left: 150, top: 690, display: 'flex', gap: 22}}>
        <Keycap label="⌃ control" at={TK.tap1} wide hint="tap" />
        <Keycap label="⌃ control" at={TK.tap2} wide hint="tap again: chat" />
        <Keycap label="↵ return" at={TK.send} wide hint="send" />
      </div>
      <div style={{position: 'absolute', right: 26, top: 540, transform: 'translateY(-50%)'}}>
        <Toolbar dots={[C.working, C.idle, C.working, C.idle]} spinning={[0, 2]} />
      </div>
      <div style={{position: 'absolute', right: 130, top: 420, width: 680, transformOrigin: 'right center', transform: `scale(${0.85 + 0.15 * pill})`, opacity: pill, fontFamily: FONT}}>
        {/* Talk recommends a recipient as you type; you review it before sending. */}
        <div style={{height: 56, marginBottom: 14, display: 'flex', alignItems: 'center', gap: 12, padding: '0 22px', borderRadius: 28, background: '#111113', color: '#fff', fontSize: 22, width: 'fit-content', opacity: suggest, transform: `translateY(${(1 - suggest) * 12}px)`}}>
          <span style={{color: C.dim}}>To</span>
          <Provider name="openai" size={22} />
          <b style={{fontWeight: 600}}>codex-api</b>
          <span style={{color: C.dim}}>· suggested</span>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={C.dim} strokeWidth={2.4} strokeLinecap="round"><path d="M6 9l6 6 6-6" /></svg>
        </div>
        <div style={{height: 92, borderRadius: 46, background: '#111113', boxShadow: '0 30px 70px rgba(0,0,0,0.28)', display: 'flex', alignItems: 'center', padding: '0 18px 0 30px', gap: 18, color: '#fff', fontSize: 28, fontWeight: 500}}>
          {sent ? (
            <div style={{display: 'flex', alignItems: 'center', gap: 14, fontSize: 25}}>
              {Icon.check(24)}
              <span>Sent to</span>
              <b>codex-api</b>
              <span style={{color: C.dim}}>· studio / api</span>
            </div>
          ) : pending ? (
            <div style={{display: 'flex', alignItems: 'center', width: '100%', fontSize: 25}}>
              <span>Sending to codex-api…</span>
              <span style={{marginLeft: 'auto', marginRight: 12, fontWeight: 600}}>Undo  esc</span>
            </div>
          ) : (
            <>
              <div style={{flex: 1, whiteSpace: 'nowrap'}}>
                {typed}
                <Caret />
              </div>
              <div style={{width: 58, height: 58, borderRadius: 29, background: typed.length === message.length ? '#fff' : 'rgba(255,255,255,0.12)', color: typed.length === message.length ? '#000' : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{Icon.send(26)}</div>
            </>
          )}
        </div>
      </div>
    </Paper>
  );
};

// ── 6. See every agent ────────────────────────────────────────────────────────────────────

type Row = {title: string; provider: 'claude' | 'openai'; state: 'working' | 'waiting' | 'done'; note?: string};
const groups: {name: string; where?: string; rows: Row[]}[] = [
  {
    name: 'studio / web',
    rows: [
      {title: 'Settings page', provider: 'claude', state: 'waiting', note: 'Needs you'},
      {title: 'Pricing copy', provider: 'claude', state: 'working'},
      {title: 'Onboarding flow', provider: 'openai', state: 'done', note: 'Finished'},
    ],
  },
  {
    name: 'studio / api',
    where: 'worktree orders-speedup',
    rows: [
      {title: 'Orders page speed', provider: 'openai', state: 'working'},
      {title: 'Flaky login test', provider: 'claude', state: 'done', note: 'Finished'},
    ],
  },
  {name: 'build-box', where: 'remote', rows: [{title: 'Load test', provider: 'openai', state: 'working'}]},
];

const AgentsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const enter = useSpring(6, {damping: 20, stiffness: 110});
  let i = 0;
  return (
    <Paper>
      <div style={{position: 'absolute', left: 150, top: 380, width: 720}}>
        <Headline text="See every agent." delay={4} size={96} sub="Grouped by project and worktree." subDelay={14} />
      </div>
      <div style={{position: 'absolute', right: 140, top: 540, transform: `translateY(-50%) translateX(${(1 - enter) * 300}px)`, opacity: enter}}>
        <Panel width={720} style={{padding: '22px 22px 18px'}}>
          {groups.map((g) => (
            <div key={g.name} style={{marginBottom: 10}}>
              <div style={{fontSize: 16, color: C.dim, padding: '8px 12px', display: 'flex', alignItems: 'center', gap: 8, letterSpacing: '0.01em'}}>
                {g.name}
                {g.where ? (
                  <>
                    <span>·</span>
                    {g.where === 'remote' ? <TerminalMark size={15} color={C.dim} /> : null}
                    {g.where}
                  </>
                ) : null}
              </div>
              {g.rows.map((r) => {
                const d = 14 + i++ * 5;
                const p = interpolate(frame, [d, d + 12], [0, 1], {...clamp, easing: ease});
                const finishing = r.title === 'Orders page speed' && frame > 180;
                const state = finishing ? 'done' : r.state;
                return (
                  <div key={r.title} style={{display: 'flex', alignItems: 'center', gap: 14, padding: '13px 12px', borderRadius: 12, opacity: p, transform: `translateY(${(1 - p) * 14}px)`, background: state === 'waiting' ? 'rgba(255,166,31,0.10)' : 'transparent', fontSize: 22}}>
                    {state === 'working' ? <Spinner size={13} /> : <Dot color={state === 'waiting' ? C.waiting : C.done} size={11} pulse={state === 'waiting'} />}
                    <Provider name={r.provider} size={22} />
                    <span>{r.title}</span>
                    <span style={{marginLeft: 'auto', fontSize: 16, color: state === 'waiting' ? C.waiting : C.dim}}>{finishing ? 'Finished' : r.note ?? 'Working'}</span>
                  </div>
                );
              })}
            </div>
          ))}
        </Panel>
      </div>
    </Paper>
  );
};

// ── 7. Away from your Mac ─────────────────────────────────────────────────────────────────

const PhoneScene: React.FC = () => {
  const frame = useCurrentFrame();
  const rise = useSpring(PH.rise, {damping: 19, stiffness: 100});
  const typed = typedText(frame, PH.reply, PH.typeAt, PH.perChar);
  const press = interpolate(frame, [PH.send - 4, PH.send, PH.send + 6], [0, 1, 0], clamp);
  const sent = frame >= PH.send;
  const swapTitle = frame > PH.title;
  const banner = [PH.banner, PH.banner + 12, PH.banner + 60, PH.banner + 72];
  return (
    <AbsoluteFill style={{background: 'radial-gradient(ellipse at 70% 40%, #1E1E22 0%, #0B0B0C 70%)', fontFamily: FONT}}>
      <div style={{position: 'absolute', left: 150, top: 410}}>
        {swapTitle ? (
          <Headline key="b" text="Answer from your phone." delay={PH.title} size={96} color="#fff" sub="Your conversations, on the same Wi-Fi." subDelay={PH.title + 10} subColor="rgba(235,235,245,0.6)" />
        ) : (
          <Headline key="a" text="Away from your Mac?" delay={4} size={96} color="#fff" />
        )}
      </div>
      <div style={{position: 'absolute', right: 250, top: 120 + (1 - rise) * 900, width: 430, height: 880, borderRadius: 68, background: '#000', border: '12px solid #2A2A2D', boxShadow: '0 60px 120px rgba(0,0,0,0.6), inset 0 0 0 2px #3a3a3e', overflow: 'hidden', color: C.text}}>
        <div style={{position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)', width: 120, height: 34, borderRadius: 17, background: '#000', zIndex: 2}} />
        <div style={{padding: '70px 26px 0', display: 'flex', alignItems: 'center', gap: 12}}>
          <Penguin size={36} />
          <div style={{fontSize: 24, fontWeight: 650}}>Inbox</div>
          <div style={{marginLeft: 'auto', fontSize: 14, color: C.dim}}>1 needs you</div>
        </div>
        <div style={{margin: '26px 18px', padding: 22, borderRadius: 22, background: '#1C1C1E'}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 10, fontSize: 15, color: C.dim}}>
            <Provider name="openai" size={20} /> api · build-box
          </div>
          <div style={{fontSize: 22, fontWeight: 650, margin: '10px 0 8px'}}>Database migration</div>
          <div style={{fontSize: 17, color: C.dim, lineHeight: 1.45}}>Migration 0042 adds the orders index. The dry run on a copy of production took 3 seconds.</div>
          <div style={{fontSize: 19, fontWeight: 600, margin: '20px 0 14px'}}>Run it on production now?</div>
          <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
            <div style={{flex: 1, height: 50, borderRadius: 25, padding: '0 18px', display: 'flex', alignItems: 'center', fontSize: 18, background: 'rgba(255,255,255,0.08)', border: `1px solid ${sent ? 'rgba(50,215,75,0.5)' : 'rgba(255,255,255,0.1)'}`, color: typed ? C.text : C.dim}}>
              {typed || 'Reply…'}
              {!sent && frame >= PH.typeAt - 10 ? <Caret /> : null}
            </div>
            <div style={{width: 50, height: 50, borderRadius: 25, background: typed.length === PH.reply.length ? C.blue : 'rgba(255,255,255,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', transform: `scale(${1 - press * 0.12})`}}>{Icon.send(22)}</div>
          </div>
          {sent ? <div style={{fontSize: 15, color: C.dim, marginTop: 12}}>Waiting for your Mac…</div> : null}
        </div>
      </div>
      {/* Notification banner drops in as the phone arrives. */}
      <div
        style={{
          position: 'absolute',
          right: 275,
          top: 150 + (1 - rise) * 900 + interpolate(frame, banner, [-30, 0, 0, -30], clamp),
          width: 380,
          opacity: interpolate(frame, banner, [0, 1, 1, 0], clamp),
          padding: '14px 16px',
          borderRadius: 20,
          background: 'rgba(60,60,64,0.92)',
          color: '#fff',
          display: 'flex',
          gap: 12,
          alignItems: 'center',
          zIndex: 3,
        }}
      >
        <Penguin size={34} />
        <div>
          <div style={{fontSize: 15, fontWeight: 650}}>codex-api needs you</div>
          <div style={{fontSize: 14, opacity: 0.75}}>Run it on production now?</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── 8. Open source, then the end card ─────────────────────────────────────────────────────

const OpenScene: React.FC = () => {
  const chips = ['Free and open source', 'Local by default', 'Uses the CLIs you already have'];
  return (
    <Paper grid>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', flexDirection: 'column'}}>
        <Headline text="Open source." delay={2} size={150} align="center" />
        <div style={{display: 'flex', gap: 18, marginTop: 48}}>
          {chips.map((c, i) => (
            <ChipIn key={c} at={16 + i * 6}>
              {c}
            </ChipIn>
          ))}
        </div>
      </AbsoluteFill>
    </Paper>
  );
};

const ChipIn: React.FC<{at: number; children: React.ReactNode}> = ({at, children}) => {
  const p = useSpring(at, {damping: 16, stiffness: 190, mass: 0.6});
  return (
    <div style={{padding: '16px 26px', borderRadius: 999, background: '#fff', boxShadow: '0 1px 0 rgba(0,0,0,0.05), 0 10px 30px rgba(0,0,0,0.06)', fontFamily: FONT, fontSize: 26, fontWeight: 550, color: C.ink, opacity: p, transform: `translateY(${(1 - p) * 20}px)`, display: 'flex', alignItems: 'center', gap: 12}}>
      <Dot color={C.beak} size={10} />
      {children}
    </div>
  );
};

const EndScene: React.FC = () => {
  const frame = useCurrentFrame();
  const pop = useSpring(0, {damping: 11, stiffness: 200, mass: 0.6});
  const reveal = interpolate(frame, [42, 72], [0, 1], {...clamp, easing: ease});
  const word = useSpring(60, {damping: 20, stiffness: 120});
  const out = interpolate(frame, [DURATION - T.end - 40, DURATION - T.end - 4], [1, 0], clamp);
  return (
    <AbsoluteFill style={{background: C.paper}}>
      <AbsoluteFill style={{opacity: reveal}}>
        <Footage name="lavender" drift={[0, -0.8]} fallback={<ShaderScene name="field" />} />

      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'flex-start', paddingTop: 170}}>
        <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 28}}>
          <Penguin size={150 - 30 * word} style={{transform: `scale(${pop})`, filter: undefined}} />
          <div style={{fontFamily: FONT, fontSize: 128, fontWeight: 650, letterSpacing: '-0.05em', color: '#fff', whiteSpace: 'nowrap', opacity: word, transform: `translateX(${(1 - word) * -40}px)`, paddingRight: 8}}>Open One</div>
        </div>
        <div style={{marginTop: 26, fontFamily: FONT, fontSize: 36, fontWeight: 500, letterSpacing: '-0.015em', color: '#fff', opacity: interpolate(frame, [80, 96], [0, 1], clamp)}}>
          The open-source inbox for your coding agents.
        </div>
        <div style={{marginTop: 18, fontFamily: FONT, fontSize: 22, color: 'rgba(255,255,255,0.85)', opacity: interpolate(frame, [100, 116], [0, 1], clamp), letterSpacing: '0.02em'}}>
          Native macOS · Claude Code · Codex · any agent via the bridge
        </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: '#000', opacity: 1 - out}} />
    </AbsoluteFill>
  );
};

// ── Sound ─────────────────────────────────────────────────────────────────────────────────

const sfx: {at: number; name: string; volume: number}[] = [
  ...[4, 10, 16, 22, 26, 30].map((d) => ({at: T.grid + d, name: 'tick', volume: 0.35})),
  {at: T.toolbar + TB.tip, name: 'pop', volume: 0.55},
  {at: T.toolbar + TB.expand - 2, name: 'whoosh', volume: 0.4},
  {at: T.answer + AN.typeAt, name: 'typing', volume: 0.45},
  {at: T.answer + AN.enter, name: 'key', volume: 0.8},
  {at: T.answer + AN.enter + 120, name: 'send', volume: 0.45},
  {at: T.answer + AN.k, name: 'key', volume: 0.8},
  {at: T.answer + AN.space, name: 'key', volume: 0.7},
  {at: T.answer + AN.e, name: 'key', volume: 0.8},
  {at: T.answer + AN.e + 4, name: 'whoosh', volume: 0.35},
  {at: T.talk + TK.tap1, name: 'key', volume: 0.8},
  {at: T.talk + TK.tap2, name: 'key', volume: 0.8},
  {at: T.talk + TK.typeAt, name: 'typing', volume: 0.45},
  {at: T.talk + TK.send, name: 'key', volume: 0.8},
  {at: T.talk + TK.send + 120, name: 'send', volume: 0.5},
  {at: T.talk + TK.suggest, name: 'tick', volume: 0.4},
  {at: T.phone + PH.banner, name: 'chime', volume: 0.5},
  {at: T.phone + PH.typeAt, name: 'tick', volume: 0.4},
  {at: T.phone + PH.send, name: 'send', volume: 0.5},
  {at: T.end, name: 'pop', volume: 0.6},
  {at: T.end + 40, name: 'shimmer', volume: 0.45},
];

export const Launch: React.FC = () => (
  <AbsoluteFill style={{background: '#000'}}>
    <Audio src={staticFile('score.mp3')} />
    {sfx.map((s, i) => (
      <Sequence key={i} from={s.at} durationInFrames={150}>
        <Audio src={staticFile(`sfx/${s.name}.mp3`)} volume={s.volume} />
      </Sequence>
    ))}

    <Sequence from={T.claude} durationInFrames={T.codex - T.claude}>
      <Push len={120} from={1.12}>
        <Footage name="beach" drift={[0, -0.8]} fallback={<ShaderScene name="amber" speed={2.5} />} />
      </Push>
      <Title>
        <Provider name="claude" size={92} color="#fff" /> Claude Code
      </Title>
    </Sequence>
    <Sequence from={T.codex} durationInFrames={T.any - T.codex}>
      <Push len={120} from={1.1}>
        <Footage name="pool" drift={[-1.5, 0]} fallback={<ShaderScene name="shelf" speed={1.6} />} />
      </Push>
      <Title>
        <Provider name="openai" size={92} color="#fff" /> Codex
      </Title>
    </Sequence>
    <Sequence from={T.any} durationInFrames={T.grid - T.any}>
      <Push len={120} from={1.08}>
        <Footage name="village" drift={[1.2, -0.3]} fallback={<HerdScene />} />
      </Push>
      <Title lift={30}>
        <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6}}>
          <div style={{fontSize: 40, fontWeight: 550, letterSpacing: '-0.01em'}}>Introducing</div>
          <div style={{display: 'flex', alignItems: 'center', gap: 30, fontSize: 124, letterSpacing: '-0.05em', lineHeight: 1.05}}>
            <Penguin size={116} style={{filter: 'drop-shadow(0 6px 24px rgba(0,0,0,0.3))'}} /> Open One
          </div>
        </div>
      </Title>
    </Sequence>
    <Sequence from={T.grid} durationInFrames={T.toolbar - T.grid}>
      <Converge />
    </Sequence>
    <Sequence from={T.toolbar} durationInFrames={T.answer - T.toolbar}>
      <ToolbarScene />
    </Sequence>
    <Sequence from={T.answer} durationInFrames={T.talk - T.answer}>
      <AnswerScene />
    </Sequence>
    <Sequence from={T.talk} durationInFrames={T.agents - T.talk}>
      <TalkScene />
    </Sequence>
    <Sequence from={T.agents} durationInFrames={T.phone - T.agents}>
      <AgentsScene />
    </Sequence>
    <Sequence from={T.phone} durationInFrames={T.open - T.phone}>
      <PhoneScene />
    </Sequence>
    <Sequence from={T.open} durationInFrames={T.end - T.open}>
      <Push len={T.end - T.open} from={1.0} to={1.04}>
        <OpenScene />
      </Push>
    </Sequence>
    <Sequence from={T.end} durationInFrames={DURATION - T.end}>
      <EndScene />
    </Sequence>
  </AbsoluteFill>
);
