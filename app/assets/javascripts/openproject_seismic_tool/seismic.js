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
