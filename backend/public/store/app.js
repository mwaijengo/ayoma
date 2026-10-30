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
    return Number.isNaN(d.getTime()) ? '' : `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  };
  const setText = (sel, value) => $$(sel).forEach((el) => { el.textContent = value; });

  $('[data-year]').textContent = new Date().getFullYear();

  let use32bit = /armv7|armv8l/i.test(ua) && !/aarch64|arm64/i.test(ua);
  const pickBuild = async () => {
    try {
      const hints = await navigator.userAgentData?.getHighEntropyValues?.(['bitness', 'architecture']);
      if (hints?.bitness === '32') use32bit = true;
    } catch (_) { /* hints are optional */ }
  };

  const applyRelease = (release) => {
    const main = release.files?.[use32bit ? 'armv7' : 'arm64'] ?? release.files?.arm64;
    if (main) {
      $$('[data-download]').forEach((a) => { a.href = main.file; });
      setText('[data-size]', mb(main.sizeBytes));
    }
    setText('[data-version]', release.version ?? '—');
    const when = date(release.updatedAt);
    setText('[data-updated]', when ? `Toleo ${release.version ?? '—'} · ${when}` : `Toleo ${release.version ?? '—'}`);

    const notes = release.notes ?? [];
    const list = $('[data-notes]');
    if (notes.length && list) {
      list.replaceChildren(...notes.map((n) => Object.assign(document.createElement('li'), { textContent: n })));
      $$('[data-whats-new]').forEach((el) => { el.hidden = false; });
    }
  };

  Promise.all([
    pickBuild(),
    fetch('/downloads/release.json', { cache: 'no-cache' }).then((r) => (r.ok ? r.json() : null)),
  ])
    .then(([, release]) => release && applyRelease(release))
    .catch(() => { /* links still point at the default files */ });

  fetch('/api/v1/store/support')
    .then((r) => (r.ok ? r.json() : null))
    .then((support) => {
      const number = String(support?.whatsapp ?? '').replace(/\D/g, '');
      if (!number) return;
      const text = encodeURIComponent('Habari AyomaMax, naomba msaada kudownload app.');
      $$('[data-whatsapp]').forEach((a) => {
        a.href = `https://wa.me/${number}?text=${text}`;
        a.hidden = false;
      });
    })
    .catch(() => { /* the help button stays hidden */ });

  const note = $('[data-device-note]');
  if (isIOS) {
    note.textContent = 'AyomaMax ni kwa simu za Android tu kwa sasa.';
    note.classList.add('warn');
  } else if (isAndroid) {
    note.textContent = 'Bonyeza Download. Kisha fuata picha za kuweka programu hapa chini.';
  }

  const modal = $('[data-modal]');
  $$('[data-download]').forEach((a) =>
    a.addEventListener('click', () => {
      if (!isAndroid) return;
      setTimeout(() => (modal.showModal ? modal.showModal() : null), 400);
    }),
  );

  const lightbox = $('[data-lightbox]');
  const lightboxImg = lightbox.querySelector('img');
  $$('.zoom').forEach((img) =>
    img.addEventListener('click', () => {
      lightboxImg.src = img.currentSrc || img.src;
      lightboxImg.alt = img.alt;
      lightbox.showModal();
    }),
  );
  lightbox.addEventListener('click', (event) => {
    if (event.target === lightbox.querySelector('.lightbox-close') || event.target === lightbox || event.target === lightboxImg) {
      lightbox.close();
    }
  });

  const toast = $('[data-toast]');
  let toastTimer;
  const showToast = (text) => {
    toast.textContent = text;
    toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.hidden = true; }, 2200);
  };
  $('[data-share]').addEventListener('click', async () => {
    const url = location.origin;
    const data = { title: 'AyomaMax', text: 'Tazama mpira moja kwa moja na AyomaMax. Download hapa:', url };
    try {
      if (navigator.share) {
        await navigator.share(data);
        return;
      }
    } catch (err) {
      if (err && err.name === 'AbortError') return;
    }
    try {
      await navigator.clipboard.writeText(url);
      showToast('Kiungo kimenakiliwa');
    } catch (_) {
      showToast(url);
    }
  });

  const sticky = $('[data-sticky]');
  const hero = $('.hero');
  if (sticky && hero && 'IntersectionObserver' in window && window.matchMedia('(max-width: 980px)').matches) {
    new IntersectionObserver(([entry]) => {
      sticky.hidden = entry.isIntersecting;
    }).observe(hero);
  }
})();
