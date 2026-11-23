(function () {
  'use strict';

  // Live progress of the job list / a single job.
  function poll(url, onData, ms) {
    function tick() {
      fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (d) { if (d) onData(d); })
        .catch(function () {})
        .finally(function () { setTimeout(tick, ms); });
    }
    setTimeout(tick, ms);
  }


  // ---- lightbox for the thumbnails of a job (prev / next / close, labelled | mask | original) ----------
  var lb = null;
  function buildLightbox() {
    var el = document.createElement('div');
    el.className = 'sl-overlay';
    el.innerHTML =
      '<div class="sl-bar"><span class="sl-count"></span><span class="sl-caption"></span>' +
      '<span class="sl-modes"></span><button type="button" class="sl-close" aria-label="Close">×</button></div>' +
      '<button type="button" class="sl-nav sl-prev" aria-label="Previous">‹</button>' +
      '<img class="sl-img" alt="">' +
      '<button type="button" class="sl-nav sl-next" aria-label="Next">›</button>';
    document.body.appendChild(el);
    lb = { el: el, img: el.querySelector('.sl-img'), items: [], i: 0, mode: 'labeled' };
    el.querySelector('.sl-close').addEventListener('click', closeLb);
    el.querySelector('.sl-prev').addEventListener('click', function () { stepLb(-1); });
    el.querySelector('.sl-next').addEventListener('click', function () { stepLb(1); });
    el.addEventListener('click', function (e) { if (e.target === el || e.target === lb.img) closeLb(); });
    document.addEventListener('keydown', function (e) {
      if (!lb || !lb.el.classList.contains('sl-open')) return;
      if (e.key === 'Escape') closeLb();
      else if (e.key === 'ArrowLeft') stepLb(-1);
      else if (e.key === 'ArrowRight') stepLb(1);
    });
  }
  function showLb() {
    var it = lb.items[lb.i];
    var mode = it.dataset['sl' + lb.mode.charAt(0).toUpperCase() + lb.mode.slice(1)] ? lb.mode : 'labeled';
    lb.img.src = it.dataset['sl' + mode.charAt(0).toUpperCase() + mode.slice(1)] || it.href;
    lb.el.querySelector('.sl-count').textContent = (lb.i + 1) + ' / ' + lb.items.length;
    lb.el.querySelector('.sl-caption').textContent = it.dataset.slCaption || '';
    var modes = lb.el.querySelector('.sl-modes');
    modes.innerHTML = '';
    [['labeled', 'Labelled'], ['mask', 'Mask'], ['source', 'Original']].forEach(function (m) {
      if (!it.dataset['sl' + m[0].charAt(0).toUpperCase() + m[0].slice(1)]) return;
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = m[1];
      if (m[0] === mode) b.className = 'sl-active';
      b.addEventListener('click', function () { lb.mode = m[0]; showLb(); });
      modes.appendChild(b);
    });
    lb.el.querySelector('.sl-prev').style.visibility = lb.items.length > 1 ? 'visible' : 'hidden';
    lb.el.querySelector('.sl-next').style.visibility = lb.items.length > 1 ? 'visible' : 'hidden';
  }
  function stepLb(d) { lb.i = (lb.i + d + lb.items.length) % lb.items.length; showLb(); }
  function openLb(items, i) {
    if (!lb) buildLightbox();
    lb.items = items; lb.i = i; lb.mode = 'labeled';
    lb.el.classList.add('sl-open');
    document.body.classList.add('sl-noscroll');
    showLb();
  }
  function closeLb() {
    lb.el.classList.remove('sl-open');
    document.body.classList.remove('sl-noscroll');
    lb.img.removeAttribute('src');
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-sl]');
    if (!a || e.ctrlKey || e.metaKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    var items = Array.prototype.slice.call(document.querySelectorAll('a[data-sl]'));
    openLb(items, items.indexOf(a));
  });

  var started = false;
  function init() {
    if (started) return;
    started = true;
    var list = document.getElementById('seismic-jobs');
    if (list) {
      poll(list.dataset.statusUrl, function (d) {
        d.jobs.forEach(function (j) {
          var tr = list.querySelector('tr[data-job-id="' + j.id + '"]');
          if (!tr) return;
          var st = tr.querySelector('.job-status span');
          st.textContent = j.status;
          st.className = 'seismic-badge seismic-' + j.status;
          tr.querySelector('.job-bar').style.width = j.percent + '%';
          tr.querySelector('.job-count').textContent = (j.done + j.failed) + '/' + j.total;
        });
      }, 5000);
    }

    var job = document.getElementById('seismic-job');
    if (job) {
      var last = null;
      poll(job.dataset.url, function (j) {
        document.getElementById('job-bar').style.width = j.percent + '%';
        document.getElementById('job-count').textContent = (j.done + j.failed) + '/' + j.total;
        var st = document.getElementById('job-status');
        st.textContent = j.status;
        st.className = 'seismic-badge seismic-' + j.status;
        // reload when a result finishes so the overlay thumbnails appear
        var sig = j.results.map(function (r) { return r.status; }).join(',');
        if (last !== null && sig !== last) window.location.reload();
        last = sig;
      }, 6000);
    }

    document.querySelectorAll('[data-seismic-import]').forEach(function (b) {
      b.addEventListener('click', function () {
        var ta = document.querySelector('textarea[name="aedes[' + b.dataset.seismicTarget + ']"]');
        if (ta) { ta.value = b.dataset.seismicImport; ta.closest('details').open = true; ta.focus(); }
      });
    });

    document.querySelectorAll('[data-seismic-dialog]').forEach(function (b) {
      b.addEventListener('click', function () {
        var d = document.getElementById(b.dataset.seismicDialog);
        if (d && d.showModal) d.showModal();
      });
    });
    document.querySelectorAll('[data-seismic-close]').forEach(function (b) {
      b.addEventListener('click', function () { b.closest('dialog').close(); });
    });

    // Shortcut on the Documents page.
    var meta = document.querySelector('meta[name="seismic-doc-link"]');
    if (meta) {
      var toolbar = document.querySelector('.toolbar-items') || document.querySelector('.toolbar');
      if (toolbar) {
        var li = document.createElement('li');
        li.className = 'toolbar-item';
        li.innerHTML = '<a class="button" href="' + meta.content + '">Analyse images for damage</a>';
        toolbar.appendChild(li);
      }
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
  document.addEventListener('turbo:load', function () { started = false; init(); });
})();
