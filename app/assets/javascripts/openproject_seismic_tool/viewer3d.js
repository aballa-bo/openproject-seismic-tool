/* Seismic tool - "Crack modelling": minimal WebGL viewer for the point cloud / mesh (binary PLY),
   plus live status polling of a queued reconstruction. No external dependency. */
(function () {
  'use strict';

  // ---- PLY (binary little endian: x y z float, r g b uchar; optional triangle faces) ----
  function parsePly(buf) {
    var u8 = new Uint8Array(buf), end = -1, i;
    for (i = 0; i < Math.min(u8.length, 4096); i++) {
      if (u8[i] === 10 && String.fromCharCode.apply(null, u8.subarray(Math.max(0, i - 10), i)) === 'end_header') { end = i + 1; break; }
    }
    if (end < 0) throw new Error('bad PLY header');
    var head = String.fromCharCode.apply(null, u8.subarray(0, end));
    var nv = +(/element vertex (\d+)/.exec(head) || [0, 0])[1];
    var nf = +(/element face (\d+)/.exec(head) || [0, 0])[1];
    var dv = new DataView(buf, end), pos = new Float32Array(nv * 3), col = new Uint8Array(nv * 3), o;
    for (i = 0; i < nv; i++) {
      o = i * 15;
      pos[3 * i] = dv.getFloat32(o, true); pos[3 * i + 1] = dv.getFloat32(o + 4, true); pos[3 * i + 2] = dv.getFloat32(o + 8, true);
      col[3 * i] = dv.getUint8(o + 12); col[3 * i + 1] = dv.getUint8(o + 13); col[3 * i + 2] = dv.getUint8(o + 14);
    }
    var idx = null;
    if (nf) {
      idx = new Uint32Array(nf * 3);
      o = nv * 15;
      for (i = 0; i < nf; i++, o += 13) {
        idx[3 * i] = dv.getInt32(o + 1, true); idx[3 * i + 1] = dv.getInt32(o + 5, true); idx[3 * i + 2] = dv.getInt32(o + 9, true);
      }
    }
    return { pos: pos, col: col, idx: idx, n: nv };
  }

  // ---- tiny matrix helpers (column-major) ----
  function mul(a, b) {
    var r = new Float32Array(16);
    for (var c = 0; c < 4; c++) for (var row = 0; row < 4; row++) {
      var s = 0;
      for (var k = 0; k < 4; k++) s += a[k * 4 + row] * b[c * 4 + k];
      r[c * 4 + row] = s;
    }
    return r;
  }
  function persp(fov, asp, n, f) {
    var t = 1 / Math.tan(fov / 2), m = new Float32Array(16);
    m[0] = t / asp; m[5] = t; m[10] = (f + n) / (n - f); m[11] = -1; m[14] = 2 * f * n / (n - f);
    return m;
  }
  function trans(x, y, z) { var m = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]); return m; }
  function rotX(a) { var c = Math.cos(a), s = Math.sin(a); return new Float32Array([1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1]); }
  function rotY(a) { var c = Math.cos(a), s = Math.sin(a); return new Float32Array([c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1]); }

  function Viewer(box) {
    var canvas = box.querySelector('canvas'), msg = box.querySelector('.sv-msg');
    var gl = canvas.getContext('webgl', { antialias: true });
    if (!gl) { msg.textContent = 'WebGL is not available in this browser: download the files and open them in MeshLab or Blender.'; return; }
    var uint = gl.getExtension('OES_element_index_uint');
    var vs = 'attribute vec3 p;attribute vec3 c;uniform mat4 m;uniform float ps;varying vec3 vc;' +
             'void main(){gl_Position=m*vec4(p,1.);gl_PointSize=ps;vc=c;}';
    var fs = 'precision mediump float;varying vec3 vc;void main(){gl_FragColor=vec4(vc,1.);}';
    function sh(t, s) { var o = gl.createShader(t); gl.shaderSource(o, s); gl.compileShader(o); return o; }
    var prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(prog); gl.useProgram(prog);
    var aP = gl.getAttribLocation(prog, 'p'), aC = gl.getAttribLocation(prog, 'c');
    var uM = gl.getUniformLocation(prog, 'm'), uS = gl.getUniformLocation(prog, 'ps');
    gl.enable(gl.DEPTH_TEST);

    var layers = {}, show = { points: true, mesh: false };
    var cam = { yaw: 0, pitch: 0, dist: 3, cx: 0, cy: 0, cz: 0, panX: 0, panY: 0, radius: 1 };
    var psize = 2;

    function upload(name, ply) {
      var L = { n: ply.n, ni: ply.idx ? ply.idx.length : 0 };
      L.pb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, L.pb); gl.bufferData(gl.ARRAY_BUFFER, ply.pos, gl.STATIC_DRAW);
      var cf = new Float32Array(ply.col.length);
      for (var i = 0; i < cf.length; i++) cf[i] = ply.col[i] / 255;
      L.cb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, L.cb); gl.bufferData(gl.ARRAY_BUFFER, cf, gl.STATIC_DRAW);
      if (ply.idx && uint) { L.ib = gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, L.ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, ply.idx, gl.STATIC_DRAW); }
      layers[name] = L;
    }
    function frame(pos) {
      var mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
      for (var i = 0; i < pos.length; i += 3) for (var k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], pos[i + k]); mx[k] = Math.max(mx[k], pos[i + k]); }
      cam.cx = (mn[0] + mx[0]) / 2; cam.cy = (mn[1] + mx[1]) / 2; cam.cz = (mn[2] + mx[2]) / 2;
      cam.radius = Math.hypot(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]) / 2 || 1;
      resetView();
    }
    function resetView() { cam.yaw = 0; cam.pitch = 0; cam.panX = 0; cam.panY = 0; cam.dist = cam.radius * 2.3; draw(); }

    function draw() {
      var w = canvas.clientWidth, h = canvas.clientHeight, dpr = window.devicePixelRatio || 1;
      if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr); }
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.clearColor(0.13, 0.15, 0.17, 1); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      var view = mul(trans(cam.panX, cam.panY, -cam.dist), mul(rotX(cam.pitch), mul(rotY(cam.yaw), trans(-cam.cx, -cam.cy, -cam.cz))));
      var mvp = mul(persp(0.8, w / Math.max(h, 1), cam.radius * 0.02, cam.radius * 30), view);
      gl.uniformMatrix4fv(uM, false, mvp);
      gl.uniform1f(uS, psize * dpr);
      function bind(L) {
        gl.bindBuffer(gl.ARRAY_BUFFER, L.pb); gl.enableVertexAttribArray(aP); gl.vertexAttribPointer(aP, 3, gl.FLOAT, false, 0, 0);
        gl.bindBuffer(gl.ARRAY_BUFFER, L.cb); gl.enableVertexAttribArray(aC); gl.vertexAttribPointer(aC, 3, gl.FLOAT, false, 0, 0);
      }
      if (show.mesh && layers.mesh && layers.mesh.ib) {
        bind(layers.mesh); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, layers.mesh.ib);
        gl.drawElements(gl.TRIANGLES, layers.mesh.ni, gl.UNSIGNED_INT, 0);
      }
      if (show.points && layers.points) { bind(layers.points); gl.drawArrays(gl.POINTS, 0, layers.points.n); }
    }

    // ---- interaction ----
    var drag = null;
    canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
    canvas.addEventListener('pointerdown', function (e) {
      drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey }; canvas.setPointerCapture(e.pointerId);
    });
    canvas.addEventListener('pointerup', function () { drag = null; });
    canvas.addEventListener('pointermove', function (e) {
      if (!drag) return;
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y; drag.x = e.clientX; drag.y = e.clientY;
      if (drag.pan) { var k = cam.dist / canvas.clientHeight; cam.panX += dx * k; cam.panY -= dy * k; }
      else { cam.yaw += dx * 0.008; cam.pitch = Math.max(-1.5, Math.min(1.5, cam.pitch + dy * 0.008)); }
      draw();
    });
    canvas.addEventListener('wheel', function (e) {
      e.preventDefault(); cam.dist = Math.max(cam.radius * 0.3, Math.min(cam.radius * 12, cam.dist * Math.exp(e.deltaY * 0.001))); draw();
    }, { passive: false });
    window.addEventListener('resize', draw);

    box.querySelectorAll('[data-sv]').forEach(function (b) {
      b.addEventListener('click', function () {
        var v = b.dataset.sv;
        if (v === 'reset') return resetView();
        show.points = v === 'points' || v === 'both'; show.mesh = v === 'mesh' || v === 'both';
        box.querySelectorAll('[data-sv]').forEach(function (x) { x.classList.toggle('sv-active', x.dataset.sv === v); });
        draw();
      });
    });
    var range = box.querySelector('.sv-psize');
    if (range) range.addEventListener('input', function () { psize = +range.value; draw(); });

    function load(url, name) {
      return fetch(url, { credentials: 'same-origin' }).then(function (r) { if (!r.ok) throw new Error(r.status); return r.arrayBuffer(); })
        .then(function (b) { var p = parsePly(b); upload(name, p); return p; });
    }
    load(box.dataset.points, 'points').then(function (p) {
      frame(p.pos); msg.style.display = 'none';
      return box.dataset.mesh ? load(box.dataset.mesh, 'mesh').then(function () { box.querySelector('[data-sv="mesh"]').disabled = !layers.mesh.ib; box.querySelector('[data-sv="both"]').disabled = !layers.mesh.ib; draw(); }) : null;
    }).catch(function (e) { msg.textContent = 'Could not load the 3D data (' + e.message + ').'; });
  }

  function init() {
    var box = document.getElementById('seismic-viewer');
    if (box && !box.dataset.ready) { box.dataset.ready = '1'; Viewer(box); }
    var job = document.getElementById('seismic-model');
    if (job && job.dataset.active === 'true' && !job.dataset.polling) {
      job.dataset.polling = '1';
      (function tick() {
        fetch(job.dataset.url, { credentials: 'same-origin', headers: { Accept: 'application/json' } })
          .then(function (r) { return r.ok ? r.json() : null; })
          .then(function (d) {
            if (d && !d.active) { window.location.reload(); return; }
            if (d) { var s = document.getElementById('model-status'); if (s) { s.textContent = d.status; s.className = 'seismic-badge seismic-' + d.status; } }
            setTimeout(tick, 4000);
          }).catch(function () { setTimeout(tick, 8000); });
      })();
    }
  }
  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
  init();
})();

/* Polygon selection on the chosen image (Crack modelling > new): a dot per click, a line from the last
   dot to the pointer, the first dot changes colour on hover, a click on it closes the polygon. */
(function () {
  'use strict';
  function init() {
    var box = document.getElementById('seismic-poly');
    if (!box || box.dataset.ready) return;
    box.dataset.ready = '1';
    var cv = box.querySelector('canvas'), ctx = cv.getContext('2d');
    var input = document.getElementById('seismic-poly-input'), stateEl = document.getElementById('seismic-poly-state');
    var form = box.closest('form'), img = new Image();
    var pts = [], closed = false, mouse = null, hoverFirst = false, R = 5;

    function state() {
      var t = !img.src ? '' : closed ? 'Polygon closed (' + pts.length + ' points).' :
        pts.length ? 'Click the first point to close the polygon.' : 'Whole image (no polygon).';
      stateEl.textContent = t;
      input.value = closed ? JSON.stringify(pts) : '';
    }
    function px(p) { return [p[0] * cv.width, p[1] * cv.height]; }
    function draw() {
      if (!img.complete || !cv.width) return;
      ctx.clearRect(0, 0, cv.width, cv.height);
      ctx.drawImage(img, 0, 0, cv.width, cv.height);
      var lw = Math.max(2, cv.width / 500), r = Math.max(R, cv.width / 150);
      if (pts.length) {
        ctx.beginPath();
        pts.forEach(function (p, i) { var q = px(p); i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]); });
        if (closed) { ctx.closePath(); ctx.fillStyle = 'rgba(255,200,0,0.22)'; ctx.fill(); }
        else if (mouse) ctx.lineTo(mouse[0], mouse[1]);
        ctx.lineWidth = lw; ctx.strokeStyle = '#ffd400'; ctx.stroke();
        pts.forEach(function (p, i) {
          var q = px(p);
          ctx.beginPath(); ctx.arc(q[0], q[1], r, 0, 2 * Math.PI);
          ctx.fillStyle = (i === 0 && hoverFirst) ? '#ff7a00' : '#ffffff'; ctx.fill();
          ctx.lineWidth = 1.5; ctx.strokeStyle = '#000'; ctx.stroke();
        });
      }
    }
    function pos(e) {
      var b = cv.getBoundingClientRect();
      return [(e.clientX - b.left) * cv.width / b.width, (e.clientY - b.top) * cv.height / b.height];
    }
    function nearFirst(m) {
      if (!pts.length || closed || pts.length < 3) return false;
      var q = px(pts[0]), r = Math.max(R, cv.width / 150) * 1.8;
      return Math.hypot(m[0] - q[0], m[1] - q[1]) <= r;
    }
    cv.addEventListener('mousemove', function (e) {
      mouse = pos(e); var h = nearFirst(mouse);
      if (h !== hoverFirst) { hoverFirst = h; cv.style.cursor = h ? 'pointer' : 'crosshair'; }
      if (!closed) draw();
    });
    cv.addEventListener('mouseleave', function () { mouse = null; hoverFirst = false; draw(); });
    cv.addEventListener('click', function (e) {
      if (closed) return;
      var m = pos(e);
      if (nearFirst(m)) { closed = true; hoverFirst = false; cv.style.cursor = 'default'; }
      else pts.push([+(m[0] / cv.width).toFixed(5), +(m[1] / cv.height).toFixed(5)]);
      state(); draw();
    });
    function reset() { pts = []; closed = false; hoverFirst = false; cv.style.cursor = 'crosshair'; state(); draw(); }
    document.getElementById('seismic-poly-cancel').addEventListener('click', reset);
    form.addEventListener('submit', function (e) {
      if (pts.length && !closed) {
        e.preventDefault();
        alert('Close the polygon by clicking its first point, or press "Cancel polygon" to use the whole image.');
      }
    });

    function show(url) {
      reset();
      img.onload = function () {
        var w = Math.min(img.naturalWidth, 1400);
        cv.width = w; cv.height = Math.round(w * img.naturalHeight / img.naturalWidth);
        box.classList.add('sp-ready'); state(); draw();
      };
      img.src = url;
    }
    var radios = form.querySelectorAll('input[name="attachment_id"]');
    radios.forEach(function (r) {
      r.addEventListener('change', function () { show(r.closest('label').querySelector('img').src); });
      if (r.checked) show(r.closest('label').querySelector('img').src);
    });
  }
  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
  init();
})();
