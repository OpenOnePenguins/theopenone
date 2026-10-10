import {Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

// Vector recreations of Open One's native UI (SwiftUI dark glass panels, edge toolbar),
// drawn from the app's own colors in Sources/OpenOne/Views.swift.

export const C = {
  paper: '#F3F3F1',
  ink: '#111113',
  sub: '#6E6E73',
  panel: 'rgba(22,22,24,0.94)',
  row: 'rgba(255,255,255,0.065)',
  line: 'rgba(255,255,255,0.09)',
  text: '#F5F5F7',
  dim: 'rgba(235,235,245,0.55)',
  working: '#FFCC66', // AgentState.working
  waiting: '#FFA61F', // AgentState.waiting
  idle: '#98989D',
  attention: '#FF3D30', // toolbar Inbox-attention marker
  done: '#32D74B',
  beak: '#FFC812',
  blue: '#0A84FF',
};

export const FONT = '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif';
export const MONO = '"SF Mono", ui-monospace, Menlo, monospace';

export const useSpring = (delay: number, config: {damping: number; stiffness: number; mass?: number} = {damping: 18, stiffness: 140, mass: 0.9}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - delay, fps, config});
};

export const Penguin: React.FC<{size: number; style?: React.CSSProperties}> = ({size, style}) => (
  <Img src={staticFile('brand/open-one-logo.png')} style={{width: size, height: size, ...style}} />
);

export const Provider: React.FC<{name: 'claude' | 'openai' | 'opencode'; size: number; color?: string}> = ({name, size, color}) => (
  <div
    style={{
      width: size,
      height: size,
      backgroundColor: color ?? (name === 'claude' ? '#D97757' : '#fff'),
      WebkitMaskImage: `url(${staticFile(`brand/provider-${name}.svg`)})`,
      WebkitMaskSize: 'contain',
      WebkitMaskRepeat: 'no-repeat',
      WebkitMaskPosition: 'center',
      flexShrink: 0,
    }}
  />
);

const stroke = {fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round'} as const;
export const Icon = {
  inbox: (s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" {...stroke}><path d="M3 13h5l1.5 2.5h5L16 13h5" /><path d="M5.5 5h13L21 13v5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18v-5z" /></svg>
  ),
  mic: (s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" {...stroke}><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" /></svg>
  ),
  camera: (s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" {...stroke}><path d="M4 8h3l1.5-2.5h7L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z" /><circle cx="12" cy="13" r="3.5" /></svg>
  ),
  more: (s = 22) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="currentColor"><circle cx="6" cy="12" r="1.7" /><circle cx="12" cy="12" r="1.7" /><circle cx="18" cy="12" r="1.7" /></svg>
  ),
  check: (s = 16, color = C.done) => (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
  ),
  send: (s = 18) => (
    <svg width={s} height={s} viewBox="0 0 24 24" {...stroke}><path d="M12 19V5M6 11l6-6 6 6" /></svg>
  ),
  globe: (s = 14) => (
    <svg width={s} height={s} viewBox="0 0 24 24" {...stroke}><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18" /></svg>
  ),
};

export const Spinner: React.FC<{size?: number; color?: string}> = ({size = 12, color = C.working}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        border: `${Math.max(2, size / 5)}px solid ${color}`,
        borderRightColor: 'transparent',
        transform: `rotate(${frame * 9}deg)`,
        flexShrink: 0,
      }}
    />
  );
};

export const Dot: React.FC<{color: string; size?: number; pulse?: boolean}> = ({color, size = 10, pulse}) => {
  const frame = useCurrentFrame();
  const s = pulse ? 1 + 0.18 * Math.max(0, Math.sin(frame / 7)) : 1;
  return (
    <div style={{width: size, height: size, borderRadius: '50%', background: color, transform: `scale(${s})`, boxShadow: pulse ? `0 0 ${size}px ${color}` : undefined, flexShrink: 0}} />
  );
};

// Headline set in SF Pro Display with tight tracking, like the native app's title style.
export const Headline: React.FC<{text: string; delay: number; size?: number; sub?: string; subDelay?: number; color?: string; subColor?: string; align?: 'left' | 'center'}> = ({
  text,
  delay,
  size = 92,
  sub,
  subDelay,
  color = C.ink,
  subColor = C.sub,
  align = 'left',
}) => {
  const frame = useCurrentFrame();
  const words = text.split(' ');
  return (
    <div style={{fontFamily: FONT, textAlign: align}}>
      <div style={{fontSize: size, fontWeight: 650, letterSpacing: '-0.045em', lineHeight: 1.02, color}}>
        {words.map((w, i) => {
          const d = delay + i * 3;
          const p = interpolate(frame - d, [0, 14], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
          return (
            <span key={i} style={{display: 'inline-block', opacity: p, transform: `translateY(${(1 - p) * 0.35 * size}px)`, filter: `blur(${(1 - p) * 10}px)`, marginRight: '0.24em'}}>
              {w}
            </span>
          );
        })}
      </div>
      {sub ? (
        <div
          style={{
            marginTop: size * 0.28,
            fontSize: size * 0.34,
            fontWeight: 450,
            letterSpacing: '-0.015em',
            color: subColor,
            opacity: interpolate(frame - (subDelay ?? delay + 10), [0, 14], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}),
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );
};

export const Keycap: React.FC<{label: string; at: number; wide?: boolean; hint?: string}> = ({label, at, wide, hint}) => {
  const frame = useCurrentFrame();
  const appear = useSpring(at - 26, {damping: 18, stiffness: 120, mass: 0.8});
  const press = interpolate(frame - at, [0, 6, 20], [0, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const gone = interpolate(frame - at, [64, 80], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18}}>
      <div
        style={{
          width: wide ? 170 : 104,
          height: 104,
          borderRadius: 24,
          background: 'linear-gradient(180deg, #2C2C2F 0%, #1A1A1C 100%)',
          boxShadow: `0 ${10 - press * 7}px 0 #050506, 0 ${24 - press * 14}px 40px rgba(0,0,0,0.28)`,
          transform: `translateY(${press * 7}px) scale(${appear * gone})`,
          opacity: Math.min(appear, gone),
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: '#F5F5F7',
          fontFamily: FONT,
          fontWeight: 500,
          fontSize: label.length > 1 ? 30 : 44,
        }}
      >
        {label}
      </div>
      {hint ? (
        <div style={{fontFamily: FONT, fontSize: 30, fontWeight: 600, color: C.sub, opacity: Math.min(appear, gone), whiteSpace: 'nowrap'}}>{hint}</div>
      ) : null}
    </div>
  );
};

export const Panel: React.FC<{width: number; children: React.ReactNode; style?: React.CSSProperties}> = ({width, children, style}) => (
  <div
    style={{
      width,
      borderRadius: 26,
      background: C.panel,
      border: `1px solid ${C.line}`,
      boxShadow: '0 40px 90px rgba(0,0,0,0.30), 0 8px 24px rgba(0,0,0,0.18), inset 0 1px 0 rgba(255,255,255,0.08)',
      color: C.text,
      fontFamily: FONT,
      overflow: 'hidden',
      ...style,
    }}
  >
    {children}
  </div>
);

// The floating edge toolbar: activity dots, Inbox, Open One, mic, screenshot, more.
export const Toolbar: React.FC<{dots: string[]; attention?: boolean; spinning?: number[]; scale?: number}> = ({dots, attention, spinning = [], scale = 1}) => (
  <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 * scale, transform: `scale(${scale})`, transformOrigin: 'right center'}}>
    <Capsule>
      {dots.map((d, i) => (spinning.includes(i) ? <Spinner key={i} size={13} color={d} /> : <Dot key={i} color={d} size={11} />))}
    </Capsule>
    <Capsule>
      <Penguin size={34} />
      <div style={{color: '#fff'}}>{Icon.mic(24)}</div>
      <div style={{color: '#fff'}}>{Icon.camera(24)}</div>
    </Capsule>
    <Capsule>
      <div style={{color: '#fff'}}>{Icon.more(24)}</div>
    </Capsule>
  </div>
);

const Capsule: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      width: 62,
      padding: '16px 0',
      borderRadius: 31,
      background: 'linear-gradient(180deg, rgba(40,40,44,0.97), rgba(14,14,16,0.97))',
      border: '1px solid rgba(255,255,255,0.12)',
      boxShadow: '0 16px 40px rgba(0,0,0,0.28), inset 0 1px 0 rgba(255,255,255,0.12)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 16,
    }}
  >
    {children}
  </div>
);

export const CompactTab: React.FC<{attention: boolean}> = ({attention}) => (
  <div
    style={{
      width: 26,
      height: 132,
      borderRadius: 13,
      background: 'linear-gradient(180deg, #2a2a2e, #0e0e10)',
      border: '1px solid rgba(255,255,255,0.12)',
      boxShadow: '0 12px 30px rgba(0,0,0,0.28)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 9,
    }}
  >
    <Spinner size={10} />
    <Dot color={C.idle} size={8} />
    <Dot color={C.waiting} size={8} />
    {attention ? <Dot color={C.attention} size={9} pulse /> : <Dot color={C.idle} size={8} />}
  </div>
);
