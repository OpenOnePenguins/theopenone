import {Config} from '@remotion/cli/config';

// WebGL scenes need a real GPU-backed context in headless Chrome.
Config.setChromiumOpenGlRenderer('angle');
Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(95);
