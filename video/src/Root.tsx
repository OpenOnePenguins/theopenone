import {Composition} from 'remotion';
import {Launch} from './Launch';
import {FPS, DURATION} from './timeline';

export const Root: React.FC = () => (
  <Composition id="Launch" component={Launch} durationInFrames={DURATION} fps={FPS} width={1920} height={1080} />
);
