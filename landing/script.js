// Motion is progressive enhancement: content is visible without JavaScript.
// CSS handles each frame; observers only mark entrances and pause offscreen loops.
const motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
let motionPaused = motionPreference.matches;
const revealTargets = [...document.querySelectorAll(
  '.section-heading, .feature, .details-row > div, .start-layout > div, .faq > div, .closing .wrap'
)];

function syncMotion() {
  const paused = motionPaused || motionPreference.matches;
  document.body.classList.toggle('motion-enabled', !paused);
  document.body.classList.toggle('motion-paused', paused);
  if (paused) revealTargets.forEach(element => element.classList.remove('reveal-pending'));
  document.dispatchEvent(new CustomEvent('openone:motionchange', {detail:{paused}}));
}

motionPreference.addEventListener('change', () => {
  motionPaused = motionPreference.matches;
  syncMotion();
});
syncMotion();

if ('IntersectionObserver' in window) {
  const reveals = new IntersectionObserver(entries => {
    entries.forEach(({ target, isIntersecting }) => {
      if (!isIntersecting) return;
      target.classList.remove('reveal-pending');
      target.classList.add('is-revealed');
      reveals.unobserve(target);
    });
  }, { threshold: 0.08 });

  revealTargets.forEach(element => {
    element.classList.add('reveal');
    if (!motionPaused && element.getBoundingClientRect().top >= window.innerHeight) {
      element.classList.add('reveal-pending');
    }
    reveals.observe(element);
  });
  document.querySelectorAll('.feature, .details-row > div').forEach((element, index) => {
    element.style.setProperty('--reveal-delay', `${(index % 3) * 100}ms`);
  });

  const zones = new IntersectionObserver(entries => {
    entries.forEach(({ target, isIntersecting }) => target.classList.toggle('motion-in-view', isIntersecting));
  }, { threshold: 0 });
  document.querySelectorAll('.hero-landscape, .hero, .feature-art, .closing').forEach(zone => zones.observe(zone));
}

// Keyboard navigation must never land on an invisible scroll-reveal target.
document.addEventListener('focusin', event => {
  event.target.closest('.reveal-pending')?.classList.remove('reveal-pending');
});

document.getElementById('copy-command').addEventListener('click', async () => {
  const status = document.getElementById('copy-status');
  try {
    await navigator.clipboard.writeText('bash scripts/build.sh\nopen "dist/Open One.app"');
    status.textContent = 'Copied. Run these from your The Open One checkout.';
  } catch { status.textContent = 'Select and copy the two commands above.'; }
});
