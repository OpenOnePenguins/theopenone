// Scroll chooses the feature; each short interaction uses real SwiftUI renders.
(() => {
  const story = document.querySelector('.scroll-story');
  const stage = story.querySelector('.native-demo');
  const canvas = stage.querySelector('.native-canvas');
  const panelImage = stage.querySelector('.native-panel img');
  const compact = stage.querySelector('.native-toolbar-compact');
  const pointer = stage.querySelector('.native-pointer');
  const caption = story.querySelector('.native-caption');
  const chapters = [...story.querySelectorAll('.story-chapter')];
  const progress = [...story.querySelectorAll('.story-progress span')];
  const preference = matchMedia('(prefers-reduced-motion: reduce)');
  let current = -1, elapsed = 0, previous = null, frame = null, next = 0;
  let events = [], visible = false, scrollFrame = null;
  const descriptions = [
    'A sample pricing page with Open One’s small side button at the screen edge.',
    'In the native Inbox, choose Three tiers. The agent starts working.',
    'Switch from Claude’s pricing-page conversation to Codex’s checkout work in the same Inbox.',
    'Review the finished result in Inbox, then see the completed three-tier pricing page.'
  ];
  const captions = [
    'Your page, with Open One at the edge.',
    'Choose an answer. Your agent carries on.',
    'Different agents. One place to follow the work.',
    'Finished work, ready to review.'
  ];
  ['inbox-question','inbox-pending','inbox-working','inbox-codex','inbox-done','toolbar-collapsed','toolbar-expanded','toolbar-working','toolbar-done'].forEach(name => {
    const image = new Image(); image.src = `assets/native/${name}.png`;
  });
  function fit() {
    const mobile = innerWidth <= 760;
    const pageView = mobile && (current === 0 || current === 3);
    const overview = mobile && current === 2;
    const scale = stage.clientWidth / (pageView ? 1180 : overview ? 1020 : mobile ? 690 : 1180);
    canvas.style.transform = `scale(${scale})`;
    canvas.style.left = mobile && !pageView ? `${-(overview ? 160 : 490) * scale}px` : '0';
    canvas.style.top = mobile && !overview && !pageView ? `${-140 * scale}px` : '0';
    stage.style.height = `${(mobile && !overview && !pageView ? 580 : 780) * scale}px`;
  }
  new ResizeObserver(fit).observe(stage); fit();
  function image(name) { panelImage.src = `assets/native/${name}.png`; }
  function cursor(x, y, click = false) {
    pointer.style.left = `${x}px`; pointer.style.top = `${y}px`;
    stage.classList.add('show-pointer');
    pointer.classList.toggle('native-click', click);
  }
  function finish() { stage.classList.remove('show-pointer'); }
  function select(index) {
    current = index; elapsed = 0; next = 0; previous = null;
    chapters.forEach((chapter, i) => chapter.classList.toggle('is-active', i === index));
    progress.forEach((item, i) => item.classList.toggle('is-active', i === index));
    stage.dataset.scene = chapters[index].dataset.scene;
    fit();
    stage.setAttribute('aria-label', descriptions[index]);
    caption.textContent = captions[index];
    stage.classList.remove('show-panel','show-toolbar','show-pointer','native-completed');
    stage.classList.toggle('pricing-ready', index === 3);
    pointer.classList.remove('native-click');
    compact.src = 'assets/native/toolbar-collapsed.png';
    image('inbox-question');
    if (index === 0) {
      // Hold the quiet opening until the reader reaches the next chapter.
      events = [];
    } else if (index === 1) {
      cursor(1010,460);
      events = [
        [150, () => cursor(1171,350)],
        [750, () => stage.classList.add('show-toolbar')],
        [950, () => cursor(1152,237)],
        [1550, () => { cursor(1152,237,true); stage.classList.add('show-panel'); }],
        [1850, () => cursor(735,440)],
        [2450, () => { cursor(735,440,true); image('inbox-pending'); }],
        [4450, () => { image('inbox-working'); finish(); }]
      ];
    } else if (index === 2) {
      stage.classList.add('show-panel','show-toolbar');
      image('inbox-working'); cursor(800,550);
      events = [
        [300, () => cursor(330,520)],
        [950, () => { cursor(330,520,true); image('inbox-codex'); }],
        [2200, finish]
      ];
    } else {
      compact.src = 'assets/native/toolbar-done.png';
      image('inbox-done'); cursor(1010,460);
      events = [
        [200, () => cursor(1171,350)],
        [850, () => stage.classList.add('show-toolbar')],
        [1050, () => cursor(1152,237)],
        [1750, () => { cursor(1152,237,true); stage.classList.add('show-panel'); }],
        [2950, () => cursor(105,160)],
        [3550, () => { cursor(105,160,true); stage.classList.remove('show-panel','show-toolbar'); }],
        [4050, () => { finish(); caption.textContent = 'Three tiers. One recommended plan. Ready to go.'; } ]
      ];
    }
    if (preference.matches) {
      if (index > 0 && index < 3) stage.classList.add('show-panel','show-toolbar');
      if (index === 2) image('inbox-codex');
      finish(); next = events.length;
    }
    clock();
  }
  function tick(now) {
    if (previous !== null) elapsed += Math.min(now - previous, 100);
    previous = now;
    while (next < events.length && elapsed >= events[next][0]) events[next++][1]();
    frame = next < events.length ? requestAnimationFrame(tick) : null;
  }
  function clock() {
    cancelAnimationFrame(frame); frame = null; previous = null;
    if (visible && !document.hidden && !preference.matches && next < events.length) frame = requestAnimationFrame(tick);
  }
  function onScroll() {
    scrollFrame = null;
    // On phones the copy lives below the sticky screen; on desktop, beside it.
    const line = innerWidth <= 760 ? innerHeight * .82 : innerHeight * .55;
    let index = 0;
    chapters.forEach((chapter, i) => { if (chapter.getBoundingClientRect().top <= line) index = i; });
    const bounds = stage.getBoundingClientRect();
    const nowVisible = bounds.bottom > innerHeight * .2 && bounds.top < innerHeight * .8;
    if (nowVisible !== visible) { visible = nowVisible; clock(); }
    if (index !== current) select(index);
  }
  function scheduleScroll() { if (scrollFrame === null) scrollFrame = requestAnimationFrame(onScroll); }
  addEventListener('scroll', scheduleScroll, {passive:true});
  addEventListener('resize', scheduleScroll);
  document.addEventListener('visibilitychange', clock);
  preference.addEventListener('change', () => select(Math.max(0, current)));
  onScroll();
})();
