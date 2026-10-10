import {useEffect, useRef} from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig, continueRender, delayRender} from 'remotion';

// Procedural "footage" for the polar opener and end card. Each shader is a function of time only,
// so every frame renders deterministically. Drop a matching MP4 into public/footage/ to replace one.

const VERT = `attribute vec2 p; void main(){ gl_Position = vec4(p, 0., 1.); }`;

const COMMON = `
precision highp float;
uniform vec2 R; uniform float t;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p), f = fract(p); f = f*f*(3.-2.*f);
  return mix(mix(h(i), h(i+vec2(1,0)), f.x), mix(h(i+vec2(0,1)), h(i+vec2(1,1)), f.x), f.y); }
float fbm(vec2 p){ float v = 0., a = .5; for(int i = 0; i < 6; i++){ v += a*n(p); p = p*2.03 + 17.; a *= .5; } return v; }
vec2 vor(vec2 p){ vec2 i = floor(p), f = fract(p); float d1 = 8., d2 = 8.;
  for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++){ vec2 g = vec2(x,y); vec2 o = vec2(h(i+g), h(i+g+5.3));
    float d = length(g + o - f); if(d < d1){ d2 = d1; d1 = d; } else if(d < d2) d2 = d; }
  return vec2(d1, d2); }
vec3 grade(vec3 c, vec2 uv){ float g = h(uv*R + fract(t)*91.) - .5; c += g*.035;
  float v = smoothstep(1.25, .35, length((uv-.5)*vec2(1.25,1.))); return c*mix(.72, 1., v); }
`;

export const SHADERS: Record<string, string> = {
  // Backlit glacial ice, warm amber: the Claude Code shot.
  amber: `${COMMON}
  void main(){ vec2 uv = gl_FragCoord.xy/R; vec2 p = (gl_FragCoord.xy - .5*R)/R.y;
    float z = 1.0 - t*.045; p *= z * 2.4; p += vec2(.15, .05)*t;
    vec2 v = vor(p*1.6 + fbm(p*2.)*.6); float edge = smoothstep(.0, .09, v.y - v.x);
    float bands = sin((fbm(p*1.3)*9. + v.x*6.) ) * .5 + .5;
    vec3 deep = vec3(.42,.16,.06), warm = vec3(.98,.55,.24), cream = vec3(1.,.9,.78), ice = vec3(.78,.84,.9);
    vec3 c = mix(deep, warm, bands); c = mix(c, cream, pow(bands, 6.)*.8);
    c = mix(ice*.9, c, smoothstep(.15, .75, fbm(p*.7 + 3.)));
    c *= .55 + .45*edge; c += (1.-edge)*vec3(1.,.82,.6)*.35;
    float glow = exp(-length(p - vec2(.9, .7))*.9); c += vec3(1.,.7,.4)*glow*.35;
    float blur = smoothstep(.2, 1.2, length((uv-.5)*vec2(1.6,1.))); c = mix(c, vec3(.86,.68,.55), blur*.35);
    gl_FragColor = vec4(grade(c, uv), 1.); }`,

  // Aerial over an ice shelf meeting deep water: the Codex shot.
  shelf: `${COMMON}
  void main(){ vec2 uv = gl_FragCoord.xy/R; vec2 p = (gl_FragCoord.xy - .5*R)/R.y;
    float persp = 1. / (1.25 - uv.y*.75); vec2 w = vec2(p.x*persp, persp*2.) + vec2(0., t*.35);
    float coast = fbm(vec2(w.x*1.2, w.y*.4)) - .48 + p.x*.55;
    float ice = smoothstep(-.01, .01, coast);
    vec3 sea = mix(vec3(.02,.12,.25), vec3(.05,.26,.42), fbm(w*3. + t*.2));
    sea += vec3(.6,.8,1.)*pow(n(w*28. + t), 12.)*.25;
    float crev = fbm(w*vec2(9., 3.)); vec3 snow = mix(vec3(.82,.88,.95), vec3(.98,.99,1.), crev);
    snow *= .86 + .14*smoothstep(.0, .3, coast);
    vec3 c = mix(sea, snow, ice); float cliff = smoothstep(.0, .03, coast) - smoothstep(.03, .06, coast); c = mix(c, vec3(.55,.75,.9), cliff*.6);
    float sky = smoothstep(.72, 1., uv.y); c = mix(c, vec3(.82,.88,.94), sky*.85);
    float haze = smoothstep(.45, .95, uv.y); c = mix(c, vec3(.78,.86,.93), haze*.35);
    gl_FragColor = vec4(grade(c, uv), 1.); }`,

  // Golden hour over a windswept snowy plain: the closing card.
  field: `${COMMON}
  void main(){ vec2 uv = gl_FragCoord.xy/R; vec2 p = (gl_FragCoord.xy - .5*R)/R.y;
    vec2 sun = vec2(.38, -.08 - t*.004); float horizon = -.2 + fbm(vec2(p.x*2., 1.))*.04;
    vec3 sky = mix(vec3(.98,.70,.46), vec3(.46,.42,.56), smoothstep(-.2, .55, p.y));
    sky = mix(sky, vec3(1.,.8,.66), exp(-length(p - sun)*3.)*.7);
    float g = horizon - p.y; float persp = 1./(g + .05);
    float drift = fbm(vec2(p.x*persp*.5 + t*.25, persp*1.5)); vec3 snow = mix(vec3(.62,.55,.6), vec3(1.,.86,.72), drift);
    snow = mix(snow, vec3(1.,.8,.55), exp(-abs(p.x - sun.x)*2.5)*smoothstep(.3, .0, g)*.6);
    vec3 c = p.y > horizon ? sky : snow;
    float spray = fbm(vec2(p.x*3. - t*.6, p.y*8.)) * smoothstep(.12, -.02, abs(p.y - horizon)); c = mix(c, vec3(1.,.9,.78), spray*.35);
    c = mix(c, vec3(1.,.78,.62), exp(-length(p - sun)*1.6)*.25);
    vec2 q = p - vec2(-.42, horizon - .012); float body = length(q*vec2(1.6,1.)) - .012; float head = length(q - vec2(0., .019)) - .0075;
    c = mix(vec3(.08,.07,.09), c, smoothstep(0., .002, min(body, head)));
    gl_FragColor = vec4(grade(c, uv), 1.); }`,
};

export const ShaderScene: React.FC<{name: keyof typeof SHADERS; speed?: number}> = ({name, speed = 1}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const canvas = useRef<HTMLCanvasElement>(null);
  const state = useRef<{gl: WebGLRenderingContext; loc: WebGLUniformLocation | null; res: WebGLUniformLocation | null} | null>(null);

  useEffect(() => {
    const gl = canvas.current!.getContext('webgl', {preserveDrawingBuffer: true, antialias: false})!;
    const compile = (type: number, src: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s) ?? 'shader');
      return s;
    };
    const prog = gl.createProgram()!;
    gl.attachShader(prog, compile(gl.VERTEX_SHADER, VERT));
    gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, SHADERS[name]));
    gl.linkProgram(prog); gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const pos = gl.getAttribLocation(prog, 'p');
    gl.enableVertexAttribArray(pos); gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);
    state.current = {gl, loc: gl.getUniformLocation(prog, 't'), res: gl.getUniformLocation(prog, 'R')};
  }, [name]);

  useEffect(() => {
    const handle = delayRender();
    const s = state.current;
    if (s) {
      s.gl.viewport(0, 0, s.gl.drawingBufferWidth, s.gl.drawingBufferHeight);
      s.gl.uniform2f(s.res, s.gl.drawingBufferWidth, s.gl.drawingBufferHeight);
      s.gl.uniform1f(s.loc, (frame / fps) * speed);
      s.gl.drawArrays(s.gl.TRIANGLES, 0, 3);
    }
    continueRender(handle);
  }, [frame, fps, speed]);

  // Render at device resolution so a --scale=2 render stays sharp.
  const dpr = typeof window === 'undefined' ? 1 : window.devicePixelRatio || 1;
  return (
    <AbsoluteFill>
      <canvas ref={canvas} width={width * dpr} height={height * dpr} style={{width: '100%', height: '100%'}} />
    </AbsoluteFill>
  );
};
