(() => {
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);
  const ua = navigator.userAgent;
  const isAndroid = /Android/i.test(ua);
  const isIOS = /iPhone|iPad|iPod/i.test(ua);

  const MONTHS = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];
  const mb = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;
  const date = (iso) => {
    const d = new Date(iso);
    return Number.isNaN(d.getTime()) ? '—' : `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  };
  const setText = (sel, value) => $$(sel).forEach((el) => { el.textContent = value; });

  $('[data-year]').textContent = new Date().getFullYear();

  // 32-bit phones need the armv7 build; Chrome reports this via client hints.
  let use32bit = /armv7|armv8l/i.test(ua) && !/aarch64|arm64/i.test(ua);
  const pickBuild = async () => {
    try {
      const hints = await navigator.userAgentData?.getHighEntropyValues?.(['bitness', 'architecture']);
      if (hints?.bitness === '32') use32bit = true;
    } catch (_) { /* hints are optional */ }
  };

  const applyRelease = (release) => {
    const main = release.files?.[use32bit ? 'armv7' : 'arm64'] ?? release.files?.arm64;
    const alt = release.files?.armv7;
    if (main) {
      $$('[data-download]').forEach((a) => { a.href = main.file; });
      setText('[data-size]', mb(main.sizeBytes));
    }
    $$('[data-download-alt]').forEach((a) => { if (alt) a.href = alt.file; });
    setText('[data-version]', release.version ?? '—');
    setText('[data-date]', date(release.updatedAt));

    const notes = release.notes ?? [];
    const list = $('[data-notes]');
    if (notes.length && list) {
      list.replaceChildren(...notes.map((n) => Object.assign(document.createElement('li'), { textContent: n })));
      setText('[data-updated]', `Imesasishwa ${date(release.updatedAt)}`);
      $$('[data-whats-new]').forEach((el) => { el.hidden = false; });
    }
  };

  Promise.all([pickBuild(), fetch('/downloads/release.json', { cache: 'no-cache' }).then((r) => (r.ok ? r.json() : null))])
    .then(([, release]) => release && applyRelease(release))
    .catch(() => { /* links still point at the default files */ });

  // Device note under the button.
  const note = $('[data-device-note]');
  if (isIOS) {
    note.textContent = 'AyomaMax ni kwa simu za Android tu kwa sasa.';
    note.classList.add('warn');
  } else if (!isAndroid) {
    note.textContent = 'Fungua ukurasa huu kwenye simu yako ya Android ili kuinstall.';
  }

  // Install help after the download starts.
  const modal = $('[data-modal]');
  $$('[data-download], [data-download-alt]').forEach((a) =>
    a.addEventListener('click', () => {
      if (!isAndroid) return;
      setTimeout(() => (modal.showModal ? modal.showModal() : null), 400);
    }),
  );

  // Tap a screenshot to view it full size.
  const lightbox = $('[data-lightbox]');
  const lightboxImg = lightbox.querySelector('img');
  $$('.shot img').forEach((img) =>
    img.addEventListener('click', () => {
      lightboxImg.src = img.src;
      lightboxImg.alt = img.alt;
      lightbox.showModal();
    }),
  );
  lightbox.addEventListener('click', () => lightbox.close());

  // Share the store link.
  const toast = $('[data-toast]');
  let toastTimer;
  const showToast = (text) => {
    toast.textContent = text;
    toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.hidden = true; }, 2200);
  };
  $('[data-share]').addEventListener('click', async () => {
    const data = { title: 'AyomaMax', text: 'Tazama mpira mubashara na AyomaMax. Pakua hapa:', url: location.origin };
    try {
      if (navigator.share) {
        await navigator.share(data);
      } else {
        await navigator.clipboard.writeText(data.url);
        showToast('Kiungo kimenakiliwa');
      }
    } catch (_) { /* user cancelled */ }
  });

  // Sticky install bar once the main button scrolls away (phones only).
  const sticky = $('[data-sticky]');
  const mainButton = $('.hero [data-download]');
  if ('IntersectionObserver' in window && window.matchMedia('(max-width: 860px)').matches) {
    new IntersectionObserver(([entry]) => { sticky.hidden = entry.isIntersecting; }).observe(mainButton);
  }
})();
