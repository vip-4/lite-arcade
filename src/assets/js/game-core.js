/* =================================================================
   Lite Arcade — 游戏内核（零依赖）
   提供：DPR 自适应画布、固定步长主循环、键盘/触屏输入、分数与最高分、
        暂停/重开/遮罩层。所有游戏共用，避免重复代码。
   ================================================================= */
(function (global) {
  'use strict';

  var TAU = Math.PI * 2;

  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
  function randInt(a, b) { return a + Math.floor(Math.random() * (b - a + 1)); }
  function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

  /**
   * 创建一个游戏实例
   * @param {Object} cfg 配置
   * @param {HTMLCanvasElement} cfg.canvas
   * @param {number} cfg.width  逻辑宽
   * @param {number} cfg.height 逻辑高
   * @param {string} cfg.storageKey localStorage 键（用于最高分）
   * @param {number} [cfg.tick] 固定逻辑步长（毫秒）；不传则按帧率更新
   * @param {Function} cfg.reset  重置状态
   * @param {Function} cfg.update (dt) 每步逻辑更新
   * @param {Function} cfg.draw   (ctx) 绘制
   * @param {Function} [cfg.onKey]    (key) 键盘事件，key 为 'ArrowUp' 等或自定义字符串
   * @param {Function} [cfg.onTap]    (x, y) 点击/触摸逻辑坐标
   * @param {Function} [cfg.onSwipe]  (dir) 'up'|'down'|'left'|'right'
   * @param {Function} [cfg.onDrag]   (x, y) 拖动逻辑坐标
   */
  function create(cfg) {
    var canvas = cfg.canvas;
    if (!canvas) throw new Error('game-core: 缺少 canvas');
    var ctx = canvas.getContext('2d');

    var W = cfg.width, H = cfg.height;
    var dpr = clamp(global.devicePixelRatio || 1, 1, 2);

    function resize() {
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      canvas.style.aspectRatio = W + ' / ' + H;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.imageSmoothingEnabled = false;
      if (game.onResize) game.onResize();
      if (!game.running) draw();
    }

    var game = {
      canvas: canvas,
      ctx: ctx,
      width: W,
      height: H,
      score: 0,
      best: 0,
      running: false,
      over: false,
      paused: false,
      state: null,
      tick: cfg.tick || 0,
      elapsed: 0,
      onResize: cfg.onResize || null
    };

    // ---------------- HUD / 遮罩 / 按钮绑定 ----------------
    var root = canvas.closest('[data-game]') || document;
    var hudEls = root.querySelectorAll('[data-hud]');
    var overlay = root.querySelector('[data-overlay]');
    var ovTitle = root.querySelector('[data-overlay-title]');
    var ovText = root.querySelector('[data-overlay-text]');

    function syncHud() {
      for (var i = 0; i < hudEls.length; i++) {
        var el = hudEls[i], k = el.getAttribute('data-hud');
        if (k === 'score') el.textContent = String(game.score);
        else if (k === 'best') el.textContent = String(game.best);
      }
    }

    function showOverlay(title, text) {
      if (!overlay) return;
      if (ovTitle) ovTitle.textContent = title || '';
      if (ovText) ovText.textContent = text || '';
      overlay.hidden = false;
      var btn = root.querySelector('[data-action="start"]');
      if (btn) btn.textContent = '重新开始';
    }
    function hideOverlay() { if (overlay) overlay.hidden = true; }

    game.showOverlay = showOverlay;
    game.hideOverlay = hideOverlay;
    game.syncHud = syncHud;

    // ---------------- 分数 ----------------
    function loadBest() {
      try { return parseInt(global.localStorage.getItem(cfg.storageKey + ':best') || '0', 10) || 0; }
      catch (e) { return 0; }
    }
    function saveBest(v) {
      try { global.localStorage.setItem(cfg.storageKey + ':best', String(v)); } catch (e) { }
    }
    game.setScore = function (v) {
      game.score = v;
      if (v > game.best) { game.best = v; saveBest(v); }
      syncHud();
    };
    game.addScore = function (v) { game.setScore(game.score + v); };

    // ---------------- 生命周期 ----------------
    game.reset = function () {
      game.score = 0;
      game.over = false;
      game.elapsed = 0;
      game.state = cfg.reset(game) || null;
      syncHud();
    };
    game.start = function () {
      if (!game.state || game.over) game.reset();
      game.running = true;
      game.paused = false;
      hideOverlay();
      if (!loopHandle) { last = 0; loopHandle = requestAnimationFrame(loop); }
    };
    game.pause = function () {
      if (!game.running) return;
      game.paused = !game.paused;
      if (game.paused) showOverlay('已暂停', '按空格或点击“继续”恢复游戏。');
      else hideOverlay();
    };
    game.toggle = function () { game.running ? game.pause() : game.start(); };
    game.gameOver = function (text) {
      game.over = true;
      game.running = false;
      showOverlay('游戏结束', (text || '') + ' 本局得分 ' + game.score + '，历史最高 ' + game.best + '。');
    };

    // ---------------- 主循环 ----------------
    var loopHandle = null, last = 0, acc = 0;
    function loop(ts) {
      loopHandle = requestAnimationFrame(loop);
      if (!last) last = ts;
      var dt = Math.min(ts - last, 100);
      last = ts;
      if (game.running && !game.paused) {
        game.elapsed += dt;
        if (game.tick > 0) {
          acc += dt;
          var guard = 0;
          while (acc >= game.tick && guard++ < 8) {
            acc -= game.tick;
            cfg.update(game, game.tick);
            if (!game.running) { acc = 0; break; }
          }
        } else {
          cfg.update(game, dt);
        }
      }
      draw();
    }

    function draw() {
      ctx.save();
      ctx.clearRect(0, 0, W, H);
      cfg.draw(game, ctx);
      ctx.restore();
    }
    game.draw = draw;

    // ---------------- 输入：键盘 ----------------
    var KEYMAP = {
      ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
      w: 'up', a: 'left', s: 'down', d: 'right', W: 'up', A: 'left', S: 'down', D: 'right'
    };

    function keyHandler(e) {
      var tag = (e.target && e.target.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea') return;

      if (e.key === ' ' || e.key === 'Spacebar') {
        e.preventDefault();
        game.toggle();
        return;
      }
      if (e.key === 'r' || e.key === 'R') { game.reset(); game.start(); return; }
      if (e.key === 'p' || e.key === 'P' || e.key === 'Escape') { game.pause(); return; }

      var dir = KEYMAP[e.key];
      if (dir) {
        e.preventDefault();
        if (!game.running) game.start();
        if (cfg.onSwipe) cfg.onSwipe(game, dir);
        if (cfg.onKey) cfg.onKey(game, dir);
        return;
      }
      if (cfg.onKey) cfg.onKey(game, e.key);
    }

    // ---------------- 输入：指针 / 触屏滑动 ----------------
    var sx = 0, sy = 0, st = 0, dragging = false;
    function toLogical(e) {
      var r = canvas.getBoundingClientRect();
      var cx = (e.touches && e.touches[0]) ? e.touches[0].clientX : e.clientX;
      var cy = (e.touches && e.touches[0]) ? e.touches[0].clientY : e.clientY;
      return { x: (cx - r.left) / r.width * W, y: (cy - r.top) / r.height * H };
    }
    function onDown(e) {
      var p = toLogical(e); sx = p.x; sy = p.y; st = Date.now(); dragging = true;
      if (cfg.onDrag) cfg.onDrag(game, p.x, p.y);
    }
    function onUp(e) {
      if (!dragging) return;
      dragging = false;
      var ev = (e.changedTouches && e.changedTouches[0]) ? e.changedTouches[0] : e;
      var r = canvas.getBoundingClientRect();
      var ex = (ev.clientX - r.left) / r.width * W;
      var ey = (ev.clientY - r.top) / r.height * H;
      var dx = ex - sx, dy = ey - sy, adx = Math.abs(dx), ady = Math.abs(dy);
      var threshold = Math.max(18, W * 0.05);
      if (adx < threshold && ady < threshold) {
        if (cfg.onTap) { if (!game.running) game.start(); cfg.onTap(game, ex, ey); }
        return;
      }
      if (!game.running) game.start();
      if (cfg.onSwipe) {
        cfg.onSwipe(game, adx > ady ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up'));
      }
    }
    function onMove(e) {
      if (!dragging || !cfg.onDrag) return;
      var p = toLogical(e);
      cfg.onDrag(game, p.x, p.y);
    }

    canvas.addEventListener('mousedown', onDown);
    canvas.addEventListener('mouseup', onUp);
    canvas.addEventListener('mousemove', onMove);
    canvas.addEventListener('touchstart', function (e) { e.preventDefault(); onDown(e); }, { passive: false });
    canvas.addEventListener('touchend', function (e) { e.preventDefault(); onUp(e); }, { passive: false });
    canvas.addEventListener('touchmove', function (e) { e.preventDefault(); onMove(e); }, { passive: false });
    global.addEventListener('keydown', keyHandler);

    // ---------------- 按钮 ----------------
    var actions = root.querySelectorAll('[data-action]');
    for (var i = 0; i < actions.length; i++) {
      (function (btn) {
        var act = btn.getAttribute('data-action');
        btn.addEventListener('click', function () {
          if (act === 'start') { game.start(); }
          else if (act === 'pause') game.pause();
          else if (act === 'restart') { game.reset(); game.start(); }
          else if (act === 'toggle') game.toggle();
        });
      })(actions[i]);
    }

    // ---------------- 初始化 ----------------
    global.addEventListener('resize', resize);
    resize();
    game.best = loadBest();
    game.reset();
    syncHud();
    showOverlay('准备开始', '按空格键、点击画布或下方按钮开始游戏。');
    draw();

    return game;
  }

  global.Arcade = {
    create: create,
    clamp: clamp,
    randInt: randInt,
    pick: pick,
    TAU: TAU,
    /** 圆角矩形路径（兼容旧浏览器） */
    roundRect: function (ctx, x, y, w, h, r) {
      r = Math.min(r, w / 2, h / 2);
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.arcTo(x + w, y, x + w, y + h, r);
      ctx.arcTo(x + w, y + h, x, y + h, r);
      ctx.arcTo(x, y + h, x, y, r);
      ctx.arcTo(x, y, x + w, y, r);
      ctx.closePath();
    },
    /** 居中文本 */
    centerText: function (ctx, text, x, y, size, color, weight) {
      ctx.save();
      ctx.font = (weight || 700) + ' ' + size + 'px -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif';
      ctx.fillStyle = color || '#fff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(text, x, y);
      ctx.restore();
    }
  };
})(window);
